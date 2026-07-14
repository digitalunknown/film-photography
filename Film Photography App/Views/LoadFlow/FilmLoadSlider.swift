import SwiftUI
import UIKit

/// Slide-to-load control: drag the roll across a film path into the camera bay.
/// Gray stroke / fill only — film stretches as you pull.
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

    private let thumbSize: CGFloat = 52
    private let trackHeight: CGFloat = 88
    private let inset: CGFloat = 8
    private let bayWidth: CGFloat = 52
    private let sprocketCount = 12
    private let filmHeight: CGFloat = 34

    private var hasRoll: Bool { stock != nil }

    private var maxTravel: CGFloat {
        max(trackWidth - bayWidth * 2 - inset * 2, 0)
    }

    private var progress: CGFloat {
        guard hasRoll, maxTravel > 0 else { return 0 }
        return min(max(dragOffset / maxTravel, 0), 1)
    }

    var body: some View {
        ZStack {
            trackChassis
            if hasRoll {
                filmLeader
            }
            promptLabel
            HStack(spacing: 0) {
                leftBay
                Spacer(minLength: 0)
                rightBay
            }
            .padding(.horizontal, inset)
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

            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.rule.opacity(0.18))
                .padding(.vertical, 14)
                .padding(.horizontal, inset + bayWidth * 0.35)

            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(AppTheme.rule, lineWidth: 1)

            VStack {
                Rectangle()
                    .fill(AppTheme.rule)
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(AppTheme.rule)
                    .frame(height: 1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, inset + 4)
        }
    }

    // MARK: - Film leader (stretch)

    private var filmLeader: some View {
        let leaderWidth = max(dragOffset + thumbSize * 0.4, 0)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(AppTheme.rule.opacity(0.22 + progress * 0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(AppTheme.rule, lineWidth: 1)
                }
                .frame(width: leaderWidth, height: filmHeight)

            VStack {
                sprocketRow(width: leaderWidth)
                Spacer(minLength: 0)
                sprocketRow(width: leaderWidth)
            }
            .frame(width: leaderWidth, height: filmHeight)

            HStack(spacing: 0) {
                ForEach(0..<sprocketCount, id: \.self) { index in
                    let notchProgress = CGFloat(index) / CGFloat(sprocketCount)
                    Rectangle()
                        .fill(AppTheme.rule.opacity(progress > notchProgress ? 0.9 : 0.35))
                        .frame(width: 1, height: 16)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: leaderWidth, height: filmHeight)
        }
        .padding(.leading, inset + (bayWidth - thumbSize) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func sprocketRow(width: CGFloat) -> some View {
        HStack(spacing: 5) {
            let count = max(Int(width / 10), 0)
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.5)
                    .strokeBorder(AppTheme.rule, lineWidth: 1)
                    .frame(width: 4, height: 4)
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
                .foregroundStyle(AppTheme.textSecondary)
                .tracking(1.2)

            if !isComplete && hasRoll {
                Text("pull →")
                    .font(InstrumentFont.mono(10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .opacity(0.45 + 0.45 * Double(sin(progress * .pi)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, bayWidth + inset)
        .opacity(hasRoll ? (isComplete ? 1 : max(0, 1 - progress * 1.8)) : 1)
        .allowsHitTesting(false)
    }

    private var promptText: String {
        if isComplete { return "loaded" }
        if hasRoll { return prompt }
        return emptyPrompt
    }

    // MARK: - Bays (matched left / right)

    private var leftBay: some View {
        bayChrome {
            if !hasRoll {
                Text("◎")
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var rightBay: some View {
        bayChrome {
            Capsule()
                .strokeBorder(AppTheme.rule, lineWidth: 1)
                .frame(width: 3, height: 26)
                .background(
                    Capsule()
                        .fill(AppTheme.rule.opacity(isComplete || progress > 0.85 ? 0.45 : 0.2))
                )

            Text(isComplete ? "●" : "◻")
                .font(InstrumentFont.mono(10))
                .foregroundStyle(
                    isComplete || progress > 0.85
                        ? AppTheme.textSecondary
                        : AppTheme.textTertiary
                )
        }
        .scaleEffect(isComplete ? 1.02 : (progress > 0.9 ? 1.01 : 1))
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isComplete)
        .animation(.easeOut(duration: 0.12), value: progress > 0.9)
    }

    private func bayChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.bg)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(AppTheme.rule, lineWidth: 1)
                }
                .frame(width: bayWidth - 6, height: trackHeight - 20)

            VStack(spacing: 6) {
                content()
            }
        }
        .frame(width: bayWidth, height: trackHeight - 12)
        .allowsHitTesting(false)
    }

    // MARK: - Thumb

    @ViewBuilder
    private var thumb: some View {
        Group {
            if hasRoll {
                monochromeRollMark
                    .offset(x: inset + (bayWidth - thumbSize) / 2 + dragOffset)
                    .scaleEffect(isComplete ? 0.94 : 1)
                    .opacity(isComplete ? 0.55 : 1)
                    .highPriorityGesture(dragGesture)
            } else {
                Button {
                    haptics.chooseRoll()
                    onChooseRoll?()
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(AppTheme.rule, lineWidth: 1)
                        .background(AppTheme.bg)
                        .overlay {
                            Text("◎")
                                .font(InstrumentFont.mono(14))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .frame(width: thumbSize - 8, height: thumbSize - 8)
                }
                .buttonStyle(.plain)
                .offset(x: inset + (bayWidth - thumbSize) / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var monochromeRollMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.rule.opacity(0.2))
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(AppTheme.rule, lineWidth: 1)
            Text(stock?.shortCode ?? "FILM")
                .font(InstrumentFont.mono(9, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
        }
        .frame(width: thumbSize - 8, height: thumbSize - 8)
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
        }
        haptics.lockIn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onComplete?()
        }
    }
}
