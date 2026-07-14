import SwiftUI
import UIKit

/// Slide-to-load control: drag the canister across a film path into the camera mouth.
/// Sprocket bumps along the drag, then a lock-in tick.
/// When `stock` is nil, shows an empty bay — tap to choose a roll.
struct FilmLoadSlider: View {
    let stock: FilmStock?
    let cameraName: String
    var prompt: String = "slide to load"
    var emptyPrompt: String = "choose a roll"
    var onChooseRoll: (() -> Void)?
    var onComplete: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isComplete = false
    @State private var trackWidth: CGFloat = 0
    @State private var lastSprocketIndex = 0
    @State private var haptics = FilmGateHaptics()
    @State private var gatePulse = false

    private let thumbSize: CGFloat = 56
    private let trackHeight: CGFloat = 88
    private let inset: CGFloat = 6
    private let cameraBayWidth: CGFloat = 52
    private let sprocketCount = 12

    private var hasRoll: Bool { stock != nil }

    private var maxTravel: CGFloat {
        max(trackWidth - thumbSize - cameraBayWidth - inset * 2, 0)
    }

    private var progress: CGFloat {
        guard hasRoll, maxTravel > 0 else { return 0 }
        return min(max(dragOffset / maxTravel, 0), 1)
    }

    private var emulsion: Color {
        stock?.emulsionTint ?? AppTheme.textTertiary
    }

