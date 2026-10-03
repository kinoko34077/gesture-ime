import SwiftUI

@main
struct GestureIMEApp: App {
    @StateObject private var library = ProfileLibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
        }
    }
}

private struct RootView: View {
    var body: some View {
        TabView {
            ProfileLibraryView()
                .tabItem {
                    Label("Profiles", systemImage: "keyboard")
                }

            SetupView()
                .tabItem {
                    Label("Setup", systemImage: "gearshape")
                }
        }
    }
}

private struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard Extension") {
                    Text("Gesture IME contains the iOS Keyboard Extension.")
                    Text("Enable it in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                    Text("Then switch keyboards from the globe key in a compatible text field.")
                }

                Section("Profile delivery") {
                    Text("This build edits and validates Profiles in the main app.")
                    Text("Cross-process delivery to the Keyboard Extension is intentionally deferred to the separate shared-container capability gate.")
                }
            }
            .navigationTitle("Gesture IME")
        }
    }
}
