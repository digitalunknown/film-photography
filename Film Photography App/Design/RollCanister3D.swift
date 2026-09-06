import CoreMotion
import RealityKit
import SwiftUI
import UIKit

/// Canister proportions measured off the flat roll artwork so the 3D model stays in
/// register with the plate art it stands in for. Values are artwork pixels; `metres`
/// converts them for RealityKit.
private enum CanisterSpec {
    static let pixel: Float = 1.0 / 1200

    static let bodyRadius: Float = 107.5
    static let bodyHeight: Float = 312

    /// Caps overhang the body and sink into it, so no two faces sit flush. The top one
    /// is the taller of the two on a real cassette, since it houses the spindle.
    static let capRadius: Float = 116.5
    static let bottomCapHeight: Float = 26
    static let topCapHeight: Float = 40
    static let capSink: Float = 2

    /// The spindle is a hollow tube with a rolled rim, not a solid nub — the bore is one
    /// of the shape's most recognisable details.
    static let spindleOuterRadius: Float = 46
    static let spindleInnerRadius: Float = 37
    static let spindleHeight: Float = 44

    /// The light trap is a slim felt-covered lip that runs the whole height and turns
    /// over both caps, rather than a block let into the shell.
    static let feltWidth: Float = 46
    static let feltDepth: Float = 32
    static let feltCentreX: Float = 105
    /// Generous against the section, so the lip reads as a rounded ridge rather than a
    /// plate seen edge-on.
    static let feltFillet: Float = 15

    /// Every edge carries a fillet. The softness is the whole point of the style: a hard
    /// 90° edge reads as CAD, a rounded one as moulded plastic.
    static let capFillet: Float = 8
    static let bodyFillet: Float = 14
    static let spindleFillet: Float = 6

    /// Body extents, which the caps and felt are placed against.
    static var bodyTop: Float { bodyHeight / 2 }
    static var bodyBottom: Float { -bodyHeight / 2 }
    /// Centres, derived so a change in cap height can't leave a part floating.
    static var bottomCapRise: Float { bodyBottom + capSink - bottomCapHeight / 2 }
    static var topCapRise: Float { bodyTop - capSink + topCapHeight / 2 }
    static var topCapCrown: Float { topCapRise + topCapHeight / 2 }
    /// Seated far enough into the cap that the bore bottoms out on it rather than
    /// showing daylight underneath.
    static var spindleRise: Float { topCapCrown - 16 + spindleHeight / 2 }
    /// The bore's dark core, set below the rim so the rim reads as a lip around a hole.
    static var spindleCore: Float { spindleRise + spindleHeight / 2 - 8 - spindleHeight * 0.35 }

    /// The felt turns over both caps, so it runs past them at each end.
    static var feltTop: Float { topCapCrown + 4 }
    static var feltBottom: Float { bottomCapRise - bottomCapHeight / 2 - 4 }
    static var feltHeight: Float { feltTop - feltBottom }
    static var feltCentreY: Float { (feltTop + feltBottom) / 2 }

    static let tongueWidth: Float = 223
    static let tongueHeight: Float = 300
    /// A few pixels off the body so the sheet hugs the cylinder without z-fighting the label.
    static let tongueWrapRadius: Float = 121
    /// How far the free end lifts off the can. Zero would glue the leader to the shell.
    static let tonguePeel: Float = 38
    /// Film leaves the felt on the +X side and wraps toward the back (−Z), so the
    /// leader sits behind the can and the label stays clear.
    static let tongueStartAngle: Float = 0
    static let tongueWrapAngle: Float = -1.28

    /// Sprocket perforations, in tongue-local artwork pixels. Scaled off the real KS-1870
    /// spec against the 300px sheet standing in for 35mm: 2.79mm along the film by
    /// 1.98mm across, on a 4.75mm pitch, with the outer edge 1.5mm off the film edge.
    /// They are wider than they are tall, which is the opposite of how they read if you
    /// go by eye.
    static let holeSize = CGSize(width: 24, height: 17)
    static let holeCorner: CGFloat = 4.5
    static let holePitch: CGFloat = 40.7
    static let holeRows: [CGFloat] = [129, -129]
    static var holeColumns: [CGFloat] { (-2...2).map { CGFloat($0) * holePitch } }

    /// Centres the assembly on the origin. The wrap sits close to the shell, so the
    /// felt is what still pulls the bounds a little off-axis.
    static let centreX: Float = 22
    static var centreY: Float { (spindleRise + spindleHeight / 2 + feltBottom) / 2 }

