import Testing
import Foundation
import ImageIO
import UIKit
@testable import Film_Photography_App

struct ScanExportTests {

    @Test func writesFrameRecordIntoExifTiffIptcAndGps() throws {
        let source = try makeSourceJPEG()
        defer { try? FileManager.default.removeItem(at: source) }

        let metadata = ScanMetadata(
            frameIndex: 12,
            captureDate: Date(timeIntervalSince1970: 1_700_000_000),
            aperture: 5.6,
            shutterSpeed: 1.0 / 250.0,
            iso: 400,
            place: "Louvre, Paris",
            latitude: 48.8606,
            longitude: -2.3376,
            notes: "Rain on the glass",
            cameraName: "Leica M6",
            lens: "50mm Summicron",
            focalLength: 50,
            serialNumber: "1234567",
            filmStock: "Portra 400",
            filmBrand: "Kodak",
            pushPull: 1
        )

        let exported = try ScanExport.write(source: source, metadata: metadata, named: "test-frame-12.jpg")
        defer { try? FileManager.default.removeItem(at: exported) }

        let imageSource = try #require(CGImageSourceCreateWithURL(exported as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )

        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifFNumber] as? Double == 5.6)
        #expect(exif[kCGImagePropertyExifExposureTime] as? Double == 1.0 / 250.0)
        #expect((exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first == 400)
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String != nil)
        #expect(exif[kCGImagePropertyExifLensModel] as? String == "50mm Summicron")
        #expect(exif[kCGImagePropertyExifFocalLength] as? Double == 50)
        #expect(exif[kCGImagePropertyExifBodySerialNumber] as? String == "1234567")

        let comment = try #require(exif[kCGImagePropertyExifUserComment] as? String)
        #expect(comment.contains("Portra 400"))
        #expect(comment.contains("Push +1"))
        #expect(comment.contains("Leica M6"))

        // Photos wants the make beside the model, or it reports no camera information.
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "Leica")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "M6")

        // Photos shows the caption and nothing else, so the film rides along with the note.
        let iptc = try #require(properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])
        #expect(
            iptc[kCGImagePropertyIPTCCaptionAbstract] as? String
                == "Rain on the glass · Kodak Portra 400 · Push +1"
        )
        #expect(
            tiff[kCGImagePropertyTIFFImageDescription] as? String
                == "Rain on the glass · Kodak Portra 400 · Push +1"
        )
        #expect(iptc[kCGImagePropertyIPTCSubLocation] as? String == "Louvre, Paris")
        #expect((iptc[kCGImagePropertyIPTCKeywords] as? [String])?.contains("Kodak") == true)

        let gps = try #require(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect((gps[kCGImagePropertyGPSLatitude] as? Double).map { abs($0 - 48.8606) < 0.001 } == true)
        #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "N")
        #expect((gps[kCGImagePropertyGPSLongitude] as? Double).map { abs($0 - 2.3376) < 0.001 } == true)
        #expect(gps[kCGImagePropertyGPSLongitudeRef] as? String == "W")
    }

    /// Bulb has no duration, so it must not be written as a zero-second exposure.
    @Test func bulbAndEmptyFieldsAreLeftOut() throws {
        let source = try makeSourceJPEG()
        defer { try? FileManager.default.removeItem(at: source) }

        let metadata = ScanMetadata(
            frameIndex: 1,
            shutterSpeed: ExposureScale.bulbSeconds,
            place: "   ",
            latitude: 0,
            longitude: 0
        )

        let exported = try ScanExport.write(source: source, metadata: metadata, named: "test-frame-1.jpg")
        defer { try? FileManager.default.removeItem(at: exported) }

        let imageSource = try #require(CGImageSourceCreateWithURL(exported as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        #expect(exif[kCGImagePropertyExifExposureTime] == nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])?[kCGImagePropertyIPTCSubLocation] == nil)
    }

    /// A one-word camera name has no make to split off, and doubling it up would read as
    /// "Nikonos Nikonos" wherever the two are shown together.
    @Test func singleWordCameraStaysAModelOnly() throws {
        let source = try makeSourceJPEG()
        defer { try? FileManager.default.removeItem(at: source) }

        let metadata = ScanMetadata(frameIndex: 3, cameraName: "Nikonos")
        let exported = try ScanExport.write(source: source, metadata: metadata, named: "test-frame-3.jpg")
        defer { try? FileManager.default.removeItem(at: exported) }

        let imageSource = try #require(CGImageSourceCreateWithURL(exported as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])

        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "Nikonos")
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
    }

    /// A frame with no note still has to name the film, since that is the only place
    /// Photos will ever show it.
    @Test func filmAloneBecomesTheCaption() throws {
        let source = try makeSourceJPEG()
        defer { try? FileManager.default.removeItem(at: source) }

        let metadata = ScanMetadata(frameIndex: 4, filmStock: "Tri-X 400", filmBrand: "Kodak")
        let exported = try ScanExport.write(source: source, metadata: metadata, named: "test-frame-4.jpg")
        defer { try? FileManager.default.removeItem(at: exported) }

        let imageSource = try #require(CGImageSourceCreateWithURL(exported as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        let iptc = try #require(properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])

        #expect(iptc[kCGImagePropertyIPTCCaptionAbstract] as? String == "Kodak Tri-X 400")
    }

    /// Stock names usually carry the brand already, so it is not said twice.
    @Test func brandIsNotRepeatedWhenTheStockAlreadyNamesIt() {
        let metadata = ScanMetadata(
            frameIndex: 1,
            filmStock: "Kodak Gold 200",
            filmBrand: "Kodak"
        )
        #expect(metadata.filmDescription == "Kodak Gold 200")
    }

    @Test func frameLensWinsOverPrimaryOnTheBody() {
        let primary = CameraLens(
            id: UUID(),
            name: "Primary Summicron",
            focalLength: "50mm",
            maxAperture: "f/2",
            notes: "",
            isPrimary: true
        )
        let extra = CameraLens(
            id: UUID(),
            name: "Elmarit",
            focalLength: "28mm",
            maxAperture: "f/2.8",
            notes: "",
            isPrimary: false
        )
        let camera = sampleCamera(lenses: [primary, extra])
        let marker = FrameMarker(frameIndex: 5, lensId: extra.id, lensName: extra.exifModel)

        #expect(ScanMetadata.lensModel(marker: marker, camera: camera) == extra.exifModel)
        #expect(ScanMetadata.lensModel(marker: nil, camera: camera) == primary.name)
        #expect(
            ScanMetadata.lensModel(
                marker: FrameMarker(frameIndex: 1, lensName: "Kept after delete"),
                camera: camera
            ) == "Kept after delete"
        )
    }

    @Test func exportNameIsFileSystemSafe() {
        #expect(ScanExport.exportName(rollLabel: "HP5 Plus", frameIndex: 7) == "HP5-Plus-frame-7.jpg")
        #expect(ScanExport.exportName(rollLabel: "Portra 400 / #3", frameIndex: 2) == "Portra-400-3-frame-2.jpg")
        #expect(ScanExport.exportName(rollLabel: "///", frameIndex: 1) == "scan-frame-1.jpg")
    }

    private func sampleCamera(lenses: [CameraLens]) -> Camera {
        Camera(
            id: UUID(),
            name: "Leica M6",
            lensSubtitle: lenses.first?.name ?? "",
            cameraType: "Rangefinder",
            serialNumber: nil,
            purchaseDate: nil,
            purchasePrice: nil,
            photoData: nil,
            quirks: [],
            repairHistory: [],
            hasAttentionNeeded: false,
            defaultFormat: nil,
            lensMinAperture: nil,
            lensMaxAperture: nil,
            lenses: lenses
        )
    }

    /// The pixels are irrelevant here; only the container has to be a real JPEG.
    private func makeSourceJPEG() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-export-source-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }
}
