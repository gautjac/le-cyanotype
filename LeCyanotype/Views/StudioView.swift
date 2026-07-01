import SwiftUI
import SwiftData
import CoreImage

/// The atelier bench. Top: the tirage on its easel. Middle: the chemical-tray process
/// selector. Bottom: the controls drawer. A toolbar gives pick / planche-contact /
/// recipes / export.
struct StudioView: View {
    @State private var model = StudioModel()
    @State private var showPicker = false
    @State private var showContactSheet = false
    @State private var showRecipes = false
    @State private var showSaveRecipe = false
    @State private var exportState: ExportState = .idle

    @Environment(\.modelContext) private var context

    enum ExportState: Equatable { case idle, working, done, failed(String) }

    var body: some View {
        NavigationStack {
            ZStack {
                darkroomBackground
                VStack(spacing: 0) {
                    easel
                    ProcessTray(selected: $model.process)
                        .padding(.vertical, 10)
                    ControlDrawer(model: model)
                }
            }
            .navigationTitle("")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showPicker) {
                PhotoPicker { image in model.load(image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showContactSheet) {
                ContactSheetView(model: model)
            }
            .sheet(isPresented: $showRecipes) {
                RecipesView(model: model)
            }
            .alert("Nommer le tirage", isPresented: $showSaveRecipe) {
                SaveRecipeAlert(model: model, context: context)
            }
            .overlay(alignment: .top) { exportBanner }
        }
    }

    // MARK: - Easel (the tirage)

    private var easel: some View {
        GeometryReader { geo in
            ZStack {
                // The easel board.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.trayDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.trayEdge, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 8)

                if let img = model.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(14)
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .tint(Theme.cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.18), value: model.previewImage)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Background

    private var darkroomBackground: some View {
        LinearGradient(
            colors: [Theme.ink, Theme.trayDark, Theme.ink],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Le Cyanotype")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.cream)
                if !model.kernelAvailable {
                    Text("mode dégradé")
                        .font(.caption2)
                        .foregroundStyle(Theme.safelight)
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showPicker = true } label: {
                Image(systemName: "photo.on.rectangle.angled")
            }
            .accessibilityLabel("Choisir une photo")

            Menu {
                Button { showContactSheet = true } label: {
                    Label("Planche-contact", systemImage: "square.grid.3x3")
                }
                Button { showRecipes = true } label: {
                    Label("Recettes", systemImage: "book.closed")
                }
                Button { showSaveRecipe = true } label: {
                    Label("Sauver la recette", systemImage: "bookmark")
                }
                Button { model.resetToProcessDefaults() } label: {
                    Label("Réinitialiser le procédé", systemImage: "arrow.counterclockwise")
                }
                Button { model.loadBundledSample() } label: {
                    Label("Photo témoin", systemImage: "photo.artframe")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            Button { Task { await export() } } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Exporter vers Photos")
            .disabled(exportState == .working)
        }
    }

    // MARK: - Export

    private func export() async {
        exportState = .working
        let image = model.renderFullResolution()
        do {
            try await ImageExporter.saveToPhotos(image)
            exportState = .done
        } catch ImageExporter.ExportError.notAuthorised {
            exportState = .failed("Accès aux Photos refusé.")
        } catch {
            exportState = .failed("Échec de l'export.")
        }
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        exportState = .idle
    }

    @ViewBuilder
    private var exportBanner: some View {
        switch exportState {
        case .idle:
            EmptyView()
        case .working:
            banner("Tirage en cours…", system: "hourglass", tint: Theme.creamDim)
        case .done:
            banner("Tirage enregistré dans Photos", system: "checkmark.seal.fill", tint: Theme.cyan)
        case .failed(let msg):
            banner(msg, system: "exclamationmark.triangle.fill", tint: Theme.safelight)
        }
    }

    private func banner(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
            Text(text).font(.system(.subheadline, design: .serif))
        }
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(Theme.trayEdge))
        .overlay(Capsule().stroke(tint.opacity(0.7), lineWidth: 1))
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(duration: 0.35), value: exportState)
    }
}

/// The name-and-save alert body, split out to keep StudioView readable.
private struct SaveRecipeAlert: View {
    let model: StudioModel
    let context: ModelContext
    @State private var name: String = ""

    var body: some View {
        TextField("Nom", text: $name)
        Button("Sauver") {
            let recipe = Recipe(
                name: name.isEmpty ? model.process.displayName : name,
                process: model.process,
                settings: model.settings)
            context.insert(recipe)
            try? context.save()
        }
        Button("Annuler", role: .cancel) {}
    }
}