    /// The canister's resting three-quarter pose, before any device tilt. Just below the
    /// cap line, which keeps the crimped rim and the spindle in silhouette; tipping the
    /// phone up from here brings the cap face and the bore into view.
    static let restYaw: Float = -0.30
    static let restPitch: Float = 0.14

    static func metres(_ pixels: Float) -> Float { pixels * pixel }
}

/// Soft-shaded 3D film canister that tilts with the device. Geometry is shared across
/// every stock; only the label colour and lettering change, so one model covers the
/// whole catalog.
struct RollCanister3D: View {
    let brand: String
    let labelColor: UIColor

    @State private var tilt = CanisterTilt()

    init(stock: FilmStock) {
        self.brand = stock.brand.uppercased()
        self.labelColor = stock.rollImageName.flatMap(CanisterLabel.color(inArtwork:))
            ?? FilmStock.brandFilterTint(for: stock.brand).map { UIColor($0) }
            ?? UIColor(AppTheme.indicator)
    }

    var body: some View {
        RealityView { content in
            let scene = CanisterBuilder.scene(brand: brand, labelColor: labelColor)
            content.add(scene.root)
            tilt.attach(scene.pivot)

            // A long lens pulled well back: a wide default FOV bends the canister's
            // silhouette badly at this size.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 20
            camera.position = [0, 0, 1.15]
            content.add(camera)
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .accessibilityLabel("\(brand) film canister")
    }
}

/// Turns device attitude into the canister's pose, so it reads as an object being held
/// rather than a picture. Whatever attitude the phone is at when the view appears becomes
/// neutral, so it looks square-on however the user happens to be holding it.
@MainActor
private final class CanisterTilt {
    private let manager = CMMotionManager()
    private var reference: CMAttitude?
    private weak var pivot: Entity?
    private var pose = SIMD2<Float>(CanisterSpec.restYaw, CanisterSpec.restPitch)

    func attach(_ pivot: Entity) {
        self.pivot = pivot
        apply()
        start()
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            self.consume(attitude)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }

    private func consume(_ attitude: CMAttitude) {
        guard let relative = attitude.copy() as? CMAttitude else { return }
        guard let reference else {
            self.reference = attitude.copy() as? CMAttitude
            return
        }
        relative.multiply(byInverseOf: reference)

        // Roll swings the canister on its own axis, pitch tips it toward the viewer.
        // Both are clamped so it never turns far enough to show its blank back.
        let target = SIMD2(
            CanisterSpec.restYaw + Self.clamp(Float(relative.roll) * 1.2, 0.85),
            CanisterSpec.restPitch + Self.clamp(Float(-relative.pitch) * 0.9, 0.35)
        )
        // Ease toward the reading — raw attitude jitters enough to shimmer.
        pose += (target - pose) * 0.18
        apply()
    }

    /// Yaw first about the canister's own axis, then pitch about the camera's. Composing
    /// it the other way carries the pitch axis around with the yaw and the canister
    /// appears to roll.
    private func apply() {
        pivot?.transform.rotation = simd_quatf(angle: pose.y, axis: [1, 0, 0])
            * simd_quatf(angle: pose.x, axis: [0, 1, 0])
    }

    private static func clamp(_ value: Float, _ limit: Float) -> Float {
        min(max(value, -limit), limit)
    }
}

/// Spins a silhouette around the Y axis. RealityKit's cylinder primitive has hard rims,
/// which fight the moulded look, so the parts that need soft edges are revolved here
/// instead with the fillets built into the profile.
private enum Lathe {
    /// A revolved part, with the texture rows its straight side wall occupies. Wrapped
    /// artwork has to stay inside that range or it smears over the fillets and the end
    /// faces, which is where the arc-length coordinate turns the corner.
    struct Turned {
        let mesh: MeshResource
        let side: ClosedRange<Float>
    }

    /// Steps per fillet. Eight is past the point where the highlight rolling across the
    /// edge shows any faceting at hero size.
    private static let filletSteps = 8
    private static let segments = 72

    /// A cylinder with both rims rounded off. The caps and body are both this shape at
    /// different proportions.
    @MainActor
    static func puck(radius: Float, height: Float, fillet: Float) -> Turned? {
        let half = height / 2
        let round = min(fillet, min(radius, half))

        var profile: [SIMD2<Float>] = [[0, -half], [radius - round, -half]]
        profile += arc(centre: [radius - round, -half + round], radius: round,
                       from: -.pi / 2, to: 0)
        profile.append([radius, half - round])
        profile += arc(centre: [radius - round, half - round], radius: round,
                       from: 0, to: .pi / 2)
        profile.append([0, half])

        // The straight wall runs from the end of the lower fillet to the start of the
        // upper one.
        return revolve(profile, side: (1 + filletSteps, 2 + filletSteps))
    }

