import Foundation

enum DevelopmentPath: String, Codable, CaseIterable {
    case lab
    case diy

    var displayName: String {
        switch self {
        case .lab: "Lab"
        case .diy: "DIY"
        }
    }
}

struct DevelopmentRecord: Codable, Hashable {
    var path: DevelopmentPath
    var labName: String?
    var dropOffDate: Date?
    var developedDate: Date?
    var developer: String?
    var dilution: String?
    var timeMinutes: Double?
    var temperatureC: Double?
    var agitationNotes: String?

    var summary: String {
        switch path {
        case .lab:
            let lab = labName ?? "Lab"
            if let developedDate {
                return "\(lab) · \(DateFormatters.medium.string(from: developedDate))"
            }
            return lab
        case .diy:
            var parts: [String] = []
            if let developer { parts.append(developer) }
            if let dilution { parts.append(dilution) }
            if let timeMinutes { parts.append(formatMinutes(timeMinutes)) }
            if let temperatureC { parts.append("\(Int(temperatureC))°C") }
            return parts.isEmpty ? "DIY" : parts.joined(separator: " · ")
        }
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let totalSeconds = Int(minutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct DevRecipePreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var developer: String
    var dilution: String
    var timeMinutes: Double
    var temperatureC: Double
    var agitationNotes: String?

    var summary: String {
        let time = {
            let totalSeconds = Int(timeMinutes * 60)
            return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        }()
        return "\(developer) \(dilution) · \(time) · \(Int(temperatureC))°C"
    }
}
