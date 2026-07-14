import SwiftUI
import UIKit

struct FilmStripView: View {
    let roll: Roll
    let stock: FilmStock?
    @Binding var selectedFrameIndex: Int?
    var onFrameLongPress: ((StripFrame) -> Void)?
    var onShiftScans: ((Int) -> Void)?
    var onOpenScan: ((StripFrame) -> Void)?
    var onFrameTap: ((StripFrame) -> Void)?

    @State private var contactSheetMode = false
    @State private var scrollPosition: Int?
    @State private var lastHapticFrame: Int?
    @State private var containerWidth: CGFloat = 0

    private let visibleFrameCount: CGFloat = 3
    private let horizontalInset: CGFloat = 0

    /// Charcoal emulsion base — slightly above pure black so gates read darker.
    static let filmBase = Color(red: 0.12, green: 0.12, blue: 0.125)
    static let stripChromeHeight: CGFloat = FilmStripFrameMetrics.chromeHeight

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if contactSheetMode {
                FilmStripContactSheet(
                    roll: roll,
                    stock: stock,
                    selectedFrameIndex: $selectedFrameIndex,
                    onFrameLongPress: onFrameLongPress
                )
            } else {
                stripScrollView
            }

            if !roll.scanFileNames.isEmpty {
                scanAlignmentControls
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        containerWidth = width
                    }
            }
        )
        .gesture(
            MagnificationGesture()
                .onEnded { value in
                    if value < 0.85 {
                        contactSheetMode = true
                    } else if value > 1.15 {
                        contactSheetMode = false
                    }
                }
        )
    }

    private var stripScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(frames.enumerated()), id: \.element.id) { offset, frame in
                    FilmStripFrameCell(
                        frame: frame,
                        roll: roll,
                        stock: stock,
                        layout: layout,
                        isSelected: selectedFrameIndex == frame.index,
                        showsTrailingMarks: offset < frames.count - 1
                    )
                    .id(frame.index)
                    .onTapGesture {
                        selectedFrameIndex = frame.index
                        onFrameTap?(frame)
                        if frame.state == .scanned {
                            onOpenScan?(frame)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onLongPressGesture {
                        onFrameLongPress?(frame)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition)
        .onChange(of: scrollPosition) { _, newValue in
            guard let newValue, newValue != lastHapticFrame else { return }
            lastHapticFrame = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: roll.frameCount) { previous, newCount in
            guard newCount > previous, newCount > 0 else { return }
            selectedFrameIndex = newCount
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                scrollPosition = newCount
            }
        }
        .onChange(of: selectedFrameIndex) { _, newValue in
            guard let newValue, scrollPosition != newValue else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                scrollPosition = newValue
            }
        }
        .frame(height: layout.frameSize.height + Self.stripChromeHeight)
        .background(Self.filmBase)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var scanAlignmentControls: some View {
        HStack {
            Text("Scan alignment")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Button {
                onShiftScans?(-1)
            } label: {
                Text("← Shift")
                    .font(InstrumentFont.mono(14))
            }
            .buttonStyle(.plain)

            Text("offset \(roll.scanAlignmentOffset)")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textTertiary)

            Button {
                onShiftScans?(1)
            } label: {
                Text("Shift →")
                    .font(InstrumentFont.mono(14))
            }
            .buttonStyle(.plain)
        }
    }
}

enum FilmStripFrameMetrics {
    static let railHeight: CGFloat = 16
    static let edgeBandHeight: CGFloat = 14
    static let gateInset: CGFloat = 5
    static var chromeHeight: CGFloat { (railHeight + edgeBandHeight) * 2 }
}

private struct FilmStripFrameCell: View {
    let frame: StripFrame
    let roll: Roll
    let stock: FilmStock?
    let layout: FilmStripLayout
    let isSelected: Bool
    var showsTrailingMarks: Bool = true

    private var edgeInk: Color { AppTheme.textSecondary.opacity(0.85) }