    /// An open tube with a rolled top rim — the spindle. The profile is walked up the
    /// outside, over the rim and back down the bore so the material stays to the right
    /// of travel throughout, which is what keeps the bore's normals facing inward.
    @MainActor
    static func tube(outerRadius: Float, innerRadius: Float,
                     height: Float, fillet: Float) -> Turned? {
        let half = height / 2
        let round = min(fillet, min((outerRadius - innerRadius) / 2, half))

        var profile: [SIMD2<Float>] = [[outerRadius, -half], [outerRadius, half - round]]
        profile += arc(centre: [outerRadius - round, half - round], radius: round,
                       from: 0, to: .pi / 2)
        profile.append([innerRadius + round, half])
        profile += arc(centre: [innerRadius + round, half - round], radius: round,
                       from: .pi / 2, to: .pi)
        profile.append([innerRadius, -half])

        return revolve(profile, side: (0, 1))
    }

    /// Excludes the starting point, which the caller has already placed.
    private static func arc(centre: SIMD2<Float>, radius: Float,
                            from: Float, to: Float) -> [SIMD2<Float>] {
        (1...filletSteps).map { step in
            let angle = from + (to - from) * Float(step) / Float(filletSteps)
            return centre + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    @MainActor
    private static func revolve(_ profile: [SIMD2<Float>],
                                side: (Int, Int)) -> Turned? {
        // Arc length drives the vertical texture coordinate, so a wrapped label doesn't
        // stretch as it crosses the fillets.
        var travelled: [Float] = [0]
        for index in 1..<profile.count {
            travelled.append(travelled[index - 1] + simd_distance(profile[index], profile[index - 1]))
        }
        let span = max(travelled.last ?? 1, .ulpOfOne)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []

        for (index, point) in profile.enumerated() {
            // Central difference, so normals blend across the fillet rather than
            // stepping at each segment and faceting the highlight.
            let before = profile[max(index - 1, 0)]
            let after = profile[min(index + 1, profile.count - 1)]
            let tangent = simd_normalize(after - before)
            // Perpendicular to the profile, pointing away from the axis.
            let outward = SIMD2<Float>(tangent.y, -tangent.x)

            for step in 0...segments {
                let angle = 2 * Float.pi * Float(step) / Float(segments)
                let cosine = cos(angle), sine = sin(angle)
                positions.append([point.x * cosine, point.y, point.x * sine])
                normals.append(simd_normalize([outward.x * cosine, outward.y, outward.x * sine]))
                // Inverted so row zero of a wrapped texture is the top of the part,
                // matching how the artwork is drawn.
                coordinates.append([Float(step) / Float(segments), 1 - travelled[index] / span])
            }
        }

        // The seam is duplicated so the texture wraps without a wedge of interpolation.
        let ring = segments + 1
        var indices: [UInt32] = []
        for row in 0..<(profile.count - 1) {
            for step in 0..<segments {
                let bottomLeft = UInt32(row * ring + step)
                let bottomRight = UInt32(row * ring + step + 1)
                let topLeft = UInt32((row + 1) * ring + step)
                let topRight = UInt32((row + 1) * ring + step + 1)
                indices += [bottomLeft, topLeft, bottomRight,
                            bottomRight, topLeft, topRight]
            }
        }

        var descriptor = MeshDescriptor(name: "canister-lathe")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        // The coordinate runs backwards against the profile, so the later index is the
        // lower bound.
        let rows = 1 - travelled[side.1] / span ... 1 - travelled[side.0] / span
        return Turned(mesh: mesh, side: rows)
    }
}

/// The film leader, swept around the back of the canister rather than bent away from it.
/// Real stock leaves the felt still hugging the shell — the curl is the memory of being
/// wound — and only the free end lifts off. Built in assembly space so the arc shares
/// an axis with the body.
private enum Sweep {
    private static let columns = 36

    @MainActor
    static func leader() -> MeshResource? {
        let height = CanisterSpec.metres(CanisterSpec.tongueHeight)
        let radius0 = CanisterSpec.metres(CanisterSpec.tongueWrapRadius)
        let peel = CanisterSpec.metres(CanisterSpec.tonguePeel)
        let theta0 = CanisterSpec.tongueStartAngle
        let sweep = CanisterSpec.tongueWrapAngle

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []

        for column in 0...columns {
            let across = Float(column) / Float(columns)
            let theta = theta0 + across * sweep
            // Quadratic peel, so the sheet leaves the trap tight and only the tongue lifts.
            let radius = radius0 + peel * across * across
            let cosine = cos(theta)
            let sine = sin(theta)
            let x = radius * cosine
            let z = radius * sine

            // Radial, so the wrap direction can't flip the lit face inward.
            let normal = simd_normalize(SIMD3<Float>(cosine, 0, sine))

            for row in 0...1 {
                positions.append([x, (0.5 - Float(row)) * height, z])
                normals.append(normal)
                coordinates.append([across, Float(row)])
            }
        }

        var indices: [UInt32] = []
        for column in 0..<columns {
            let corner = UInt32(column * 2)
            indices += [corner, corner + 1, corner + 2,
                        corner + 2, corner + 1, corner + 3]
        }

        var descriptor = MeshDescriptor(name: "canister-leader")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}

/// Reads the label colour out of the flat roll artwork, so the model and the plate art
/// it stands in for can't drift apart, and every stock is covered rather than the five
/// brands that carry a filter tint.
///
/// The artwork shares a template: the canister body sits in the left of the opaque
/// bounds, carrying the brand colour banded against a neutral. Sampling is relative to
/// those bounds because the art isn't consistently registered on its canvas.
private nonisolated enum CanisterLabel {
    /// Fractions of the artwork's opaque bounds that enclose the label body.
    private static let region = (x: 0.08..<0.42, y: 0.30..<0.75)
    /// Under this share of coloured pixels the label is genuinely neutral — Ilford's
    /// silver, Leica's black — rather than a brand colour banded against one.
    private static let brandShare = 0.15
    private static let chromaFloor = 0.20
    /// Outline ink, which is never the label. The bar stays low so the stocks whose
    /// labels really are near-black are not mistaken for it.
    private static let inkCeiling: UInt8 = 12

    private static let cache = NSCache<NSString, UIColor>()

    static func color(inArtwork imageName: String) -> UIColor? {
        let key = imageName as NSString
        if let known = cache.object(forKey: key) { return known }
        guard let sampled = sample(imageName) else { return nil }
        cache.setObject(sampled, forKey: key)
        return sampled
    }

    private static func sample(_ imageName: String) -> UIColor? {
        guard let image = UIImage(named: imageName)?.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let bounds = opaqueBounds(of: pixels, width: width, height: height) else {
            return nil
        }
        return dominantColor(in: pixels, width: width, bounds: bounds)
    }

    private static func opaqueBounds(of pixels: [UInt8], width: Int, height: Int) -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 127 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func dominantColor(in pixels: [UInt8], width: Int, bounds: CGRect) -> UIColor? {
        let x0 = Int(bounds.minX + region.x.lowerBound * bounds.width)
        let x1 = Int(bounds.minX + region.x.upperBound * bounds.width)
        let y0 = Int(bounds.minY + region.y.lowerBound * bounds.height)
        let y1 = Int(bounds.minY + region.y.upperBound * bounds.height)

        var everything: [UInt32: Int] = [:]
        var coloured: [UInt32: Int] = [:]
        var total = 0
        var colouredTotal = 0

        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * width + x) * 4
                // Only fully opaque pixels, which drops antialiased edges along with
                // the background and keeps the tally to the artwork's flat fills.
                guard pixels[offset + 3] == 255 else { continue }
                let red = pixels[offset], green = pixels[offset + 1], blue = pixels[offset + 2]
                if red < inkCeiling, green < inkCeiling, blue < inkCeiling { continue }

                let key = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
                everything[key, default: 0] += 1
                total += 1

                let high = max(red, green, blue), low = min(red, green, blue)
                if Double(high - low) / Double(high) > chromaFloor {
                    coloured[key, default: 0] += 1
                    colouredTotal += 1
                }
            }
        }

        guard total > 0 else { return nil }
        let pool = Double(colouredTotal) / Double(total) >= brandShare ? coloured : everything
        guard let winner = pool.max(by: { $0.value < $1.value })?.key else { return nil }

        return UIColor(red: CGFloat(winner >> 16 & 0xFF) / 255,
                       green: CGFloat(winner >> 8 & 0xFF) / 255,
                       blue: CGFloat(winner & 0xFF) / 255,
                       alpha: 1)
    }
}

private enum CanisterBuilder {
    @MainActor
    static func scene(brand: String, labelColor: UIColor) -> (root: Entity, pivot: Entity) {
        let root = Entity()

        // Lights are siblings of the pivot, not children, so tilting the canister moves
        // it through the light rather than dragging the light along with it.
        let ambient = Entity()
        if let environment = CanisterLighting.environment() {
            ambient.components.set(ImageBasedLightComponent(source: .single(environment)))
        }
        root.addChild(ambient)
        root.addChild(CanisterLighting.key())
        root.addChild(CanisterLighting.fill())

        let pivot = Entity()
        root.addChild(pivot)

        let assembly = Entity()
        assembly.position = [-CanisterSpec.metres(CanisterSpec.centreX),
                             -CanisterSpec.metres(CanisterSpec.centreY),
                             0]
        pivot.addChild(assembly)

        // Caps stay close to the body colour: they are glossy black on a real cassette
        // and only the rolled rim needs to catch a highlight. The film has its own
        // acetate colour, baked in the texture rather than tinted from this slate.
        let shell = UIColor(AppTheme.canisterBody).shaded(by: 0.8)

        if let turned = Lathe.puck(radius: CanisterSpec.metres(CanisterSpec.bodyRadius),
                                   height: CanisterSpec.metres(CanisterSpec.bodyHeight),
                                   fillet: CanisterSpec.metres(CanisterSpec.bodyFillet)),
           let print = CanisterTexture.label(color: labelColor, brand: brand, side: turned.side),
           let material = printed(print) {
            assembly.addChild(ModelEntity(mesh: turned.mesh, materials: [material]))
        }

        for (height, rise) in [(CanisterSpec.topCapHeight, CanisterSpec.topCapRise),
                               (CanisterSpec.bottomCapHeight, CanisterSpec.bottomCapRise)] {
            if let cap = puck(radius: CanisterSpec.capRadius,
                              height: height,
                              fillet: CanisterSpec.capFillet,
                              material: gloss(shell)) {
                cap.position.y = CanisterSpec.metres(rise)
                assembly.addChild(cap)
            }
        }

        if let turned = Lathe.tube(
            outerRadius: CanisterSpec.metres(CanisterSpec.spindleOuterRadius),
            innerRadius: CanisterSpec.metres(CanisterSpec.spindleInnerRadius),
            height: CanisterSpec.metres(CanisterSpec.spindleHeight),
            fillet: CanisterSpec.metres(CanisterSpec.spindleFillet)
        ) {
            let spindle = ModelEntity(mesh: turned.mesh, materials: [gloss(shell)])
            spindle.position.y = CanisterSpec.metres(CanisterSpec.spindleRise)
            assembly.addChild(spindle)
        }

        // Nothing occludes the bore, so it takes the same ambient as the spindle wall and
        // the tube reads as a solid nub. This plugs it with a near-black core set below
        // the rim, which is what the glossy rim needs to read against.
        if let bore = puck(radius: CanisterSpec.spindleInnerRadius,
                           height: CanisterSpec.spindleHeight * 0.7,
                           fillet: 2,
                           material: nap(shell.shaded(by: 0.35))) {
            bore.position.y = CanisterSpec.metres(CanisterSpec.spindleCore)
            assembly.addChild(bore)
        }

        // The light trap is felt over a crimped seam: a slim lip proud of the shell that
        // runs past both caps, rather than a housing let into the body. Matte, so it
        // stays quiet beside the glossy caps.
        let felt = ModelEntity(
            mesh: .generateBox(width: CanisterSpec.metres(CanisterSpec.feltWidth),
                               height: CanisterSpec.metres(CanisterSpec.feltHeight),
                               depth: CanisterSpec.metres(CanisterSpec.feltDepth),
                               cornerRadius: CanisterSpec.metres(CanisterSpec.feltFillet)),
            // Matte takes no highlight, so the felt needs a higher base than the glossy
            // caps just to stay off the background. Lifting the palette's slate that far
            // turns it visibly blue, so the lift is paired with a pull to neutral: it
            // reads as the same black as the caps while still separating from the page.
            materials: [nap(shell.shaded(by: 1.3).neutralised(to: 0.15))]
        )
        felt.position = [CanisterSpec.metres(CanisterSpec.feltCentreX),
                         CanisterSpec.metres(CanisterSpec.feltCentreY),
                         0]
        assembly.addChild(felt)

        if let tongue = tongueEntity() {
            assembly.addChild(tongue)
        }

        // Every surface has to opt into the image-based light by name; there is no
        // scene-wide ambient in a non-AR RealityView.
        receive(ambient, in: pivot)
        return (root, pivot)
    }

