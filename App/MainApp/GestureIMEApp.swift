import Foundation
import SwiftUI

@main
struct GestureIMEApp: App {
    @StateObject private var library = ProfileLibraryModel()
    @StateObject private var productSettings = ProductSettingsModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(productSettings)
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
    @EnvironmentObject private var productSettings: ProductSettingsModel

    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard Extension") {
                    Text("Gesture IME contains the iOS Keyboard Extension.")
                    Text("Enable it in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                    Text("Then switch keyboards from the globe key in a compatible text field.")
                }

                Section("Product settings") {
                    Stepper(
                        onIncrement: productSettings.incrementHaptic,
                        onDecrement: productSettings.decrementHaptic
                    ) {
                        HStack {
                            Text("Haptic strength")
                            Spacer()
                            Text(String(format: "%.2f", productSettings.values.hapticStrength))
                                .monospacedDigit()
                        }
                    }

                    Stepper(
                        onIncrement: productSettings.incrementHeightScale,
                        onDecrement: productSettings.decrementHeightScale
                    ) {
                        HStack {
                            Text("Keyboard height scale")
                            Spacer()
                            Text(String(format: "%.2fx", productSettings.values.keyboardHeightScale))
                                .monospacedDigit()
                        }
                    }

                    Button("Reset product settings") {
                        productSettings.reset()
                    }

                    if let errorMessage = productSettings.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Product settings delivery") {
                    Text(productSettings.deliveryStatus)
                    Text("Haptic and height values are device/product preferences and are not written into Profile v3 JSON.")
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
