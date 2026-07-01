import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import simd
import UIKit

/// The darkroom. Takes a source `CIImage` + a `Process` + `ProcessSettings` and
/// produces the finished plate: the source is run through the physically-modeled
/// `altProcess` Metal kernel (tone reproduction + toning + grain), then the Core
/// Image graph layers the real-world imperfections — bundled paper/plate texture,
/// hand-coated brush edge, chemical speckle / plate scratches, and edge falloff.
///
/// One instance, reused for every frame of the live preview and for the full-res
/// export. Textures are generated procedurally once and cached (so results look
/// real without shipping large binaries), and every step degrades gracefully if
/// the kernel or a filter is unavailable.
final class ProcessEngine {

    private let kernel: CIColorKernel?
    private let textures = TextureFoundry()

    init() {
        var loaded: CIColorKernel?
        // The kernel is compiled into the app's default Metal library at build time
        // (AltProcess.ci.metal, CoreImage stitchable). Load it by function name.
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let data = try? Data(contentsOf: url) {
            loaded = try? CIColorKernel(functionName: "altProcess", fromMetalLibraryData: data)
        }
        if loaded == nil {
            loaded = Self.loadFromAnyMetallib(function: "altProcess")
        }
        self.kernel = loaded
        if loaded == nil {
            Log.render.error("altProcess kernel failed to load — using Core Image fallback graph")
        }
    }