    @MainActor
    private static func receive(_ light: Entity, in entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for child in entity.children { receive(light, in: child) }
    }

    @MainActor
    private static func puck(radius: Float, height: Float, fillet: Float,
                             material: PhysicallyBasedMaterial) -> ModelEntity? {
        guard let turned = Lathe.puck(radius: CanisterSpec.metres(radius),
                                      height: CanisterSpec.metres(height),
                                      fillet: CanisterSpec.metres(fillet)) else { return nil }
        return ModelEntity(mesh: turned.mesh, materials: [material])
    }

    /// Glossy black plastic, for the caps and spindle. The tight highlight rolling round
    /// the crimped rim is what keeps them legible once they are this dark.
    @MainActor
    private static func gloss(_ color: UIColor) -> PhysicallyBasedMaterial {
        var material = surface(roughness: 0.26, specular: 0.75)
        material.baseColor = .init(tint: color)
        return material
    }

    /// Felt: no highlight at all, so the light trap stays a flat dark band.
    @MainActor
    private static func nap(_ color: UIColor) -> PhysicallyBasedMaterial {
        var material = surface(roughness: 0.97, specular: 0.04)
        material.baseColor = .init(tint: color)
        return material
    }

    /// Wrapped artwork. The tint stays white so the texture carries the colour.
    @MainActor
    private static func printed(_ image: CGImage) -> PhysicallyBasedMaterial? {
        guard let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else {
            return nil
        }
        var material = surface(roughness: 0.55, specular: 0.35)
        material.baseColor = .init(tint: .white, texture: .init(texture))
        return material
    }

