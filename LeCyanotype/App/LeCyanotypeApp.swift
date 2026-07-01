import SwiftUI
import SwiftData

@main
struct LeCyanotypeApp: App {
    /// SwiftData store for saved recipes. Falls back to an in-memory store if the disk
    /// store can't be created, so the app never fails to launch.
    let container: ModelContainer = {
        let schema = Schema([Recipe.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }()

    var body: some Scene {
        WindowGroup {
            StudioView()
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
        .modelContainer(container)
    }
}
