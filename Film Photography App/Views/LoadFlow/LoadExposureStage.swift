import SwiftUI
import PhotosUI
import UIKit

/// Slide-to-load gate that morphs into a blank exposures carousel after lock-in.
struct LoadExposureStage: View {
    enum StartMode {
        /// Show the film load slider.
        case slide
        /// Play the post-load strip reveal (blank frames cascade in).
        case reveal
        /// Jump straight to the exposures carousel.
        case carousel
    }

    let roll: Roll
    let stock: FilmStock?
    var cameraName: String
    var canSlide: Bool
    var startMode: StartMode
    var emptyPrompt: String = "choose a camera"
    var footnote: String? = nil
    var onChoose: (() -> Void)?
    var onChangeSelection: (() -> Void)?
    var onCommitLoad: (() -> Void)?
    var onAdvance: () -> Void
    var onSetCount: (Int) -> Void
    var onRevealFinished: (() -> Void)?

    @State private var phase: Phase
    @State private var revealedCount: Int
    @State private var selectedFrameIndex: Int?
    @State private var expandHeight: CGFloat
    @State private var didStartReveal = false
    @State private var containerWidth: CGFloat = 0
    @State private var viewingFrame: StripFrame?
    @State private var scanPickerItems: [PhotosPickerItem] = []
    @Environment(AppStore.self) private var store

    private enum Phase {
        case slide
        case expanding
        case carousel
    }

    private let visibleFrameCount: CGFloat = 3
    private let horizontalInset: CGFloat = 0

    private var frameTotal: Int {
        max(roll.totalExposures, 1)
    }

    private var layout: FilmStripLayout {
        if containerWidth > 1 {
            return FilmStripLayout.layout(
                for: roll.format,
                visibleCount: visibleFrameCount,
                containerWidth: containerWidth,
                horizontalInset: horizontalInset
            )
        }
        return FilmStripLayout.layout(for: roll.format, cellHeight: 110)
    }

    private var stripChassisHeight: CGFloat {
        layout.frameSize.height + FilmStripView.stripChromeHeight
    }

    private var sectionTitle: String {
        phase == .slide ? "Load" : "Exposures"
    }

    init(
        roll: Roll,
        stock: FilmStock?,
        cameraName: String,
        canSlide: Bool,
        startMode: StartMode,
        emptyPrompt: String = "choose a camera",
        footnote: String? = nil,
        onChoose: (() -> Void)? = nil,
        onChangeSelection: (() -> Void)? = nil,
        onCommitLoad: (() -> Void)? = nil,
        onAdvance: @escaping () -> Void,
        onSetCount: @escaping (Int) -> Void,
        onRevealFinished: (() -> Void)? = nil
    ) {
        self.roll = roll
        self.stock = stock
        self.cameraName = cameraName
        self.canSlide = canSlide
        self.startMode = startMode
        self.emptyPrompt = emptyPrompt
        self.footnote = footnote
        self.onChoose = onChoose
        self.onChangeSelection = onChangeSelection
        self.onCommitLoad = onCommitLoad
        self.onAdvance = onAdvance
        self.onSetCount = onSetCount
        self.onRevealFinished = onRevealFinished

        let fallback = FilmStripLayout.layout(for: roll.format, cellHeight: 96)
        switch startMode {
        case .slide:
            _phase = State(initialValue: .slide)
            _revealedCount = State(initialValue: 0)
            _expandHeight = State(initialValue: 148)
        case .reveal:
            _phase = State(initialValue: .expanding)
            _revealedCount = State(initialValue: 0)
            _expandHeight = State(initialValue: fallback.frameSize.height + FilmStripView.stripChromeHeight)
        case .carousel:
            _phase = State(initialValue: .carousel)
            _revealedCount = State(initialValue: max(roll.totalExposures, 1))
            _expandHeight = State(initialValue: fallback.frameSize.height + FilmStripView.stripChromeHeight)
        }
    }