    @MainActor
    private static func surface(roughness: Float, specular: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: specular)
        // The revolved parts include an inward-facing bore, whose winding runs opposite
        // to the outer wall. Normals already point the right way, so culling is the only
        // thing that would drop it.
        material.faceCulling = .none
        return material
    }

    /// The film is a double-sided sheet rather than a solid — real film has no thickness
    /// worth modelling — with the perforations and the leader taper carried as alpha so
    /// they read as cutouts. The mesh is already in assembly space, hugging the body.
    @MainActor
    private static func tongueEntity() -> ModelEntity? {
        guard let image = CanisterTexture.film(),
              let material = cutout(from: image),
              let mesh = Sweep.leader()
        else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Acetate is lacquered. Mid roughness keeps the key light's sheen broad — a tighter
    /// lobe, with only two lights and a gradient environment, reflects the dark half of
    /// that environment and the film goes black. Clearcoat adds the hard specular that
    /// the base lobe is too wide to hold on its own.
    @MainActor
    private static func cutout(from image: CGImage) -> PhysicallyBasedMaterial? {
        guard var material = printed(image) else { return nil }
        material.roughness = .init(floatLiteral: 0.24)
        material.specular = .init(floatLiteral: 1.0)
        material.clearcoat = .init(floatLiteral: 0.55)
        material.clearcoatRoughness = .init(floatLiteral: 0.18)
        material.opacityThreshold = 0.5
        return material
    }
}

private enum CanisterLighting {
    /// A soft key from upper front left. Low enough in intensity that the image-based
    /// light still carries most of the form, which is what keeps the shading gentle
    /// instead of contrasty.
    @MainActor
    static func key() -> DirectionalLight {
        let light = DirectionalLight()
        light.light.intensity = 1950
        light.light.color = .white
        light.look(at: .zero, from: [-0.45, 0.75, 1.0], relativeTo: nil)
        return light
    }

