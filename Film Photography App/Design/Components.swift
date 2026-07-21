import SwiftUI
import UIKit

// MARK: - Structure

struct HairlineRule: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.rule)
            .frame(height: 0.5)
    }
}

/// Stronger rule between detail sections.
struct SectionRule: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.textPrimary)
            .frame(height: 2)
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "+"

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(InstrumentFont.display(32, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(InstrumentFont.mono(20))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(AppTheme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(InstrumentFont.mono(12, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .tracking(1.0)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    var valueBright: Bool = true
    var showsDivider: Bool = true

    var body: some View {
        InstrumentRow(label: label, showsDivider: showsDivider) {
            Text(value)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(valueBright ? AppTheme.textPrimary : AppTheme.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Label on the left half; detail starts at center and stays left-aligned (Polestar-style spec row).
struct InstrumentRow<Trailing: View>: View {
    let label: String
    var showsDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                HairlineRule()
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Text(label)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                trailing()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }
}

/// Menu-style dropdown row with label left, value in the detail column.
struct InstrumentMenuRow<MenuContent: View>: View {
    let label: String
    let value: String
    var valueBright: Bool = true
    var showsDivider: Bool = true
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        InstrumentRow(label: label, showsDivider: showsDivider) {
            Menu {
                menuContent()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(value)
                        .font(InstrumentFont.mono(12))
                        .foregroundStyle(valueBright ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(InstrumentFont.mono(9, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Label left, editable control in the detail column.
struct InstrumentEditableRow<Content: View>: View {
    let label: String
    var showsDivider: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        InstrumentRow(label: label, showsDivider: showsDivider) {
            content()
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// Hero content above the first detail section (strip, photo, metrics).
struct DetailHeroBlock<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            content()
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }
}

struct LedgerRowHeader: View {
    let glyph: String
    let primary: String
    let secondary: String?
    let value: String
    var valueSecondary: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            Text(glyph)
                .font(InstrumentFont.mono(11))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(primary)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let secondary {
                    Text(secondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                Text(value)
                    .font(InstrumentFont.mono(13))
                    .foregroundStyle(AppTheme.textPrimary)
                if let valueSecondary {
                    Text(valueSecondary)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}

struct DisclosureBlock<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                content()
            }
            .padding(.leading, 22)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xs)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct TextAction: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.rule)
        }
        .buttonStyle(.plain)
    }
}

struct InstrumentEmptyState: View {
    let message: String
    var primaryAction: String
    var primaryHandler: () -> Void
    var secondaryAction: String? = nil
    var secondaryHandler: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(message)
                .font(InstrumentFont.mono(13))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                TextAction(label: primaryAction, action: primaryHandler)
                if let secondaryAction, let secondaryHandler {
                    TextAction(label: secondaryAction, action: secondaryHandler)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 48)
    }
}

struct FilterChipRow: View {
    let options: [String]
    @Binding var selection: String
    /// Sentinel for “no filter” (not shown as a chip).
    var clearValue: String
    /// When set, returns a brand tint — or `nil` for the neutral type-chip style.
    var tintForOption: ((String) -> Color?)? = nil

    @Namespace private var chipNamespace

    private var isFiltered: Bool {
        selection != clearValue && options.contains(selection)
    }

    private var visibleOptions: [String] {
        isFiltered ? [selection] : options
    }

    private var chipAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(visibleOptions, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        withAnimation(chipAnimation) {
                            if isSelected {
                                selection = clearValue
                            } else {
                                selection = option
                            }
                        }
                    } label: {
                        chipLabel(
                            option: option,
                            isSelected: isSelected,
                            showsClear: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: option, in: chipNamespace)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading))
                        )
                    )
                    .accessibilityLabel(option)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .animation(chipAnimation, value: selection)
            .animation(chipAnimation, value: options)
        }
    }

    @ViewBuilder
    private func chipLabel(option: String, isSelected: Bool, showsClear: Bool) -> some View {
        let content = HStack(spacing: 6) {
            if showsClear {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(option)
                .font(InstrumentFont.mono(12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)

        if let tintForOption, let tint = tintForOption(option) {
            content
                .foregroundStyle(tint)
                .background(tint.opacity(isSelected ? 0.22 : 0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(tint.opacity(isSelected ? 0.85 : 0.55), lineWidth: 1)
                )
        } else {
            content
                .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                .background(
                    (isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .opacity(isSelected ? 0.10 : 0.06),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            (isSelected ? AppTheme.textPrimary : AppTheme.textTertiary)
                                .opacity(isSelected ? 0.45 : 0.55),
                            lineWidth: 1
                        )
                )
        }
    }
}

struct UnderlineMeter: View {
    let label: String
    let value: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(InstrumentFont.mono(12))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.rule).frame(height: 0.5)
                    Rectangle().fill(AppTheme.textPrimary).frame(width: geo.size.width * progress, height: 0.5)
                }
            }
            .frame(height: 0.5)
        }
    }
}

/// Segmented frame tally — one tick per exposure, filled for frames shot.
struct FrameExposureCounter: View {
    let shot: Int
    let total: Int
    var showsSegmentBar: Bool = true
    var onIncrement: (() -> Void)? = nil
    var onDecrement: (() -> Void)? = nil
    var onSetCount: ((Int) -> Void)? = nil

    @State private var scrubShot: Int?
    @State private var lastScrubbed: Int?

    private var safeTotal: Int { max(total, 1) }
    private var safeShot: Int { min(max(shot, 0), safeTotal) }
    private var displayedShot: Int { scrubShot ?? safeShot }
    private var remaining: Int { max(safeTotal - displayedShot, 0) }
    private var canIncrement: Bool { remaining > 0 && onIncrement != nil }
    private var canDecrement: Bool {
        displayedShot > 0 && (onDecrement != nil || onSetCount != nil)
    }
    private var canScrub: Bool { onSetCount != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        VerticalSpinnerNumber(
                            value: displayedShot,
                            font: InstrumentFont.mono(36, weight: .bold),
                            color: AppTheme.textPrimary,
                            digitHeight: 40
                        )
                        Text("/\(safeTotal)")
                            .font(InstrumentFont.mono(16))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }

                    Text(statusLabel)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: statusLabel)
                }

                Spacer(minLength: AppTheme.Spacing.sm)

                HStack(spacing: AppTheme.Spacing.md) {
                    undoButton
                    shutterButton
                }
            }

            if showsSegmentBar {
                segmentBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayedShot) of \(safeTotal) frames shot")
        .onChange(of: shot) { _, _ in
            scrubShot = nil
            lastScrubbed = nil
        }
    }

    private var statusLabel: String {
        if displayedShot <= 0 { return "unexposed" }
        if remaining <= 0 { return "finished" }
        return remaining == 1 ? "1 left" : "\(remaining) left"
    }

    private var undoButton: some View {
        Button {
            guard canDecrement else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                if let onDecrement {
                    onDecrement()
                } else {
                    onSetCount?(max(displayedShot - 1, 0))
                }
            }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.rule, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canDecrement)
        .opacity(canDecrement ? 1 : 0.28)
        .accessibilityLabel("Undo exposure")
        .accessibilityHint(canDecrement ? "Steps frames shot back by one" : "No exposures to undo")
    }

    private var shutterButton: some View {
        let progress = CGFloat(displayedShot) / CGFloat(safeTotal)
        let ringSize: CGFloat = 54
        let buttonSize: CGFloat = 44
        let ringLine: CGFloat = 3

        return Button {
            guard canIncrement else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                onIncrement?()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(AppTheme.rule, lineWidth: ringLine)
                    .frame(width: ringSize, height: ringSize)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AppTheme.textPrimary,
                        style: StrokeStyle(lineWidth: ringLine, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
                    .animation(.easeOut(duration: 0.2), value: displayedShot)

                Circle()
                    .fill(AppTheme.textPrimary)
                    .frame(width: buttonSize, height: buttonSize)
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.bg)
            }
            .frame(width: ringSize, height: ringSize)
        }
        .buttonStyle(.plain)
        .disabled(!canIncrement)
        .opacity(canIncrement ? 1 : 0.35)
        .accessibilityLabel("Log exposure")
        .accessibilityHint(canIncrement ? "Increments frames shot by one" : "Roll is finished")
        .accessibilityValue("\(displayedShot) of \(safeTotal) frames")
    }

    private var segmentBar: some View {
        GeometryReader { geo in
            let count = safeTotal
            let gap: CGFloat = count > 40 ? 1.5 : 2
            let totalGap = gap * CGFloat(max(count - 1, 0))
            let segmentWidth = max((geo.size.width - totalGap) / CGFloat(count), 1.5)

            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < displayedShot ? AppTheme.textPrimary : AppTheme.rule)
                        .frame(width: segmentWidth, height: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: geo.size.width))
        }
        .frame(height: 28)
        .padding(.vertical, 6)
        .accessibilityLabel("Exposure strip")
        .accessibilityHint(canScrub ? "Drag to set frames shot" : "")
        .accessibilityValue("\(displayedShot) of \(safeTotal)")
        .accessibilityAdjustableAction { direction in
            guard let onSetCount else { return }
            let next: Int
            switch direction {
            case .increment: next = min(displayedShot + 1, safeTotal)
            case .decrement: next = max(displayedShot - 1, 0)
            @unknown default: return
            }
            guard next != displayedShot else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onSetCount(next)
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canScrub else { return }
                let next = count(at: value.location.x, width: width)
                if scrubShot == nil {
                    UISelectionFeedbackGenerator().prepare()
                }
                if lastScrubbed != next {
                    lastScrubbed = next
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                        scrubShot = next
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } else {
                    scrubShot = next
                }
            }
            .onEnded { value in
                guard let onSetCount else {
                    scrubShot = nil
                    lastScrubbed = nil
                    return
                }
                let next = count(at: value.location.x, width: width)
                lastScrubbed = nil
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    scrubShot = next
                    if next != safeShot {
                        onSetCount(next)
                    } else {
                        scrubShot = nil
                    }
                }
            }
    }

    private func count(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let clampedX = min(max(x, 0), width)
        if clampedX <= 0 { return 0 }
        let raw = Int((clampedX / width * CGFloat(safeTotal)).rounded(.up))
        return min(max(raw, 0), safeTotal)
    }
}

