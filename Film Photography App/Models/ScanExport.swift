import CoreLocation
import CoreTransferable
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// What the app knows about a frame, in the shape EXIF wants it. A film scan arrives from
/// the lab with nothing in it — no camera, no exposure, no date beyond when it was
/// digitised — so everything here comes from what the photographer logged while shooting.
nonisolated struct ScanMetadata: Sendable {
    var frameIndex: Int
    var captureDate: Date? = nil
    var aperture: Double? = nil
    var shutterSpeed: Double? = nil
    var iso: Int? = nil
    var place: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var notes: String? = nil
    var cameraName: String? = nil
    var lens: String? = nil
    var focalLength: Double? = nil
    var serialNumber: String? = nil
    var filmStock: String? = nil
    var filmBrand: String? = nil
    var pushPull: Int? = nil

    /// Where the frame was shot, if a fix was ever taken. Zero is a real place in the
    /// Atlantic, so it reads as unset rather than as the Gulf of Guinea.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// What the photographer wrote about the frame, with the film it was shot on. This is
    /// the description field, which is the one place Photos shows any of this — it has a
    /// caption and nothing else, so the film has to travel in here to be seen at all.
    var caption: String? {
        var parts: [String] = []
        if let notes = notes?.trimmedOrNil { parts.append(notes) }
        if let film = filmDescription { parts.append(film) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The stock as it would be written on the box, rated however it was shot.
    var filmDescription: String? {
        let brand = filmBrand?.trimmedOrNil
        let film = filmStock?.trimmedOrNil

        // Stock names often carry the brand already, so it is only prefixed when it is
        // missing — otherwise "Kodak Portra 400" comes out as "Kodak Kodak Portra 400".
        let name: String? = switch (brand, film) {
        case let (brand?, film?): film.localizedCaseInsensitiveContains(brand) ? film : "\(brand) \(film)"
        case let (brand?, nil): brand
        case let (nil, film?): film
        case (nil, nil): nil
        }
        guard let name else { return nil }

        guard let pushPull, pushPull != 0 else { return name }
        return "\(name) · \(pushPull > 0 ? "Push +\(pushPull)" : "Pull \(pushPull)")"
    }

    /// One readable line for the comment field, for tools that surface it. Everything the
    /// frame knows, in the order it would be said out loud.
    var summary: String? {
        var parts: [String] = []
        if let film = filmDescription { parts.append(film) }
        if let cameraName = cameraName?.trimmedOrNil { parts.append(cameraName) }
        if let place = place?.trimmedOrNil { parts.append(place) }
        parts.append("Frame \(frameIndex)")
        return parts.joined(separator: " · ")
    }
}

/// A scan on its way out of the app.
///
/// The file is built when the share sheet asks for it rather than up front, so exporting
/// a whole roll doesn't rewrite thirty-six images before the sheet even opens — and the
/// ones the photographer doesn't send anywhere are never written at all.
nonisolated struct ExportedScan: Identifiable, Sendable, Transferable {
    let rollId: UUID
    let fileName: String
    let exportName: String
    let metadata: ScanMetadata

    var id: String { fileName }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { scan in
            SentTransferredFile(try scan.write())
        }
        .suggestedFileName { $0.exportName }
    }

    func write() throws -> URL {
        try ScanExport.write(
            source: ScanStorage.url(for: rollId, fileName: fileName),
            metadata: metadata,
            named: exportName
        )
    }
}

@MainActor
extension ScanMetadata {
    /// Everything the roll has on record for one frame. The box speed stands in when the
    /// frame was never given an ISO of its own, since that is what the film was rated at.
    init(roll: Roll, frameIndex: Int, marker: FrameMarker?, camera: Camera?, stock: FilmStock?) {
        self.init(
            frameIndex: frameIndex,
            captureDate: marker?.captureDate,
            aperture: marker?.aperture,
            shutterSpeed: marker?.shutterSpeed,
            iso: marker?.iso ?? roll.shootingISO ?? stock?.iso,
            place: marker?.location,
            latitude: marker?.latitude,
            longitude: marker?.longitude,
            notes: marker?.notes,
            cameraName: camera?.name,
            lens: Self.lensModel(marker: marker, camera: camera),
            focalLength: Self.focalLength(marker: marker, camera: camera),
            serialNumber: camera?.serialNumber,
            filmStock: stock?.name,
            filmBrand: stock?.brand,
            pushPull: roll.pushPull
        )
    }
}

extension ScanMetadata {
    /// Frame glass first; live lens on the body if that id still exists; then the
    /// denormalized name; then the body's default. P&S and unset frames use the default.
    static func lensModel(marker: FrameMarker?, camera: Camera?) -> String? {
        if let lensId = marker?.lensId,
           let lens = camera?.lenses.first(where: { $0.id == lensId }) {
            let model = lens.exifModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !model.isEmpty { return model }
        }
        if let named = marker?.lensName?.trimmingCharacters(in: .whitespacesAndNewlines), !named.isEmpty {
            return named
        }
        let fallback = camera?.primaryLensName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }

    static func selectedLens(marker: FrameMarker?, camera: Camera?) -> CameraLens? {
        if let lensId = marker?.lensId,
           let lens = camera?.lenses.first(where: { $0.id == lensId }) {
            return lens
        }
        return camera?.primaryLens
    }

    static func focalLength(marker: FrameMarker?, camera: Camera?) -> Double? {
        selectedLens(marker: marker, camera: camera)?.focalLengthMillimeters
    }
}

@MainActor
extension ExportedScan {
    /// Every frame on the roll that has a scan behind it, in frame order.
    static func all(for roll: Roll, in store: AppStore) -> [ExportedScan] {
        let markers = Dictionary(
            roll.frameMarkers.map { ($0.frameIndex, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        let camera = roll.cameraId.flatMap { store.camera(for: $0) }
        let stock = store.stock(for: roll.stockId)

        return StripFrameBuilder.frames(for: roll).compactMap { frame in
            guard let fileName = frame.scanFileName else { return nil }
            return ExportedScan(
                roll: roll,
                frameIndex: frame.index,
                fileName: fileName,
                marker: markers[frame.index],
                camera: camera,
                stock: stock
            )
        }
    }

    init(
        roll: Roll,
        frameIndex: Int,
        fileName: String,
        marker: FrameMarker?,
        camera: Camera?,
        stock: FilmStock?
    ) {
        self.init(
            rollId: roll.id,
            fileName: fileName,
            exportName: ScanExport.exportName(rollLabel: stock?.name ?? "scan", frameIndex: frameIndex),
            metadata: ScanMetadata(
                roll: roll,
                frameIndex: frameIndex,
                marker: marker,
                camera: camera,
                stock: stock
            )
        )
    }
}

nonisolated enum ScanExport {
    enum Failure: Error {
        case unreadable
        case unwritable
    }

    /// Copies a scan out to a temporary file with the app's record of the shot written
    /// into it. The encoded image is passed straight through — only the metadata around
    /// it is rewritten — so exporting never costs the scan any quality, however many
    /// times it is done.
    static func write(source: URL, metadata: ScanMetadata, named exportName: String) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let containerType = CGImageSourceGetType(imageSource)
        else { throw Failure.unreadable }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent(exportName)
        try? FileManager.default.removeItem(at: destinationURL)

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            containerType,
            1,
            nil
        ) else { throw Failure.unwritable }

        let existing = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        CGImageDestinationAddImageFromSource(
            destination,
            imageSource,
            0,
            properties(merging: existing, with: metadata) as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable }
        return destinationURL
    }

    /// A scan may already carry properties from whatever digitised it, so the app's own
    /// record is layered over what is there rather than replacing it wholesale.
    private static func properties(
        merging existing: [CFString: Any],
        with metadata: ScanMetadata
    ) -> [CFString: Any] {
        var properties = existing
        var exif = existing[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var tiff = existing[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var iptc = existing[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        if let aperture = metadata.aperture, aperture > 0 {
            exif[kCGImagePropertyExifFNumber] = aperture
            exif[kCGImagePropertyExifApertureValue] = 2 * log2(aperture)
        }

        // Bulb is held open by hand, so there is no duration to record. Writing it as
        // zero would read as an instantaneous exposure, which is worse than silence.
        if let shutter = metadata.shutterSpeed, shutter > 0 {
            exif[kCGImagePropertyExifExposureTime] = shutter
            exif[kCGImagePropertyExifShutterSpeedValue] = -log2(shutter)
        }

        if let iso = metadata.iso, iso > 0 {
            exif[kCGImagePropertyExifISOSpeedRatings] = [iso]
        }

        // The date the frame was shot, not the date it was scanned — which is all the
        // file itself would otherwise know.
        if let captureDate = metadata.captureDate {
            let stamp = exifDate.string(from: captureDate)
            exif[kCGImagePropertyExifDateTimeOriginal] = stamp
            exif[kCGImagePropertyExifDateTimeDigitized] = stamp
            tiff[kCGImagePropertyTIFFDateTime] = stamp
        }

        if let lens = metadata.lens?.trimmedOrNil {
            exif[kCGImagePropertyExifLensModel] = lens
        }
        if let focalLength = metadata.focalLength, focalLength > 0 {
            exif[kCGImagePropertyExifFocalLength] = focalLength
        }
        if let serial = metadata.serialNumber?.trimmedOrNil {
            exif[kCGImagePropertyExifBodySerialNumber] = serial
        }
        if let summary = metadata.summary {
            exif[kCGImagePropertyExifUserComment] = summary
        }
        // Photos reports "no camera information" unless the make is there beside the
        // model, so a name like "Leica M6" is split into the two the format expects. A
        // single-word name is left as a model on its own rather than doubled up.
        if let camera = metadata.cameraName?.trimmedOrNil {
            let words = camera.split(separator: " ", maxSplits: 1).map(String.init)
            if words.count == 2 {
                tiff[kCGImagePropertyTIFFMake] = words[0]
                tiff[kCGImagePropertyTIFFModel] = words[1]
            } else {
                tiff[kCGImagePropertyTIFFModel] = camera
            }
        }
        // Photos reads its caption out of the description, and readers disagree about
        // where that lives — IPTC for some, the older TIFF tag for others — so it goes in
        // both. This is also the only field Photos will show the film in.
        if let caption = metadata.caption {
            iptc[kCGImagePropertyIPTCCaptionAbstract] = caption
            tiff[kCGImagePropertyTIFFImageDescription] = caption
        }
        if let place = metadata.place?.trimmedOrNil {
            iptc[kCGImagePropertyIPTCSubLocation] = place
        }

        let keywords = [metadata.filmBrand, metadata.filmStock].compactMap(\.?.trimmedOrNil)
        if !keywords.isEmpty {
            iptc[kCGImagePropertyIPTCKeywords] = keywords
        }
        if let gps = gps(for: metadata) {
            properties[kCGImagePropertyGPSDictionary] = gps
        }

        properties[kCGImagePropertyExifDictionary] = exif
        properties[kCGImagePropertyTIFFDictionary] = tiff
        if !iptc.isEmpty {
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }
        return properties
    }

    /// EXIF stores coordinates unsigned, with the hemisphere alongside. A frame with no
    /// fix reads as zero, which is a real place in the Atlantic, so it is left out.
    private static func gps(for metadata: ScanMetadata) -> [CFString: Any]? {
        guard let latitude = metadata.latitude,
              let longitude = metadata.longitude,
              latitude != 0 || longitude != 0
        else { return nil }

        return [
            kCGImagePropertyGPSLatitude: abs(latitude),
            kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(longitude),
            kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W",
        ]
    }

    private static let exifDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    /// File name for the share sheet. Anything a file system would object to is dropped,
    /// since stock names carry slashes and plus signs of their own.
    static func exportName(rollLabel: String, frameIndex: Int) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let label = rollLabel.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { name, character in
                // Runs of stripped characters collapse rather than stacking up dashes.
                if character == "-", name.last == "-" { return }
                name.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let stem = label.isEmpty ? "scan" : label
        return "\(stem)-frame-\(frameIndex).jpg"
    }
}

/// Saving into Photos, keeping everything the export wrote.
///
/// The file is handed over whole rather than as a decoded image: passing a `UIImage` — or
/// going through an intermediary that re-encodes on the way — leaves Photos with bare
/// pixels and drops the camera, exposure, date and place along with the rest of the EXIF.
nonisolated enum PhotoLibraryExport {
    enum Failure: LocalizedError {
        case accessDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "In Camera needs permission to add photos. You can grant it in Settings."
            case .saveFailed(let reason):
                reason
            }
        }
    }

    static func save(_ scans: [ExportedScan]) async throws {
        guard !scans.isEmpty else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.accessDenied }

        // Rewriting the metadata means reading and re-muxing each file, so it happens off
        // the main actor — a whole roll is thirty-six of them.
        let files = try await Task.detached(priority: .userInitiated) {
            try scans.map { scan in (url: try scan.write(), scan: scan) }
        }.value

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for file in files {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = file.scan.exportName
                    request.addResource(with: .photo, fileURL: file.url, options: options)

                    // Photos files an asset by its own date and location rather than by
                    // reading them back out of the file, so both are set here too.
                    if let captureDate = file.scan.metadata.captureDate {
                        request.creationDate = captureDate
                    }
                    if let coordinate = file.scan.metadata.coordinate {
                        request.location = CLLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    }
                }
            }
        } catch {
            throw Failure.saveFailed(error.localizedDescription)
        }
    }
}

nonisolated private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
