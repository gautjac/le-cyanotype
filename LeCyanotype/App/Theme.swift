import SwiftUI

/// Le Cyanotype's visual identity: a wet-darkroom, 19th-century atelier. Deep
/// chemical-tray blacks and blues, warm letterpress cream, sepia and cyan swatches.
/// Type wants a letterpress feel — we lean on serif display for titles and a small,
/// tracked, uppercased caption for labels.
enum Theme {
    // Chemical-tray darks — the safelight gloom of the darkroom.
    static let ink       = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let trayDark  = Color(red: 0.10, green: 0.12, blue: 0.15)
    static let trayEdge  = Color(red: 0.16, green: 0.18, blue: 0.22)

    // Warm letterpress paper / cream for text on dark.
    static let cream     = Color(red: 0.93, green: 0.90, blue: 0.82)
    static let creamDim  = Color(red: 0.72, green: 0.69, blue: 0.62)

    // Process accents.
    static let cyan      = Color(red: 0.13, green: 0.42, blue: 0.62)  // cyanotype blue
    static let sepia     = Color(red: 0.55, green: 0.38, blue: 0.24)  // sepia toner
    static let silver    = Color(red: 0.66, green: 0.68, blue: 0.72)  // plate silver

    // The safelight glow used for the accent.
    static let safelight = Color(red: 0.78, green: 0.24, blue: 0.20)

    /// A letterpress caption: small, uppercased, generously tracked.
    static func letterpress(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .serif).weight(.semibold))
            .tracking(2.2)
            .foregroundStyle(Theme.creamDim)
    }

    /// A serif display title.
    static func title(_ text: String) -> some View {
        Text(text)
            .font(.system(.title2, design: .serif).weight(.semibold))
            .foregroundStyle(Theme.cream)
    }
}

extension SIMD3 where Scalar == Float {
    /// Convenience Color from a process swatch triple.
    var color: Color { Color(red: Double(x), green: Double(y), blue: Double(z)) }
}