/// Vertical reel-style digits that spin when the value changes.
struct VerticalSpinnerNumber: View {
    let value: Int
    var font: Font
    var color: Color
    var digitHeight: CGFloat = 40

    /// Digits keyed by place from the right (0 = ones) so columns keep identity while spinning.
    private var places: [(place: Int, digit: Int)] {
        let chars = Array(String(max(value, 0)))
        return chars.enumerated().compactMap { index, character in
            guard let digit = Int(String(character)) else { return nil }
            return (chars.count - 1 - index, digit)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(places, id: \.place) { item in
                VerticalSpinnerDigit(
                    digit: item.digit,
                    font: font,
                    color: color,
                    height: digitHeight
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: digitHeight * 0.35)),
                        removal: .opacity.combined(with: .offset(y: -digitHeight * 0.25))
                    )
                )
            }
        }
        .frame(height: digitHeight)
        .clipped()
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: value)
        .accessibilityLabel("\(value)")
    }
}

private struct VerticalSpinnerDigit: View {
    let digit: Int
    var font: Font
    var color: Color
    var height: CGFloat

    var body: some View {
        ZStack {
            // Invisible sizing glyph keeps mono columns stable.
            Text("0")
                .font(font)
                .monospacedDigit()
                .opacity(0)

            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { number in
                    Text("\(number)")
                        .font(font)
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .frame(height: height)
                }
            }
            .offset(y: -CGFloat(digit) * height)
        }
        .frame(height: height, alignment: .top)
        .clipped()
    }
}