    /// A dim fill from the opposite side. Without it the shadow side goes to nearly the
    /// screen background and the canister loses its silhouette against it.
    @MainActor
    static func fill() -> DirectionalLight {
        let light = DirectionalLight()
        light.light.intensity = 700
        light.light.color = .white
        light.look(at: .zero, from: [0.9, -0.25, 0.55], relativeTo: nil)
        return light
    }

    /// A studio gradient standing in for a lit room: bright above, mid at the horizon,
    /// falling to near black below. Cheaper and far more predictable than shipping an
    /// HDR environment, and it is all the ambient a single prop needs.
    @MainActor
    static func environment() -> EnvironmentResource? {
        let size = CGSize(width: 256, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let stops: [CGColor] = [
                UIColor(white: 0.94, alpha: 1).cgColor,
                UIColor(white: 0.60, alpha: 1).cgColor,
                UIColor(white: 0.14, alpha: 1).cgColor
            ]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: stops as CFArray,
                                            locations: [0, 0.55, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? EnvironmentResource(equirectangular: cgImage)
    }
}

private extension UIColor {
    /// Whether print over this colour has to be dark or light to read.
    var isLight: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return true }
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.45
    }

    /// Scales brightness while holding hue and saturation, for baking shading into a
    /// texture without drifting off the artwork's colour.
    func shaded(by factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(hue: hue,
                       saturation: saturation,
                       brightness: min(brightness * factor, 1),
                       alpha: alpha)
    }

