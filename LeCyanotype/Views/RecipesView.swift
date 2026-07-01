import SwiftUI
import SwiftData

/// The recipe book — saved looks (process + settings), persisted with SwiftData.
/// Tapping a recipe applies it to the bench; swipe to delete.
struct RecipesView: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                if recipes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(recipes) { recipe in
                            Button { apply(recipe) } label: { row(recipe) }
                                .listRowBackground(Theme.trayDark)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Recettes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(Theme.cream)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(Theme.creamDim)
            Text("Aucune recette sauvée")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.cream)
            Text("Ajuste un procédé, puis « Sauver la recette » depuis le menu.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Theme.creamDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(recipe.process.swatch.color)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.trayEdge, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.cream)
                Text(recipe.process.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.creamDim)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.creamDim)
        }
        .padding(.vertical, 4)
    }

    private func apply(_ recipe: Recipe) {
        model.apply(recipe)
        dismiss()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(recipes[index]) }
        try? context.save()
    }
}
