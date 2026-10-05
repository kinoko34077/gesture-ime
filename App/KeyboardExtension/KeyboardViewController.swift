import SwiftUI
import UIKit
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

final class KeyboardHostingController<Content: View>: UIHostingController<Content> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .bottom
    }
}

/// #93: `playInputClick()` sounds only when the keyboard's input view adopts
/// `UIInputViewAudioFeedback` and enables clicks.
final class KeyboardClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

@MainActor
final class KeyboardViewController: UIInputViewController {
    private static let baseKeyboardHeight: Double = 344

    private var keyboardHost: KeyboardHostingController<AnyView>?
    private var productModel: AnyObject?
    private var composition: AzooKeyCompositionBridge?
    private var heightConstraint: NSLayoutConstraint?
    private var installedSettings: ProductSettingsValues = .defaults
    private var configurationSource = KeyboardSharedConfigurationSource()
    private var installedConfiguration: KeyboardResolvedConfiguration?
    private var pendingConfiguration: KeyboardResolvedConfiguration?
    private var errorLabel: UILabel?

    override func loadView() {
        super.loadView()
        inputView = KeyboardClickInputView(frame: .zero, inputViewStyle: .keyboard)
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let composition = AzooKeyCompositionBridge(proxy: textDocumentProxy)
        self.composition = composition

        do {
            try installConfiguration(configurationSource.load())
        } catch {
            installError(String(describing: error))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        composition?.setTextDocumentProxy(textDocumentProxy)
        refreshSharedConfigurationIfNeeded()
        pushHostFacts()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        pushHostFacts()
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        pushHostFacts()
    }

    override func viewWillDisappear(_ animated: Bool) {
        composition?.close()
        super.viewWillDisappear(animated)
    }

    private var hasActiveTouches: Bool {
        if let model = productModel as? ProfileV3ProductKeyboardViewModel {
            return model.gestureCoordinator.hasActiveTouches
        }
        if let model = productModel as? ProductKeyboardViewModel {
            return model.gestureCoordinator.hasActiveTouches
        }
        return false
    }

    /// #128/#95 §F9: shared generations are checked when the keyboard becomes
    /// visible. A generation observed during an active touch is retained as
    /// pending and installed only after the coordinator reaches an idle boundary.
    private func refreshSharedConfigurationIfNeeded() {
        do {
            let next = try configurationSource.load()
            guard next != installedConfiguration else { return }

            if hasActiveTouches {
                pendingConfiguration = next
                return
            }

            try installConfiguration(next)
        } catch {
            if installedConfiguration == nil {
                installError(String(describing: error))
            }
        }
    }

    private func installPendingConfigurationIfNeeded() {
        guard !hasActiveTouches,
              let next = pendingConfiguration,
              next != installedConfiguration else {
            return
        }

        pendingConfiguration = nil
        do {
            try installConfiguration(next)
        } catch {
            if installedConfiguration == nil {
                installError(String(describing: error))
            }
        }
    }

    private func installConfiguration(
        _ configuration: KeyboardResolvedConfiguration
    ) throws {
        guard let composition else {
            throw KeyboardConfigurationError.compositionUnavailable
        }
        guard !hasActiveTouches else {
            pendingConfiguration = configuration
            return
        }

        let root: AnyView
        let retainedModel: AnyObject

        if Self.profileSchema(configuration.profileJSON) == "gesture-ime.profile.v3" {
            let runtime = try IOSProfileV3RuntimeAdapter(
                profileJSON: configuration.profileJSON
            )
            let model = try ProfileV3ProductKeyboardViewModel(
                runtime: runtime,
                composition: composition,
                productSettings: configuration.productSettings,
                keySoundCapability: ProductKeySoundCapability(
                    hasFullAccess: hasFullAccess
                ),
                keyboardTheme: IOSKeyboardTheme(
                    profileJSON: configuration.profileJSON
                ),
                onNextKeyboard: { [weak self] in
                    self?.advanceToNextInputMode()
                },
                onDismissKeyboard: { [weak self] in
                    self?.dismissKeyboard()
                }
            )
            root = AnyView(ProfileV3ProductKeyboardRoot(model: model))
            retainedModel = model
        } else {
            let layout = try KeyboardLayoutRuntime.compile(
                profileJSON: configuration.profileJSON
            )
            let store = GesturePolicyStore(defaultPolicy: layout.defaultPolicy)
            let model = ProductKeyboardViewModel(
                initialLayout: layout,
                policyStore: store,
                composition: composition,
                onNextKeyboard: { [weak self] in
                    self?.advanceToNextInputMode()
                },
                onDismissKeyboard: { [weak self] in
                    self?.dismissKeyboard()
                }
            )
            root = AnyView(AzooKeyProductKeyboardRoot(model: model))
            retainedModel = model
        }

        configureIdleCallback(for: retainedModel)
        replaceKeyboardRoot(
            root,
            productSettings: configuration.productSettings
        )
        productModel = retainedModel
        installedConfiguration = configuration
        pendingConfiguration = nil
        pushHostFacts()
    }

    private func configureIdleCallback(for model: AnyObject) {
        let callback: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.installPendingConfigurationIfNeeded()
            }
        }

