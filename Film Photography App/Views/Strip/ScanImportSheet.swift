import SwiftUI
import UIKit

/// A scan picked from the library but not yet written to the roll. Built on a background
/// task, so it stays off the main actor.
nonisolated struct PendingScan: Identifiable, Sendable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage?
}

/// A frame a scan can be dropped onto, carrying whatever the shutter already logged for
/// it. Seeing the place and date a frame was shot on is what makes it possible to tell
/// which photo belongs to which frame.
struct ScanImportFrame: Identifiable {
    let index: Int
    let location: String?
    let date: Date?
    /// Scan already written to this frame, if any.
    var existingScan: String? = nil

    var id: Int { index }
}

/// A photo sitting on a frame in the arrange sheet. Scans already on the roll are moved
/// around alongside newly picked ones — an import is rarely in the right order, and the
/// order only becomes obvious once the whole roll is laid out together.
enum ArrangedScan {
    case existing(fileName: String)
    case picked(PendingScan)
}

/// Frame-by-frame placement for a multi-image import. The frame column on the left is
/// fixed; scans are dragged between rows on the right. A partial set — ten scans from a
/// twenty-four exposure roll — can therefore be spread out with gaps where nothing was
/// scanned, rather than being forced onto consecutive frames.
struct ScanImportSheet: View {
    let rollId: UUID
    let frames: [ScanImportFrame]
    let onCancel: () -> Void
    let onConfirm: ([Int: ArrangedScan]) -> Void

