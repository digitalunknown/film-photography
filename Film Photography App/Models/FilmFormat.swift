import Foundation

enum FilmFormat: String, CaseIterable, Codable, Identifiable, Hashable {
    case format35Full = "35mm"
    case format35Half = "35mm half-frame"
    case format35Pano = "35mm panoramic"
    case format120_645 = "120 6×4.5"
    case format120_66 = "120 6×6"
    case format120_67 = "120 6×7"
    case format120_69 = "120 6×9"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var defaultExposures: Int {
        switch self {
        case .format35Full: 36
        case .format35Half: 72
        case .format35Pano: 24
        case .format120_645: 16
        case .format120_66: 12
        case .format120_67: 10
        case .format120_69: 8
        }
    }

    var is120: Bool {
        switch self {
        case .format35Full, .format35Half, .format35Pano: false
        default: true
        }
    }
}
