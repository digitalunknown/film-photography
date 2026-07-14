import SwiftUI
import UIKit

/// Offscreen-capable strip layout data. SwiftUI views can consume this; export can render via `UIImage` later.
struct FilmStripRenderModel {
    let roll: Roll
    let stock: FilmStock?
    let frames: [StripFrame]
    let layout: FilmStripLayout
    let baseColor: UIColor
    let edgeColor: UIColor

    init(roll: Roll, stock: FilmStock?) {
        self.roll = roll
        self.stock = stock
        self.frames = StripFrameBuilder.frames(for: roll)
        self.layout = FilmStripLayout.layout(for: roll.format)
        self.baseColor = UIColor(stock?.stripBaseColor ?? Color(red: 0.141, green: 0.075, blue: 0.035))
        self.edgeColor = UIColor(stock?.stripEdgePrintColor ?? Color(red: 0.85, green: 0.62, blue: 0.28))
    }

    var totalSize: CGSize {
        let cellWidth = layout.frameSize.width
        let cellHeight = layout.frameSize.height + 36
        return CGSize(width: cellWidth * CGFloat(frames.count), height: cellHeight)
    }
}

enum FilmStripRenderer {
    static func renderModel(for roll: Roll, stock: FilmStock?) -> FilmStripRenderModel {
        FilmStripRenderModel(roll: roll, stock: stock)
    }
}