    private var stockLabel: String {
        (stock?.name ?? "FILM").uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            sprocketRail
            topEdgeBand
            frameArea
            bottomEdgeBand
            sprocketRail
        }
        .frame(width: layout.frameSize.width)
        .background(FilmStripView.filmBase)
        .overlay(alignment: .trailing) {
            if showsTrailingMarks {
                interFrameMarks
            }
        }
    }

    private var interFrameMarks: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: FilmStripFrameMetrics.railHeight)
            Text("→")
                .font(InstrumentFont.mono(7))
                .foregroundStyle(edgeInk)
                .frame(height: FilmStripFrameMetrics.edgeBandHeight)
            Spacer(minLength: 0)
            Text("◎")
                .font(InstrumentFont.mono(8))
                .foregroundStyle(edgeInk)
                .frame(height: FilmStripFrameMetrics.edgeBandHeight)
            Color.clear.frame(height: FilmStripFrameMetrics.railHeight)
        }
        .offset(x: 4)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var sprocketRail: some View {
        if layout.showsSprockets {
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    sprocketHole
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: FilmStripFrameMetrics.railHeight)
            .padding(.horizontal, 6)
        } else {
            Color.clear.frame(height: 4)
        }
    }

    private var sprocketHole: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .strokeBorder(edgeInk, lineWidth: 1)
            .frame(width: 9, height: 7)
    }

    private var topEdgeBand: some View {
        Text(stockLabel)
            .font(InstrumentFont.mono(7))
            .foregroundStyle(edgeInk)
            .tracking(0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity)
            .frame(height: FilmStripFrameMetrics.edgeBandHeight)
            .padding(.horizontal, FilmStripFrameMetrics.gateInset + 2)
    }

    @ViewBuilder
    private var frameArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black)

            switch frame.state {
            case .unexposed, .exposed:
                emptyGateMark
            case .pinned:
                VStack(spacing: 6) {
                    emptyGateMark
                    if let location = frame.marker?.location, !location.isEmpty {
                        Text(location)
                            .font(InstrumentFont.mono(7))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            case .scanned:
                Group {
                    if let fileName = frame.scanFileName,
                       let image = ScanStorage.thumbnail(for: roll.id, fileName: fileName) {
                        GeometryReader { geo in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        Color.white.opacity(0.06)
                        emptyGateMark
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(
                    isSelected ? AppTheme.textSecondary : Color.clear,
                    lineWidth: 1
                )
        }
        .padding(.horizontal, FilmStripFrameMetrics.gateInset)
        .frame(width: layout.frameSize.width, height: layout.frameSize.height)
    }

    private var emptyGateMark: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(edgeInk.opacity(0.7), lineWidth: 1)
            .frame(width: 14, height: 14)
    }

    private var bottomEdgeBand: some View {
        Text(frame.negativeNotation)
            .font(InstrumentFont.mono(7))
            .foregroundStyle(edgeInk)
            .frame(maxWidth: .infinity)
            .frame(height: FilmStripFrameMetrics.edgeBandHeight)
    }
}

struct FilmStripContactSheet: View {
    let roll: Roll
    let stock: FilmStock?
    @Binding var selectedFrameIndex: Int?
    var onFrameLongPress: ((StripFrame) -> Void)?

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 100), spacing: 4)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(frames) { frame in
                MiniFrameTick(frame: frame, roll: roll, stock: stock, size: 72)
                    .onTapGesture { selectedFrameIndex = frame.index }
                    .onLongPressGesture { onFrameLongPress?(frame) }
            }
        }
    }
}

struct MiniStripView: View {
    let roll: Roll
    let stock: FilmStock?

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
    }

    private var baseColor: Color {
        stock?.stripBaseColor ?? Color(red: 0.141, green: 0.075, blue: 0.035)
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(frames.prefix(72)) { frame in
                MiniFrameTick(frame: frame, roll: roll, stock: stock, size: nil)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(baseColor.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct MiniFrameTick: View {
    let frame: StripFrame
    let roll: Roll
    let stock: FilmStock?
    var size: CGFloat?

    var body: some View {
        Group {
            if let size {
                frameContent
                    .frame(width: size * 0.65, height: size * 0.85)
            } else {
                frameContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var frameContent: some View {
        ZStack {
            tickColor
            if frame.state == .pinned {
                Circle().fill(Color.white.opacity(0.5)).frame(width: 3, height: 3)
            }
            if frame.state == .scanned,
               let fileName = frame.scanFileName,
               let image = ScanStorage.thumbnail(for: roll.id, fileName: fileName, maxSize: 40) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
    }

    private var tickColor: Color {
        switch frame.state {
        case .unexposed: Color.black.opacity(0.6)
        case .exposed: Color.white.opacity(0.25)
        case .pinned: Color.white.opacity(0.45)
        case .scanned: Color.white.opacity(0.7)
        }
    }
}
