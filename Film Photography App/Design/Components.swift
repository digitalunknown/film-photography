import SwiftUI
import UIKit

// MARK: - Fields

extension Text {
    /// Placeholder copy for an empty field. The palette has one weak text colour, so
    /// prompts use it rather than the system placeholder grey.
    static func fieldPrompt(_ placeholder: String) -> Text {
        Text(placeholder).foregroundStyle(AppTheme.textSecondary)
    }
}

extension TextField where Label == Text {
    /// Text field whose placeholder is drawn in the palette's weak text colour. The
    /// placeholder doubles as the accessibility label, as it would with a plain title.
    init(placeholder: String, text: Binding<String>, axis: Axis = .horizontal) {
        self.init(
            text: text,
            prompt: .fieldPrompt(placeholder),
            axis: axis
        ) {
            Text(placeholder)
        }
    }
}

// MARK: - Structure

/// The one divider style — `#F0F1F5` at 10%, one point thick. Used between rows, between
/// detail sections, and to split card columns; nothing else should draw its own separator.
extension View {
    /// The one border style — `AppTheme.strokeWidth` of `AppTheme.rule`, inset inside the
    /// given shape. Anything needing a neutral outline uses this instead of picking its
    /// own width and colour.
    func instrumentStroke<S: InsettableShape>(_ shape: S) -> some View {
        overlay(shape.strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth))
    }
}

/// Leading-edge dismiss for add sheets — always the X, never a worded Cancel.
struct InstrumentCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideIcon(.x)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityLabel("Close")
    }
}

/// Full-width page tabs. A hairline runs the width of the device; the active tab
/// sits on a thicker primary rule so the selection reads as a mark, not a pill.
struct InstrumentSegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String, icon: Lucide)]
    @Binding var selection: Value

    private var indicatorHeight: CGFloat { 2.5 }
    static var paneAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        withAnimation(Self.paneAnimation) {
                            selection = option.value
                        }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            LucideIcon(option.icon)
                            Text(option.title)
                                .font(AppType.body)
                        }
                        .foregroundStyle(selection == option.value ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }

            ZStack(alignment: .bottomLeading) {
                HairlineRule()
                GeometryReader { geo in
                    let count = max(options.count, 1)
                    let width = geo.size.width / CGFloat(count)
                    let index = options.firstIndex { $0.value == selection } ?? 0
                    Rectangle()
                        .fill(AppTheme.textPrimary)
                        .frame(width: width, height: indicatorHeight)
                        .offset(x: width * CGFloat(index))
                }
                .frame(height: indicatorHeight)
            }
        }
    }
}

struct HairlineRule: View {
    var axis: Axis = .horizontal

