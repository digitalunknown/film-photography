import SwiftUI
import UIKit

/// Cohesive pipeline experience: a stage strip plus the same slide-to-gate
/// interaction as loading film. Inventory rolls keep `FilmLoadSlider` instead.
struct PipelineRailView: View {
    let status: RollStatus
    let stock: FilmStock?
    var canRevert: Bool = false
    var onAdvance: () -> Void
    var onRevert: (() -> Void)?

    private var emulsion: Color {
        stock?.emulsionTint ?? AppTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            PipelineStageStrip(status: status, emulsion: emulsion)

            if status.isInventory {
                inventoryHint
            } else if let prompt = status.pipelineSlidePrompt, let next = status.nextStatus {
                PipelineAdvanceSlider(
                    stock: stock,
                    prompt: prompt,
                    gateLabel: next.pipelineNodeLabel.uppercased(),
                    onComplete: onAdvance
                )
                .id("\(status.rawValue)-\(stock?.id.uuidString ?? "none")")
            } else {
                completedHint
            }

            if canRevert, let onRevert, let previous = status.previousStatus {
                Button(action: onRevert) {
                    Text("← Back to \(previous.displayName)")
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inventoryHint: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("◎")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textTertiary)
            Text("Pull the roll into a camera above to advance.")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var completedHint: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("●")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(emulsion)
            Text("Roll archived — end of the line.")
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

// MARK: - Stage strip

private struct PipelineStageStrip: View {
    let status: RollStatus
    let emulsion: Color

    private let stages = RollStatus.railCases

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            GeometryReader { geo in
                let count = stages.count
                let spacing = geo.size.width / CGFloat(max(count - 1, 1))

                ZStack(alignment: .leading) {
                    // Base rail
                    Capsule()
                        .fill(AppTheme.rule)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: 5)

                    // Progress fill
                    Capsule()
                        .fill(emulsion.opacity(0.85))
                        .frame(width: max(progressWidth(in: geo.size.width), 0), height: 2)
                        .offset(y: 5)

                    HStack(spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                            stageNode(stage, index: index)
                                .frame(width: index == count - 1 ? 12 : spacing, alignment: .leading)
                        }
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    Text(stage.pipelineNodeLabel.uppercased())
                        .font(InstrumentFont.mono(8))
                        .foregroundStyle(labelColor(for: stage))
                        .tracking(0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == stages.count - 1 ? .trailing : .center))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pipeline status \(status.displayName)")
    }

    private func progressWidth(in total: CGFloat) -> CGFloat {
        guard let index = stages.firstIndex(of: status.normalized) else { return 0 }
        guard stages.count > 1 else { return 0 }
        return total * CGFloat(index) / CGFloat(stages.count - 1)
    }

    private func stageNode(_ stage: RollStatus, index: Int) -> some View {
        let current = status.normalized
        let isCurrent = stage == current
        let isPast = stage < current

        return ZStack {
            Circle()
                .fill(AppTheme.bg)
                .frame(width: isCurrent ? 12 : 10, height: isCurrent ? 12 : 10)
            Circle()
                .strokeBorder(
                    isCurrent || isPast ? emulsion : AppTheme.rule,
                    lineWidth: isCurrent ? 2 : 1
                )
                .frame(width: isCurrent ? 12 : 10, height: isCurrent ? 12 : 10)
            if isPast || isCurrent {
                Circle()
                    .fill(emulsion)
                    .frame(width: isCurrent ? 5 : 4, height: isCurrent ? 5 : 4)
            }
        }
        .frame(width: 12, height: 12, alignment: .leading)
    }

    private func labelColor(for stage: RollStatus) -> Color {
        let current = status.normalized
        if stage == current { return AppTheme.textPrimary }
        if stage < current { return AppTheme.textSecondary }
        return AppTheme.textTertiary
    }
}

// MARK: - Slide to advance (same language as FilmLoadSlider)

private struct PipelineAdvanceSlider: View {
    let stock: FilmStock?
    let prompt: String
    let gateLabel: String
    var onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isComplete = false
    @State private var trackWidth: CGFloat = 0
    @State private var lastSprocketIndex = 0
    @State private var haptics = FilmGateHaptics()

    private let thumbSize: CGFloat = 52
    private let trackHeight: CGFloat = 76
    private let inset: CGFloat = 6
    private let gateWidth: CGFloat = 64
    private let sprocketCount = 10

    private var maxTravel: CGFloat {
        max(trackWidth - thumbSize - gateWidth - inset * 2, 0)
    }

    private var progress: CGFloat {
        guard maxTravel > 0 else { return 0 }
        return min(max(dragOffset / maxTravel, 0), 1)
    }

    private var emulsion: Color {
        stock?.emulsionTint ?? AppTheme.textSecondary
    }

    var body: some View {
        ZStack(alignment: .leading) {
            chassis
            filmLeader
            promptLabel
            gate
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
        .disabled(isComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prompt)
        .accessibilityHint("Swipe right to advance")
    }

    private var chassis: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(AppTheme.bg)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.03))
                .padding(.vertical, 10)
                .padding(.leading, inset)
                .padding(.trailing, gateWidth - 4)
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(AppTheme.rule, lineWidth: 0.5)
            VStack {
                Rectangle().fill(AppTheme.rule.opacity(0.85)).frame(height: 1)
                Spacer()
                Rectangle().fill(AppTheme.rule.opacity(0.85)).frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.trailing, gateWidth * 0.45)
        }
    }

    private var filmLeader: some View {
        let leaderWidth = max(dragOffset + thumbSize * 0.35, 0)
        return RoundedRectangle(cornerRadius: 1)
            .fill(
                LinearGradient(
                    colors: [
                        emulsion.opacity(0.12 + progress * 0.18),
                        emulsion.opacity(0.32 + progress * 0.35),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: leaderWidth, height: 28)
            .padding(.leading, inset)
            .allowsHitTesting(false)
    }

    private var promptLabel: some View {
        VStack(spacing: 2) {
            Text(isComplete ? "advanced" : prompt)
                .font(InstrumentFont.mono(11))
                .foregroundStyle(isComplete ? emulsion : AppTheme.textSecondary)
                .tracking(1.0)
            if !isComplete {
                Text("pull →")
                    .font(InstrumentFont.mono(10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .opacity(0.5 + 0.5 * Double(sin(progress * .pi)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, thumbSize + AppTheme.Spacing.sm)
        .padding(.trailing, gateWidth)
        .opacity(isComplete ? 1 : max(0, 1 - progress * 1.8))
        .allowsHitTesting(false)
    }

    private var gate: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(gateLabel)
                    .font(InstrumentFont.mono(9, weight: .bold))
                    .foregroundStyle(progress > 0.85 || isComplete ? AppTheme.textPrimary : AppTheme.textTertiary)
                    .tracking(0.6)
                Capsule()
                    .fill(AppTheme.rule)
                    .frame(width: 3, height: 22)
                    .overlay(
                        Capsule()
                            .fill(emulsion.opacity(0.15 + progress * 0.55))
                    )
            }
            .frame(width: gateWidth - 10, height: trackHeight - 16)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        progress > 0.8 || isComplete ? emulsion.opacity(0.6) : AppTheme.rule,
                        lineWidth: isComplete ? 1.25 : 0.75
                    )
            )
            .padding(.trailing, inset + 2)
            .scaleEffect(isComplete ? 1.04 : (progress > 0.9 ? 1.02 : 1.0))
        }
        .allowsHitTesting(false)
    }

    private var thumb: some View {
        Group {
            if let stock {
                RollPlate(stock: stock, size: thumbSize - 10)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(
                                        progress > 0.85 || isComplete ? emulsion.opacity(0.85) : AppTheme.rule,
                                        lineWidth: isComplete ? 1.25 : 0.5
                                    )
                            )
                    )
                    .shadow(color: emulsion.opacity(progress * 0.22), radius: 6, y: 0)
                    .offset(x: inset + dragOffset)
                    .scaleEffect(isComplete ? 0.9 : 1)
                    .opacity(isComplete ? 0.5 : 1)
                    .highPriorityGesture(dragGesture)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(AppTheme.rule, lineWidth: 0.5)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Text("→")
                            .font(InstrumentFont.mono(14))
                            .foregroundStyle(AppTheme.textSecondary)
                    )
                    .offset(x: inset + dragOffset)
                    .highPriorityGesture(dragGesture)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isComplete else { return }
                if dragOffset == 0 && value.translation.width > 0 {
                    haptics.prepare()
                    haptics.grab()
                }
                let next = min(max(value.translation.width, 0), maxTravel)
                let nextProgress = maxTravel > 0 ? next / maxTravel : 0
                let sprocket = Int((min(max(nextProgress, 0), 1) * CGFloat(sprocketCount)).rounded(.down))
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
                guard !isComplete else { return }
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

    private func complete() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            dragOffset = maxTravel
            isComplete = true
        }
        haptics.lockIn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onComplete()
        }
    }
}

/// Shared gate haptics for load + advance slides.
final class FilmGateHaptics {
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    func prepare() {
        soft.prepare()
        light.prepare()
        medium.prepare()
        rigid.prepare()
        notify.prepare()
        selection.prepare()
    }

    func grab() {
        soft.impactOccurred(intensity: 0.55)
        soft.prepare()
    }

    func chooseRoll() {
        light.impactOccurred(intensity: 0.7)
    }

    func sprocket(progress: CGFloat) {
        let p = min(max(progress, 0), 1)
        if p < 0.35 {
            selection.selectionChanged()
            selection.prepare()
        } else if p < 0.7 {
            light.impactOccurred(intensity: 0.45 + 0.35 * p)
            light.prepare()
        } else if p < 0.9 {
            medium.impactOccurred(intensity: 0.55 + 0.35 * p)
            medium.prepare()
        } else {
            rigid.impactOccurred(intensity: 0.85)
            rigid.prepare()
        }
    }

    func cancel() {
        soft.impactOccurred(intensity: 0.4)
    }

    func lockIn() {
        rigid.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [notify] in
            notify.notificationOccurred(.success)
        }
    }
}