    var body: some View {
        ZStack(alignment: .leading) {
            trackChassis
            filmPathGuides
            if hasRoll {
                filmLeader
            }
            promptLabel
            cameraMouth
            thumb
        }
        .frame(height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { trackWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in
                        trackWidth = width
                    }
            }
        )
        .onChange(of: stock?.id) { _, _ in
            dragOffset = 0
            isComplete = false
            lastSprocketIndex = 0
            gatePulse = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            hasRoll
                ? "Load \(stock?.name ?? "roll") into \(cameraName)"
                : "Choose a roll to load into \(cameraName)"
        )
        .accessibilityHint(hasRoll ? "Swipe right to load" : "Double tap to choose a roll")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if !hasRoll { onChooseRoll?() }
        }
        .disabled(isComplete)
    }

    // MARK: - Chassis

    private var trackChassis: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(AppTheme.bg)

            // Inner well — film channel
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.03))
                .padding(.vertical, 10)
                .padding(.leading, inset)
                .padding(.trailing, cameraBayWidth - 4)

            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(AppTheme.rule, lineWidth: 0.5)

            // Top & bottom rails
            VStack {
                Rectangle()
                    .fill(AppTheme.rule.opacity(0.85))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(AppTheme.rule.opacity(0.85))
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.trailing, cameraBayWidth * 0.55)
        }
    }

    private var filmPathGuides: some View {
        HStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                Capsule()
                    .fill(AppTheme.rule.opacity(hasRoll ? 0.35 : 0.55))
                    .frame(width: 14, height: 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, thumbSize + AppTheme.Spacing.sm)
        .padding(.trailing, cameraBayWidth + AppTheme.Spacing.sm)
        .opacity(hasRoll ? max(0, 0.7 - progress * 0.9) : 0.8)
        .allowsHitTesting(false)
    }

    // MARK: - Film leader with sprockets

    private var filmLeader: some View {
        let leaderWidth = max(dragOffset + thumbSize * 0.35, 0)
        return ZStack(alignment: .leading) {
            // Emulsion body
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [
                            emulsion.opacity(0.15 + progress * 0.2),
                            emulsion.opacity(0.35 + progress * 0.35),
                            emulsion.opacity(0.22 + progress * 0.25),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: leaderWidth, height: 36)

            // Sprocket perforations — top & bottom rows
            VStack {
                sprocketRow(width: leaderWidth)
                Spacer(minLength: 0)
                sprocketRow(width: leaderWidth)
            }
            .frame(width: leaderWidth, height: 36)

            // Frame divider ticks along the leader
            HStack(spacing: 0) {
                ForEach(0..<sprocketCount, id: \.self) { index in
                    let notchProgress = CGFloat(index) / CGFloat(sprocketCount)
                    Rectangle()
                        .fill(AppTheme.bg.opacity(0.45))
                        .frame(width: 1, height: 18)
                        .opacity(progress > notchProgress ? 0.9 : 0.25)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: leaderWidth, height: 36)
            .opacity(0.7)
        }
        .padding(.leading, inset)
        .frame(maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private func sprocketRow(width: CGFloat) -> some View {
        HStack(spacing: 5) {
            let count = max(Int(width / 10), 0)
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(AppTheme.bg.opacity(0.75))
                    .frame(width: 4, height: 5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    // MARK: - Prompt

    private var promptLabel: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text(promptText)
                .font(InstrumentFont.mono(11))
                .foregroundStyle(isComplete ? emulsion : AppTheme.textSecondary)
                .tracking(1.2)

            if !isComplete && hasRoll {
                Text("pull →")
                    .font(InstrumentFont.mono(10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .opacity(0.5 + 0.5 * Double(sin(progress * .pi)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, thumbSize + AppTheme.Spacing.sm)
        .padding(.trailing, cameraBayWidth)
        .opacity(hasRoll ? (isComplete ? 1 : max(0, 1 - progress * 1.8)) : 1)
        .allowsHitTesting(false)
    }

    private var promptText: String {
        if isComplete { return "loaded" }
        if hasRoll { return prompt }
        return emptyPrompt
    }

    // MARK: - Camera mouth

    private var cameraMouth: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                // Camera body bay
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(
                                progress > 0.8 || isComplete
                                    ? emulsion.opacity(0.55 + (gatePulse ? 0.35 : 0))
                                    : AppTheme.rule,
                                lineWidth: isComplete ? 1.25 : 0.75
                            )
                    )
                    .frame(width: cameraBayWidth - 8, height: trackHeight - 16)
                    .shadow(color: emulsion.opacity(isComplete ? 0.35 : progress * 0.2), radius: isComplete ? 10 : 4)

                VStack(spacing: 6) {
                    // Film slot
                    Capsule()
                        .fill(AppTheme.rule)
                        .frame(width: 3, height: 28)
                        .overlay(
                            Capsule()
                                .fill(emulsion.opacity(0.15 + progress * 0.55))
                        )

                    Text(isComplete ? "●" : "◻")
                        .font(InstrumentFont.mono(10))
                        .foregroundStyle(
                            isComplete || progress > 0.85
                                ? AppTheme.textPrimary
                                : AppTheme.textTertiary
                        )
                }
            }
            .padding(.trailing, inset + 2)
            .scaleEffect(isComplete ? 1.04 : (progress > 0.9 ? 1.02 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isComplete)
            .animation(.easeOut(duration: 0.12), value: progress > 0.9)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Thumb / canister

    @ViewBuilder
    private var thumb: some View {
        Group {
            if let stock {
                ZStack {
                    // Soft glow under the moving roll
                    Circle()
                        .fill(emulsion.opacity(0.12 + progress * 0.2))
                        .blur(radius: 10)
                        .frame(width: thumbSize, height: thumbSize)

                    RollPlate(stock: stock, size: thumbSize - 10)
                        .padding(5)
                        .background(thumbChrome(active: true))
                }
                .offset(x: inset + dragOffset)
                .scaleEffect(isComplete ? 0.92 : 1.0 - progress * 0.04)
                .opacity(isComplete ? 0.55 : 1)
                .highPriorityGesture(dragGesture)
            } else {
                Button {
                    haptics.chooseRoll()
                    onChooseRoll?()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 1)
                            .strokeBorder(AppTheme.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: thumbSize - 10, height: thumbSize - 10)
                        Text("◎")
                            .font(InstrumentFont.mono(16))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(5)
                    .background(thumbChrome(active: false))
                }
                .buttonStyle(.plain)
                .offset(x: inset)
            }
        }
    }

    private func thumbChrome(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(AppTheme.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        active && (isComplete || progress > 0.85)
                            ? emulsion.opacity(0.85)
                            : AppTheme.rule,
                        lineWidth: active && isComplete ? 1.25 : 0.5
                    )
            )
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard hasRoll, !isComplete else { return }
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
                guard hasRoll, !isComplete else { return }
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
        return Int((clamped * CGFloat(sprocketCount)).rounded(.down))
    }

    private func complete() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            dragOffset = maxTravel
            isComplete = true
            gatePulse = true
        }
        haptics.lockIn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onComplete?()
        }
    }
}
