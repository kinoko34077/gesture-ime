import SwiftUI
import GestureIMEProfileAuthoring

struct ProductEditView: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var stageNavigation = ProfileV3EditNavigationState()
    @State private var renamingLayer = false
    @State private var confirmingLayerDelete = false

    var body: some View {
        GeometryReader { geometry in
            let layout = ProfileV3ProductEditLayoutPolicy.resolve(
                width: Double(geometry.size.width),
                height: Double(geometry.size.height)
            )

            Group {
                switch layout.mode {
                case .sideBySide:
                    HStack(spacing: 0) {
                        canvasRegion
                            .frame(width: CGFloat(layout.canvasExtent))
                        Divider()
                        inspectorRegion
                            .frame(width: CGFloat(layout.inspectorExtent))
                    }

                case .stacked:
                    VStack(spacing: 0) {
                        canvasRegion
                            .frame(height: CGFloat(layout.canvasExtent))
                        Divider()
                        inspectorRegion
                            .frame(height: CGFloat(layout.inspectorExtent))
                    }
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .navigationTitle(editor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editor.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!editor.canUndo)
                .accessibilityLabel("取り消す")

                Button {
                    editor.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!editor.canRedo)
                .accessibilityLabel("やり直す")
            }
        }
        .sheet(isPresented: $renamingLayer) {
            ProductTextEditSheet(
                title: "キーボード面の名前",
                label: "名前",
                initialValue: selectedLayerName
            ) { name in
                editor.renameSelectedLayer(name)
            }
        }
        .confirmationDialog(
            "このキーボード面を削除しますか？",
            isPresented: $confirmingLayerDelete,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                stageNavigation.reset()
                editor.deleteSelectedLayer()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private var canvasRegion: some View {
        VStack(spacing: 0) {
            contextBar
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            ProductBoardCanvas(editor: editor)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
    }

    private var inspectorRegion: some View {
        ScrollView {
            if let entry = editor.selectedEntry {
                ProductKeyInspector(
                    editor: editor,
                    entry: entry,
                    stageDepth: stageNavigation.depth,
                    onOpenNextStage: openNextStage
                )
                .id(entry.id + "@" + (editor.currentBoardID ?? ""))
            } else {
                ContentUnavailableView {
                    Label("キーを選択", systemImage: "hand.tap")
                } description: {
                    Text("上のキーボードから編集するキーを選択します。")
                }
                .padding(.vertical, 28)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var contextBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Picker(
                    "キーボード面",
                    selection: Binding(
                        get: { editor.selectedLayerID },
                        set: { id in
                            stageNavigation.reset()
                            editor.selectLayer(id)
                        }
                    )
                ) {
                    ForEach(editor.layers) { layer in
                        Text(layerDisplayName(layer))
                            .tag(layer.id)
                    }
                }
                .pickerStyle(.menu)

                layerMenu

                Spacer(minLength: 4)

                if stageNavigation.canGoBack {
                    Button {
                        goBackOneStage()
                    } label: {
                        Label("前の段階", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("前の段階へ戻る")
                }

                Text("\(stageNavigation.depth)段階目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Picker(
                "編集モード",
                selection: $editor.tool
            ) {
                ForEach(ProfileV3CanvasTool.allCases) { tool in
                    Text(ProfileV3DisplayCatalog.text(tool.displayKey).shortLabel)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var layerMenu: some View {
        Menu {
            Section("追加") {
                ForEach(ProfileV3Preset.allCases) { preset in
                    Button(ProfileV3DisplayCatalog.title(preset.displayKey)) {
                        stageNavigation.reset()
                        editor.createLayer(fromPreset: preset)
                    }
                }
            }

            Divider()

            Button("名前を変更") {
                renamingLayer = true
            }

            Button("最初に表示") {
                editor.setSelectedLayerInitial()
            }

            Button("複製") {
                duplicateCurrentLayer()
            }

            Button("削除", role: .destructive) {
                confirmingLayerDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("キーボード面の操作")
    }

    private var selectedLayerName: String {
        editor.layers
            .first(where: { $0.id == editor.selectedLayerID })?
            .name ?? ""
    }

    private func layerDisplayName(
        _ layer: ProfileV3LayerSummary
    ) -> String {
        let name = (layer.name?.isEmpty == false ? layer.name : nil)
            ?? "キーボード面"
        return layer.isInitial ? name + " ★" : name
    }

    private func duplicateCurrentLayer() {
        let suffix = UUID().uuidString.lowercased()
        let name = selectedLayerName.isEmpty
            ? "キーボード面のコピー"
            : selectedLayerName + " のコピー"
        stageNavigation.reset()
        editor.duplicateSelectedLayer(
            newLayerID: "layer.\(suffix)",
            name: name,
            newRootBoardID: "board.\(suffix)"
        )
    }

    private func openNextStage() {
        guard
            let sourceBoardID = editor.currentBoardID,
            let sourceEntryID = editor.selectedEntryID
        else {
            return
        }

        if editor.selectedNextStageBoardID == nil {
            editor.createNextStageForSelected()
        }

        guard let target = editor.selectedNextStageBoardID else {
            return
        }

        stageNavigation.push(
            sourceBoardID: sourceBoardID,
            sourceEntryID: sourceEntryID,
            destinationBoardID: target
        )
        editor.navigate(to: target)
    }

    private func goBackOneStage() {
        guard let frame = stageNavigation.pop() else {
            return
        }

        editor.navigateBack()

        guard editor.currentBoardID == frame.sourceBoardID else {
            stageNavigation.reset()
            return
        }

        if editor.entries.contains(where: { $0.id == frame.sourceEntryID }) {
            editor.selectEntry(frame.sourceEntryID)
        }
    }
}
