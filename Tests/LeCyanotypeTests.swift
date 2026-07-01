import XCTest
import CoreImage
@testable import LeCyanotype

/// Tests for the darkroom: every process has a coherent physical recipe, settings
/// defaults are chemically honest, the engine renders non-degenerate images for every
/// process, and the export path produces valid JPEG data. These run on the Simulator
/// against the bundled sample scene, so pick → process → export is verified end to end.
final class LeCyanotypeTests: XCTestCase {

    // MARK: - Process recipes

    func testAllProcessesHaveDistinctSwatches() {
        let swatches = Process.allCases.map { $0.swatch }
        for i in 0..<swatches.count {
            for j in (i+1)..<swatches.count {
                let d = distance(swatches[i], swatches[j])
                XCTAssertGreaterThan(d, 0.05, "\(Process.allCases[i]) and \(Process.allCases[j]) swatches too similar")
            }
        }
    }

    func testEveryProcessHasNonEmptyFrenchNameAndBlurb() {
        for p in Process.allCases {
            XCTAssertFalse(p.displayName.isEmpty)
            XCTAssertFalse(p.blurb.isEmpty)
        }
    }

    func testKernelIndicesAreUniqueAndContiguous() {
        let indices = Process.allCases.map { $0.kernelIndex }.sorted()
        XCTAssertEqual(indices, [0, 1, 2, 3, 4])
    }

    func testCurveConstantsArePhysicallySane() {
        for p in Process.allCases {
            let c = p.curve
            XCTAssertGreaterThan(c.gamma, 0.3, "\(p) gamma too low")
            XCTAssertLessThan(c.gamma, 3.0, "\(p) gamma too high")
            XCTAssertGreaterThanOrEqual(c.toe, 0.0)
            XCTAssertLessThanOrEqual(c.shoulder, 1.0)
        }
    }

    func testTintTypeIsHigherContrastThanDaguerreotype() {
        // Wet-plate collodion is famously contrasty; the daguerreotype is delicate.
        XCTAssertGreaterThan(Process.tintype.curve.gamma, Process.daguerreotype.curve.gamma)
    }

    func testPlateProcessesReportPlateSurface() {
        XCTAssertTrue(Process.tintype.isPlate)
        XCTAssertTrue(Process.daguerreotype.isPlate)
        XCTAssertFalse(Process.cyanotype.isPlate)
        XCTAssertFalse(Process.vandyke.isPlate)
        XCTAssertFalse(Process.saltPrint.isPlate)
    }

    func testOnlyPlateProcessesHaveMetalSheen() {
        for p in Process.allCases {
            if p.isPlate {
                XCTAssertGreaterThan(p.metalSheen, 0)
            } else {
                XCTAssertEqual(p.metalSheen, 0)
            }
        }
    }

    func testSpectralWeightsArePreservingAndBlueBiased() {
        // Every emulsion is orthochromatic-or-worse: weighted to blue, and normalised
        // so a neutral grey keeps its value (sum ≈ 1) rather than darkening or lifting.
        for p in Process.allCases {
            let s = p.spectral
            XCTAssertEqual(s.x + s.y + s.z, 1.0, accuracy: 0.01, "\(p) spectral weights should sum to ~1")
            XCTAssertGreaterThan(s.z, s.x, "\(p) should favour blue over red")
            XCTAssertGreaterThan(s.z, s.y, "\(p) should favour blue over green")
        }
    }

    func testCyanotypeIsMostSpectrallySelective() {
        // Cyanotype is nearly blind to red; the daguerreotype has the broadest response.
        XCTAssertGreaterThan(Process.cyanotype.spectral.z, Process.daguerreotype.spectral.z,
                             "Cyanotype should be the bluest-selective")
        XCTAssertLessThan(Process.cyanotype.spectral.x, Process.daguerreotype.spectral.x,
                          "Cyanotype should see the least red")
    }

    func testGrainScalesWithSilverContent() {
        // Grain is a silver phenomenon: the collodion tintype grains hardest, the
        // grainless Prussian-blue cyanotype the least.
        XCTAssertEqual(Process.tintype.silverGrain, Process.allCases.map(\.silverGrain).max())
        XCTAssertEqual(Process.cyanotype.silverGrain, Process.allCases.map(\.silverGrain).min())
        XCTAssertLessThan(Process.cyanotype.silverGrain, Process.tintype.silverGrain)
        for p in Process.allCases {
            XCTAssertGreaterThan(p.silverGrain, 0)
            XCTAssertLessThanOrEqual(p.silverGrain, 1.0)
        }
    }

    func testOnlyCyanotypeBronzes() {
        for p in Process.allCases {
            if p == .cyanotype {
                XCTAssertGreaterThan(p.bronzing, 0, "Cyanotype should bronze at Dmax")
            } else {
                XCTAssertEqual(p.bronzing, 0, "\(p) should not bronze")
            }
        }
    }

    // MARK: - Settings defaults

