import Foundation
import SwiftData

/// A saved recipe — one process plus its control settings. Persisted with SwiftData
/// so a look Jac dials in survives relaunch. Kept deliberately flat (all Doubles +
/// a process raw value) so it migrates trivially.
@Model
final class Recipe {
    var name: String
    var processRaw: String
    var exposure: Double
    var contrast: Double
    var toning: Double
    var texture: Double
    var vignette: Double
    var grain: Double
    var brushEdge: Double
    var createdAt: Date

    init(name: String,
         process: Process,
         settings: ProcessSettings,
         createdAt: Date = .now) {
        self.name = name
        self.processRaw = process.rawValue
        self.exposure = settings.exposure
        self.contrast = settings.contrast
        self.toning = settings.toning
        self.texture = settings.texture
        self.vignette = settings.vignette
        self.grain = settings.grain
        self.brushEdge = settings.brushEdge
        self.createdAt = createdAt
    }

    var process: Process { Process(rawValue: processRaw) ?? .cyanotype }

    var settings: ProcessSettings {
        ProcessSettings(exposure: exposure, contrast: contrast, toning: toning,
                        texture: texture, vignette: vignette, grain: grain,
                        brushEdge: brushEdge)
    }
}

/// The live control state for the darkroom — the sliders. A plain value type so it's
/// cheap to copy into the render engine every frame.
struct ProcessSettings: Equatable {
    var exposure: Double   // EV, −2…+2
    var contrast: Double   // 0.5…1.8
    var toning: Double     // 0…1
    var texture: Double    // 0…1 paper/plate texture amount
    var vignette: Double   // 0…1
    var grain: Double      // 0…1
    var brushEdge: Double  // 0…1 hand-coated deckle edge

    /// The chemically-honest starting point for a process — its defaults.
    static func defaults(for process: Process) -> ProcessSettings {
        ProcessSettings(
            exposure: 0.0,
            contrast: 1.0,
            toning: 1.0,
            texture: process.defaultTexture,
            vignette: process.defaultVignette,
            grain: process.isPlate ? 0.35 : 0.22,
            brushEdge: process.isPlate ? 0.0 : 0.45
        )
    }
}
