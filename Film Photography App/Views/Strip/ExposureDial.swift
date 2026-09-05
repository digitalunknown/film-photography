import SwiftUI

/// A photographic value ladder, one notch per whole stop. Ordered the way a camera dial
/// reads left to right: wider apertures and slower speeds first.
struct ExposureScale {
    struct Notch {
        let value: Double
        let label: String
    }

    /// Bulb holds the shutter open for as long as it is held, so it has no timed value.
    /// Non-positive seconds stand for it wherever a shutter speed is stored or printed.
    static let bulbSeconds: Double = 0

    let notches: [Notch]
    /// Stands in for the value until the frame has one, keeping the reading's shape so
    /// the dial still looks like a dial rather than an empty box.
    let blankLabel: String
    /// Where the needle parks before the photographer has set anything.
    let defaultIndex: Int

    /// Stops are logarithmic, so nearness is measured there rather than on raw values.
    /// Untimed notches sit outside that space and are matched exactly instead.
    func nearestIndex(to value: Double) -> Int {
        guard value > 0 else {
            return notches.firstIndex { $0.value <= 0 } ?? defaultIndex
        }
        let target = log(value)
        return notches.indices
            .filter { notches[$0].value > 0 }
            .min { abs(log(notches[$0].value) - target) < abs(log(notches[$1].value) - target) }
            ?? defaultIndex
    }

    static let aperture: ExposureScale = {
        let stops: [Double] = [1, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22, 32, 45, 64]
        return ExposureScale(
            notches: stops.map { Notch(value: $0, label: "f/" + String(format: "%g", $0)) },
            blankLabel: "f/--",
            defaultIndex: stops.firstIndex(of: 8) ?? 0
        )
    }()

    static let shutter: ExposureScale = {
        let denominators: [Double] = [1, 2, 4, 8, 15, 30, 60, 125, 250, 500, 1000, 2000, 4000]

        var notches = [Notch(value: bulbSeconds, label: "B")]
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
    @Binding var selection: Int?

    private static let height: CGFloat = 70
    private static let corner = AppTheme.Spacing.lg
    /// Points of travel per whole stop. Generous enough that the ladder runs well past
    /// both ends of the dial, giving the scale room to be dragged through.
    private static let pitch: CGFloat = 24
    private static let tickWidth: CGFloat = 1.25
    private static let tickHeight: CGFloat = 24
    /// Ticks brighten towards the left so the scale reads as building up to the value.
    private static let tickShadeLeading: CGFloat = 0.55
    private static let tickShadeTrailing: CGFloat = 0.12
    private static let needleWidth: CGFloat = 2
    private static let needleHeight: CGFloat = 14
    /// Holds the needles off the card edge so both rounded ends stay visible.
    private static let needleInset: CGFloat = 2
    /// Carries the scale between notches when a turn isn't tracking a finger.
    private static let glide: Animation = .snappy(duration: 0.18)
    @State private var width: CGFloat = 0
    @State private var dragOrigin: Int?
    @State private var spin: CGFloat = 0
    @State private var notchesTurned = 0

    /// An unset field parks the needle on the scale's default so the dial still reads as
    /// one; the value stays greyed out until it is actually turned.
    private var index: Int {
        selection ?? scale.defaultIndex
    }

    private var isSet: Bool {
        selection != nil
    }

    /// Where the scale sits under the needle, measured in notches. Whole at rest, and
    /// fractional while the dial is being turned or is gliding to the notch it landed on.
    private var position: CGFloat {
        CGFloat(index) - spin / Self.pitch
    }

    var body: some View {
        ZStack {
            Ticks(position: position, count: scale.notches.count)
            needles
            readout
        }
        // Groups the layers so the readout can erase the ticks behind it without
        // punching through the glass underneath.
        .compositingGroup()
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipShape(.rect(cornerRadius: Self.corner))
        // Figma cuts the dial face darker than the sheet. Liquid glass can only lighten
        // what is behind it, so the face is a flat fill with a hairline rim instead.
        .background(AppTheme.well, in: .rect(cornerRadius: Self.corner))
        .overlay {
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(AppTheme.surface, lineWidth: 1.25)
        }
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onTapGesture(coordinateSpace: .local) { step(from: $0) }
        .simultaneousGesture(spinGesture)
        .sensoryFeedback(.selection, trigger: notchesTurned)
        .accessibilityElement()
        .accessibilityLabel(unit)
        .accessibilityValue(scale.notches[index].label)
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

                for notch in 0..<count {
                    let x = centre + (CGFloat(notch) - position) * pitch
                    guard x > -tickWidth, x < size.width + tickWidth else { continue }

                    let tick = CGRect(
                        x: x - tickWidth / 2,
                        y: top,
                        width: tickWidth,
                        height: tickHeight
                    )
                    let ramp = min(max(x / size.width, 0), 1)
                    let shade = ExposureDial.tickShadeLeading
                        + (ExposureDial.tickShadeTrailing - ExposureDial.tickShadeLeading) * ramp
                    context.fill(
                        Path(roundedRect: tick, cornerRadius: tickWidth / 2),
                        with: .color(AppTheme.textSecondary.opacity(shade))
                    )
                }
            }
        }
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
            Text(isSet ? scale.notches[index].label : scale.blankLabel)
                .font(AppType.title)
                .foregroundStyle(AppTheme.textPrimary)
            Text(unit)
                .font(AppType.microRegular)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white, location: 0.2),
                    .init(color: .white, location: 0.8),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Only as tall as the thirds, so a whole stop's taller tick keeps its tips
            // even when the value sits right on top of it.
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

    private func commit(_ target: Int) {
        let target = clamped(target)
        guard target != selection else { return }
        selection = target
        notchesTurned += 1
    }

    private func clamped(_ target: Int) -> Int {
        min(max(target, 0), scale.notches.count - 1)
    }
}
