import Foundation
import UIKit
import KeyboardExtensionUtils
import KanaKanjiConverterModuleWithDefaultDictionary

struct CompositionCandidateSnapshot: Equatable, Sendable {
    let index: Int
    let text: String
    let selected: Bool
}

actor AzooKeyConversionWorker {
    private let converter: KanaKanjiConverter
    private let options: ConvertRequestOptions

    init() {
        self.converter = KanaKanjiConverter.withDefaultDictionary(preloadDictionary: false)

        let fileManager = FileManager.default
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let storage = base.appendingPathComponent("GestureIMEConverter", isDirectory: true)
        try? fileManager.createDirectory(at: storage, withIntermediateDirectories: true)

        self.options = ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: true,
            learningType: .nothing,
            maxMemoryCount: 0,
            shouldResetMemory: false,
            memoryDirectoryURL: storage,
            sharedContainerURL: storage,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "Gesture IME")
        )

        self.converter.setKeyboardLanguage(.ja_JP)
    }

    func requestCandidates(for composing: ComposingText) -> [Candidate] {
        guard !composing.isEmpty else { return [] }
        return converter.requestCandidates(composing, options: options).mainResults
    }

    func selected(_ candidate: Candidate) {
        converter.setCompletedData(candidate)
    }

    func stopComposition() {
        converter.stopComposition()
    }
}

@MainActor
final class AzooKeyCompositionBridge {
    private let displayedTextManager = DisplayedTextManager(
        isLiveConversionEnabled: false,
        isMarkedTextEnabled: true
    )
    private let worker = AzooKeyConversionWorker()

    private var composingText = ComposingText()
    private var candidates: [Candidate] = []
    private var selectedCandidateIndex: Int?
    private var revision = 0

    var onCandidatesChanged: (([CompositionCandidateSnapshot]) -> Void)?

    init(proxy: any UITextDocumentProxy) {
        displayedTextManager.setTextDocumentProxy(.mainProxy(proxy))
    }

    var isComposing: Bool {
        !composingText.isEmpty
    }

    func setTextDocumentProxy(_ proxy: any UITextDocumentProxy) {
        displayedTextManager.setTextDocumentProxy(.mainProxy(proxy))
    }

    func insert(_ text: String) {
        guard !text.isEmpty else { return }

        if text == " " || text == "　" {
            if isComposing {
                cycleCandidate()
            } else {
                displayedTextManager.insertText(text)
            }
            return
        }

        if text == "\n" || text == "\t" {
            commitSelectionOrRaw()
            displayedTextManager.insertText(text)
            return
        }

        selectedCandidateIndex = nil
        composingText.insertAtCursorPosition(text, inputStyle: .direct)
        displayedTextManager.updateComposingText(
            composingText: composingText,
            newLiveConversionText: nil
        )
        refreshCandidates()
    }

    func directInsert(_ text: String) {
        commitSelectionOrRaw()
        displayedTextManager.insertText(text)
    }

    func deleteBackward(count: Int) {
        guard count > 0 else { return }

        if composingText.isEmpty {
            displayedTextManager.deleteBackward(count: count)
            return
        }

        selectedCandidateIndex = nil
        composingText.deleteBackwardFromCursorPosition(count: count)
        displayedTextManager.updateComposingText(
            composingText: composingText,
            newLiveConversionText: nil
        )

        if composingText.isEmpty {
            displayedTextManager.stopComposition()
            clearCandidates()
            Task { await worker.stopComposition() }
        } else {
            refreshCandidates()
        }
    }

    func moveCursor(_ offset: Int) {
        guard offset != 0 else { return }
        commitSelectionOrRaw()
        displayedTextManager.moveCursor(count: offset)
    }

    func selectCandidate(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        let candidate = candidates[index]

        composingText.prefixComplete(composingCount: candidate.composingCount)
        displayedTextManager.updateComposingText(
            composingText: composingText,
            completedPrefix: candidate.text,
            isSelected: false
        )

        revision += 1
        selectedCandidateIndex = nil
        Task { await worker.selected(candidate) }

        if composingText.isEmpty {
            displayedTextManager.stopComposition()
            clearCandidates()
            Task { await worker.stopComposition() }
        } else {
            refreshCandidates()
        }
    }

    func commitSelectionOrRaw() {
        if let selectedCandidateIndex,
           candidates.indices.contains(selectedCandidateIndex) {
            selectCandidate(at: selectedCandidateIndex)
            if composingText.isEmpty {
                return
            }
        }

        guard !composingText.isEmpty else { return }

        let raw = composingText.convertTarget
        let empty = ComposingText()
        displayedTextManager.updateComposingText(
            composingText: empty,
            completedPrefix: raw,
            isSelected: false
        )

        composingText = empty
        revision += 1
        selectedCandidateIndex = nil
        clearCandidates()
        Task { await worker.stopComposition() }
    }

    func close() {
        commitSelectionOrRaw()
    }

    private func cycleCandidate() {
        guard !candidates.isEmpty else {
            refreshCandidates()
            return
        }

        let next = if let selectedCandidateIndex {
            (selectedCandidateIndex + 1) % candidates.count
        } else {
            0
        }
        selectedCandidateIndex = next

        displayedTextManager.updateComposingText(
            composingText: composingText,
            newLiveConversionText: candidates[next].text
        )
        publishCandidates()
    }

    private func refreshCandidates() {
        revision += 1
        let expectedRevision = revision
        let snapshot = composingText

        if snapshot.isEmpty {
            clearCandidates()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await worker.requestCandidates(for: snapshot)
            guard revision == expectedRevision else { return }
            candidates = result
            selectedCandidateIndex = nil
            publishCandidates()
        }
    }

    private func clearCandidates() {
        candidates = []
        selectedCandidateIndex = nil
        publishCandidates()
    }

    private func publishCandidates() {
        let selected = selectedCandidateIndex
        onCandidatesChanged?(
            candidates.enumerated().map { index, candidate in
                CompositionCandidateSnapshot(
                    index: index,
                    text: candidate.text,
                    selected: index == selected
                )
            }
        )
    }
}