struct SkeletalBarChart: View {
    let values: [Double]
    let labels: [String]
    var maxValue: Double?

    private var ceiling: Double {
        maxValue ?? (values.max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(value > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 2, height: max(4, CGFloat(value / max(ceiling, 1)) * 64))
                    Text(labels[index])
                        .font(InstrumentFont.mono(10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 88)
    }
}

struct HeroMetric: View {
    let label: String
    let sublabel: String?
    let value: String

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(InstrumentFont.mono(11))
                    .foregroundStyle(AppTheme.textPrimary)
                if let sublabel {
                    Text(sublabel)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(InstrumentFont.display(52, weight: .light))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

struct GhostCircleButton: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InstrumentFont.mono(16))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(AppTheme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct DetailBackHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            GhostCircleButton(label: "‹") { dismiss() }
            Spacer()
        }
        .padding(.bottom, AppTheme.Spacing.lg)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                SectionLabel(title: title)
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
            content()
        }
        .padding(.bottom, AppTheme.Spacing.md)
    }
}

struct InstrumentDetailChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .instrumentScreen()
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func instrumentDetailChrome() -> some View {
        modifier(InstrumentDetailChrome())
    }

    func instrumentDetailContent() -> some View {
        padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
    }

    /// Detail ScrollViews inherit large system bottom content margins under TabView.
    /// Zero those out and let safe area + explicit padding handle the footer.
    func instrumentDetailScroll() -> some View {
        contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
    }

    /// Dismisses the software keyboard regardless of which field holds focus.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Keyboard accessory Done control with a little air above the keys.
