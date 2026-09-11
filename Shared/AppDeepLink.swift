import Foundation

/// URLs the home-screen widget uses to open a roll in the app.
enum AppDeepLink {
    static let scheme = "incamera"

    static func roll(_ id: UUID) -> URL {
        URL(string: "\(scheme)://roll/\(id.uuidString)")!
    }

    static func rollId(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "roll" else { return nil }
        let token = url.pathComponents.last { $0 != "/" }
        return token.flatMap(UUID.init(uuidString:))
    }
}
