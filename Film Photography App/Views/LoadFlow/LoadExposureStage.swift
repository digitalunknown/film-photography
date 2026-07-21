import SwiftUI
import PhotosUI
import UIKit

/// Slide-to-load gate that swaps into the exposures carousel after lock-in.
struct LoadExposureStage: View {
    enum StartMode {
        /// Show the film load slider.
        case slide
        /// Show the exposures carousel (counter, strip, scans).
        case carousel
    }

    let roll: Roll
    let stock: FilmStock?
    var cameraName: String
    var canSlide: Bool
    var startMode: StartMode
    var onChoose: (() -> Void)?
    var onChangeSelection: (() -> Void)?
    var onCommitLoad: (() -> Void)?
    var onAdvance: () -> Void
    var onUndo: (() -> Void)? = nil
    var onSetCount: (Int) -> Void

    @State private var phase: Phase
    @State private var selectedFrameIndex: Int?
    @State private var containerWidth: CGFloat = 0
    @State private var viewingFrame: StripFrame?
    @State private var scanPickerItems: [PhotosPickerItem] = []
    @State private var showLoadVisual = false
    @Environment(AppStore.self) private var store

    private enum Phase {
        case slide
        case carousel
    }

    private let visibleFrameCount: CGFloat = 3

    private var frameTotal: Int {
        max(roll.totalExposures, 1)
    }

    private var layout: FilmStripLayout {
        if containerWidth > 1 {
            return FilmStripLayout.layout(
                for: roll.format,
                visibleCount: visibleFrameCount,
                containerWidth: containerWidth,
                horizontalInset: 0
            )
        }
        return FilmStripLayout.layout(for: roll.format, cellHeight: 110)
    }

    init(
        roll: Roll,
        stock: FilmStock?,
        cameraName: String,
        canSlide: Bool,
        startMode: StartMode,
        onChoose: (() -> Void)? = nil,
        onChangeSelection: (() -> Void)? = nil,
        onCommitLoad: (() -> Void)? = nil,
        onAdvance: @escaping () -> Void,
        onUndo: (() -> Void)? = nil,
        onSetCount: @escaping (Int) -> Void
    ) {
        self.roll = roll
        self.stock = stock
        self.cameraName = cameraName
        self.canSlide = canSlide
        self.startMode = startMode
        self.onChoose = onChoose
        self.onChangeSelection = onChangeSelection
        self.onCommitLoad = onCommitLoad
        self.onAdvance = onAdvance
        self.onUndo = onUndo
        self.onSetCount = onSetCount

        switch startMode {
        case .slide:
            _phase = State(initialValue: .slide)
            _showLoadVisual = State(initialValue: canSlide)
        case .carousel:
            _phase = State(initialValue: .carousel)
            _showLoadVisual = State(initialValue: false)
        }
    }

    var body: some View {
        DetailSection(title: "") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                switch phase {
                case .slide:
                    slideContent
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                            )
                        )
                case .carousel:
                    carouselContent
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 12))
                                    .combined(with: .scale(scale: 0.98, anchor: .top)),
                                removal: .opacity
                            )
                        )
                }
            }
            .animation(.spring(response: 0.52, dampingFraction: 0.86), value: phase)
            .animation(.spring(response: 0.48, dampingFraction: 0.84), value: showLoadVisual)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in
                            containerWidth = width
                        }
                }
            )
        }
        .onAppear {
            if phase == .slide {
                showLoadVisual = canSlide
            }
        }
        .onChange(of: canSlide) { _, enabled in
            guard phase == .slide else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                showLoadVisual = enabled
            }
        }
        .onChange(of: startMode) { _, newMode in
            switch newMode {
            case .slide:
                phase = .slide
                selectedFrameIndex = nil
                showLoadVisual = canSlide
            case .carousel:
                // Only jump if we aren't already animating through load.
                if phase != .carousel {
                    phase = .carousel
                }
            }
        }
        .onChange(of: roll.status.isInventory) { _, isInventory in
            if isInventory {
                phase = .slide
                selectedFrameIndex = nil
                showLoadVisual = canSlide
            }
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
            .presentationDragIndicator(.hidden)
            .presentationBackground(AppTheme.bg)
            .preferredColorScheme(.dark)
        }
        .onChange(of: scanPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importScans(items) }
        }
    }

    // MARK: - Slide

    private var slideContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if showLoadVisual {
                FilmLoadSlider(
                    stock: stock,
                    layout: layout,
                    isEnabled: canSlide,
                    playsEntrance: true,
                    onComplete: { finishLoad() }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
                    )
                )
            }

            if onChoose != nil || onChangeSelection != nil {
                Button {
                    (canSlide ? (onChangeSelection ?? onChoose) : (onChoose ?? onChangeSelection))?()
                } label: {
                    Text(canSlide ? cameraName : "Load to Camera")
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
                onDecrement: onUndo,
                onSetCount: onSetCount
            )
            .transition(.opacity.combined(with: .move(edge: .top)))

            FilmStripView(
                roll: roll,
                stock: stock,
                selectedFrameIndex: $selectedFrameIndex,
                onOpenScan: { frame in
                    viewingFrame = frame
                }
            )

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
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    private func finishLoad() {
        onCommitLoad?()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        // Let the slider finish filling the chamber, then crossfade into the loaded UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                phase = .carousel
            }
        }
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
