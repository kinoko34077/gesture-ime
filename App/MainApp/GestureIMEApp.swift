import SwiftUI

@main
struct GestureIMEApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

private struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard Extension") {
                    Text("Gesture IME contains a development keyboard extension.")
                    Text("Enable it in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                    Text("Then switch keyboards from the globe key in a normal text field.")
                }

                Section("Phase 3") {
                    Text("Kana input is direct hiragana insertion for now. Kana/Kanji conversion is Phase 4.")
                    Text("Gesture sensitivity can be changed from the ⚙︎ key inside the keyboard.")
                }
            }
            .navigationTitle("Gesture IME")
        }
    }
}