    /// One entry per frame in `frames`. `nil` is a frame left without a scan.
    @State private var slots: [ArrangedScan?]
    /// Thumbnails for the scans already on the roll, read off disk in the background.
    @State private var existingThumbnails: [String: UIImage] = [:]
    /// Row the photo being dragged started on.
    @State private var dragSource: Int?
    /// Where the finger is, and where it and the list stood when it went down. Held in
    /// screen terms because the list can travel underneath the finger mid-drag.
    @State private var fingerY: CGFloat = 0
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartScroll: CGFloat = 0
    /// Row the finger has come to rest over, which is the only one that steps aside.
    @State private var settledIndex: Int?
    @State private var rowFrames: [Int: CGRect] = [:]
    /// Row centres frozen at the moment a drag starts. Rows re-measure themselves as the
    /// column shifts around, and reading those live values mid-drag makes the maths shift
    /// underfoot, which shows up as photos twitching between positions.
    @State private var dragAnchors: [Int: CGFloat] = [:]
    /// The source row's centre, and the gap between neighbouring rows.
    @State private var dragAnchorY: CGFloat = 0
    @State private var rowStep: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var scroll = ScrollMetrics()
    /// The scroll view on screen, for telling how close to an edge the finger is.
    @State private var viewport: CGRect = .zero

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0
    }

    private let scanCount: Int

    init(
        rollId: UUID,
        scans: [PendingScan],
        frames: [ScanImportFrame],
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([Int: ArrangedScan]) -> Void
    ) {
        self.rollId = rollId
        self.frames = frames
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.scanCount = scans.count

        // Scans already on the roll stay on their own frames; newly picked ones fill
        // forward from the first frame still free.
        var initial = frames.map { frame in
            frame.existingScan.map(ArrangedScan.existing)
        }
        var queue = scans[...]
        for index in initial.indices where initial[index] == nil {
            guard let next = queue.first else { break }
            initial[index] = .picked(next)
            queue = queue.dropFirst()
        }
        _slots = State(initialValue: initial)
    }

    private static let frameColumnWidth: CGFloat = 20
    private static let thumbWidth: CGFloat = 90
    private static let thumbHeight: CGFloat = 60
    /// Decoded at retina width for the slot rather than full size.
    private static let thumbPixelSize: CGFloat = 270
    private static let slotCorner = AppTheme.Spacing.sm
    private static let handleWidth: CGFloat = 44
    /// Rows are measured in here so a drag can tell which frame it is over.
    private static let listSpace = "arrangeScansList"
    /// How near an edge the finger has to be before the list starts travelling, and how
    /// far it travels per frame while it does.
    private static let autoScrollBand: CGFloat = 88
    private static let autoScrollStep: CGFloat = 9
    /// How long the finger has to hold over a frame before that frame makes room. Long
    /// enough that sweeping the length of the roll disturbs nothing on the way past.
    private static let settleDelay: Duration = .milliseconds(110)

    private var placedCount: Int {
        slots.compactMap { $0 }.count
    }

    private var placement: [Int: ArrangedScan] {
        var result: [Int: ArrangedScan] = [:]
        for (index, scan) in slots.enumerated() {
            if let scan {
                result[frames[index].index] = scan
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            content
                .instrumentScreen()
                .navigationTitle("Arrange Scans")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .instrumentSheetChrome()
        .presentationDetents([.large])
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                    if index > 0 {
                        HairlineRule()
                    }
                    row(index: index, frame: frame)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.bottom, AppTheme.Spacing.xl)
            .coordinateSpace(.named(Self.listSpace))
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y,
                viewport: geometry.containerSize.height,
                content: geometry.contentSize.height
            )
        } action: { _, metrics in
            scroll = metrics
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { viewport = $0 }
        .task(id: edgeScroll) { await driveEdgeScroll() }
        .task(id: hoverIndex) { await settleHover() }
        .task { await loadExistingThumbnails() }
    }

    private var header: some View {
        Text(hint)
            .font(AppType.callout)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, AppTheme.Spacing.lg)
    }

    /// One run of prose rather than stacked lines, so it wraps as a single block.
    private var hint: String {
        let advice = "Drag a photo onto the frame you shot it on, and any frame you leave empty stays empty."
        guard scanCount > 0 else {
            let existing = frames.lazy.filter { $0.existingScan != nil }.count
            let photos = existing == 1 ? "1 photo" : "\(existing) photos"
            return "\(photos) on a \(frames.count) frame roll. \(advice)"
        }
        let photos = scanCount == 1 ? "1 photo" : "\(scanCount) photos"
        return "\(photos) uploaded onto a \(frames.count) frame roll. \(advice)"
    }

    /// Scans already on the roll are read off disk, so their thumbnails are decoded in
    /// the background — a full roll is thirty-six of them, and doing that during layout
    /// stalls the sheet as it opens.
    private func loadExistingThumbnails() async {
        let names = frames.compactMap(\.existingScan)
        guard !names.isEmpty else { return }
        let rollId = rollId
        let maxSize = Self.thumbPixelSize

        existingThumbnails = await Task.detached(priority: .userInitiated) {
            var loaded: [String: UIImage] = [:]
            for name in names {
                loaded[name] = ScanStorage.thumbnail(
                    for: rollId,
                    fileName: name,
                    maxSize: maxSize,
                    laidOnSide: true
                )
            }
            return loaded
        }.value
    }

    private func row(index: Int, frame: ScanImportFrame) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text("\(frame.index)")
                .font(AppType.body)
                .monospacedDigit()
                .foregroundStyle(slots[index] == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                .frame(width: Self.frameColumnWidth, alignment: .leading)

            frameDetails(frame)

            imageColumn(index: index)
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.listSpace))
        } action: { rowFrames[index] = $0 }
        // Lifts the travelling photo over the rows it passes.
        .zIndex(dragSource == index ? 1 : 0)
    }

    /// The photo and its handle, which travel up and down together while the frame and
    /// its details hold their place in the row.
    private func imageColumn(index: Int) -> some View {
        let isDragging = dragSource == index
        return HStack(spacing: AppTheme.Spacing.md) {
            slot(index: index)
            handle(index: index)
        }
        .offset(y: isDragging ? dragOffset : displacement(for: index))
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.4 : 0), radius: 12, y: 6)
        .animation(makeRoomAnimation(for: index), value: settledIndex)
    }

    /// Only a frame making room for an incoming photo animates, and it eases rather than
    /// springs: sweeping over a run of photos would otherwise leave a trail of them
    /// overshooting back and forth.
    ///
    /// Nothing animates once the finger lifts. By then the drag has already shown where
    /// both photos are going, so animating the commit would replay a move the eye has
    /// just followed — which reads as the slots rearranging themselves a second time,
    /// after the drop. Landing them silently leaves each photo exactly where the drag
    /// said it would be. The photo in hand is never animated either, since it has to
    /// track the finger with nothing lagging in between.
    private func makeRoomAnimation(for index: Int) -> Animation? {
        guard let dragSource, dragSource != index else { return nil }
        return .easeOut(duration: 0.16)
    }

    /// How far the photo in hand has travelled from the row it was lifted off, in the
    /// list's own coordinates.
    ///
    /// The list scrolls itself when the finger nears an edge, and a drag gesture only
    /// reports a new location when the finger *itself* moves. Folding in how far the list
    /// has travelled keeps the photo pinned under the finger throughout; reading the
    /// gesture alone, it would sit still while the list slid out from under it and then
    /// leap the distance the moment the finger twitched.
    private var dragOffset: CGFloat {
        guard dragSource != nil else { return 0 }
        return (fingerY - dragStartY) + (scroll.offset - dragStartScroll)
    }

    /// Row the photo would land on if the finger lifted now: whichever centre the photo
    /// in hand is closest to.
    private var hoverIndex: Int? {
        guard dragSource != nil else { return nil }
        return frameNearest(to: dragAnchorY + dragOffset)
    }

    /// Which way the list carries itself while the finger sits near an edge.
    private var edgeScroll: Int {
        guard dragSource != nil, viewport.height > 0 else { return 0 }
        let withinViewport = fingerY - viewport.minY
        if withinViewport < Self.autoScrollBand { return -1 }
        if withinViewport > viewport.height - Self.autoScrollBand { return 1 }
        return 0
    }

    /// How far a frame's photo moves aside for the one being dragged over it.
    ///
    /// It steps one row towards the frame being vacated — no further, however far apart
    /// the two are. The pair really is about to trade places, but sliding this photo the
    /// whole way would fling it across the roll and usually clean off the screen, to
    /// preview a move the drop makes instantly anyway. A row's worth is enough to read as
    /// making way. Frames either side of the pair are untouched, which is what keeps the
    /// gaps the photographer left intact.
    private func displacement(for index: Int) -> CGFloat {
        guard let dragSource,
              settledIndex == index,
              index != dragSource,
              slots[index] != nil,
              let vacated = dragAnchors[dragSource],
              let occupied = dragAnchors[index]
        else { return 0 }

        return min(max(vacated - occupied, -rowStep), rowStep)
    }

    /// The frame the photo would drop onto right now, marked while the finger is still
    /// down so the landing spot is never a surprise.
    private func isTargeted(_ index: Int) -> Bool {
        dragSource != nil && dragSource != index && hoverIndex == index
    }

    /// Only the frame the finger has actually stopped over makes room. Every frame the
    /// drag crosses on its way there is briefly the nearest one, and letting each of those
    /// step aside and back sets photos moving all down the list that were never involved.
    private func settleHover() async {
        guard dragSource != nil else {
            settledIndex = nil
            return
        }
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled else { return }
        settledIndex = hoverIndex
    }

    /// Only so much of the roll is on screen at once, so holding the photo near an edge
    /// draws the rest of the list past it. The target is stepped along locally rather than
    /// read back from the scroll view, which would stall against its own reporting lag.
    private func driveEdgeScroll() async {
        guard edgeScroll != 0 else { return }

        var target = scroll.offset
        while !Task.isCancelled, dragSource != nil {
            let limit = max(scroll.content - scroll.viewport, 0)
            let next = min(max(target + CGFloat(edgeScroll) * Self.autoScrollStep, 0), limit)
            guard next != target else { return }

            target = next
            scrollPosition.scrollTo(y: target)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Vertical only: the photo tracks the finger's rise and fall and lands on whichever
    /// frame it is sitting over, so nothing can be dropped outside the list.
    ///
    /// The finger is followed on screen rather than in the list's own space, which slides
    /// about underneath it whenever the list scrolls.
    private func reorderGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { drag in
                if dragSource == nil {
                    let anchors = rowFrames.mapValues(\.midY)
                    dragSource = index
                    dragAnchors = anchors
                    dragAnchorY = anchors[index] ?? 0
                    rowStep = Self.rowStep(between: anchors)
                    dragStartY = drag.startLocation.y
                    dragStartScroll = scroll.offset
                }
                fingerY = drag.location.y
            }
            .onEnded { _ in
                if let dragSource, let hoverIndex {
                    // Settles without animation: the offset and the slots change in the
                    // same pass, so the photo is simply already there.
                    swap(from: dragSource, to: hoverIndex)
                }
                dragSource = nil
                settledIndex = nil
                dragAnchors = [:]
            }
    }

    private func frameNearest(to y: CGFloat) -> Int? {
        dragAnchors.min { abs($0.value - y) < abs($1.value - y) }?.key
    }

    /// The gap between neighbouring rows, taken from the rows themselves so it holds up
    /// however tall they turn out to be.
    private static func rowStep(between anchors: [Int: CGFloat]) -> CGFloat {
        let centres = anchors.values.sorted()
        return zip(centres, centres.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .min() ?? 0
    }

    private func shift(_ index: Int, by delta: Int) {
        swap(from: index, to: index + delta)
    }

    /// What the shutter logged for this frame. Both lines always render so rows keep an
    /// even rhythm down the list, with the placeholders dimmed like any unset field.
    private func frameDetails(_ frame: ScanImportFrame) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(frame.location ?? "No location")
                .font(AppType.body)
                .foregroundStyle(frame.location == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
            Text(frame.date.map { $0.formatted(date: .long, time: .omitted) } ?? "No date")
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func slot(index: Int) -> some View {
        if let scan = slots[index] {
            thumbnail(scan)
                .overlay {
                    if isTargeted(index) {
                        RoundedRectangle(cornerRadius: Self.slotCorner)
                            .strokeBorder(AppTheme.textPrimary, lineWidth: 2)
                    }
                }
                .contextMenu {
                    Button("Remove scan", lucide: .trash, role: .destructive) {
                        slots[index] = nil
                    }
                }
        } else {
            emptySlot(isTargeted: isTargeted(index))
        }
    }

    /// The one place a drag can begin. Its touch area runs the full height of the photo
    /// and well past the icon, so it is comfortable to catch without the photo itself
    /// swallowing the gesture. Empty frames keep a dimmed handle so the column stays
    /// even, but there is nothing there to pick up.
    @ViewBuilder
    private func handle(index: Int) -> some View {
        let grip = LucideIcon(.gripVertical)
            .foregroundStyle(handleTint(index: index))
            .frame(width: Self.handleWidth, height: Self.thumbHeight)
            .contentShape(.rect)

        if slots[index] == nil {
            grip.accessibilityHidden(true)
        } else {
            grip
                .highPriorityGesture(reorderGesture(index: index))
                .accessibilityLabel("Move the photo on frame \(frames[index].index)")
                .accessibilityAction(named: "Move up") { shift(index, by: -1) }
                .accessibilityAction(named: "Move down") { shift(index, by: 1) }
        }
    }

    /// The handle in hand reads at full strength; the rest stay quiet.
    private func handleTint(index: Int) -> Color {
        if dragSource == index {
            return AppTheme.textPrimary
        }
        return slots[index] == nil ? AppTheme.rule : AppTheme.textSecondary
    }

    private func thumbnail(_ scan: ArrangedScan) -> some View {
        RoundedRectangle(cornerRadius: Self.slotCorner)
            .fill(AppTheme.surface)
            .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            .overlay {
                if let preview = preview(for: scan) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    LucideIcon(.scan)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.slotCorner))
    }

    /// Newly picked scans carry their own preview; ones already on the roll wait on the
    /// background read, showing the empty gate mark until it lands.
    private func preview(for scan: ArrangedScan) -> UIImage? {
        switch scan {
        case .picked(let pending): pending.preview
        case .existing(let fileName): existingThumbnails[fileName]
        }
    }

    private func emptySlot(isTargeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: Self.slotCorner)
            .strokeBorder(isTargeted ? AppTheme.textPrimary : AppTheme.rule, lineWidth: 1)
            .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            .overlay {
                LucideIcon(.scan)
                    .foregroundStyle(isTargeted ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
    }

    /// Landing on an empty frame moves the scan; landing on a filled one trades the two.
    /// Nothing shuffles along, so the gaps the photographer left stay where they are and
    /// no image is ever silently discarded.
    private func swap(from source: Int, to destination: Int) {
        guard source != destination,
              slots.indices.contains(source),
              slots.indices.contains(destination)
        else { return }

        let moving = slots[source]
        slots[source] = slots[destination]
        slots[destination] = moving
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onCancel) {
                LucideIcon(.x)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { onConfirm(placement) }
                .font(AppType.body)
                .disabled(placedCount == 0)
        }
    }
}