        if let model = model as? ProfileV3ProductKeyboardViewModel {
            model.gestureCoordinator.onBecameIdle = callback
        } else if let model = model as? ProductKeyboardViewModel {
            model.gestureCoordinator.onBecameIdle = callback
        }
    }

    /// Normalizes UIKit host traits into the shared runtime's closed fact
    /// vocabulary; no layout decisions are made here.
    private func pushHostFacts() {
        guard let model = productModel as? ProfileV3ProductKeyboardViewModel else {
            return
        }
        let proxy = textDocumentProxy
        let returnKey: String = switch proxy.returnKeyType ?? .default {
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .send: "send"
        case .next: "next"
        case .done: "done"
        case .join: "join"
        case .route: "route"
        case .continue: "continue"
        case .emergencyCall: "emergencyCall"
        default: "default"
        }
        let keyboardType: String = switch proxy.keyboardType ?? .default {
        case .asciiCapable: "ascii"
        case .numbersAndPunctuation: "numbers"
        case .URL: "url"
        case .emailAddress: "email"
        case .phonePad, .namePhonePad: "phone"
        case .numberPad, .decimalPad, .asciiCapableNumberPad: "decimal"
        case .twitter: "twitter"
        case .webSearch: "webSearch"
        default: "default"
        }
        let mode: String = switch proxy.autocapitalizationType ?? .sentences {
        case .none: "none"
        case .words: "words"
        case .allCharacters: "allCharacters"
        default: "sentences"
        }
        model.updateHostFacts(IOSHostInputFacts(
            returnKey: returnKey,
            keyboardType: keyboardType,
            autocapitalizeNext: IOSHostInputFacts.autocapitalizeNext(
                mode: mode,
                textBefore: proxy.documentContextBeforeInput
            ),
            needsInputModeSwitchKey: needsInputModeSwitchKey
        ))
    }

    private func replaceKeyboardRoot(
        _ root: AnyView,
        productSettings: ProductSettingsValues
    ) {
        heightConstraint?.isActive = false
        heightConstraint = nil

        if let oldHost = keyboardHost {
            oldHost.willMove(toParent: nil)
            oldHost.view.removeFromSuperview()
            oldHost.removeFromParent()
            keyboardHost = nil
        }

        errorLabel?.removeFromSuperview()
        errorLabel = nil

        let host = KeyboardHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()

        installedSettings = productSettings
        let scaledHeight = currentKeyboardHeight()
        let height = view.heightAnchor.constraint(
            equalToConstant: CGFloat(scaledHeight)
        )
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])

        keyboardHost = host
        heightConstraint = height
    }

    /// #80: portrait/landscape height adapts the viewport only; Board
    /// coordinates stay semantic and the renderer re-maps them.
    private func currentKeyboardHeight() -> Double {
        let base = IOSKeyboardLayoutPolicy.baseHeight(
            compactVertical: traitCollection.verticalSizeClass == .compact
        )
        return (try? installedSettings.scaledKeyboardHeight(baseHeight: base)) ?? base
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.heightConstraint?.constant = CGFloat(self.currentKeyboardHeight())
        })
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        heightConstraint?.constant = CGFloat(currentKeyboardHeight())
    }

    private static func profileSchema(_ profileJSON: String) -> String? {
        guard let data = profileJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["schema"] as? String
    }

    private func installError(_ message: String) {
        errorLabel?.removeFromSuperview()

        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12)
        label.text = "Keyboard load failed\n\(message)"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: 12
            ),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -12
            )
        ])
        errorLabel = label
    }
}

private enum KeyboardConfigurationError: Error {
    case compositionUnavailable
}