    func testDefaultsAreChemicallyHonest() {
        for p in Process.allCases {
            let s = ProcessSettings.defaults(for: p)
            XCTAssertEqual(s.exposure, 0, accuracy: 0.001)
            XCTAssertEqual(s.contrast, 1, accuracy: 0.001)
            XCTAssertEqual(s.toning, 1, accuracy: 0.001)
            XCTAssertEqual(s.texture, p.defaultTexture, accuracy: 0.001)
            XCTAssertEqual(s.vignette, p.defaultVignette, accuracy: 0.001)
            // Plate processes don't hand-coat, so no brush edge.
            if p.isPlate { XCTAssertEqual(s.brushEdge, 0, accuracy: 0.001) }
        }
    }

    func testTintTypeVignettesHeavierThanCyanotype() {
        XCTAssertGreaterThan(Process.tintype.defaultVignette, Process.cyanotype.defaultVignette)
    }

    // MARK: - Recipe round-trip

    func testRecipeRoundTripPreservesSettings() {
        let settings = ProcessSettings(exposure: 0.5, contrast: 1.3, toning: 0.8,
                                       texture: 0.4, vignette: 0.6, grain: 0.3, brushEdge: 0.2)
        let recipe = Recipe(name: "Essai", process: .vandyke, settings: settings)
        XCTAssertEqual(recipe.process, .vandyke)
        XCTAssertEqual(recipe.settings, settings)
    }

    // MARK: - Bundled sample

    func testBundledSampleLoadsWithPositiveExtent() {
        let img = BundledSample.image()
        XCTAssertGreaterThan(img.extent.width, 0)
        XCTAssertGreaterThan(img.extent.height, 0)
        XCTAssertTrue(img.extent.width.isFinite)
    }

    func testSynthesisedFallbackIsValid() {
        let img = BundledSample.synthesised()
        XCTAssertGreaterThan(img.extent.width, 0)
        XCTAssertGreaterThan(img.extent.height, 0)
    }

    // MARK: - Engine rendering

    func testEngineRendersEveryProcessToValidImage() {
        let engine = ProcessEngine()
        let source = BundledSample.image()
        for p in Process.allCases {
            let out = engine.render(source, process: p, settings: .defaults(for: p))
            XCTAssertEqual(out.extent.width, source.extent.width, accuracy: 1,
                           "\(p) changed extent width")
            XCTAssertEqual(out.extent.height, source.extent.height, accuracy: 1,
                           "\(p) changed extent height")
            // The rendered image must bake to a real CGImage.
            let ui = ImageExporter.uiImage(from: out)
            XCTAssertNotNil(ui, "\(p) failed to bake")
        }
    }

    func testProcessesProduceVisiblyDifferentOutput() {
        // Cyanotype (blue) and Van Dyke (brown) should differ in average colour.
        let engine = ProcessEngine()
        let source = CIUtil.downscale(BundledSample.image(), maxDimension: 200)
        let blue = averageColor(engine.render(source, process: .cyanotype, settings: .defaults(for: .cyanotype)))
        let brown = averageColor(engine.render(source, process: .vandyke, settings: .defaults(for: .vandyke)))
        // Cyanotype should be bluer (higher B relative to R); Van Dyke warmer (higher R).
        XCTAssertGreaterThan(blue.b - blue.r, brown.b - brown.r,
                             "Cyanotype should be cooler than Van Dyke")
    }

    func testExportProducesJPEGData() {
        let engine = ProcessEngine()
        let source = CIUtil.downscale(BundledSample.image(), maxDimension: 400)
        let out = engine.render(source, process: .cyanotype, settings: .defaults(for: .cyanotype))
        let data = ImageExporter.jpeg(from: out)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 1000, "JPEG suspiciously small")
    }

    func testExposureChangesBrightness() {
        let engine = ProcessEngine()
        let source = CIUtil.downscale(BundledSample.image(), maxDimension: 200)
        var dark = ProcessSettings.defaults(for: .cyanotype); dark.exposure = -1.5
        var bright = ProcessSettings.defaults(for: .cyanotype); bright.exposure = 1.5
        let dl = luminance(averageColor(engine.render(source, process: .cyanotype, settings: dark)))
        let bl = luminance(averageColor(engine.render(source, process: .cyanotype, settings: bright)))
        XCTAssertGreaterThan(bl, dl, "More exposure should read brighter")
    }

    // MARK: - Helpers

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d.x*d.x + d.y*d.y + d.z*d.z).squareRoot()
    }

    private func averageColor(_ image: CIImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let extent = image.extent
        let filter = CIFilter(name: "CIAreaAverage")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: "inputExtent")
        guard let out = filter.outputImage else { return (0,0,0) }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIUtil.context.render(out, toBitmap: &bitmap, rowBytes: 4,
                              bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                              format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (CGFloat(bitmap[0])/255, CGFloat(bitmap[1])/255, CGFloat(bitmap[2])/255)
    }

    private func luminance(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        0.2126*c.r + 0.7152*c.g + 0.0722*c.b
    }
}