    var body: some View {
        DetailSection(title: sectionTitle) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                switch phase {
                case .slide:
                    slideContent
                case .expanding:
                    expandingContent
                case .carousel:
                    carouselContent
                }
            }
            .animation(.spring(response: 0.48, dampingFraction: 0.86), value: phase)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in
                            containerWidth = width
                            if phase != .slide {
                                expandHeight = FilmStripLayout.layout(
                                    for: roll.format,
                                    visibleCount: visibleFrameCount,
                                    containerWidth: width,
                                    horizontalInset: horizontalInset
                                ).frameSize.height + FilmStripView.stripChromeHeight
                            }
                        }
                }
            )
        }
        .onAppear {
            if startMode == .reveal, !didStartReveal {
                didStartReveal = true
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                revealFramesSequentially()
            }
        }
        .onChange(of: startMode) { _, newMode in
            guard newMode == .slide else { return }
            phase = .slide
            revealedCount = 0
            expandHeight = 148
            didStartReveal = false
            selectedFrameIndex = nil
        }
        .sheet(item: $viewingFrame) { frame in
            NavigationStack {
                ScanFrameView(
                    rollId: roll.id,
                    frame: frame,
                    stock: stock
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
        }
        .onChange(of: scanPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importScans(items) }
        }
    }

    // MARK: - Slide

    private var slideContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            FilmLoadSlider(
                stock: stock,
                cameraName: cameraName,
                prompt: canSlide ? "slide to load" : emptyPrompt,
                emptyPrompt: emptyPrompt,
                onChooseRoll: canSlide ? nil : onChoose
            ) {
                beginExpandAfterCommit()
            }
            .allowsHitTesting(canSlide)
            .overlay {
                if !canSlide {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onChoose?() }
                }
            }

            if canSlide {
                HStack {
                    Text(footnote ?? cameraName)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    if let onChangeSelection {
                        Button("Change →", action: onChangeSelection)
                            .font(InstrumentFont.mono(11))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            } else if let footnote {
                Text(footnote)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textTertiary)
            } else {
                Text("Tap the bay to choose a camera, then slide to load.")
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    // MARK: - Expanding morph

    private var expandingContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("loaded")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
                .tracking(1.2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(1...frameTotal, id: \.self) { index in
                        blankFrameCell(index: index)
                            .opacity(index <= revealedCount ? 1 : 0)
                            .scaleEffect(index <= revealedCount ? 1 : 0.92, anchor: .leading)
                            .offset(x: index <= revealedCount ? 0 : -8)
                    }
                }
            }
            .frame(height: expandHeight)
            .background(FilmStripView.filmBase)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    // MARK: - Carousel

    private var carouselContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            FrameExposureCounter(
                shot: roll.frameCount,
                total: frameTotal,
                showsSegmentBar: false,
                onIncrement: onAdvance,
                onSetCount: onSetCount
            )

            FilmStripView(
                roll: roll,
                stock: stock,
                selectedFrameIndex: $selectedFrameIndex,
                onOpenScan: { frame in
                    viewingFrame = frame
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            PhotosPicker(
                selection: $scanPickerItems,
                maxSelectionCount: max(roll.totalExposures, 1),
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Add Scans")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay {
                        Rectangle()
                            .strokeBorder(AppTheme.rule, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    private func importScans(_ items: [PhotosPickerItem]) async {
        let startFrame = await MainActor.run { nextFrameIndexForScans() }
        let cap = max(roll.totalExposures, 1)
        var firstImported: Int?

        for (offset, item) in items.enumerated() {
            let frameIndex = startFrame + offset
            guard frameIndex <= cap else { break }
            guard let data = await loadImageData(from: item),
                  let jpeg = ScanStorage.normalizedJPEG(from: data)
            else { continue }

            await MainActor.run {
                store.setFramePhoto(on: roll.id, frameIndex: frameIndex, imageData: jpeg)
                if firstImported == nil {
                    firstImported = frameIndex
                }
            }
        }

        await MainActor.run {
            scanPickerItems = []
            if let firstImported {
                selectedFrameIndex = firstImported
            }
        }
    }

    private func nextFrameIndexForScans() -> Int {
        let maxPhoto = roll.framePhotoFileNames.keys.compactMap(Int.init).max() ?? 0
        let maxScan = roll.scanFileNames.isEmpty
            ? 0
            : roll.scanFileNames.count + roll.scanAlignmentOffset
        return max(maxPhoto, maxScan, 0) + 1
    }

    private func loadImageData(from item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        if let transfer = try? await item.loadTransferable(type: FrameScanImageTransfer.self) {
            return transfer.data
        }
        return nil
    }

    private func blankFrameCell(index: Int) -> some View {
        let edgeInk = AppTheme.textSecondary.opacity(0.85)
        let stockLabel = (stock?.name ?? "FILM").uppercased()
        let railHeight = FilmStripFrameMetrics.railHeight
        let edgeBandHeight = FilmStripFrameMetrics.edgeBandHeight
        let gateInset = FilmStripFrameMetrics.gateInset

        return VStack(spacing: 0) {
            if layout.showsSprockets {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .strokeBorder(edgeInk, lineWidth: 1)
                            .frame(width: 9, height: 7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: railHeight)
                .padding(.horizontal, 6)
            }

            Text(stockLabel)
                .font(InstrumentFont.mono(7))
                .foregroundStyle(edgeInk)
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .frame(height: edgeBandHeight)
                .padding(.horizontal, gateInset + 2)

            ZStack {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(edgeInk.opacity(0.7), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, gateInset)
            .frame(width: layout.frameSize.width, height: layout.frameSize.height)

            Text(String(format: "%d %dA", index, index))
                .font(InstrumentFont.mono(7))
                .foregroundStyle(edgeInk)
                .frame(maxWidth: .infinity)
                .frame(height: edgeBandHeight)

            if layout.showsSprockets {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .strokeBorder(edgeInk, lineWidth: 1)
                            .frame(width: 9, height: 7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: railHeight)
                .padding(.horizontal, 6)
            }
        }
        .frame(width: layout.frameSize.width)
        .background(FilmStripView.filmBase)
    }

    // MARK: - Transition

    private func beginExpandAfterCommit() {
        onCommitLoad?()
        // Let the slider finish its lock-in beat, then unspool into frames.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            beginExpand()
        }
    }

    private func beginExpand() {
        guard phase == .slide else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            phase = .expanding
            expandHeight = stripChassisHeight
        }

        revealFramesSequentially()
    }

    private func revealFramesSequentially() {
        let total = frameTotal
        let step = max(0.018, min(0.045, 0.55 / Double(total)))

        for index in 1...total {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(index)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    revealedCount = index
                }
                if index % 3 == 0 || index == total {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if index == total {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            phase = .carousel
                        }
                        onRevealFinished?()
                    }
                }
            }
        }
    }
}

/// Reliable PhotosPicker image transfer — `Data.self` alone often fails for library assets.
private struct FrameScanImageTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .png) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .heic) { FrameScanImageTransfer(data: $0) }
        DataRepresentation(importedContentType: .image) { FrameScanImageTransfer(data: $0) }
    }
}
