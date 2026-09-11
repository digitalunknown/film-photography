import SwiftUI
import UIKit

struct FrameDetailEditor: View {
    @Environment(AppStore.self) private var store

    let rollId: UUID
    let frame: StripFrame
    var onViewScan: (() -> Void)?

    @State private var apertureText = ""
    @State private var shutterText = ""
    @State private var locationText = ""
    @State private var descriptionText = ""
    @State private var isLoading = false

    private var canEdit: Bool {
        frame.state != .unexposed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            InstrumentRow(label: "Frame \(frame.index)", showsDivider: false) {
                if frame.state == .scanned {
                    Button("View scan") {
                        onViewScan?()
                    }
                    .font(AppType.body)
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if canEdit {
                frameField(label: "Aperture", placeholder: "f/8", text: $apertureText, keyboard: .decimalPad)
                frameField(label: "Shutter speed", placeholder: "1/125", text: $shutterText, keyboard: .numbersAndPunctuation)
                frameField(label: "Location", placeholder: "Lafayette Sq", text: $locationText)
                frameField(label: "Description", placeholder: "Notes", text: $descriptionText, axis: .vertical)
            } else {
                Text("Frame not yet exposed.")
                    .font(AppType.callout)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .onAppear { loadFromMarker() }
        .onChange(of: frame.index) { _, _ in loadFromMarker() }
        .onChange(of: apertureText) { _, _ in saveIfNeeded() }
        .onChange(of: shutterText) { _, _ in saveIfNeeded() }
        .onChange(of: locationText) { _, _ in saveIfNeeded() }
        .onChange(of: descriptionText) { _, _ in saveIfNeeded() }
    }

    private func frameField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        InstrumentRow(label: label) {
            TextField(placeholder: placeholder, text: text, axis: axis)
                .font(AppType.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
                .keyboardType(keyboard)
        }
    }

    private func loadFromMarker() {
        isLoading = true
        defer { isLoading = false }

        guard let marker = frame.marker else {
            apertureText = ""
            shutterText = ""
            locationText = ""
            descriptionText = ""
            return
        }
        apertureText = marker.aperture.map { ExposureFormat.aperture($0) } ?? ""
        shutterText = marker.shutterSpeed.map { ExposureFormat.shutter($0) } ?? ""
        locationText = marker.location ?? ""
        descriptionText = marker.notes ?? ""
    }

    private func saveIfNeeded() {
        guard !isLoading else { return }
        save()
    }

    private func save() {
        guard canEdit else { return }

        var marker = frame.marker ?? FrameMarker(frameIndex: frame.index)
        marker.frameIndex = frame.index
        marker.aperture = parseAperture(apertureText)
        marker.shutterSpeed = ExposureFormat.parseShutter(shutterText)
        marker.location = locationText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        marker.notes = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let hasData = marker.aperture != nil
            || marker.shutterSpeed != nil
            || marker.location != nil
            || marker.notes != nil
            || frame.marker != nil

        guard hasData else { return }
        store.upsertFrameMarker(rollId, marker: marker)
    }

    private func parseAperture(_ text: String) -> Double? {
        ExposureFormat.parseAperture(text)
    }
}

enum ExposureFormat {
    static func aperture(_ value: Double) -> String {
        if value == ExposureScale.autoValue { return "Auto" }
        return "f/" + String(format: "%g", value)
    }

    static func parseAperture(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("Auto") == .orderedSame {
            return ExposureScale.autoValue
        }
        let number = trimmed
            .replacingOccurrences(of: "f/", with: "")
            .replacingOccurrences(of: "F/", with: "")
        guard !number.isEmpty else { return nil }
        return Double(number)
    }

    static func shutter(_ seconds: Double) -> String {
        if seconds == ExposureScale.autoValue { return "Auto" }
        guard seconds > 0 else { return "B" }
        if seconds >= 1 { return String(format: "%.1f", seconds) }
        let denom = Int(round(1.0 / seconds))
        return "1/\(max(denom, 1))"
    }

    static func parseShutter(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("Auto") == .orderedSame {
            return ExposureScale.autoValue
        }
        if trimmed.caseInsensitiveCompare("B") == .orderedSame {
            return ExposureScale.bulbSeconds
        }
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            guard parts.count == 2, let denom = Double(parts[1]), denom > 0 else { return nil }
            return 1.0 / denom
        }

        // A trailing "s" means seconds. A bare integer above 1 is a denominator —
        // "90" is 1/90, the way a shutter dial writes it.
        let lowered = trimmed.lowercased()
        if lowered.hasSuffix("sec") {
            trimmed = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespaces)
            return Double(trimmed)
        }
        if lowered.hasSuffix("s") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            return Double(trimmed)
        }
        guard let number = Double(trimmed) else { return nil }
        if number == floor(number), number > 1 {
            return 1 / number
        }
        return number
    }

    static func exposure(aperture: Double?, shutterSpeed: Double?) -> String? {
        var parts: [String] = []
        if let shutterSpeed {
            parts.append(shutter(shutterSpeed))
        }
        if let aperture {
            parts.append(Self.aperture(aperture))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
