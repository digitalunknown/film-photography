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

    private var frames: [StripFrame] {
        StripFrameBuilder.frames(for: roll)
    }

    private var layout: FilmStripLayout {
        FilmStripLayout.layout(for: roll.format)
    }

    private var baseColor: Color {
        stock?.stripBaseColor ?? Color(red: 0.141, green: 0.075, blue: 0.035)
    }

    private var edgeColor: Color {
        stock?.stripEdgePrintColor ?? Color(red: 0.85, green: 0.62, blue: 0.28)
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
                        baseColor: baseColor,
                        edgeColor: edgeColor,
                        isSelected: selectedFrameIndex == frame.index
                    )
                    .id(frame.index)
                    .onTapGesture {
                        selectedFrameIndex = frame.index
                        onFrameTap?(frame)
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
        .frame(height: layout.frameSize.height + 36)
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

private struct FilmStripFrameCell: View {
    let frame: StripFrame
    let roll: Roll
    let stock: FilmStock?
    let layout: FilmStripLayout
    let baseColor: Color
    let edgeColor: Color
    let isSelected: Bool

    private let railHeight: CGFloat = 10
    private let edgeBandHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            sprocketRail
            topEdgeMarking
            frameArea
            bottomEdgeMarking
            sprocketRail
        }
        .frame(width: layout.frameSize.width)
        .background(baseColor)
        .overlay {
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var sprocketRail: some View {
        if layout.showsSprockets {
            HStack(spacing: layout.frameSize.width / 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 6, height: 4)
                }
            }
            .frame(height: railHeight)
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: 2)
        }
    }

    private var topEdgeMarking: some View {
        Text(stock?.stripEdgeLabel ?? "FILM →")
            .font(InstrumentFont.mono(6))
            .foregroundStyle(edgeColor.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(height: edgeBandHeight)
            .frame(maxWidth: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var frameArea: some View {
        ZStack {
            frameBackground

            switch frame.state {
            case .unexposed:
                Text(String(format: "%02d", frame.index))
                    .font(InstrumentFont.mono(10))
                    .foregroundStyle(Color.white.opacity(0.12))
            case .exposed:
                Text(String(format: "%02d", frame.index))
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(Color.white.opacity(0.35))
            case .pinned:
                VStack(spacing: 4) {
                    Text("◎")
                        .font(InstrumentFont.mono(14))
                        .foregroundStyle(edgeColor.opacity(0.9))
                    if let location = frame.marker?.location, !location.isEmpty {
                        Text(location)
                            .font(InstrumentFont.mono(7))
                            .foregroundStyle(edgeColor.opacity(0.7))
                            .lineLimit(1)
                    } else if let marker = frame.marker {
                        Text(DateFormatters.short.string(from: marker.timestamp))
                            .font(InstrumentFont.mono(7))
                            .foregroundStyle(edgeColor.opacity(0.7))
                    }
                }
            case .scanned:
                if let fileName = frame.scanFileName,
                   let image = ScanStorage.thumbnail(for: roll.id, fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.15)
                }
            }
        }
        .frame(width: layout.frameSize.width, height: layout.frameSize.height)
        .clipped()
    }

    private var frameBackground: Color {
        switch frame.state {
        case .unexposed: baseColor.opacity(0.95)
        case .exposed: baseColor.opacity(0.85)
        case .pinned: baseColor.opacity(0.75)
        case .scanned: baseColor
        }
    }

    private var bottomEdgeMarking: some View {
        HStack {
            Text(frame.negativeNotation)
                .font(InstrumentFont.mono(6))
                .foregroundStyle(edgeColor.opacity(0.8))
            Spacer()
            if frame.state == .pinned || (frame.state == .scanned && frame.marker != nil) {
                if let marker = frame.marker, let label = telemetryLabel(for: marker) {
                    Text(label)
                        .font(InstrumentFont.mono(6))
                        .foregroundStyle(edgeColor.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(height: edgeBandHeight)
    }

    private func telemetryLabel(for marker: FrameMarker) -> String? {
        var parts: [String] = []
        if let location = marker.location, !location.isEmpty {
            parts.append(location)
        }
        parts.append("◎")
        if let exposure = ExposureFormat.exposure(aperture: marker.aperture, shutterSpeed: marker.shutterSpeed) {
            parts.append(exposure)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