    private static func loadFromAnyMetallib(function: String) -> CIColorKernel? {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "metallib", subdirectory: nil) else { return nil }
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let k = try? CIColorKernel(functionName: function, fromMetalLibraryData: data) {
                return k
            }
        }
        return nil
    }

    var kernelAvailable: Bool { kernel != nil }

    // MARK: - Public render

    /// Render `source` through `process` under `settings`. Result is cropped to the
    /// source extent, ready to display or export.
    func render(_ source: CIImage, process: Process, settings: ProcessSettings) -> CIImage {
        let e = source.extent
        guard e.width > 0, e.height > 0 else { return source }

        // 1. Optional optical softness (collodion / mirror render a touch soft).
        var img = source
        if process.defaultBlur > 0.01 {
            img = img.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: process.defaultBlur])
                .cropped(to: e)
        }

        // 2. The chemistry — tone reproduction + toning + grain via the Metal kernel.
        img = chemistry(img, process: process, settings: settings, extent: e)

        // 3. Paper / plate texture, multiplied through so the tooth reads in the tone.
        img = applyTexture(img, process: process, amount: settings.texture, extent: e)

        // 4. Chemical speckle (coffee-stain flecks) or plate scratches.
        img = applyImperfections(img, process: process, extent: e)

        // 5. Hand-coated brush edge (deckle) — paper processes only.
        img = applyBrushEdge(img, process: process, amount: settings.brushEdge, extent: e)

        // 6. Edge falloff / vignette.
        img = applyVignette(img, intensity: settings.vignette, extent: e)

        return img.cropped(to: e)
    }

    // MARK: - Chemistry (kernel)

    private func chemistry(_ image: CIImage, process: Process, settings: ProcessSettings, extent: CGRect) -> CIImage {
        let grain = textures.grain(extent: extent)
        let curve = process.curve
        let tone = process.tone

        if let kernel {
            let args: [Any] = [
                image.clampedToExtent(),
                grain.clampedToExtent(),
                process.kernelIndex,
                Float(settings.exposure),
                Float(settings.contrast),
                Float(settings.toning),
                Float(settings.grain),
                curve.gamma, curve.toe, curve.shoulder,
                vec3(tone.shadow), vec3(tone.mid), vec3(tone.high), tone.pivot,
                vec3(process.spectral),
                process.metalSheen,
                process.silverGrain,
                process.bronzing,
            ]
            if let out = kernel.apply(extent: extent, arguments: args) {
                return out.cropped(to: extent)
            }
        }
        return fallbackChemistry(image, process: process, settings: settings, extent: extent)
    }

    /// Pure-Core-Image approximation used only if the Metal kernel can't load: a
    /// desaturate → contrast → duotone map with the process's shadow/highlight colours.
    private func fallbackChemistry(_ image: CIImage, process: Process, settings: ProcessSettings, extent: CGRect) -> CIImage {
        let tone = process.tone
        let mono = image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: NSNumber(value: process.desatBias * 0.6),
                kCIInputContrastKey: NSNumber(value: settings.contrast),
                kCIInputBrightnessKey: NSNumber(value: settings.exposure * 0.4),
            ])
        let duo = mono.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: CGFloat(tone.shadow.x), green: CGFloat(tone.shadow.y), blue: CGFloat(tone.shadow.z)),
            "inputColor1": CIColor(red: CGFloat(tone.high.x), green: CGFloat(tone.high.y), blue: CGFloat(tone.high.z)),
        ])
        let mixAmt = settings.toning
        // Blend toward neutral when toning is dialed down.
        return blend(top: duo, bottom: mono, alpha: mixAmt, extent: extent)
    }

    // MARK: - Texture

    private func applyTexture(_ image: CIImage, process: Process, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0.01 else { return image }
        let tex = textures.surface(for: process, extent: extent)
        // Overlay blend keeps the tone but stamps the tooth into the midtones.
        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = tex
        overlay.backgroundImage = image
        let stamped = (overlay.outputImage ?? image).cropped(to: extent)
        return blend(top: stamped, bottom: image, alpha: amount, extent: extent)
    }

    // MARK: - Imperfections

    private func applyImperfections(_ image: CIImage, process: Process, extent: CGRect) -> CIImage {
        if process.isPlate {
            // Plate scratches: thin bright streaks. Approximated with a stretched,
            // high-contrast noise field screened over the image at low opacity.
            let scratches = textures.scratches(extent: extent)
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = scratches
            screen.backgroundImage = image
            let out = (screen.outputImage ?? image).cropped(to: extent)
            return blend(top: out, bottom: image, alpha: 0.35, extent: extent)
        } else {
            // Coffee-stain / chemical speckle: sparse dark flecks multiplied in.
            let speckle = textures.speckle(extent: extent)
            let mult = CIFilter.multiplyCompositing()
            mult.inputImage = speckle
            mult.backgroundImage = image
            let out = (mult.outputImage ?? image).cropped(to: extent)
            return blend(top: out, bottom: image, alpha: 0.5, extent: extent)
        }
    }

    // MARK: - Brush edge (hand-coated deckle)

    private func applyBrushEdge(_ image: CIImage, process: Process, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0.01, !process.isPlate else { return image }
        // Paper white the coated image sits on — the process's highlight colour.
        let hi = process.tone.high
        let paper = CIImage(color: CIColor(red: CGFloat(hi.x), green: CGFloat(hi.y), blue: CGFloat(hi.z)))
            .cropped(to: extent)
        // A ragged coating mask: white in the middle, ragged toward the edges.
        let mask = textures.brushMask(extent: extent, ragged: amount)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = paper
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Vignette

    private func applyVignette(_ image: CIImage, intensity: Double, extent: CGRect) -> CIImage {
        guard intensity > 0.01 else { return image }
        let v = CIFilter.vignetteEffect()
        v.inputImage = image
        v.center = CGPoint(x: extent.midX, y: extent.midY)
        v.radius = Float(max(extent.width, extent.height) * 0.72)
        v.intensity = Float(intensity)
        v.falloff = 0.45
        return (v.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Helpers

    private func blend(top: CIImage, bottom: CIImage, alpha: Double, extent: CGRect) -> CIImage {
        let a = max(0, min(1, alpha))
        if a >= 0.999 { return top }
        if a <= 0.001 { return bottom }
        let faded = top.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a)),
        ])
        let over = CIFilter.sourceOverCompositing()
        over.inputImage = faded
        over.backgroundImage = bottom
        return (over.outputImage ?? bottom).cropped(to: extent)
    }

    private func vec3(_ v: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z))
    }
}
