import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Manufactures the physical surfaces of the darkroom procedurally, so a finished
/// tirage looks like it lives on real paper or a real plate without shipping large
/// texture binaries. Each surface is generated from Core Image's noise generators
/// (deterministic per size) and cached by extent so the live preview stays cheap.
///
/// The generators are seeded so a given process on a given photo always looks the
/// same run to run — the imperfections are consistent, like a real coated sheet.
final class TextureFoundry {

    private var cache: [String: CIImage] = [:]

    private func cached(_ key: String, _ make: () -> CIImage) -> CIImage {
        if let c = cache[key] { return c }
        let img = make()
        cache[key] = img
        return img
    }

    private func sizeKey(_ extent: CGRect) -> String {
        "\(Int(extent.width))x\(Int(extent.height))"
    }

    // MARK: - Paper / plate surface

    /// The physical tooth of the support. Paper processes get a fibrous, warm-mottled
    /// deckle; plate processes get a fine, near-flat lacquer with subtle sheen.
    func surface(for process: Process, extent: CGRect) -> CIImage {
        cached("surface-\(process.rawValue)-\(sizeKey(extent))") {
            if process.isPlate {
                return plateSurface(extent: extent)
            } else {
                return paperSurface(extent: extent)
            }
        }
    }

    private func paperSurface(extent: CGRect) -> CIImage {
        // Watercolour tooth: low-frequency mottle (uneven sizing / hand-coating) plus
        // a fine fibre grain, kept near mid-grey so an overlay blend nudges tone
        // rather than tinting it.
        let mottle = CIFilter.randomGenerator().outputImage?
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0, kCIInputContrastKey: 0.9,
            ])
            .applyingGaussianBlur(sigma: max(2, extent.width / 220))
            .cropped(to: extent) ?? flat(0.5, extent: extent)
        let fibre = CIFilter.randomGenerator().outputImage?
            .transformed(by: CGAffineTransform(translationX: 137, y: 219))
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0, kCIInputContrastKey: 0.42,
            ])
            .applyingGaussianBlur(sigma: 0.5)
            .cropped(to: extent) ?? flat(0.5, extent: extent)
        // Combine mottle + fibre, recentre on 0.5 grey.
        let combined = CIFilter.overlayBlendMode()
        combined.inputImage = fibre
        combined.backgroundImage = mottle
        return recenter(combined.outputImage ?? mottle, extent: extent)
    }

    private func plateSurface(extent: CGRect) -> CIImage {
        // Lacquered iron / silvered mirror: very fine grain plus a faint diagonal
        // sheen gradient so highlights glint. Near-neutral so it doesn't muddy tone.
        let grain = CIFilter.randomGenerator().outputImage?
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0, kCIInputContrastKey: 0.24,
            ])
            .cropped(to: extent) ?? flat(0.5, extent: extent)
        let sheen = CIFilter.linearGradient()
        sheen.point0 = CGPoint(x: extent.minX, y: extent.minY)
        sheen.point1 = CGPoint(x: extent.maxX, y: extent.maxY)
        sheen.color0 = CIColor(red: 0.46, green: 0.46, blue: 0.46)
        sheen.color1 = CIColor(red: 0.56, green: 0.56, blue: 0.56)
        let sheenImg = (sheen.outputImage ?? flat(0.5, extent: extent)).cropped(to: extent)
        let combined = CIFilter.overlayBlendMode()
        combined.inputImage = grain
        combined.backgroundImage = sheenImg
        return recenter(combined.outputImage ?? sheenImg, extent: extent)
    }

    // MARK: - Grain (chemical / silver)

    /// A neutral grain field, centred on 0.5, that the kernel modulates by mid-tone.
    func grain(extent: CGRect) -> CIImage {
        cached("grain-\(sizeKey(extent))") {
            // Clumped a touch (sigma 0.7) so the grain survives display scaling and
            // reads as silver particles, not per-pixel hiss, with contrast to hold
            // amplitude after the blur.
            let n = CIFilter.randomGenerator().outputImage?
                .transformed(by: CGAffineTransform(translationX: 53, y: 91))
                .cropped(to: extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0, kCIInputContrastKey: 1.7,
                ])
                .applyingGaussianBlur(sigma: 0.7)
                .cropped(to: extent) ?? self.flat(0.5, extent: extent)
            return n
        }
    }

    // MARK: - Speckle (coffee-stain flecks)

    /// Sparse dark flecks — dust, chemical spots, coffee-stain speckle — as a mostly
    /// white field with occasional dark specks, meant to be multiplied in.
    func speckle(extent: CGRect) -> CIImage {
        cached("speckle-\(sizeKey(extent))") {
            // Thresholded noise: keep only the darkest ~4% as specks, rest white.
            let noise = CIFilter.randomGenerator().outputImage?
                .transformed(by: CGAffineTransform(translationX: 311, y: 47))
                .cropped(to: extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0, kCIInputBrightnessKey: 0.42, kCIInputContrastKey: 6.0,
                ])
                .applyingFilter("CIColorClamp")
                .cropped(to: extent) ?? self.flat(1, extent: extent)
            // Soften the specks so they read as stains, not pixels; warm them slightly.
            let soft = noise.applyingGaussianBlur(sigma: max(0.6, extent.width / 700)).cropped(to: extent)
            // Lift toward white so only the strongest flecks survive as multipliers.
            return soft.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.28,
            ]).applyingFilter("CIColorClamp").cropped(to: extent)
        }
    }

    // MARK: - Scratches (plate)

    /// Thin bright streaks for plate processes — horizontal-stretched high-contrast
    /// noise, mostly black with occasional bright lines, meant to be screened over.
    func scratches(extent: CGRect) -> CIImage {
        cached("scratch-\(sizeKey(extent))") {
            let noise = CIFilter.randomGenerator().outputImage?
                .transformed(by: CGAffineTransform(translationX: 7, y: 173))
                .cropped(to: extent) ?? self.flat(0, extent: extent)
            // Stretch vertically thin, horizontally long → streaks.
            let streaked = noise
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0, kCIInputBrightnessKey: -0.35, kCIInputContrastKey: 8.0,
                ])
                .clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [
                    kCIInputRadiusKey: max(8, extent.width / 40),
                    kCIInputAngleKey: 0.18,
                ])
                .cropped(to: extent)
            return streaked.applyingFilter("CIColorClamp").cropped(to: extent)
        }
    }

    // MARK: - Brush edge mask (hand-coated deckle)

    /// A coating mask: white (coated) in the centre, ragged/torn toward the edges by
    /// `ragged`. Used to reveal paper white where the emulsion wasn't brushed.
    func brushMask(extent: CGRect, ragged: Double) -> CIImage {
        let key = "brush-\(sizeKey(extent))-\(Int(ragged * 100))"
        return cached(key) {
            // A soft radial base: coated centre, falling off toward edges.
            let radial = CIFilter.radialGradient()
            radial.center = CGPoint(x: extent.midX, y: extent.midY)
            radial.radius0 = Float(min(extent.width, extent.height) * 0.30)
            radial.radius1 = Float(max(extent.width, extent.height) * (0.62 - 0.14 * ragged))
            radial.color0 = CIColor(red: 1, green: 1, blue: 1)
            radial.color1 = CIColor(red: 0, green: 0, blue: 0)
            let base = (radial.outputImage ?? self.flat(1, extent: extent)).cropped(to: extent)
            // Ragged edge: displace the falloff with low-freq noise so the coating
            // border looks brushed by hand, not a clean oval.
            let noise = CIFilter.randomGenerator().outputImage?
                .transformed(by: CGAffineTransform(translationX: 401, y: 233))
                .cropped(to: extent)
                .applyingGaussianBlur(sigma: max(4, extent.width / 90))
                .cropped(to: extent) ?? self.flat(0.5, extent: extent)
            let mix = CIFilter.multiplyCompositing()
            mix.inputImage = self.recenter(noise, extent: extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.5, kCIInputContrastKey: 1.0 + ragged,
                ])
            mix.backgroundImage = base
            let masked = (mix.outputImage ?? base).cropped(to: extent)
            // Keep the very centre solidly coated regardless of raggedness.
            return masked.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.1,
            ]).applyingFilter("CIColorClamp").cropped(to: extent)
        }
    }

    // MARK: - Primitives

    private func flat(_ v: Double, extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: CGFloat(v), green: CGFloat(v), blue: CGFloat(v))).cropped(to: extent)
    }

    /// Recentre a field around mid-grey (0.5) so overlay/blend nudges rather than tints.
    /// Uses a wide gain (0.8) so the surface keeps real deviation from grey — an overlay
    /// blend against a field pinned too close to 0.5 is nearly a no-op.
    private func recenter(_ image: CIImage, extent: CGRect) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.8, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.8, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.8, w: 0),
            "inputBiasVector": CIVector(x: 0.1, y: 0.1, z: 0.1, w: 0),
        ]).cropped(to: extent)
    }
}
