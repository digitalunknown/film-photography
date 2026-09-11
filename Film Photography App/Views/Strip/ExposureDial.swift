import SwiftUI

/// A photographic value ladder, one notch per whole stop. Ordered the way a camera dial
/// reads left to right: wider apertures and slower speeds first.
struct ExposureScale {
    struct Notch {
        let value: Double
        let label: String
    }

    /// The camera chose the stop, so there is no number to record. Negative so it never
    /// collides with bulb (0) or a real reading.
    static let autoValue: Double = -1

    /// Bulb holds the shutter open for as long as it is held, so it has no timed value.
    /// Zero stands for it wherever a shutter speed is stored or printed.
    static let bulbSeconds: Double = 0

    let notches: [Notch]
    /// Stands in for the value until the frame has one, keeping the reading's shape so
    /// the dial still looks like a dial rather than an empty box.
    let blankLabel: String
    /// Where the needle parks before the photographer has set anything.
    let defaultIndex: Int

    var autoIndex: Int? {
        notches.firstIndex { $0.value == Self.autoValue }
    }

    /// True when `value` is this notch, not merely the nearest stop.
    func exactIndex(of value: Double) -> Int? {
        if value <= 0 {
            return notches.firstIndex { $0.value == value }
        }
        return notches.firstIndex {
            $0.value > 0 && abs(log($0.value) - log(value)) < 1e-6
        }
    }

    func displayLabel(for value: Double) -> String {
        if let index = exactIndex(of: value) {
            return notches[index].label
        }
        return blankLabel.hasPrefix("f/")
            ? ExposureFormat.aperture(value)
            : ExposureFormat.shutter(value)
    }

    func parse(_ text: String) -> Double? {
        blankLabel.hasPrefix("f/")
            ? ExposureFormat.parseAperture(text)
            : ExposureFormat.parseShutter(text)
    }

    /// Stops are logarithmic, so nearness is measured there rather than on raw values.
    /// Untimed notches (Auto, Bulb) sit outside that space and are matched exactly.
    func nearestIndex(to value: Double) -> Int {
        guard value > 0 else {
            return notches.firstIndex { $0.value == value } ?? defaultIndex
        }
        let target = log(value)
        return notches.indices
            .filter { notches[$0].value > 0 }
            .min { abs(log(notches[$0].value) - target) < abs(log(notches[$1].value) - target) }
            ?? defaultIndex
    }

    static let aperture: ExposureScale = {
        let stops: [Double] = [1, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22, 32, 45, 64]
        var notches = [Notch(value: autoValue, label: "Auto")]
        notches += stops.map { Notch(value: $0, label: "f/" + String(format: "%g", $0)) }
        return ExposureScale(
            notches: notches,
            blankLabel: "f/--",
            defaultIndex: notches.firstIndex { $0.value == 8 } ?? 0
        )
    }()

    static let shutter: ExposureScale = {
        let denominators: [Double] = [1, 2, 4, 8, 15, 30, 60, 125, 250, 500, 1000, 2000, 4000]

        var notches = [Notch(value: autoValue, label: "Auto")]
        notches.append(Notch(value: bulbSeconds, label: "B"))
        notches += denominators.map { denominator in
            Notch(
                value: 1 / denominator,
                label: denominator == 1 ? "1s" : "1/" + String(format: "%g", denominator)
            )
        }

        return ExposureScale(
            notches: notches,
            blankLabel: "1/--",
            defaultIndex: notches.firstIndex { abs($0.value - 1.0 / 125.0) < .ulpOfOne } ?? 0
        )
    }()
}

/// Camera-style dial: whichever notch sits under the fixed centre needle is the value.
/// Drag to spin the scale, or tap either side of the needle to step a single notch.
struct ExposureDial: View {
    let unit: String
    let scale: ExposureScale
    @Binding var value: Double?

    private static let height: CGFloat = 70
    private static let corner = AppTheme.Spacing.lg
    /// Points of travel per whole stop. Generous enough that the ladder runs well past
    /// both ends of the dial, giving the scale room to be dragged through.
    private static let pitch: CGFloat = 24
    /// Minor ticks drawn between each pair of whole stops. The ladder still snaps stop to
    /// stop; these only make the scale read as a finely graduated dial rather than a comb.
    private static let subdivisions = 4
    private static let tickWidth: CGFloat = 1.25
    private static let tickHeight: CGFloat = 16
    /// Everything left of the needle is "filled": it builds from dim at the left edge to
    /// full strength under the needle, so turning up the value fills the dial.
    private static let fillShadeMin: CGFloat = 0.35
    private static let fillShadeMax: CGFloat = 1.0
    /// Right of the needle — the part not yet reached.
    private static let emptyShade: CGFloat = 0.16
    /// Before the frame carries a reading there is nothing to fill, so the whole scale
    /// sits at one inert shade, matching the greyed-out needle.
    private static let inertShade: CGFloat = 0.30
    private static let needleWidth: CGFloat = 2
    private static let needleHeight: CGFloat = 14
    /// Holds the needles off the card edge so both rounded ends stay visible.
    private static let needleInset: CGFloat = 2
    /// Carries the scale between notches when a turn isn't tracking a finger.
    private static let glide: Animation = .snappy(duration: 0.18)
    /// Line box for the spinning readout — matches a 17pt title so the reel clips cleanly.
    private static let valueHeight: CGFloat = 22
    @State private var width: CGFloat = 0
    @State private var dragOrigin: Int?
    @State private var spin: CGFloat = 0
    @State private var notchesTurned = 0
    @State private var showingCustom = false
    @State private var customText = ""

