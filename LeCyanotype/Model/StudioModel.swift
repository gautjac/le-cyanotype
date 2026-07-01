import SwiftUI
import CoreImage
import Observation

/// The darkroom's brain. Holds the loaded source photograph, the chosen process, the
/// live control settings, and drives the render engine. Preview renders happen on a
/// downscaled copy for interactivity; export renders at full resolution.
@MainActor
@Observable
final class StudioModel {

    // The engine is stateless across frames; one instance for the app.
    let engine = ProcessEngine()

    /// The full-resolution source photograph currently loaded.
    private(set) var source: CIImage
    /// A downscaled copy used for the live preview (rebuilt when the source changes).
    private var previewSource: CIImage

    var process: Process = .cyanotype {
        didSet { if oldValue != process { onProcessChanged() } }
    }
    var settings: ProcessSettings = .defaults(for: .cyanotype)

    /// The rendered preview UIImage, republished whenever inputs change.
    private(set) var previewImage: UIImage?

    /// Whether the physically-modeled Metal kernel loaded (surfaced in the UI as a badge).
    var kernelAvailable: Bool { engine.kernelAvailable }

    private var renderTask: Task<Void, Never>?

    init() {
        let sample = BundledSample.image()
        self.source = sample
        self.previewSource = CIUtil.downscale(sample, maxDimension: 1200)
        scheduleRender()
    }

    // MARK: - Loading a photo

    func load(_ image: CIImage) {
        source = image
        previewSource = CIUtil.downscale(image, maxDimension: 1200)
        scheduleRender()
    }

    func loadBundledSample() {
        load(BundledSample.image())
    }

    // MARK: - Process / settings changes

    private func onProcessChanged() {
        // Adopt the chemically-honest defaults for the newly-selected process, so a tap
        // on "Ferrotype" instantly reads like a tintype before any manual tweaking.
        settings = .defaults(for: process)
        scheduleRender()
    }

    /// Reset the current process to its factory recipe.
    func resetToProcessDefaults() {
        settings = .defaults(for: process)
        scheduleRender()
    }

    /// Called by the UI after a slider edit.
    func settingsChanged() { scheduleRender() }

    // MARK: - Recipes

    func apply(_ recipe: Recipe) {
        process = recipe.process       // triggers defaults then we override below
        settings = recipe.settings
        scheduleRender()
    }

    // MARK: - Rendering

    /// Debounced live-preview render on a background priority so the sliders stay smooth.
    func scheduleRender() {
        renderTask?.cancel()
        let src = previewSource
        let proc = process
        let set = settings
        let eng = engine
        renderTask = Task { [weak self] in
            // Small debounce to coalesce rapid slider updates.
            try? await Task.sleep(nanoseconds: 12_000_000)
            if Task.isCancelled { return }
            let rendered: UIImage? = await Task.detached(priority: .userInitiated) {
                let out = eng.render(src, process: proc, settings: set)
                return ImageExporter.uiImage(from: out)
            }.value
            if Task.isCancelled { return }
            await MainActor.run { self?.previewImage = rendered }
        }
    }

    /// The full-resolution finished tirage, for export or the share sheet.
    func renderFullResolution() -> CIImage {
        engine.render(source, process: process, settings: settings)
    }

    // MARK: - Planche-contact (contact sheet)

    /// A thumbnail for each process at its default recipe, for the comparison grid.
    /// Rendered off a small copy so building the grid is cheap.
    func contactSheet() async -> [(Process, UIImage?)] {
        let thumb = CIUtil.downscale(source, maxDimension: 420)
        let eng = engine
        return await Task.detached(priority: .utility) {
            Process.allCases.map { proc in
                let out = eng.render(thumb, process: proc, settings: .defaults(for: proc))
                return (proc, ImageExporter.uiImage(from: out))
            }
        }.value
    }
}
