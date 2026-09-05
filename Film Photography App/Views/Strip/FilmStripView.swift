import SwiftUI
import UIKit

struct FilmStripView: View {
    let roll: Roll
    let stock: FilmStock?
    @Binding var selectedFrameIndex: Int?
    var onRemoveScan: ((StripFrame) -> Void)?
    var onShiftScans: ((Int) -> Void)?
    var onOpenScan: ((StripFrame) -> Void)?
    var onFrameTap: ((StripFrame) -> Void)?

    @State private var contactSheetMode = false
    @State private var scrollPosition: Int?
    @State private var lastHapticFrame: Int?
    @State private var containerWidth: CGFloat = 0

    private let visibleFrameCount: CGFloat = 3
    private var horizontalInset: CGFloat { FilmStripFrameMetrics.stripPadding * 2 }

    /// Charcoal emulsion base — slightly above pure black so gates read darker.
    static let filmBase = AppTheme.surface

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
    }

    /// Frame the strip parks on: the one most recently exposed, so logging a frame leaves
    /// it under the brackets with the date and place the shutter just stamped on it, ready
    /// to be annotated. Frame 1 stands in until the first exposure.
    private var currentExposureFrame: Int {
        min(max(roll.frameCount, 1), max(roll.totalExposures, 1))
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
        return FilmStripLayout.layout(for: roll.format, cellHeight: FilmStripFrameMetrics.gateHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if contactSheetMode {
                FilmStripContactSheet(
                    roll: roll,
                    stock: stock,
                    selectedFrameIndex: $selectedFrameIndex,
                    onRemoveScan: onRemoveScan
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
        VStack(spacing: FilmStripFrameMetrics.railGap) {
            sprocketRail
            gateScrollView
            sprocketRail
        }
        .padding(.vertical, FilmStripFrameMetrics.stripPadding)
        .background(Self.filmBase)
        .clipShape(RoundedRectangle(cornerRadius: FilmStripFrameMetrics.stripCorner))
    }

    private var sprocketRail: some View {
        FilmSprocketRail(isVisible: layout.showsSprockets)
            .padding(.leading, FilmStripFrameMetrics.stripPadding)
    }

    private var gateScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FilmStripFrameMetrics.gateGap) {
                ForEach(frames) { frame in
                    gateCell(frame)
                        .id(frame.index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        // Centre anchor parks the active frame in the middle gate; the scroll view clamps
        // at the ends, so the first and last frames sit in the outer gates instead.
        .scrollPosition(id: $scrollPosition, anchor: .center)
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
        .frame(height: layout.frameSize.height)
        .contentMargins(.horizontal, FilmStripFrameMetrics.stripPadding, for: .scrollContent)
    }

    /// The menu is only attached to gates that actually hold a scan — an empty one would
    /// still take the long press and lift, then present nothing.
    @ViewBuilder
    private func gateCell(_ frame: StripFrame) -> some View {
        let cell = FilmStripFrameCell(
            frame: frame,
            roll: roll,
            stock: stock,
            layout: layout,
            isCurrent: frame.index == currentExposureFrame
        )
        .onTapGesture {
            selectedFrameIndex = frame.index
            onFrameTap?(frame)
            onOpenScan?(frame)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        if frame.state == .scanned, let onRemoveScan {
            cell.contextMenu {
                Button("Remove scan", lucide: .trash, role: .destructive) {
                    onRemoveScan(frame)
                }
            }
        } else {
            cell
        }
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
        HStack(spacing: AppTheme.Spacing.md) {
            Text("Scan alignment")
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Button {
                onShiftScans?(-1)
            } label: {
                LucideIcon(.chevronLeft)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shift scans back")

            Text("\(roll.scanAlignmentOffset)")
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()

            Button {
                onShiftScans?(1)
            } label: {
                LucideIcon(.chevronRight)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shift scans forward")
        }
    }
}

/// Film-strip chrome from the Figma spec: a 132pt strip built from an 84pt gate,
/// 8pt perforation bands, and 8pt padding/gutters above and below.
enum FilmStripFrameMetrics {
    /// Inset between the strip edge and the perforation bands.
    static let stripPadding: CGFloat = AppTheme.Spacing.sm
    /// Perforation band height.
    static let railHeight: CGFloat = 8
    /// Gutter between a perforation band and the gate.
    static let railGap: CGFloat = AppTheme.Spacing.sm
    /// Perforations are 12×8 on a fixed 20pt pitch, clipped at the strip edge.
    static let sprocketWidth: CGFloat = 12
    static let sprocketHeight: CGFloat = 8
    static let sprocketPitch: CGFloat = 20
    static let sprocketCorner: CGFloat = 1
    /// Gate interior: 4pt corners, 8pt gutter between exposures.
    static let gateHeight: CGFloat = 84
    static let gateGap: CGFloat = AppTheme.Spacing.sm
    static let gateCorner: CGFloat = AppTheme.Spacing.xs
    /// Corner brackets marking the current exposure.
    static let bracketArm: CGFloat = 16
    static let bracketWidth: CGFloat = 2
    static let stripCorner: CGFloat = AppTheme.Spacing.sm
    /// Hairline strokes for strip chrome (1 display pixel).
    static var strokeWidth: CGFloat { 1 / max(UIScreen.main.scale, 1) }
    /// Cut-out perforation color — matches the page behind the strip.
    static let sprocketCutout = AppTheme.bg

    static var chromeHeight: CGFloat { (stripPadding + railHeight + railGap) * 2 }
}

/// Continuous perforation band. Holes keep a fixed pitch regardless of gate width so
/// they line up across the whole strip, and the run clips mid-hole at the trailing edge.
/// Drawn in a `Canvas` so the overflowing run never widens the surrounding layout.
struct FilmSprocketRail: View {
    var isVisible: Bool = true

    var body: some View {
        Canvas { context, size in
            guard isVisible else { return }
            var x: CGFloat = 0
            while x < size.width {
                let hole = CGRect(
                    x: x,
                    y: 0,
                    width: FilmStripFrameMetrics.sprocketWidth,
                    height: FilmStripFrameMetrics.sprocketHeight
                )
                context.fill(
                    Path(roundedRect: hole, cornerRadius: FilmStripFrameMetrics.sprocketCorner),
                    with: .color(FilmStripFrameMetrics.sprocketCutout)
                )
                x += FilmStripFrameMetrics.sprocketPitch
            }
        }
        .frame(height: FilmStripFrameMetrics.railHeight)
    }
}

/// Corner marks for a framed gate. Each mark runs `length` along both edges and turns on
/// `cornerRadius`, so the stroke stays concentric with a rounded frame's edge. Leave the
/// radius at zero for square gates like the film-strip exposures.
struct FrameCornerStroke: Shape {
    var length: CGFloat = 8
    var lineWidth: CGFloat = 2
    var cornerRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        // The stroke is centred on the path, so pull it half a line inside the frame edge.
        let inset = lineWidth / 2
        let box = rect.insetBy(dx: inset, dy: inset)
        let arm = min(length, min(box.width, box.height) / 2)
        let radius = min(max(cornerRadius - inset, 0), arm)

        var path = Path()

        // Top-left
        path.move(to: CGPoint(x: box.minX, y: box.minY + arm))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addCorner(
            center: CGPoint(x: box.minX + radius, y: box.minY + radius),
            radius: radius,
            from: .degrees(180),
            to: .degrees(270)
        )
        path.addLine(to: CGPoint(x: box.minX + arm, y: box.minY))

        // Top-right
        path.move(to: CGPoint(x: box.maxX - arm, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addCorner(
            center: CGPoint(x: box.maxX - radius, y: box.minY + radius),
            radius: radius,
            from: .degrees(270),
            to: .degrees(360)
        )
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + arm))

        // Bottom-right
        path.move(to: CGPoint(x: box.maxX, y: box.maxY - arm))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addCorner(
            center: CGPoint(x: box.maxX - radius, y: box.maxY - radius),
            radius: radius,
            from: .degrees(0),
            to: .degrees(90)
        )
        path.addLine(to: CGPoint(x: box.maxX - arm, y: box.maxY))

        // Bottom-left
        path.move(to: CGPoint(x: box.minX + arm, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addCorner(
            center: CGPoint(x: box.minX + radius, y: box.maxY - radius),
            radius: radius,
            from: .degrees(90),
            to: .degrees(180)
        )
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - arm))

        return path
    }
}

private extension Path {
    /// Arc that degrades to a sharp corner when the radius is zero.
    mutating func addCorner(center: CGPoint, radius: CGFloat, from: Angle, to: Angle) {
        guard radius > 0 else { return }
        addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
    }
}

private struct FilmStripFrameCell: View {
    let frame: StripFrame
    let roll: Roll
    let stock: FilmStock?
    let layout: FilmStripLayout
    var isCurrent: Bool = false

    var body: some View {
        gateArea
    }

    @ViewBuilder
    private var gateArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FilmStripFrameMetrics.gateCorner)
                .fill(AppTheme.bg)

            switch frame.state {
            case .unexposed:
                emptyGateMark
            case .exposed, .pinned:
                exposedGateMark
            case .scanned:
                Group {
                    if let fileName = frame.scanFileName,
                       let image = ScanStorage.thumbnail(
                           for: roll.id,
                           fileName: fileName,
                           maxSize: 400,
                           laidOnSide: true
                       ) {
                        GeometryReader { geo in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        AppTheme.textPrimary.opacity(0.06)
                        exposedGateMark
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .frame(width: layout.frameSize.width, height: layout.frameSize.height)
        .clipShape(RoundedRectangle(cornerRadius: FilmStripFrameMetrics.gateCorner))
        .overlay {
            if isCurrent {
                FrameCornerStroke(
                    length: FilmStripFrameMetrics.bracketArm,
                    lineWidth: FilmStripFrameMetrics.bracketWidth,
                    cornerRadius: FilmStripFrameMetrics.gateCorner
                )
                .stroke(
                    AppTheme.textPrimary,
                    style: StrokeStyle(
                        lineWidth: FilmStripFrameMetrics.bracketWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    /// A gate still waiting to be shot.
    private var emptyGateMark: some View {
        LucideIcon(.scan)
            .foregroundStyle(isCurrent ? AppTheme.textPrimary : AppTheme.textSecondary)
    }

    /// A frame the shutter has already advanced past. It reads as filled even without a
    /// scan on it, so it gets the tick rather than the empty gate's framing marks.
    private var exposedGateMark: some View {
        LucideIcon(.squareCheck)
            .foregroundStyle(AppTheme.textPrimary)
    }
}

struct FilmStripContactSheet: View {
    let roll: Roll
    let stock: FilmStock?
    @Binding var selectedFrameIndex: Int?
    var onRemoveScan: ((StripFrame) -> Void)?

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 100), spacing: 4)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(frames) { frame in
                tick(frame)
            }
        }
    }

    @ViewBuilder
    private func tick(_ frame: StripFrame) -> some View {
        let mark = MiniFrameTick(frame: frame, roll: roll, stock: stock, size: 72)
            .onTapGesture { selectedFrameIndex = frame.index }

        if frame.state == .scanned, let onRemoveScan {
            mark.contextMenu {
                Button("Remove scan", lucide: .trash, role: .destructive) {
                    onRemoveScan(frame)
                }
            }
        } else {
            mark
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
                Circle().fill(AppTheme.textPrimary.opacity(0.5)).frame(width: 3, height: 3)
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
        case .unexposed: AppTheme.bg.opacity(0.6)
        case .exposed: AppTheme.textPrimary.opacity(0.25)
        case .pinned: AppTheme.textPrimary.opacity(0.45)
        case .scanned: AppTheme.textPrimary.opacity(0.7)
        }
    }
}
