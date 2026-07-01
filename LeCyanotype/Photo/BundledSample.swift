import CoreImage
import UIKit

/// The bundled demo photograph, so pick → process → export is fully demoable in the
/// Simulator with no photo-library round-trip. A real still with a full tonal range
/// (sky, foliage, architecture, skin-like midtones) so every process has something to
/// bite into. Falls back to a synthesised gradient scene if the file is ever missing.
enum BundledSample {

    /// The sample as a correctly-oriented CIImage.
    static func image() -> CIImage {
        if let url = Bundle.main.url(forResource: "sample_scene", withExtension: "jpg", subdirectory: "Sample"),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data),
           let ci = CIImage(image: ui) {
            return ci
        }
        // Also try without the subdirectory (folder-reference flattening differences).
        if let url = Bundle.main.url(forResource: "sample_scene", withExtension: "jpg"),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data),
           let ci = CIImage(image: ui) {
            return ci
        }
        Log.photo.error("bundled sample missing — synthesising a fallback scene")
        return synthesised()
    }

    /// A synthesised, photographic-ish scene used only if the bundled file is absent:
    /// a gradient sky over a darker foreground with a soft luminous subject, giving the
    /// processes a real tonal range to render.
    static func synthesised() -> CIImage {
        let size = CGSize(width: 1400, height: 1000)
        let rect = CGRect(origin: .zero, size: size)

        let sky = CIFilter(name: "CILinearGradient")!
        sky.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint0")
        sky.setValue(CIVector(x: 0, y: size.height * 0.45), forKey: "inputPoint1")
        sky.setValue(CIColor(red: 0.62, green: 0.74, blue: 0.88), forKey: "inputColor0")
        sky.setValue(CIColor(red: 0.90, green: 0.92, blue: 0.95), forKey: "inputColor1")
        let skyImg = (sky.outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))).cropped(to: rect)

        let ground = CIFilter(name: "CILinearGradient")!
        ground.setValue(CIVector(x: 0, y: size.height * 0.45), forKey: "inputPoint0")
        ground.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint1")
        ground.setValue(CIColor(red: 0.30, green: 0.34, blue: 0.22), forKey: "inputColor0")
        ground.setValue(CIColor(red: 0.10, green: 0.12, blue: 0.08), forKey: "inputColor1")
        let groundImg = (ground.outputImage ?? CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2))).cropped(to: rect)

        // Split at the horizon.
        let horizonMask = CIFilter(name: "CILinearGradient")!
        horizonMask.setValue(CIVector(x: 0, y: size.height * 0.50), forKey: "inputPoint0")
        horizonMask.setValue(CIVector(x: 0, y: size.height * 0.44), forKey: "inputPoint1")
        horizonMask.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor0")
        horizonMask.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor1")
        let mask = (horizonMask.outputImage ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1))).cropped(to: rect)

        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(skyImg, forKey: kCIInputImageKey)
        blend.setValue(groundImg, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        var scene = (blend.outputImage ?? skyImg).cropped(to: rect)

        // A luminous subject — a soft warm sun/lantern — for a highlight anchor.
        let sun = CIFilter(name: "CIRadialGradient")!
        sun.setValue(CIVector(x: size.width * 0.68, y: size.height * 0.66), forKey: "inputCenter")
        sun.setValue(20.0, forKey: "inputRadius0")
        sun.setValue(180.0, forKey: "inputRadius1")
        sun.setValue(CIColor(red: 1.0, green: 0.96, blue: 0.86), forKey: "inputColor0")
        sun.setValue(CIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 0), forKey: "inputColor1")
        if let sunImg = sun.outputImage?.cropped(to: rect) {
            let over = CIFilter(name: "CISourceOverCompositing")!
            over.setValue(sunImg, forKey: kCIInputImageKey)
            over.setValue(scene, forKey: kCIInputBackgroundImageKey)
            scene = (over.outputImage ?? scene).cropped(to: rect)
        }
        return scene
    }
}
