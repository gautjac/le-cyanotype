import CoreImage
import simd

/// The five historical processes Le Cyanotype simulates. Each carries a
/// physically-motivated recipe — the emulsion's characteristic curve, the pigment
/// or metal it deposits (as a shadow/mid/highlight split-tone), its spectral
/// response, its texture leaning (deckle paper vs. lacquered plate), and the
/// imperfections that betray it (fog, tarnish, plate scratches, coffee speckle).
enum Process: String, CaseIterable, Identifiable, Codable {
    case cyanotype
    case tintype
    case daguerreotype
    case vandyke
    case saltPrint

    var id: String { rawValue }

    /// French display name, letterpress-cased.
    var displayName: String {
        switch self {
        case .cyanotype:     return "Cyanotype"
        case .tintype:       return "Ferrotype"
        case .daguerreotype: return "Daguerréotype"
        case .vandyke:       return "Van Dyke"
        case .saltPrint:     return "Albumine"
        }
    }

    /// A one-line note in the language of the darkroom — shown under the swatch.
    var blurb: String {
        switch self {
        case .cyanotype:
            return "Fer sensible aux UV, viré au bleu de Prusse. Papier aquarelle."
        case .tintype:
            return "Collodion humide sur fer laqué. Argent, contraste dur, vignette."
        case .daguerreotype:
            return "Miroir d'argent poli. Demi-tons délicats, ternissure aux bords."
        case .vandyke:
            return "Sel de fer et d'argent. Brun chaud, mat, sur papier chiffon."
        case .saltPrint:
            return "Chlorure d'argent viré à l'or. Sépia doux, split-tone."
        }
    }

    /// The dominant swatch colour used in the UI (chemical-tray tab).
    var swatch: SIMD3<Float> {
        switch self {
        case .cyanotype:     return SIMD3(0.09, 0.24, 0.44)  // Prussian blue
        case .tintype:       return SIMD3(0.16, 0.17, 0.19)  // cold silver-grey
        case .daguerreotype: return SIMD3(0.55, 0.57, 0.60)  // polished mirror
        case .vandyke:       return SIMD3(0.28, 0.16, 0.08)  // Van Dyke brown
        case .saltPrint:     return SIMD3(0.42, 0.30, 0.20)  // warm sepia
        }
    }

    // MARK: - Physical recipe fed to the Metal kernel

    /// Characteristic-curve constants (gamma slope, toe/fog lift, highlight shoulder).
    var curve: (gamma: Float, toe: Float, shoulder: Float) {
        switch self {
        // Cyanotype has a long, gentle scale but deep blue-black shadows.
        case .cyanotype:     return (1.15, 0.02, 0.30)
        // Wet-plate collodion is famously contrasty with hard blacks, creamy highs.
        case .tintype:       return (1.55, 0.04, 0.55)
        // Daguerreotype is delicate and low-contrast — a whisper of tone.
        case .daguerreotype: return (0.85, 0.06, 0.65)
        // Van Dyke: medium contrast, warm, rich shadow.
        case .vandyke:       return (1.25, 0.03, 0.35)
        // Salt/albumen: soft, long tonal scale, gentle shoulder.
        case .saltPrint:     return (1.05, 0.03, 0.45)
        }
    }

    /// Shadow / mid / highlight tone colours and the tonal pivot for the split-tone.
    var tone: (shadow: SIMD3<Float>, mid: SIMD3<Float>, high: SIMD3<Float>, pivot: Float) {
        switch self {
        case .cyanotype:
            // Deep Prussian blue → cyan mid → cool paper white.
            return (SIMD3(0.02, 0.09, 0.22), SIMD3(0.10, 0.34, 0.56), SIMD3(0.86, 0.93, 0.98), 0.55)
        case .tintype:
            // Near-black → cool grey → silvered off-white.
            return (SIMD3(0.03, 0.04, 0.05), SIMD3(0.30, 0.32, 0.35), SIMD3(0.90, 0.91, 0.93), 0.50)
        case .daguerreotype:
            // Charcoal → silver-blue → luminous mirror white.
            return (SIMD3(0.10, 0.11, 0.13), SIMD3(0.45, 0.48, 0.52), SIMD3(0.93, 0.95, 0.97), 0.48)
        case .vandyke:
            // Deep chocolate → warm brown → cream.
            return (SIMD3(0.08, 0.04, 0.02), SIMD3(0.34, 0.20, 0.11), SIMD3(0.92, 0.85, 0.74), 0.52)
        case .saltPrint:
            // Warm sepia shadow → tan mid → matte ivory.
            return (SIMD3(0.14, 0.09, 0.05), SIMD3(0.46, 0.34, 0.23), SIMD3(0.94, 0.90, 0.82), 0.53)
        }
    }

    /// How monochromatic the process is (0 = fully spectral/UV response, 1 = neutral luma).
    var desatBias: Float {
        switch self {
        case .cyanotype:     return 0.15  // strong UV/blue response
        case .tintype:       return 0.35  // blue-sensitive collodion
        case .daguerreotype: return 0.55
        case .vandyke:       return 0.45
        case .saltPrint:     return 0.40
        }
    }

    /// Additive metallic specular in the highlights (plate processes).
    var metalSheen: Float {
        switch self {
        case .tintype:       return 0.10
        case .daguerreotype: return 0.16
        default:             return 0.0
        }
    }

    // MARK: - Finishing defaults (Core Image graph, not the kernel)

    /// Default vignette intensity — plate processes vignette heavily.
    var defaultVignette: Double {
        switch self {
        case .tintype:       return 0.85
        case .daguerreotype: return 0.70
        case .cyanotype:     return 0.25
        case .vandyke:       return 0.35
        case .saltPrint:     return 0.30
        }
    }

    /// Default texture blend — paper processes show tooth, plate processes stay slick.
    var defaultTexture: Double {
        switch self {
        case .cyanotype:     return 0.55
        case .vandyke:       return 0.50
        case .saltPrint:     return 0.45
        case .tintype:       return 0.30
        case .daguerreotype: return 0.20
        }
    }

    /// Whether this process shows a plate (slick lacquer) vs. paper (deckle) surface.
    var isPlate: Bool { self == .tintype || self == .daguerreotype }

    /// A gentle optical softness (collodion/mirror processes render slightly soft).
    var defaultBlur: Double {
        switch self {
        case .tintype:       return 0.8
        case .daguerreotype: return 0.6
        default:             return 0.0
        }
    }

    /// Numeric selector handed to the kernel.
    var kernelIndex: Float {
        switch self {
        case .cyanotype:     return 0
        case .tintype:       return 1
        case .daguerreotype: return 2
        case .vandyke:       return 3
        case .saltPrint:     return 4
        }
    }
}