    private static let thickness: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(AppTheme.rule)
            .frame(
                width: axis == .vertical ? Self.thickness : nil,
                height: axis == .horizontal ? Self.thickness : nil
            )
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
                    .font(AppType.largeTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppTheme.textPrimary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLabel: View {
    let title: String
    var style: Style = .list

    enum Style {
        case list
        case detail
    }

    var body: some View {
        Text(title.uppercased())
            .font(style == .detail ? AppType.section : AppType.calloutEmphasized)
            .foregroundStyle(AppTheme.textPrimary)
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
                .font(AppType.body)
                .foregroundStyle(valueBright ? AppTheme.textPrimary : AppTheme.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Figma detail row: secondary label on the left, value pinned to the trailing edge.
/// The label absorbs the slack, so short values sit flush right. Dividers and the 16pt
/// rhythm come from the enclosing stack, matching the Figma auto-layout.
struct DetailFieldRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text(label)
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            value()
                .frame(minHeight: AppTheme.iconSize, alignment: .center)
        }
        .frame(minHeight: AppTheme.iconSize, alignment: .center)
    }
}

/// Trailing value text for a `DetailFieldRow`.
struct DetailFieldValue: View {
    let text: String
    var isPlaceholder: Bool = false

    var body: some View {
        Text(text)
            .font(AppType.body)
            .foregroundStyle(isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary)
            .multilineTextAlignment(.trailing)
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
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                Text(label)
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                trailing()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AppTheme.Spacing.lg)
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
                        .font(AppType.body)
                        .foregroundStyle(valueBright ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                    LucideIcon(.chevronsUpDown)
                        .foregroundStyle(AppTheme.textPrimary)
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
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }
}

/// Hero content above the first detail section (strip, photo, metrics).
struct DetailHeroBlock<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            content()
        }
        .padding(.bottom, AppTheme.Spacing.xl)
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
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(primary)
                    .font(AppType.title)
                    .foregroundStyle(AppTheme.textPrimary)
                if let secondary {
                    Text(secondary)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                Text(value)
                    .font(AppType.calloutEmphasized)
                    .foregroundStyle(AppTheme.textPrimary)
                if let valueSecondary {
                    Text(valueSecondary)
                        .font(AppType.callout)
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
            .padding(.leading, AppTheme.Spacing.xl)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xs)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// 35pt outlined circle wrapping a 24pt Lucide glyph — Figma metadata row accessory.
struct CircleIconButton: View {
    let icon: Lucide
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideIcon(icon)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 35, height: 35)
                .background(Circle().strokeBorder(AppTheme.textPrimary, lineWidth: AppTheme.strokeWidth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Figma metadata row: label stacked above its value, with an optional round action button
/// on the trailing edge for a one-tap shortcut (drop a pin, stamp today's date).
struct StackedFieldRow<Value: View>: View {
    let label: String
    var accessory: Lucide? = nil
    var accessoryLabel: String? = nil
    var accessoryAction: (() -> Void)? = nil
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(label)
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let accessory, let accessoryAction {
                CircleIconButton(icon: accessory, action: accessoryAction)
                    .accessibilityLabel(accessoryLabel ?? label)
            }
        }
    }
}

/// Full-width outlined pill — Figma "ADD SCANS" primary action.
struct PillButtonLabel: View {
    let title: String
    var icon: Lucide?
    var isProminent: Bool = false
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if isBusy {
                ProgressView()
                    .controlSize(.regular)
                    .tint(isProminent ? AppTheme.bg : AppTheme.textPrimary)
                    .frame(width: AppTheme.iconSize, height: AppTheme.iconSize)
            } else if let icon {
                LucideIcon(icon)
            }
            Text(title.uppercased())
                .font(AppType.button)
        }
        .foregroundStyle(isProminent ? AppTheme.bg : AppTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
        .background {
            if isProminent {
                Capsule().fill(AppTheme.textPrimary)
            } else {
                Capsule().strokeBorder(AppTheme.textPrimary, lineWidth: AppTheme.strokeWidth)
            }
        }
        .contentShape(Capsule())
    }
}

struct TextAction: View {
    let label: String
    var icon: Lucide? = .chevronRight
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(label)
                    .font(AppType.calloutEmphasized)
                if let icon {
                    LucideIcon(icon)
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text(message)
                .font(AppType.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                TextAction(label: primaryAction, action: primaryHandler)
                if let secondaryAction, let secondaryHandler {
                    TextAction(label: secondaryAction, action: secondaryHandler)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.xl * 2)
    }
}

struct FilterChipRow: View {
    let options: [String]
    @Binding var selection: String
    /// Sentinel for “no filter” (not shown as a chip).
    var clearValue: String
    /// When set, returns a brand tint — or `nil` for the neutral chip style.
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
        let content = HStack(spacing: AppTheme.Spacing.xs) {
            if showsClear {
                LucideIcon(.x, size: 16)
            }
            Text(option)
                .font(AppType.footnote)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)

        // Brand chips keep the shared capsule and spacing; only the colour changes.
        let tint = tintForOption?(option)

        content
            .foregroundStyle(tint ?? (isSelected ? AppTheme.textPrimary : AppTheme.textSecondary))
            // The brand wash sits over the shared surface so branded and neutral chips
            // carry the same visual weight.
            .background(wash(tint: tint, isSelected: isSelected), in: Capsule())
            .background(AppTheme.surface, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(border(tint: tint, isSelected: isSelected), lineWidth: AppTheme.strokeWidth)
            )
    }

    /// `surface` is light enough that a low-alpha tint reads as dust rather than colour,
    /// so the wash needs to be strong to survive the composite.
    private func wash(tint: Color?, isSelected: Bool) -> Color {
        guard let tint else { return .clear }
        return tint.opacity(isSelected ? 0.38 : 0.24)
    }

    private func border(tint: Color?, isSelected: Bool) -> Color {
        guard let tint else {
            return isSelected ? AppTheme.textPrimary : AppTheme.textSecondary
        }
        return isSelected ? tint : tint.opacity(0.7)
    }
}

struct UnderlineMeter: View {
    let label: String
    let value: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(label)
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(AppType.body)
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
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                    VerticalSpinnerNumber(
                        value: displayedShot,
                        font: AppType.counter,
                        color: AppTheme.textPrimary,
                        digitHeight: AppType.counterDigitHeight
                    )
                    Text("/\(safeTotal)")
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()

