import Foundation
import UIKit
import KeyboardExtensionUtils
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

@MainActor
final class AzooKeyCompositionController {
    struct Snapshot: Equatable {
        var candidates: [String]
        var selectedIndex: Int?
        var isComposing: Bool
    }

    var onSnapshotChanged: ((Snapshot) -> Void)?

    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private let displayedTextManager = DisplayedTextManager(
        isLiveConversionEnabled: false,
        isMarkedTextEnabled: true
    )

    private var composingText = ComposingText()
    private var candidates: [Candidate] = []
    private var selectedIndex: Int?

    init(proxy: any UITextDocumentProxy) {
        displayedTextManager.setTextDocumentProxy(.mainProxy(proxy))
        converter.setKeyboardLanguage(.ja_JP)
        publishSnapshot()
    }

    func setTextDocumentProxy(_ proxy: any UITextDocumentProxy) {
        displayedTextManager.setTextDocumentProxy(.mainProxy(proxy))
    }

    func insert(_ text: String, direct: Bool = false) {
        guard !text.isEmpty else { return }

        if direct {
            commitSelectedOrRaw()
            displayedTextManager.insertText(text)
            return
        }

        if text == " " || text == "　" || text == "\t" {
            if composingText.isEmpty {
                displayedTextManager.insertText(text)
            } else {
                cycleCandidate()
            }
            return
        }

        if text == "\n" {
            if composingText.isEmpty {
                displayedTextManager.insertText(text)
            } else {
                commitSelectedOrRaw()
            }
            return
        }

        composingText.insertAtCursorPosition(text, inputStyle: .direct)
        refreshCandidatesAndDisplay()
    }

    func deleteBackward(count: Int) {
        guard count > 0 else { return }

        if composingText.isEmpty {
            displayedTextManager.deleteBackward(count: count)
            return
        }

        composingText.deleteBackwardFromCursorPosition(count: count)
        if composingText.isEmpty {
            displayedTextManager.updateComposingText(
                composingText: composingText,
                newLiveConversionText: nil
            )
            clearCompositionState()
        } else {
            refreshCandidatesAndDisplay()
        }
    }

    func moveCursor(offset: Int) {
        guard offset != 0 else { return }
        if !composingText.isEmpty {
            commitSelectedOrRaw()
        }
        displayedTextManager.moveCursor(count: offset)
    }

    func commit() {
        guard !composingText.isEmpty else { return }
        commitSelectedOrRaw()
    }

    func selectCandidate(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        complete(candidate: candidates[index])
    }

    func cycleCandidate() {
        guard !candidates.isEmpty else { return }
        if let selectedIndex {
            self.selectedIndex = (selectedIndex + 1) % candidates.count
        } else {
            selectedIndex = 0
        }
        publishSnapshot()
    }

    func stopCompositionForExternalReset() {
        composingText.stopComposition()
        converter.stopComposition()
        displayedTextManager.stopComposition()
        candidates.removeAll()
        selectedIndex = nil
        publishSnapshot()
    }

    func close() {
        if !composingText.isEmpty {
            commitSelectedOrRaw()
        }
        converter.commitUpdateLearningData()
        displayedTextManager.closeKeyboard()
    }

    private func refreshCandidatesAndDisplay() {
        displayedTextManager.updateComposingText(
            composingText: composingText,
            newLiveConversionText: nil
        )

        let inputData = composingText.prefixToCursorPosition()
        guard !inputData.isEmpty else {
            candidates.removeAll()
            selectedIndex = nil
            publishSnapshot()
            return
        }

        let result = converter.requestCandidates(inputData, options: requestOptions())
        candidates = result.mainResults
        if candidates.isEmpty {
            selectedIndex = nil
        } else if let selectedIndex, candidates.indices.contains(selectedIndex) {
            self.selectedIndex = selectedIndex
        } else {
            selectedIndex = 0
        }
        publishSnapshot()
    }

    private func complete(candidate: Candidate) {
        composingText.prefixComplete(composingCount: candidate.composingCount)
        displayedTextManager.updateComposingText(
            composingText: composingText,
            completedPrefix: candidate.text,
            isSelected: false
        )
        converter.updateLearningData(candidate)
        converter.setCompletedData(candidate)

        if composingText.isEmpty {
            converter.stopComposition()
            candidates.removeAll()
            selectedIndex = nil
            publishSnapshot()
        } else {
            refreshCandidatesAndDisplay()
        }
    }

    private func commitSelectedOrRaw() {
        if let selectedIndex, candidates.indices.contains(selectedIndex) {
            complete(candidate: candidates[selectedIndex])
            if !composingText.isEmpty {
                commitRawRemainder()
            }
        } else {
            commitRawRemainder()
        }
    }

    private func commitRawRemainder() {
        guard !composingText.isEmpty else {
            clearCompositionState()
            return
        }

        let raw = composingText.convertTarget
        composingText.stopComposition()
        displayedTextManager.updateComposingText(
            composingText: composingText,
            completedPrefix: raw,
            isSelected: false
        )
        converter.stopComposition()
        clearCompositionState()
    }

    private func clearCompositionState() {
        candidates.removeAll()
        selectedIndex = nil
        publishSnapshot()
    }

    private func publishSnapshot() {
        onSnapshotChanged?(
            Snapshot(
                candidates: candidates.map(\.text),
                selectedIndex: selectedIndex,
                isComposing: !composingText.isEmpty
            )
        )
    }

    private func requestOptions() -> ConvertRequestOptions {
        let library = (
            try? FileManager.default.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        ) ?? FileManager.default.temporaryDirectory

        return ConvertRequestOptions(
            N_best: 12,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: true,
            halfWidthKanaCandidate: true,
            learningType: .nothing,
            maxMemoryCount: 0,
            shouldResetMemory: false,
            memoryDirectoryURL: library,
            sharedContainerURL: library,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "Gesture IME")
        )
    }
}
