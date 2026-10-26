import Foundation

/// URLs the home-screen widget uses to open a roll or the add-film sheet.
enum AppDeepLink {
    static let scheme = "incamera"

    static var addFilm: URL {
        URL(string: "\(scheme)://add-film")!
    }

    static var myFilm: URL {
        URL(string: "\(scheme)://my-film")!
    }

    static func roll(_ id: UUID) -> URL {
        URL(string: "\(scheme)://roll/\(id.uuidString)")!
    }

    static func isAddFilm(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == "add-film"
    }

    static func isMyFilm(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == "my-film"
    }

    static func rollId(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "roll" else { return nil }
        let token = url.pathComponents.last { $0 != "/" }
        return token.flatMap(UUID.init(uuidString:))
    }
}
