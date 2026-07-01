import SwiftUI

/// The planche-contact: the current photograph run through every process side by side,
/// each at its factory recipe, so Jac can compare the chemistries at a glance and dip
/// the photo in whichever one sings. Tapping a frame selects that process and closes.
struct ContactSheetView: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var frames: [(Process, UIImage?)] = []
    @State private var loading = true

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                ScrollView {
                    if loading {
                        ProgressView("Développement…")
                            .tint(Theme.cyan)
                            .foregroundStyle(Theme.creamDim)
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(frames, id: \.0) { process, image in
                                frame(process, image)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Planche-contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Theme.cream)
                }
            }
        }
        .task {
            frames = await model.contactSheet()
            loading = false
        }
    }

    private func frame(_ process: Process, _ image: UIImage?) -> some View {
        Button {
            model.process = process
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.trayDark)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(6)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.creamDim)
                    }
                }
                .aspectRatio(1.3, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(process == model.process ? Theme.cyan : Theme.trayEdge,
                                lineWidth: process == model.process ? 2 : 1)
                )
                // Letterpress caption strip under each frame.
                HStack {
                    Circle().fill(process.swatch.color).frame(width: 8, height: 8)
                    Text(process.displayName)
                        .font(.system(.caption, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.cream)
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