    /// Pulls a colour toward grey while holding its brightness, for parts that have to
    /// read as black rather than as a dark tint of the palette.
    func neutralised(to fraction: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(hue: hue,
                       saturation: saturation * fraction,
                       brightness: brightness,
                       alpha: alpha)
    }
}

private enum CanisterTexture {
    /// Artwork pixels are drawn at 3x so the perforation edges stay crisp when the hero
    /// fills the screen.
    private static let density: CGFloat = 3

    static func film() -> CGImage? {
        let width = CGFloat(CanisterSpec.tongueWidth)
        let height = CGFloat(CanisterSpec.tongueHeight)
        let size = CGSize(width: width * density, height: height * density)
        let outline = leaderOutline(width: size.width, height: size.height)

        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext

            cg.saveGState()
            cg.addPath(outline)
            cg.clip()

            // Acetate is a warm chocolate, not the canister's grey. Lit side lifted
            // enough to stay off the page; the shade side is almost black.
            let lit = UIColor(red: 0.36, green: 0.22, blue: 0.15, alpha: 1)
            let shade = UIColor(red: 0.11, green: 0.07, blue: 0.05, alpha: 1)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [lit.cgColor, shade.cgColor] as CFArray,
                                         locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: size.width, y: size.height),
                                      options: [.drawsBeforeStartLocation,
                                                .drawsAfterEndLocation])
            }

            // Lacquer sheen, baked because two lights and a gradient environment can't
            // lay a highlight this broad on a wrap this tight. Cool-white bands, the
            // colour of a specular on dark acetate, running across the length so they
            // ride the curvature as the canister tilts.
            let sheen = [
                UIColor(red: 0.78, green: 0.88, blue: 1, alpha: 0).cgColor,
                UIColor(red: 0.86, green: 0.92, blue: 1, alpha: 0.34).cgColor,
                UIColor(red: 0.78, green: 0.88, blue: 1, alpha: 0).cgColor,
                UIColor(red: 0.92, green: 0.86, blue: 0.78, alpha: 0.14).cgColor,
                UIColor(red: 0.78, green: 0.88, blue: 1, alpha: 0).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: sheen as CFArray,
                                         locations: [0, 0.22, 0.48, 0.72, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: size.width, y: 0),
                                      options: [.drawsBeforeStartLocation,
                                                .drawsAfterEndLocation])
            }
            cg.restoreGState()

            let clip = UIBezierPath(cgPath: outline)
            for row in CanisterSpec.holeRows {
                for column in CanisterSpec.holeColumns {
                    let hole = CGRect(
                        x: (column + width / 2 - CanisterSpec.holeSize.width / 2) * density,
                        y: (height / 2 - row - CanisterSpec.holeSize.height / 2) * density,
                        width: CanisterSpec.holeSize.width * density,
                        height: CanisterSpec.holeSize.height * density
                    )
                    // The tongue only keeps the top row; skip any hole the cut removed.
                    guard clip.contains(CGPoint(x: hole.midX, y: hole.midY)) else { continue }
                    cg.setBlendMode(.clear)
                    cg.addPath(UIBezierPath(roundedRect: hole,
                                            cornerRadius: CanisterSpec.holeCorner * density).cgPath)
                    cg.fillPath()
                    cg.setBlendMode(.normal)
                }
            }
        }.cgImage
    }

    /// Classic 35mm leader: full height out of the cassette, a rounded shoulder cutting
    /// away the bottom edge, then a half-height tongue with a rounded tip. Only the
    /// top perforation row survives onto the tongue.
    private static func leaderOutline(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let tip = height * 0.07
        let tongue = height * 0.50
        let fullUntil = width * 0.34
        let scoopEnd = width * 0.56

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width - tip, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: tip),
                          control: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: tongue - tip * 0.55))
        path.addQuadCurve(to: CGPoint(x: width - tip, y: tongue),
                          control: CGPoint(x: width, y: tongue))
        path.addLine(to: CGPoint(x: scoopEnd, y: tongue))
        path.addCurve(to: CGPoint(x: fullUntil, y: height),
                      control1: CGPoint(x: scoopEnd - width * 0.05, y: tongue + (height - tongue) * 0.42),
                      control2: CGPoint(x: fullUntil + width * 0.11, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    /// The label, wrapped around the body rather than applied as a flat decal, so the
    /// print follows the curve.
    ///
    /// The brand is the only real text. Everything else is abstract print — a spec
    /// panel, fine rules and a DX-style barcode — which reads as a dense film label at
    /// hero size without inventing copy for twenty-five stocks. It is laid out in the
    /// arc the camera actually sees, trailing off around the curve at both ends: the
    /// felt lip covers `u` 0, and the resting pose brings roughly `u` 0.04–0.37 to face
    /// front.
    static func label(color: UIColor, brand: String, side: ClosedRange<Float>) -> CGImage? {
        // Sized so texels come out square on the body: the wrap covers the whole
        // circumference, while the side wall covers only part of the texture's height.
        // Guessing at this leaves the print stretched one way or the other.
        let height: CGFloat = 640
        let wall = CGFloat(CanisterSpec.bodyHeight - 2 * CanisterSpec.bodyFillet)
        let girth = 2 * .pi * CGFloat(CanisterSpec.bodyRadius)
        let size = CGSize(width: girth * CGFloat(side.upperBound - side.lowerBound) * height / wall,
                          height: height)
        // Print has to read against whatever the stock's label colour is, so it flips to
        // light on the near-black labels.
        let ink = color.isLight ? UIColor(white: 0.07, alpha: 1) : UIColor(white: 0.9, alpha: 1)

        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.setFillColor(color.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Confined to the straight wall, inset so nothing runs into the fillets
            // where the wrap turns the corner and would smear.
            let wall = CGFloat(side.lowerBound) * size.height
            let depth = CGFloat(side.upperBound - side.lowerBound) * size.height
            let top = wall + depth * 0.05
            let height = depth * 0.9

            /// A stripe running up the canister, placed in label fractions: `across` is
            /// the wrap, `down` and `length` the run up the wall.
            func stripe(across: ClosedRange<CGFloat>, down: CGFloat,
                        length: CGFloat, _ fill: UIColor) {
                cg.setFillColor(fill.cgColor)
                cg.fill(CGRect(x: across.lowerBound * size.width,
                               y: top + down * height,
                               width: (across.upperBound - across.lowerBound) * size.width,
                               height: length * height))
            }

            // Spec panel butted against the felt lip, banding fine print against the
            // brand colour the way a real cassette does.
            stripe(across: 0.048...0.147, down: 0, length: 1, ink)
            stripe(across: 0.064...0.081, down: 0.05, length: 0.66, color)
            stripe(across: 0.090...0.101, down: 0.05, length: 0.42, color)
            stripe(across: 0.116...0.140, down: 0.82, length: 0.13, color)

            // Two rules of fine print and a barcode cluster, running off around the
            // curve. Kept few and heavy: thin marks at this size read as streaks.
            stripe(across: 0.302...0.313, down: 0.08, length: 0.56, ink)
            stripe(across: 0.322...0.330, down: 0.08, length: 0.34, ink)

            var across: CGFloat = 0.346
            for (index, weight) in [5, 3, 8, 3, 4, 6, 3, 9].enumerated() {
                let width = CGFloat(weight) * 0.0016
                if index.isMultiple(of: 2) {
                    stripe(across: across...(across + width), down: 0.46, length: 0.5, ink)
                }
                across += width
            }

            brandmark(brand, in: cg, ink: ink,
                      rect: CGRect(x: 0.166 * size.width, y: top,
                                   width: 0.124 * size.width, height: height))
        }.cgImage
    }

    /// Brand lettering, turned on its side to read bottom-to-top up the canister.
    private static func brandmark(_ brand: String, in cg: CGContext,
                                  ink: UIColor, rect: CGRect) {
        cg.saveGState()
        cg.translateBy(x: rect.midX, y: rect.midY)
        cg.rotate(by: -.pi / 2)

        let line = NSAttributedString(string: brand, attributes: [
            .font: UIFont.systemFont(ofSize: rect.width * 0.82, weight: .black),
            .foregroundColor: ink,
            .kern: 3
        ])
        let bounds = line.size()
        // Long brand names are squeezed rather than clipped.
        if bounds.width > rect.height {
            cg.scaleBy(x: rect.height / bounds.width, y: 1)
        }
        line.draw(at: CGPoint(x: -bounds.width / 2, y: -bounds.height / 2))
        cg.restoreGState()
    }
}
