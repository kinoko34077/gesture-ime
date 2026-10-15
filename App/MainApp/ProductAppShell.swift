import SwiftUI
import GestureIMEProfileAuthoring

/// Main App shell rebuilt from the user-task contract in #186.
/// The selected Profile/editor session is shared across every task domain.
struct ProductAppShell: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @StateObject private var workspace = ProfileV3Workspace()

    var body: some View {
        let editor = workspace.editor(library: library)

        TabView {
            NavigationStack {
                Group {
                    if let editor {
                        ProductEditView(editor: editor)
                            .id(editor.profileID)
                    } else {
                        ProductEmptyWorkspace()
                    }
                }
                .toolbar {
                    scopeToolbar(editor: editor)
                }
            }
            .tabItem {
                Label(ProfileV3AppTab.edit.title, systemImage: "keyboard")
            }

            NavigationStack {
                ProductInputHome(editor: editor)
                    .toolbar {
                        scopeToolbar(editor: editor)
                    }
            }
            .tabItem {
                Label(ProfileV3AppTab.input.title, systemImage: "hand.draw")
            }

            NavigationStack {
                Group {
                    if let editor {
                        ProductDesignView(editor: editor)
                            .id(editor.profileID)
                    } else {
                        ProductEmptyWorkspace()
                    }
                }
                .toolbar {
                    scopeToolbar(editor: editor)
                }
            }
            .tabItem {
                Label(ProfileV3AppTab.design.title, systemImage: "paintpalette")
            }

            NavigationStack {
                ProductSettingsHome(editor: editor)
            }
            .tabItem {
                Label(ProfileV3AppTab.settings.title, systemImage: "gearshape")
            }
        }
    }

    @ToolbarContentBuilder
    private func scopeToolbar(
        editor: ProfileV3EditorModel?
    ) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProductProfileScopeButton(workspace: workspace)
        }

        if let editor {
            ToolbarItem(placement: .topBarTrailing) {
                ProductSaveControls(editor: editor)
            }
        }
    }
}
