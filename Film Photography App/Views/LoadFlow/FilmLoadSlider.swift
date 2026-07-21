import SwiftUI
import UIKit

/// Slide-to-load: empty camera chamber with a film gate you pull across.
/// Gate height matches `FilmStripView` so the swap to the loaded strip feels continuous.
struct FilmLoadSlider: View {
    let stock: FilmStock?
    var layout: FilmStripLayout = .layout(for: .format35Full, cellHeight: 110)
    var isEnabled: Bool = true
    /// When true, the film gate slides into the chamber on appear.
    var playsEntrance: Bool = false
    var onComplete: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isComplete = false
    @State private var trackWidth: CGFloat = 0
    @State private var lastSprocketIndex = 0
    @State private var haptics = FilmGateHaptics()
    @State private var entranceOffset: CGFloat = 0
    @State private var entranceReady = false

    private let sprocketTickCount = 10
    private let stroke = FilmStripFrameMetrics.strokeWidth

    private var hasRoll: Bool { stock != nil }

    private var chassisHeight: CGFloat {
        layout.frameSize.height + FilmStripFrameMetrics.chromeHeight
    }

    private var gateWidth: CGFloat {
        max(layout.frameSize.width, 44)
    }

    private var maxTravel: CGFloat {
        max(trackWidth - gateWidth, 0)
    }

    private var progress: CGFloat {
        guard hasRoll, isEnabled, maxTravel > 0 else { return 0 }
        return min(max(dragOffset / maxTravel, 0), 1)
    }

    private var displayedGateOffset: CGFloat {
        entranceReady ? dragOffset : entranceOffset
    }

    private var edgeInk: Color { AppTheme.textSecondary.opacity(0.85) }

    private var stockLabel: String {
        (stock?.name ?? "FILM").uppercased()
    }

    private var gateInset: CGFloat {
        FilmStripFrameMetrics.gateInset(forCellWidth: gateWidth)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                cameraChamber(width: width)

                if hasRoll, entranceReady, (dragOffset > 0 || isComplete) {
                    filmGate(
                        width: dragOffset + gateWidth,
                        showsMark: false,
                        dimmed: false
                    )
                    .allowsHitTesting(false)
                }

                filmGate(
                    width: gateWidth,
                    showsMark: true,
                    dimmed: !hasRoll || (!isEnabled && hasRoll)
                )
                .offset(x: displayedGateOffset)
                .opacity(isComplete ? 0.55 : 1)
                .highPriorityGesture(
                    hasRoll && isEnabled && !isComplete && entranceReady ? dragGesture : nil
                )
            }
            .frame(width: width, height: chassisHeight)
            .clipShape(Rectangle())
            .overlay {
                Rectangle()
                    .strokeBorder(AppTheme.rule, lineWidth: stroke)
            }
            .onAppear {
                trackWidth = width
                runEntranceIfNeeded()
            }
            .onChange(of: width) { _, newWidth in
                trackWidth = newWidth
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: chassisHeight)
        .opacity(isEnabled || !hasRoll ? 1 : 0.55)
        .onChange(of: stock?.id) { _, _ in
            dragOffset = 0
            isComplete = false
            lastSprocketIndex = 0
            entranceReady = false
            runEntranceIfNeeded()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasRoll ? "Slide to load roll" : "No roll selected")
        .accessibilityHint(hasRoll && isEnabled ? "Swipe right to load" : "")
        .disabled(isComplete || !isEnabled || !hasRoll || !entranceReady)
    }

    private func runEntranceIfNeeded() {
        guard playsEntrance, hasRoll, isEnabled else {
            entranceOffset = 0
            entranceReady = true
            return
        }
        entranceOffset = -gateWidth - 12
        entranceReady = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                entranceOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                entranceReady = true
                dragOffset = 0
            }
        }
    }

    // MARK: - Camera chamber

    private func cameraChamber(width: CGFloat) -> some View {
        Rectangle()
            .fill(AppTheme.bg)
            .overlay {
                Rectangle()
                    .fill(AppTheme.rule.opacity(0.35))
                    .padding(1)
            }
            .frame(width: width, height: chassisHeight)
    }

    // MARK: - Gate cell

    private func filmGate(width: CGFloat, showsMark: Bool, dimmed: Bool) -> some View {
        let inset = FilmStripFrameMetrics.gateInset(forCellWidth: min(width, gateWidth))

        return VStack(spacing: 0) {
            if layout.showsSprockets {
                sprocketRail(width: width)
            }

            Text(showsMark ? stockLabel : " ")
                .font(InstrumentFont.mono(6))
                .foregroundStyle(edgeInk)
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(height: FilmStripFrameMetrics.edgeBandHeight)
                .padding(.horizontal, inset + 1)

            ZStack {
                Rectangle()
                    .fill(Color.black)

                if width > gateWidth {
                    HStack(spacing: 0) {
                        ForEach(0..<sprocketTickCount, id: \.self) { index in
                            let notchProgress = CGFloat(index) / CGFloat(sprocketTickCount)
                            Rectangle()
                                .fill(
                                    AppTheme.rule.opacity(
                                        progress > notchProgress ? 0.95 : 0.35
                                    )
                                )
                                .frame(width: stroke)
                                .frame(maxHeight: .infinity)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if showsMark {
                    RoundedRectangle(cornerRadius: 1.5)
                        .strokeBorder(edgeInk.opacity(0.7), lineWidth: stroke)
                        .frame(width: 11, height: 11)
                }
            }
            .padding(.horizontal, inset)
            .frame(height: layout.frameSize.height)

            Color.clear
                .frame(height: FilmStripFrameMetrics.edgeBandHeight)

            if layout.showsSprockets {
                sprocketRail(width: width)
            }
        }
        .frame(width: width, height: chassisHeight, alignment: .leading)
        .background(FilmStripView.filmBase)
        .opacity(dimmed ? 0.45 : 1)
    }

    private func sprocketRail(width: CGFloat) -> some View {
        let count = max(Int(width / 12), FilmStripFrameMetrics.sprocketCount)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: FilmStripFrameMetrics.sprocketCorner)
                    .fill(FilmStripFrameMetrics.sprocketCutout)
                    .frame(
                        width: FilmStripFrameMetrics.sprocketWidth,
                        height: FilmStripFrameMetrics.sprocketHeight
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width, height: FilmStripFrameMetrics.railHeight)
        .padding(.horizontal, gateInset)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard hasRoll, isEnabled, !isComplete else { return }
                if dragOffset == 0 && value.translation.width > 0 {
                    haptics.prepare()
                    haptics.grab()
                }

                let next = min(max(value.translation.width, 0), maxTravel)
                let nextProgress = maxTravel > 0 ? next / maxTravel : 0
                let sprocket = sprocketIndex(for: nextProgress)

                if sprocket != lastSprocketIndex {
                    let advancing = sprocket > lastSprocketIndex
                    lastSprocketIndex = sprocket
                    if advancing && sprocket > 0 {
                        haptics.sprocket(progress: nextProgress)
                    }
                }

                dragOffset = next
            }
            .onEnded { _ in
                guard hasRoll, isEnabled, !isComplete else { return }
                if progress >= 0.9 {
                    complete()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        dragOffset = 0
                    }
                    lastSprocketIndex = 0
                    haptics.cancel()
                }
            }
    }

    private func sprocketIndex(for progress: CGFloat) -> Int {
        let clamped = min(max(progress, 0), 1)
        return Int((clamped * CGFloat(sprocketTickCount)).rounded(.down))
    }

    private func complete() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            dragOffset = maxTravel
            isComplete = true
        }
        haptics.lockIn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onComplete?()
        }
    }
}
