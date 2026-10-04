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

    func complete(_ candidate: Candidate, nextComposing: ComposingText?) -> [Candidate] {
        converter.setCompletedData(candidate)

        if let nextComposing, !nextComposing.isEmpty {
            return converter.requestCandidates(nextComposing, options: options).mainResults
        }

        converter.stopComposition()
        return []
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

    func setTextDocumentProxy(_ proxy: any UITextDocumentProxy) {
        displayedTextManager.setTextDocumentProxy(.mainProxy(proxy))
    }

    var isComposing: Bool {
        !composingText.isEmpty
    }


    /// Exact common-runtime composition input. No Unicode normalization is applied here.
    var semanticComposition: String {
        composingText.convertTarget
    }

    /// Conversion is active once the user has selected/cycled into a concrete candidate.
    ///
    /// Candidate availability is exposed separately so Profiles can distinguish
    /// "there are candidates" from "a conversion candidate is actively selected".
    var semanticConversionActive: Bool {
        selectedCandidateIndex != nil
    }

    var semanticConversionHasCandidates: Bool {
        !candidates.isEmpty
    }

    /// Replace one exact authored Unicode-scalar suffix in the active composition.
    ///
    /// ComposingText's editing counts are Swift Character units. The shared v3
    /// transform contract is Unicode-scalar exact. We therefore first choose the
    /// only Character-aligned suffix with the same Character count as matchedSource,
    /// then require exact scalar equality before mutating. A scalar suffix that
    /// would cut through a grapheme cluster fails closed.
    @discardableResult
    func replaceCompositionTail(
        matchedSource: String,
        replacement: String
    ) -> Bool {
        guard !matchedSource.isEmpty,
              !composingText.isEmpty,
              composingText.isAtEndIndex else {
            return false
        }

        let sourceCharacterCount = matchedSource.count
        guard sourceCharacterCount <= composingText.convertTarget.count else {
            return false
        }

        let current = composingText.convertTarget
        let boundary = current.index(
            current.endIndex,
            offsetBy: -sourceCharacterCount
        )
        let currentSuffix = current[boundary...]

        guard currentSuffix.unicodeScalars.elementsEqual(
            matchedSource.unicodeScalars
        ) else {
            return false
        }

        selectedCandidateIndex = nil
        composingText.deleteBackwardFromCursorPosition(
            count: sourceCharacterCount
        )
        if !replacement.isEmpty {
            composingText.insertAtCursorPosition(
                replacement,
                inputStyle: .direct
            )
        }

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

        return true
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

    func deleteForward(count: Int) {
        guard count > 0 else { return }

        if composingText.isEmpty {
            displayedTextManager.deleteForward(count: count)
            return
        }

        selectedCandidateIndex = nil
        composingText.deleteForwardFromCursorPosition(count: count)
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
        completeCandidate(candidates[index], commitRemainder: false)
    }

    func commitSelectionOrRaw() {
        if let selectedCandidateIndex,
           candidates.indices.contains(selectedCandidateIndex) {
            completeCandidate(candidates[selectedCandidateIndex], commitRemainder: true)
            return
        }

        commitRawRemainder()
    }

    private func completeCandidate(_ candidate: Candidate, commitRemainder: Bool) {
        composingText.prefixComplete(composingCount: candidate.composingCount)
        displayedTextManager.updateComposingText(
            composingText: composingText,
            completedPrefix: candidate.text,
            isSelected: false
        )

        revision += 1
        let expectedRevision = revision
        selectedCandidateIndex = nil

        if commitRemainder, !composingText.isEmpty {
            let raw = composingText.convertTarget
            let empty = ComposingText()
            displayedTextManager.updateComposingText(
                composingText: empty,
                completedPrefix: raw,
                isSelected: false
            )
            composingText = empty
        }

        let nextSnapshot = composingText.isEmpty ? nil : composingText

        if nextSnapshot == nil {
            displayedTextManager.stopComposition()
            clearCandidates()
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await worker.complete(candidate, nextComposing: nextSnapshot)
            guard revision == expectedRevision else { return }

            if nextSnapshot == nil {
                return
            }

            candidates = result
            selectedCandidateIndex = nil
            publishCandidates()
        }
    }

    private func commitRawRemainder() {
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