                    Text(statusLabel)
                        .font(AppType.titleRegular)
                        .foregroundStyle(AppTheme.textSecondary)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: statusLabel)
                }

                Spacer(minLength: AppTheme.Spacing.sm)

                HStack(spacing: AppTheme.Spacing.lg) {
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
            LucideIcon(.chevronsLeft)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 35, height: 35)
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.textSecondary, lineWidth: AppTheme.strokeWidth)
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
        let ringSize: CGFloat = 60
        let ringLine: CGFloat = 3
        let coreSize: CGFloat = 50

        return Button {
            guard canIncrement else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                onIncrement?()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(AppTheme.well, lineWidth: ringLine)
                    .frame(width: ringSize, height: ringSize)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AppTheme.textPrimary,
                        style: StrokeStyle(lineWidth: ringLine, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
                    .animation(.easeOut(duration: 0.2), value: displayedShot)

                Circle()
                    .fill(AppTheme.textPrimary)
                    .frame(width: coreSize, height: coreSize)

                LucideIcon(.aperture)
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
        .padding(.vertical, AppTheme.Spacing.sm)
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

/// Spring used by the exposure counter and the dial readouts so both reels move as one.
enum VerticalSpinnerMotion {
    static let animation: Animation = .spring(response: 0.42, dampingFraction: 0.78)
}

/// Vertical reel of discrete labels — same motion as `VerticalSpinnerNumber`, for
/// values that are not a single decimal digit (aperture and shutter readouts).
struct VerticalSpinnerText: View {
    let labels: [String]
    let index: Int
    var font: Font
    var color: Color
    var height: CGFloat

    private var clampedIndex: Int {
        guard !labels.isEmpty else { return 0 }
        return min(max(index, 0), labels.count - 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(font)
                    .hidden()
            }

            VStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(font)
                        .foregroundStyle(color)
                        .frame(height: height)
                }
            }
            .offset(y: -CGFloat(clampedIndex) * height)
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .animation(VerticalSpinnerMotion.animation, value: clampedIndex)
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
        .animation(VerticalSpinnerMotion.animation, value: value)
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
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.md) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: AppTheme.Spacing.sm) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(value > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 2, height: max(4, CGFloat(value / max(ceiling, 1)) * 64))
                    Text(labels[index])
                        .font(AppType.micro)
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
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                if let sublabel {
                    Text(sublabel)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(AppType.largeTitle)
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

/// 40×40 translucent circle matching the Figma toolbar buttons.
struct GhostCircleButton: View {
    let icon: Lucide
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideIcon(icon)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppTheme.textPrimary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct DetailBackHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            GhostCircleButton(icon: .chevronLeft) { dismiss() }
                .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.bottom, AppTheme.Spacing.xl)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                SectionLabel(title: title, style: .detail)
                    .padding(.bottom, AppTheme.Spacing.lg)
            }
            content()
        }
        .padding(.bottom, AppTheme.Spacing.lg)
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
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
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
        Button("Done") {
            action()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
        .font(AppType.body)
        // Air between the accessory and the keys. A `Color.clear` spacer used to provide
        // this, but it is greedy horizontally and stretched the button across the bar.
        .padding(.bottom, AppTheme.Spacing.sm)
    }
}

struct StockPlate: View {
    let name: String
    let shortCode: String
    let imageName: String?
    var square: Bool = true
    var height: CGFloat = 160

    init(stock: FilmStock, square: Bool = true, height: CGFloat = 160) {
        self.name = stock.name
        self.shortCode = stock.shortCode
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
                    .padding(square ? AppTheme.Spacing.xs : AppTheme.Spacing.lg)
            } else {
                Rectangle()
                    .fill(AppTheme.surface)
                Text(shortCode)
                    .font(AppType.title)
                    .foregroundStyle(AppTheme.textSecondary)
                Rectangle()
                    .strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth)
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
        let hasImage = imageName.flatMap { UIImage(named: $0) } != nil
        ZStack {
            if hasImage, let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppTheme.surface)
                LucideIcon(.film)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.sm))
        .overlay {
            if !hasImage {
                RoundedRectangle(cornerRadius: AppTheme.Spacing.sm)
                    .strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth)
            }
        }
    }
}

/// Shared accent chip used for expired rolls and discontinued stocks.
struct AccentBadge: View {
    enum Style {
        case full
        case compact
    }

    let text: String
    var style: Style = .full
    var accessibilityName: String

    var body: some View {
        Group {
            switch style {
            case .full:
                Text(text)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .strokeBorder(AppTheme.accent, lineWidth: AppTheme.strokeWidth)
                    }
            case .compact:
                Text(text)
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .strokeBorder(AppTheme.accent, lineWidth: AppTheme.strokeWidth)
                    }
            }
        }
        .font(AppType.badge)
        .foregroundStyle(AppTheme.accent)
        .accessibilityLabel(accessibilityName)
    }
}

/// Expiry flag. Detail headers spell it out; list rows use the compact `E` disc so the
/// badge doesn't crowd the roll title.
struct ExpiredLabel: View {
    var style: AccentBadge.Style = .full

    var body: some View {
        AccentBadge(
            text: style == .full ? "EXPIRED" : "E",
            style: style,
            accessibilityName: "Expired"
        )
    }
}

/// Discontinued catalog flag. Grid uses `D`; the stock title uses `DISC.`
struct DiscontinuedLabel: View {
    var style: AccentBadge.Style = .full

