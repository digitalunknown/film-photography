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

    /// Frame highlighted for the next exposure (frame 1 when nothing has been shot yet).
    private var currentExposureFrame: Int {
        let total = max(roll.totalExposures, 1)
        if roll.frameCount >= total {
            return total
        }
        return roll.frameCount + 1
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
                ForEach(frames) { frame in
                    FilmStripFrameCell(
                        frame: frame,
                        roll: roll,
                        stock: stock,
                        layout: layout,
                        isCurrent: frame.index == currentExposureFrame
                    )
                    .id(frame.index)
                    .onTapGesture {
                        selectedFrameIndex = frame.index
                        onFrameTap?(frame)
                        onOpenScan?(frame)
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
        .onAppear {
            scrollToCurrentExposure(animated: false)
        }
        .onChange(of: scrollPosition) { _, newValue in
            guard let newValue, newValue != lastHapticFrame else { return }
            lastHapticFrame = newValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: roll.frameCount) { _, _ in
            scrollToCurrentExposure(animated: true)
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

    private func scrollToCurrentExposure(animated: Bool) {
        let current = currentExposureFrame
        selectedFrameIndex = current
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                scrollPosition = current
            }
        } else {
            scrollPosition = current
        }
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
    /// Perforation band — kept slim so the gate dominates (~24 of 35mm).
    static let railHeight: CGFloat = 10
    /// Edge print sits between the holes and the gate.
    static let edgeBandHeight: CGFloat = 8
    static let sprocketCount = 8
    static let sprocketWidth: CGFloat = 5
    static let sprocketHeight: CGFloat = 4
    static let sprocketCorner: CGFloat = 0.75
    /// Hairline strokes for strip chrome (1 display pixel).
    static var strokeWidth: CGFloat { 1 / max(UIScreen.main.scale, 1) }
    /// Cut-out perforation color — matches the page behind the strip.
    static let sprocketCutout = Color.black

    static var chromeHeight: CGFloat { (railHeight + edgeBandHeight) * 2 }

    static func gateInset(forCellWidth width: CGFloat) -> CGFloat {
        max(width * FilmStripLayout.interframeGapFraction * 0.5, 2)
    }
}

/// L-shaped corner marks for the current exposure frame.
private struct FrameCornerStroke: Shape {
    var length: CGFloat = 8
    var lineWidth: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let arm = min(length, min(rect.width, rect.height) / 2)
        var path = Path()

        // Top-left
        path.move(to: CGPoint(x: inset, y: inset + arm))
        path.addLine(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: inset + arm, y: inset))

        // Top-right
        path.move(to: CGPoint(x: rect.maxX - inset - arm, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: inset + arm))

        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - arm))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset - arm, y: rect.maxY - inset))

        // Bottom-left
        path.move(to: CGPoint(x: inset + arm, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: inset, y: rect.maxY - inset - arm))

        return path
    }
}

private struct FilmStripFrameCell: View {
    let frame: StripFrame
    let roll: Roll
    let stock: FilmStock?
    let layout: FilmStripLayout
    var isCurrent: Bool = false

    private var edgeInk: Color { AppTheme.textSecondary.opacity(0.85) }
    private var gateInset: CGFloat {
        FilmStripFrameMetrics.gateInset(forCellWidth: layout.frameSize.width)
    }

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
    }

    @ViewBuilder
    private var sprocketRail: some View {
        if layout.showsSprockets {
            HStack(spacing: 0) {
                ForEach(0..<FilmStripFrameMetrics.sprocketCount, id: \.self) { _ in
                    sprocketHole
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: FilmStripFrameMetrics.railHeight)
            .padding(.horizontal, gateInset)
        } else {
            Color.clear.frame(height: 3)
        }
    }

    private var sprocketHole: some View {
        RoundedRectangle(cornerRadius: FilmStripFrameMetrics.sprocketCorner)
            .fill(FilmStripFrameMetrics.sprocketCutout)
            .frame(
                width: FilmStripFrameMetrics.sprocketWidth,
                height: FilmStripFrameMetrics.sprocketHeight
            )
    }

    private var topEdgeBand: some View {
        Text(stockLabel)
            .font(InstrumentFont.mono(6))
            .foregroundStyle(edgeInk)
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .frame(height: FilmStripFrameMetrics.edgeBandHeight)
            .padding(.horizontal, gateInset + 1)
    }

    @ViewBuilder
    private var frameArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.black)

            switch frame.state {
            case .unexposed, .exposed:
                emptyGateMark
            case .pinned:
                VStack(spacing: 4) {
                    emptyGateMark
                    if let location = frame.marker?.location, !location.isEmpty {
                        Text(location)
                            .font(InstrumentFont.mono(6))
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
                .clipShape(RoundedRectangle(cornerRadius: 0.5))
            }
        }
        .overlay {
            if isCurrent {
                FrameCornerStroke(length: 8, lineWidth: 2)
                    .stroke(
                        AppTheme.textPrimary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter)
                    )
            }
        }
        .padding(.horizontal, gateInset)
        .frame(width: layout.frameSize.width, height: layout.frameSize.height)
    }

    private var emptyGateMark: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .strokeBorder(edgeInk.opacity(0.7), lineWidth: FilmStripFrameMetrics.strokeWidth)
            .frame(width: 11, height: 11)
    }

    private var bottomEdgeBand: some View {
        Text("\(frame.index)")
            .font(InstrumentFont.mono(6))
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
