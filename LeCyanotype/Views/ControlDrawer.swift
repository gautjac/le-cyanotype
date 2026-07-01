import SwiftUI

/// The controls drawer at the bench: exposure, contrast, toning, texture, vignette,
/// grain, and the hand-coated brush edge. Each is a letterpress-labelled slider that
/// re-renders the live preview on change. Brush edge disables itself for plate
/// processes (you can't hand-coat a lacquered plate).
struct ControlDrawer: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.trayEdge)
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 14) {
                    slider("Exposition", value: $model.settings.exposure,
                           range: -2...2, system: "sun.max")
                    slider("Contraste", value: $model.settings.contrast,
                           range: 0.5...1.8, system: "circle.lefthalf.filled")
                    slider("Virage", value: $model.settings.toning,
                           range: 0...1, system: "drop")
                    slider("Grain", value: $model.settings.grain,
                           range: 0...1, system: "aqi.medium")
                    slider(model.process.isPlate ? "Plaque" : "Papier",
                           value: $model.settings.texture,
                           range: 0...1, system: "square.grid.4x3.fill")
                    slider("Vignettage", value: $model.settings.vignette,
                           range: 0...1, system: "circle.dashed")
                    slider("Bord au pinceau", value: $model.settings.brushEdge,
                           range: 0...1, system: "paintbrush.pointed",
                           disabled: model.process.isPlate)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
        .frame(height: 268)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.trayDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.trayEdge, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: -4)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func slider(_ label: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        system: String,
                        disabled: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 15))
                .foregroundStyle(disabled ? Theme.creamDim.opacity(0.35) : Theme.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Theme.letterpress(label)
                Slider(value: value, in: range) { editing in
                    if !editing { model.settingsChanged() }
                }
                .tint(Theme.cyan)
                .onChange(of: value.wrappedValue) { _, _ in model.settingsChanged() }
                .disabled(disabled)
                .opacity(disabled ? 0.35 : 1)
            }
        }
    }
}