struct InstrumentKeyboardDoneButton: View {
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Button("Done") {
                action()
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
            .font(InstrumentFont.mono(13))

            // Gap between the accessory and the keyboard — not inside the button.
            Color.clear
                .frame(height: 8)
                .allowsHitTesting(false)
        }
    }
}

struct StockPlate: View {
    let name: String
    let shortCode: String
    let tint: Color
    let imageName: String?
    var square: Bool = true
    var height: CGFloat = 160

    init(stock: FilmStock, square: Bool = true, height: CGFloat = 160) {
        self.name = stock.name
        self.shortCode = stock.shortCode
        self.tint = stock.emulsionTint
        self.imageName = stock.rollImageName
        self.square = square
        self.height = height
    }

    var body: some View {
        ZStack {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(square ? AppTheme.Spacing.xs : AppTheme.Spacing.md)
            } else {
                Rectangle()
                    .fill(tint.opacity(0.22))
                Text(shortCode)
                    .font(InstrumentFont.mono(square ? 22 : 28))
                    .foregroundStyle(tint.opacity(0.92))
                Rectangle()
                    .strokeBorder(AppTheme.rule, lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(StockPlateSizing(square: square, height: height))
        .background(AppTheme.bg)
        .clipped()
        .accessibilityLabel("\(name) plate")
    }
}

private struct StockPlateSizing: ViewModifier {
    let square: Bool
    let height: CGFloat

    func body(content: Content) -> some View {
        if square {
            content.aspectRatio(1, contentMode: .fit)
        } else {
            content.frame(height: height)
        }
    }
}

struct RollPlate: View {
    var tint: Color = AppTheme.textTertiary
    var size: CGFloat = 56
    var imageName: String?

    init(tint: Color = AppTheme.textTertiary, size: CGFloat = 44) {
        self.tint = tint
        self.size = size
        self.imageName = nil
    }

    init(stock: FilmStock?, size: CGFloat = 44) {
        self.tint = stock?.emulsionTint ?? AppTheme.textTertiary
        self.size = size
        self.imageName = stock?.rollImageName
    }

    var body: some View {
        ZStack {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(tint.opacity(0.18))
                Text("◎")
                    .font(InstrumentFont.mono(size * 0.32))
                    .foregroundStyle(tint.opacity(0.85))
                Rectangle()
                    .strokeBorder(AppTheme.rule, lineWidth: 0.5)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

/// Shared roll row used on Rolls list and Camera detail.
struct ExpiredLabel: View {
    private static let red = Color(red: 1, green: 0.23, blue: 0.19)

    var body: some View {
        Text("EXPIRED")
            .font(InstrumentFont.mono(8, weight: .bold))
            .foregroundStyle(Self.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay {
                Rectangle()
                    .strokeBorder(Self.red, lineWidth: 1)
            }
            .accessibilityLabel("Expired")
    }
}

struct MonthYearPicker: UIViewRepresentable {
    @Binding var date: Date

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .yearAndMonth
        picker.preferredDatePickerStyle = .wheels
        picker.tintColor = .white
        picker.overrideUserInterfaceStyle = .dark
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.date = date
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(date: $date)
    }

    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) {
            self.date = date
        }

        @objc func changed(_ sender: UIDatePicker) {
            date.wrappedValue = ExpirationDate.normalize(sender.date)
        }
    }
}

/// Shared roll row used on Rolls list and Camera detail.
struct RollLedgerRow: View {
    @Environment(AppStore.self) private var store
    let roll: Roll
    var showsCameraName: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            RollPlate(stock: stock, size: 64)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                    Text(rowPrimary)
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if roll.isExpired {
                        ExpiredLabel()
                            .layoutPriority(1)
                    }
                }

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(InstrumentFont.mono(11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                if !roll.status.isInventory {
                    Text("\(roll.frameCount)/\(roll.totalExposures)")
                        .font(InstrumentFont.mono(13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                }
            }
            .layoutPriority(1)
        }
    }

    private var stock: FilmStock? {
        store.stock(for: roll.stockId)
    }

    private var rowPrimary: String {
        if let stock = store.stock(for: roll.stockId) {
            return stock.name
        }
        return roll.shortId
    }

    private var cameraName: String? {
        guard roll.status.showsCamera, let camera = store.camera(for: roll.cameraId) else { return nil }
        return camera.name
    }

    private var noteText: String? {
        guard let notes = roll.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else { return nil }
        return notes
    }

    private var secondaryLine: String? {
        let camera = showsCameraName ? cameraName : nil
        switch (camera, noteText) {
        case let (camera?, note?):
            return "\(camera) · \(note)"
        case let (camera?, nil):
            return camera
        case let (nil, note?):
            return note
        case (nil, nil):
            return nil
        }
    }
}

struct CameraPhotoPlate: View {
    var photoData: Data? = nil
    var size: CGFloat = 56
    var square: Bool = true
    var height: CGFloat = 220

    var body: some View {
        Group {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().strokeBorder(AppTheme.rule, lineWidth: 0.5)
                    Text("◻")
                        .font(InstrumentFont.mono((square ? size : min(height, 120)) * 0.28))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: square ? nil : .infinity)
        .frame(width: square ? size : nil, height: square ? size : height)
        .clipped()
        .background(AppTheme.bg)
    }
}

struct UndoDeletionBanner: View {
    let rollLabel: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text("\(rollLabel) deleted")
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button("Undo", action: onUndo)
                .font(InstrumentFont.mono(12))
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.textPrimary)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.rule)
    }
}

struct InstrumentFormBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func instrumentFormStyle() -> some View {
        modifier(InstrumentFormBackground())
    }

    /// Half-height by default, expandable to full; matches instrument chrome.
    func instrumentSheetChrome() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(AppTheme.bg)
            .preferredColorScheme(.dark)
    }
}
