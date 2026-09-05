import Foundation
import SwiftUI

enum FrameState: String, Codable, Hashable {
    case unexposed
    case exposed
    case pinned
    case scanned
}

struct StripFrame: Identifiable, Hashable {
    let index: Int
    let state: FrameState
    let marker: FrameMarker?
    let scanFileName: String?

    var id: Int { index }

    var negativeNotation: String {
        "\(index) \(index)A"
    }
}

enum StripFrameBuilder {
    static func frames(for roll: Roll) -> [StripFrame] {
        let maxPinIndex = roll.frameMarkers.map(\.frameIndex).max() ?? 0
        let maxScanFrame = roll.scanFileNames.isEmpty ? 0 : roll.scanFileNames.count + roll.scanAlignmentOffset
        let maxPhotoFrame = roll.framePhotoFileNames.keys.compactMap(Int.init).max() ?? 0
        let span = max(roll.totalExposures, roll.frameCount, maxPinIndex, maxScanFrame, maxPhotoFrame, 1)
        let pinByIndex = pinLookup(from: roll.frameMarkers)

        return (1...span).map { index in
            if let photo = roll.framePhotoFileName(forFrame: index) {
                return StripFrame(
                    index: index,
                    state: .scanned,
                    marker: pinByIndex[index],
                    scanFileName: photo
                )
            }
            let scanFile = roll.scanFileName(forFrame: index)
            if scanFile != nil {
                return StripFrame(
                    index: index,
                    state: .scanned,
                    marker: pinByIndex[index],
                    scanFileName: scanFile
                )
            }
            if let marker = pinByIndex[index] {
                return StripFrame(index: index, state: .pinned, marker: marker, scanFileName: nil)
            }
            if index <= roll.frameCount {
                return StripFrame(index: index, state: .exposed, marker: nil, scanFileName: nil)
            }
            return StripFrame(index: index, state: .unexposed, marker: nil, scanFileName: nil)
        }
    }

    private static func pinLookup(from markers: [FrameMarker]) -> [Int: FrameMarker] {
        var lookup: [Int: FrameMarker] = [:]
        for marker in markers.sorted(by: { $0.timestamp < $1.timestamp }) {
            lookup[marker.frameIndex] = marker
        }
        return lookup
    }
}

extension Roll {
    func scanFileName(forFrame frameIndex: Int) -> String? {
        let scanIndex = frameIndex - 1 - scanAlignmentOffset
        guard scanIndex >= 0, scanIndex < scanFileNames.count else { return nil }
        return scanFileNames[scanIndex]
    }
}

struct FilmStripLayout {
    let frameSize: CGSize
    let showsSprockets: Bool
    let framesPerCell: Int

    /// Aspect ratio width / height for the gate interior (not including sprocket rails).
    static func aspectRatio(for format: FilmFormat) -> CGFloat {
        switch format {
        case .format35Full: 1.5
        case .format35Half: 0.75
        case .format35Pano: 2.4
        case .format120_645: 1.33
        case .format120_66: 1.0
        case .format120_67: 1.17
        case .format120_69: 1.5
        }
    }

    static func showsSprockets(for format: FilmFormat) -> Bool {
        switch format {
        case .format35Full, .format35Half, .format35Pano: true
        default: false
        }
    }

    static func layout(for format: FilmFormat, cellHeight: CGFloat = 120) -> FilmStripLayout {
        let aspect = aspectRatio(for: format)
        let height = format == .format35Half ? cellHeight * 0.5 : cellHeight
        let width = height * aspect
        return FilmStripLayout(
            frameSize: CGSize(width: width, height: height),
            showsSprockets: showsSprockets(for: format),
            framesPerCell: format == .format35Half ? 2 : 1
        )
    }

    /// Size gates so `visibleCount` of them plus their gutters fill the strip viewport.
    /// `frameSize` is the gate itself — the caller adds `gateGap` between cells.
    static func layout(
        for format: FilmFormat,
        visibleCount: CGFloat,
        containerWidth: CGFloat,
        horizontalInset: CGFloat = 12
    ) -> FilmStripLayout {
        let usable = max(containerWidth - horizontalInset, 1)
        let count = max(visibleCount, 1)
        let gutters = FilmStripFrameMetrics.gateGap * (count - 1)
        let gateWidth = max((usable - gutters) / count, 1)
        return FilmStripLayout(
            frameSize: CGSize(width: gateWidth, height: gateHeight(for: format, gateWidth: gateWidth)),
            showsSprockets: showsSprockets(for: format),
            framesPerCell: format == .format35Half ? 2 : 1
        )
    }

    /// Gates keep their format's true aspect, so full-frame 35mm reads 3:2.
    private static func gateHeight(for format: FilmFormat, gateWidth: CGFloat) -> CGFloat {
        gateWidth / aspectRatio(for: format)
    }
}
