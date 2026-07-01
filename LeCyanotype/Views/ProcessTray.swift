import SwiftUI

/// The chemical-tray process selector — a horizontal row of enamel trays, one per
/// process, each swatched in its real pigment/metal. Tapping a tray dips the photo in
/// that chemistry.
struct ProcessTray: View {
    @Binding var selected: Process

    var body: some View {
        VStack(spacing: 6) {
            Theme.letterpress("Les bains")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Process.allCases) { process in
                        trayButton(process)
                    }
                }
                .padding(.horizontal, 16)
            }
            Text(selected.blurb)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Theme.creamDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(height: 30)
                .animation(.easeInOut(duration: 0.2), value: selected)
        }
    }

    private func trayButton(_ process: Process) -> some View {
        let isOn = process == selected
        return Button {
            withAnimation(.spring(duration: 0.3)) { selected = process }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Enamel tray with a pool of chemistry.
                    RoundedRectangle(cornerRadius: 9)
                        .fill(process.swatch.color)
                        .frame(width: 62, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isOn ? Theme.cream : Theme.trayEdge,
                                        lineWidth: isOn ? 2 : 1)
                        )
                        .overlay(
                            // A little meniscus highlight so it reads as liquid.
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.22), .clear],
                                        startPoint: .top, endPoint: .center)
                                )
                                .frame(width: 62, height: 46)
                        )
                        .shadow(color: .black.opacity(isOn ? 0.5 : 0.25),
                                radius: isOn ? 8 : 3, y: 3)
                        .scaleEffect(isOn ? 1.06 : 1.0)
                    if isOn {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Text(process.displayName)
                    .font(.system(.caption2, design: .serif).weight(isOn ? .bold : .regular))
                    .foregroundStyle(isOn ? Theme.cream : Theme.creamDim)
            }
        }
        .buttonStyle(.plain)
    }
}