    var body: some View {
        AccentBadge(
            text: style == .full ? "DISC." : "D",
            style: style,
            accessibilityName: "Discontinued"
        )
    }
}

struct MonthYearPicker: UIViewRepresentable {
    @Binding var date: Date

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .yearAndMonth
        picker.preferredDatePickerStyle = .wheels
        picker.tintColor = UIColor(AppTheme.textPrimary)
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
    /// When set, the second line is the roll's status instead of the camera name —
    /// used on a camera's history list, where the body is already known.
    var showsStatus: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
            RollPlate(stock: stock, size: 100)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text(rowPrimary)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if roll.isExpired {
                        ExpiredLabel(style: .compact)
                            .layoutPriority(1)
                    }

                    Spacer(minLength: AppTheme.Spacing.xs)

                    if !roll.status.isInventory {
                        Text("\(roll.frameCount)/\(roll.totalExposures)")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                }

                if let cameraLine {
                    Text(cameraLine)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let noteText {
                    Text(noteText)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stock: FilmStock? {
        store.stock(for: roll.stockId)
    }

    private var rowPrimary: String {
        store.label(for: roll)
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

    private var cameraLine: String? {
        if showsStatus { return roll.status.displayName }
        return showsCameraName ? cameraName : nil
    }
}

/// Placeholder tile for a lens that has no photograph yet — same 100pt plate as
/// cameras and rolls, with the aperture mark standing in for glass.
struct LensPlate: View {
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            Rectangle().fill(AppTheme.surface)
            LucideIcon(.aperture)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.sm))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Spacing.sm)
                .strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth)
        }
    }
}

/// Same ledger shape as a camera row: 100pt plate, title, optional spec, notes.
struct LensLedgerRow: View {
    let lens: CameraLens
    var showsDefault: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
            LensPlate(size: 100)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text(lens.name)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if lens.isPrimary, showsDefault {
                        Text("Default")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textSecondary)
                            .layoutPriority(1)
                    }
                }

                if let spec = lens.specLine {
                    Text(spec)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                let notes = lens.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    Text(notes)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CameraPhotoPlate: View {
    var photoData: Data? = nil
    var size: CGFloat = 56
    var square: Bool = true

    /// The hero matches the frame gate on the frame detail screen, so a camera is shown at
    /// the same proportions — and the same corner — as the photos it takes.
    private static let heroAspect: CGFloat = 3.0 / 2.0
    private static let heroCorner = AppTheme.Spacing.sm

    private var image: UIImage? {
        photoData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        if square {
            fill
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.sm))
                .background(AppTheme.bg)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.sm)
                        .strokeBorder(AppTheme.rule, lineWidth: AppTheme.strokeWidth)
                }
        } else {
            Rectangle()
                .fill(AppTheme.bg)
                .aspectRatio(Self.heroAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { fill }
                .clipShape(RoundedRectangle(cornerRadius: Self.heroCorner))
                .instrumentStroke(RoundedRectangle(cornerRadius: Self.heroCorner))
        }
    }

    @ViewBuilder
    private var fill: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(AppTheme.surface)
                LucideIcon(.camera)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

struct CameraLedgerRow: View {
    @Environment(AppStore.self) private var store
    let camera: Camera

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
            CameraPhotoPlate(photoData: camera.photoData, size: 100)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    Text(camera.name)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: AppTheme.Spacing.xs)

                    if let roll = loadedRoll {
                        Text("\(roll.frameCount)/\(roll.totalExposures)")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    } else {
                        Text("Empty")
                            .font(AppType.title)
                            .foregroundStyle(AppTheme.textSecondary)
                            .layoutPriority(1)
                    }
                }

                if let subtitle = camera.listSubtitle {
                    Text(subtitle)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let stockName = loadedStock?.name {
                    Text(stockName)
                        .font(AppType.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadedRoll: Roll? { store.loadedRoll(for: camera.id) }
    private var loadedStock: FilmStock? {
        guard let roll = loadedRoll else { return nil }
        return store.stock(for: roll.stockId)
    }
}

struct PersistFailureBanner: View {
    let problem: PersistProblem
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            Text(problem.message)
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button(problem.retryTitle, action: onRetry)
                .font(AppType.calloutEmphasized)
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.textPrimary)
                .fixedSize()
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, AppTheme.Spacing.lg)
        .background(AppTheme.surface)
    }
}

struct UndoDeletionBanner: View {
    let rollLabel: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Text("\(rollLabel) deleted")
                .font(AppType.callout)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button("Undo", action: onUndo)
                .font(AppType.calloutEmphasized)
                .foregroundStyle(AppTheme.textPrimary)
                .underline(color: AppTheme.textPrimary)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, AppTheme.Spacing.lg)
        .background(AppTheme.surface)
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
