//
//  MessageViewController.swift
//  Gameball
//

import UIKit

/// The root view controller of the message window.
///
/// Exists to own the things only a view controller can answer: supported orientations, the
/// preferred presentation orientation, and status bar appearance. It **constrains** orientation
/// rather than deferring the message when the device is turned the wrong way — a campaign
/// authored portrait-only should still be seen, not silently skipped.
final class MessageViewController: UIViewController {

    private let context: PresentationContext
    private let messageView: InAppMessageView

    init(context: PresentationContext, messageView: InAppMessageView) {
        self.context = context
        self.messageView = messageView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        // A plain clear view, so whatever the message does not cover shows the host app.
        let root = UIView()
        root.backgroundColor = .clear
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Modals and fullscreens take VoiceOver focus exclusively; a slideup must not, or the
        // customer loses access to the app behind it.
        let exclusive = context.message.type != .slideup
        view.accessibilityViewIsModal = exclusive

        messageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.topAnchor.constraint(equalTo: view.topAnchor),
            messageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            messageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch context.message.orientation {
        case .portrait:  return .portrait
        case .landscape: return .landscape
        case .any:       return .all
        }
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return context.preferredOrientation
    }

    /// Inherited from the host rather than asserted, so the message does not flash the status
    /// bar to a different style while it is up.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    override var prefersStatusBarHidden: Bool {
        return false
    }
}
