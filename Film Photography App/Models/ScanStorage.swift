import Foundation
import ImageIO
import UIKit

/// Pure file and image I/O — deliberately off the main actor so decoding never blocks UI.
nonisolated enum ScanStorage {
    /// Decoded gate images are re-requested on every SwiftUI layout pass, so they are
    /// cached rather than re-read and re-rendered from disk each time.
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    /// Tests point this at an isolated folder so they never touch live scans.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var scansDirectory: URL {
        if let directoryOverride { return directoryOverride }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FilmPhotographyApp/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Every scan file as `(rollId, fileName)` plus the file URL, for backup.
    static func allScanFiles() -> [(rollId: UUID, fileName: String, url: URL)] {
        let fm = FileManager.default
        guard let rollDirs = try? fm.contentsOfDirectory(
            at: scansDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return rollDirs.flatMap { rollDir -> [(UUID, String, URL)] in
            guard let rollId = UUID(uuidString: rollDir.lastPathComponent),
                  let files = try? fm.contentsOfDirectory(
                    at: rollDir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  )
            else { return [] }
            return files.compactMap { file in
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { return nil }
                return (rollId, file.lastPathComponent, file)
            }
        }
    }

    /// Swap the scan tree for one unpacked from a backup. The previous tree is moved
    /// aside first so a failed copy can be put back.
    static func replaceAll(with source: URL?) throws {
        let fm = FileManager.default
        let dest = scansDirectory
        let aside = dest.deletingLastPathComponent()
            .appendingPathComponent("Scans.replaced-\(UUID().uuidString)", isDirectory: true)

        let hadDest = fm.fileExists(atPath: dest.path)
        if hadDest {
            try fm.moveItem(at: dest, to: aside)
        }

        do {
            if let source, fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: dest)
            } else {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            }
            thumbnailCache.removeAllObjects()
            if hadDest { try? fm.removeItem(at: aside) }
        } catch {
            if hadDest {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: aside, to: dest)
            }
            throw error
        }
    }

    static func saveScan(data: Data, rollId: UUID, fileName: String) -> String? {
        let rollDir = scansDirectory.appendingPathComponent(rollId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: rollDir, withIntermediateDirectories: true)
        let url = rollDir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            thumbnailCache.removeAllObjects()
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

    /// Downsamples straight out of the image source, so a 6000px scan never gets fully
    /// decoded just to fill a small gate. Pass `laidOnSide` to bake the portrait rotation
    /// into the result instead of paying for it on every draw.
    static func thumbnail(
        for rollId: UUID,
        fileName: String,
        maxSize: CGFloat = 200,
        laidOnSide: Bool = false
    ) -> UIImage? {
        let key = cacheKey(rollId: rollId, fileName: fileName, maxSize: maxSize, laidOnSide: laidOnSide)
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let fileURL = url(for: rollId, fileName: fileName)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = downsample(source, maxSize: maxSize, laidOnSide: laidOnSide)
        else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// Preview for scan data that has been picked but not written to the roll yet.
    static func preview(from data: Data, maxSize: CGFloat = 240, laidOnSide: Bool = false) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsample(source, maxSize: maxSize, laidOnSide: laidOnSide)
    }

    private static func downsample(
        _ source: CGImageSource,
        maxSize: CGFloat,
        laidOnSide: Bool
    ) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxSize, 1),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        return laidOnSide ? image.laidOnSide : image
    }

    private static func cacheKey(
        rollId: UUID,
        fileName: String,
        maxSize: CGFloat,
        laidOnSide: Bool
    ) -> NSString {
        "\(rollId.uuidString)/\(fileName)@\(Int(maxSize))\(laidOnSide ? "-side" : "")" as NSString
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
        thumbnailCache.removeAllObjects()
    }
}

nonisolated extension UIImage {
    /// Lays a portrait scan on its side so it fills the landscape frame gate. The rotation
    /// is flattened into pixels rather than left on the orientation flag, because an
    /// orientation-flagged image is re-transformed on every draw and stutters badly.
    var laidOnSide: UIImage {
        guard size.height > size.width, let cgImage else { return self }
        let oriented = UIImage(cgImage: cgImage, scale: scale, orientation: .right)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: oriented.size, format: format)
        return renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
    }
}