    /// An unset field parks the needle on the scale's default so the dial still reads as
    /// one; the value stays greyed out until it is actually turned. A custom amount
    /// sits on the nearest stop.
    private var index: Int {
        value.map { scale.nearestIndex(to: $0) } ?? scale.defaultIndex
    }

    private var isSet: Bool {
        value != nil
    }

    private var isCustom: Bool {
        guard let value else { return false }
        return scale.exactIndex(of: value) == nil
    }

    /// A finger is on the scale. Used to lift the rim so the active dial reads as held.
    private var isTurning: Bool {
        dragOrigin != nil
    }

    /// Where the scale sits under the needle, measured in notches. Whole at rest, and
    /// fractional while the dial is being turned or is gliding to the notch it landed on.
    private var position: CGFloat {
        CGFloat(index) - spin / Self.pitch
    }

    var body: some View {
        ZStack {
            Ticks(position: position, count: scale.notches.count, isSet: isSet)
            needles
            readout
        }
        // Groups the layers so the readout can erase the ticks behind it without
        // punching through the glass underneath.
        .compositingGroup()
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipShape(.rect(cornerRadius: Self.corner))
        // The face sits flush with the sheet, so only the hairline rim separates the two.
        // It stays a flat fill rather than glass, which can only lighten what is behind it.
        .background(AppTheme.bg, in: .rect(cornerRadius: Self.corner))
        .overlay {
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(
                    AppTheme.textPrimary.opacity(isTurning ? 0.28 : 0.10),
                    lineWidth: AppTheme.strokeWidth
                )
                .animation(.easeOut(duration: 0.16), value: isTurning)
        }
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onTapGesture(coordinateSpace: .local) { step(from: $0) }
        .simultaneousGesture(spinGesture)
        .contextMenu {
            Button("Custom", lucide: .pencil) {
                customText = value.map { scale.displayLabel(for: $0) } ?? ""
                Task { @MainActor in
                    showingCustom = true
                }
            }
            .font(AppType.body)
            Button("Unset", lucide: .squareX) {
                withAnimation(Self.glide) {
                    value = nil
                    spin = 0
                }
            }
            .font(AppType.body)
            .disabled(!isSet)
        }
        .alert(customTitle, isPresented: $showingCustom) {
            TextField(customPlaceholder, text: $customText)
                .keyboardType(.numbersAndPunctuation)
            Button("Set") { applyCustom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(customPrompt)
        }
        .sensoryFeedback(.selection, trigger: notchesTurned)
        .accessibilityElement()
        .accessibilityLabel(unit)
        .accessibilityValue(value.map { scale.displayLabel(for: $0) } ?? scale.blankLabel)
        .accessibilityAdjustableAction { direction in
            withAnimation(Self.glide) {
                switch direction {
                case .increment: commit(index + 1)
                case .decrement: commit(index - 1)
                default: break
                }
            }
        }
    }

    // MARK: - Parts

    /// Drawn rather than stacked so a long scale costs nothing in layout.
    ///
    /// A `Canvas` renders whatever it is handed and SwiftUI cannot interpolate between
    /// two of its drawings, so the scale lives in its own `Animatable` view. That hands
    /// it every position between the old notch and the new one, letting the ticks glide
    /// across instead of cutting straight to the next stop.
    private struct Ticks: View, Animatable {
        var position: CGFloat
        let count: Int
        let isSet: Bool

        var animatableData: CGFloat {
            get { position }
            set { position = newValue }
        }

        var body: some View {
            Canvas { context, size in
                let pitch = ExposureDial.pitch
                let tickWidth = ExposureDial.tickWidth
                let tickHeight = ExposureDial.tickHeight
                let centre = size.width / 2
                let top = (size.height - tickHeight) / 2

                for tickIndex in 0...((count - 1) * ExposureDial.subdivisions) {
                    let notch = CGFloat(tickIndex) * step
                    let x = centre + (notch - position) * pitch
                    guard x > -tickWidth, x < size.width + tickWidth else { continue }

                    let tick = CGRect(
                        x: x - tickWidth / 2,
                        y: top,
                        width: tickWidth,
                        height: tickHeight
                    )
                    context.fill(
                        Path(roundedRect: tick, cornerRadius: tickWidth / 2),
                        with: .color(shade(notch: notch, x: x, centre: centre))
                    )
                }
            }
        }

        /// Filled ticks ramp toward the needle so the fill reads as building up to it.
        /// The ramp is measured in screen space rather than along the ladder, so it looks
        /// the same at either end of the scale.
        private func shade(notch: CGFloat, x: CGFloat, centre: CGFloat) -> Color {
            guard isSet else {
                return AppTheme.textSecondary.opacity(ExposureDial.inertShade)
            }
            guard notch <= position + step / 2 else {
                return AppTheme.textSecondary.opacity(ExposureDial.emptyShade)
            }
            let ramp = min(max(x / centre, 0), 1)
            let shade = ExposureDial.fillShadeMin
                + (ExposureDial.fillShadeMax - ExposureDial.fillShadeMin) * ramp
            return AppTheme.textPrimary.opacity(shade)
        }

        private var step: CGFloat { 1 / CGFloat(ExposureDial.subdivisions) }
    }

    /// Fixed centre marks, reaching in from the top and bottom edges.
    private var needles: some View {
        VStack(spacing: 0) {
            needle
            Spacer(minLength: 0)
            needle
        }
        .padding(.vertical, Self.needleInset)
    }

    /// Amber only once the frame carries a reading; until then the needle is as inert as
    /// the rest of the scale.
    private var needle: some View {
        Capsule()
            .fill(isSet ? AppTheme.indicator : AppTheme.textSecondary)
            .frame(width: Self.needleWidth, height: Self.needleHeight)
    }

    /// Clears a space in the scale for the value to sit in. The backing gradient erases
    /// the ticks rather than covering them, so the glass still shows through the gap.
    private var readout: some View {
        VStack(spacing: 0) {
            Group {
                if let value, isCustom {
                    Text(scale.displayLabel(for: value))
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: Self.valueHeight)
                } else if isSet {
                    VerticalSpinnerText(
                        labels: scale.notches.map(\.label),
                        index: index,
                        font: AppType.title,
                        color: AppTheme.textPrimary,
                        height: Self.valueHeight
                    )
                } else {
                    Text(scale.blankLabel)
                        .font(AppType.title)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(height: Self.valueHeight)
                }
            }
            .frame(height: Self.valueHeight)
            .clipped()
            Text(unit)
                .font(AppType.microRegular)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.xl + AppTheme.Spacing.sm)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white, location: 0.32),
                    .init(color: .white, location: 0.68),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Only as tall as the tick band, so the fill either side of the value stays
            // untouched above and below it.
            .frame(height: Self.tickHeight)
            .blendMode(.destinationOut)
        }
    }

    // MARK: - Turning

    /// The scale tracks the finger continuously while the value snaps to whole notches,
    /// so ticks and labels never drift out of step with the needle. The gesture runs
    /// alongside the enclosing scroll view and only takes hold once a drag is clearly
    /// sideways, leaving a vertical swipe that starts on a dial free to scroll the page.
    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                if dragOrigin == nil {
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    dragOrigin = index
                }
                guard let origin = dragOrigin else { return }

                let travelled = drag.translation.width
                let target = clamped(origin - Int((travelled / Self.pitch).rounded()))
                let slack = travelled - CGFloat(origin - target) * Self.pitch
                spin = min(max(slack, -Self.pitch / 2), Self.pitch / 2)
                commit(target)
            }
            .onEnded { _ in
                dragOrigin = nil
                withAnimation(Self.glide) { spin = 0 }
            }
    }

    /// Tapping to one side of the needle nudges a single notch, like a rocker switch.
    /// Nothing tracks the finger here, so the scale is animated across to the new notch.
    private func step(from point: CGPoint) {
        withAnimation(Self.glide) {
            commit(point.x < width / 2 ? index - 1 : index + 1)
        }
    }

    private var customTitle: String {
        scale.blankLabel.hasPrefix("f/") ? "Custom aperture" : "Custom shutter"
    }

    private var customPlaceholder: String {
        scale.blankLabel.hasPrefix("f/") ? "f/3.5" : "1/90"
    }

    private var customPrompt: String {
        scale.blankLabel.hasPrefix("f/")
            ? "Type an f-number, like 3.5."
            : "Type a speed, like 1/90 or 90."
    }

    private func applyCustom() {
        guard let parsed = scale.parse(customText) else { return }
        withAnimation(Self.glide) {
            value = parsed
            spin = 0
        }
        notchesTurned += 1
    }

    private func commit(_ target: Int) {
        let target = clamped(target)
        let next = scale.notches[target].value
        guard next != value else { return }
        value = next
        notchesTurned += 1
    }

    private func clamped(_ target: Int) -> Int {
        min(max(target, 0), scale.notches.count - 1)
    }
}
