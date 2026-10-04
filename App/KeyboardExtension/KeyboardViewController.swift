import SwiftUI
import UIKit

final class KeyboardHostingController<Content: View>: UIHostingController<Content> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .bottom
    }
}

@MainActor
final class KeyboardViewController: UIInputViewController {
    private var keyboardHost: KeyboardHostingController<AnyView>?
    private var productModel: AnyObject?
    private var composition: AzooKeyCompositionBridge?
    private var heightConstraint: NSLayoutConstraint?

    override func loadView() {
        super.loadView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let profileJSON = try BuiltInProfileLoader.loadJSON()
            let composition = AzooKeyCompositionBridge(proxy: textDocumentProxy)
            let root: AnyView
            let retainedModel: AnyObject

            if Self.profileSchema(profileJSON) == "gesture-ime.profile.v3" {
                let runtime = try IOSProfileV3RuntimeAdapter(
                    profileJSON: profileJSON
                )
                let model = try ProfileV3ProductKeyboardViewModel(
                    runtime: runtime,
                    composition: composition,
                    onNextKeyboard: { [weak self] in
                        self?.advanceToNextInputMode()
                    },
                    onDismissKeyboard: { [weak self] in
                        self?.dismissKeyboard()
                    }
                )
                root = AnyView(
                    ProfileV3ProductKeyboardRoot(model: model)
                )
                retainedModel = model
            } else {
                // Accepted v1/v2 staging path remains unchanged until A5 migrates
                // the built-in product Profile to v3.
                let layout = try KeyboardLayoutRuntime.compile(
                    profileJSON: profileJSON
                )
                let store = GesturePolicyStore(
                    defaultPolicy: layout.defaultPolicy
                )
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
                root = AnyView(
                    AzooKeyProductKeyboardRoot(model: model)
                )
                retainedModel = model
            }

            installKeyboardRoot(root)
            self.composition = composition
            self.productModel = retainedModel
        } catch {
            installError(String(describing: error))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        composition?.setTextDocumentProxy(textDocumentProxy)
    }

    override func viewWillDisappear(_ animated: Bool) {
        composition?.close()
        super.viewWillDisappear(animated)
    }

    private func installKeyboardRoot(_ root: AnyView) {
        let host = KeyboardHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()

        let height = view.heightAnchor.constraint(equalToConstant: 344)
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

    private static func profileSchema(_ profileJSON: String) -> String? {
        guard let data = profileJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["schema"] as? String
    }

    private func installError(_ message: String) {
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
    }
}
