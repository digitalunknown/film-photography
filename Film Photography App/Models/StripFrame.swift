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
        let base = String(format: "%02d", index)
        return "\(base) \(base)A"
    }
}

enum StripFrameBuilder {
    static func frames(for roll: Roll) -> [StripFrame] {
        let maxPinIndex = roll.frameMarkers.map(\.frameIndex).max() ?? 0
        let maxScanFrame = roll.scanFileNames.isEmpty ? 0 : roll.scanFileNames.count + roll.scanAlignmentOffset
        let span = max(roll.totalExposures, roll.frameCount, maxPinIndex, maxScanFrame)
        let pinByIndex = pinLookup(from: roll.frameMarkers)

        return (1...span).map { index in
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

    static func layout(for format: FilmFormat, cellHeight: CGFloat = 120) -> FilmStripLayout {
        switch format {
        case .format35Full:
            let width = cellHeight * 1.5
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight), showsSprockets: true, framesPerCell: 1)
        case .format35Half:
            let width = cellHeight * 0.75
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight * 0.5), showsSprockets: true, framesPerCell: 2)
        case .format35Pano:
            let width = cellHeight * 2.4
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight), showsSprockets: true, framesPerCell: 1)
        case .format120_645:
            let width = cellHeight * 1.33
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight), showsSprockets: false, framesPerCell: 1)
        case .format120_66:
            return FilmStripLayout(frameSize: CGSize(width: cellHeight, height: cellHeight), showsSprockets: false, framesPerCell: 1)
        case .format120_67:
            let width = cellHeight * 1.17
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight), showsSprockets: false, framesPerCell: 1)
        case .format120_69:
            let width = cellHeight * 1.5
            return FilmStripLayout(frameSize: CGSize(width: width, height: cellHeight), showsSprockets: false, framesPerCell: 1)
        }
    }
}
