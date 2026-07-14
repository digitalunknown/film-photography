import Foundation
import UIKit

enum ScanStorage {
    private static var scansDirectory: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FilmPhotographyApp/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func saveScan(data: Data, rollId: UUID, fileName: String) -> String? {
        let rollDir = scansDirectory.appendingPathComponent(rollId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: rollDir, withIntermediateDirectories: true)
        let url = rollDir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func url(for rollId: UUID, fileName: String) -> URL {
        scansDirectory
            .appendingPathComponent(rollId.uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func thumbnail(for rollId: UUID, fileName: String, maxSize: CGFloat = 200) -> UIImage? {
        let fileURL = url(for: rollId, fileName: fileName)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Flattens EXIF orientation into pixel data so strip fills stay upright.
    static func normalizedJPEG(from data: Data, quality: CGFloat = 0.88) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalizedJPEG(from: image, quality: quality)
    }

    static func normalizedJPEG(from image: UIImage, quality: CGFloat = 0.88) -> Data? {
        let oriented: UIImage
        if image.imageOrientation == .up {
            oriented = image
        } else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = image.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            oriented = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        return oriented.jpegData(compressionQuality: quality)
    }

    static func deleteScan(rollId: UUID, fileName: String) {
        let fileURL = url(for: rollId, fileName: fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
