//
//  GameballWidgetView.swift
//  Gameball
//

import UIKit
import WebKit

/// A reward campaign in a `WKWebView`, which reports when it is actually drawn.
///
/// **Its own web view, deliberately.** `showProfile` builds one of its own in
/// `GB_WEBVIEWWIDGETViewController`, and this does not share it: the two have different message
/// handler names, different lifetimes and different close semantics, and every integration already
/// shipped depends on that one behaving exactly as it does.
///
/// The readiness contract is what this view exists for. The page finishes navigating two to three
/// seconds before the campaign is drawn — the widget renders after its own fetches resolve — so
/// presenting on `didFinish` alone puts a loading skeleton in front of the customer every time.
/// Worse, the content lives in `about:srcdoc` iframes, so a readiness check that reads only the top
/// document never fires at all.
final class GameballWidgetView: UIView, InAppMessageView {

    /// How long the campaign has to become ready before the message is abandoned.
    ///
    /// Measured on iOS: content arrives 2.4-5.9s after load begins, whichever way the view is
    /// hidden. Twelve seconds clears that with room for a slow network, and a customer who would
    /// have waited longer was going to close the card anyway.
    static let readyTimeout: TimeInterval = 12

    private(set) var presented = false
    weak var coordinator: MessageViewCoordinating?

    private let message: GameballInAppMessage
    private let attributes: MessageViewAttributes
    private let url: URL
    private let webView: WKWebView
    private let closeButton: MessageCloseButton
    /// Where a link tapped inside the game goes. Injected so a test can see it go.
    private let openOutside: (URL) -> Void
    private var timeoutWork: DispatchWorkItem?
    private var settled = false
    /// Whether a dismissal has begun. The close button, the scrim, the page's own close and a
    /// failed load can each ask, and the presenter must hear it once.
    private var dismissing = false
    private var onReady: (() -> Void)?
    private var onFailed: (() -> Void)?

    init(message: GameballInAppMessage,
         attributes: MessageViewAttributes,
         url: URL,
         coordinator: MessageViewCoordinating?,
         onFailed: (() -> Void)?,
         openOutside: @escaping (URL) -> Void = { MessageActionRouter.liveOpenURL($0, external: true) }) {
        self.message = message
        self.attributes = attributes
        self.url = url
        self.coordinator = coordinator
        self.onFailed = onFailed
        self.openOutside = openOutside

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        // Over every game, whatever the campaign says: the widget draws no close or back control
        // for a game on mobile, so without this a fullscreen game could only be left by leaving
        // the app. The glyph sits on the page, which the SDK cannot see, so it is resolved against
        // the surface the page is drawn on — white unless the campaign names one.
        self.closeButton = MessageCloseButton(
            tintColor: MessageTheme.closeGlyphColor(named: message.style.closeButtonColor,
                                                    background: message.style.backgroundColor
                                                        ?? .white))

        super.init(frame: .zero)

        backgroundColor = message.type == .fullscreen
            ? (message.style.backgroundColor ?? .white)
            : message.style.frameColor ?? UIColor.black.withAlphaComponent(0.6)

        // Behind a modal game: a tap outside the game closes it. A control of its own rather than
        // a recogniser on this view, which would also see every tap meant for the game — and could
        // cancel it. Fullscreen has no outside to tap.
        if message.type != .fullscreen && message.dismissOnScrimTap {
            let scrim = UIControl()
            scrim.translatesAutoresizingMaskIntoConstraints = false
            // VoiceOver reaches the close button, which says what it does; the scrim would not.
            scrim.isAccessibilityElement = false
            scrim.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            addSubview(scrim)
            NSLayoutConstraint.activate([
                scrim.topAnchor.constraint(equalTo: topAnchor),
                scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
                scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrim.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        addSubview(webView)

        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        addSubview(closeButton)

        configuration.userContentController.add(GBScriptMessageProxy(target: self), name: "GBIamReady")
        configuration.userContentController.add(GBScriptMessageProxy(target: self), name: "GBIamClose")
        configuration.userContentController.add(GBScriptMessageProxy(target: self), name: "GBIamEvent")
        webView.navigationDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - InAppMessageView

    func install(in container: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        let guide = container.safeAreaLayoutGuide
        if message.type == .fullscreen {
            // The surface runs edge to edge — a fullscreen campaign takes over the screen — while
            // the content is inset, so the campaign's own controls and footer stay clear of the
            // notch and the home indicator.
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: guide.topAnchor),
                webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
            ])
        } else {
            // Shaped, not stretched. The widget sizes its content off the viewport *width*, so a
            // box much wider than this clips its own copy — measured at roughly 0.96, where a
            // wheel lost the right-hand label.
            let width = webView.widthAnchor.constraint(lessThanOrEqualToConstant: attributes.modal.maxWidth)
            NSLayoutConstraint.activate([
                webView.centerXAnchor.constraint(equalTo: centerXAnchor),
                webView.centerYAnchor.constraint(equalTo: centerYAnchor),
                width,
                webView.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor,
                                                 constant: attributes.modal.margin.left),
                webView.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor,
                                                  constant: -attributes.modal.margin.right),
                webView.heightAnchor.constraint(equalTo: webView.widthAnchor,
                                                multiplier: 1 / Self.widgetAspectRatio),
                webView.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor,
                                             constant: attributes.modal.margin.top),
                webView.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor,
                                                constant: -attributes.modal.margin.bottom)
            ])
            webView.layer.cornerRadius = attributes.modal.cornerRadius
            webView.clipsToBounds = true
        }

        // The game's top-end corner, which is inside the safe area: a fullscreen game is inset
        // into it and a modal one sits within its margins. Placed as each message composition
        // places its own close button.
        let inset: (top: CGFloat, end: CGFloat) = message.type == .fullscreen
            ? (0, 8)
            : (attributes.modal.closeInset, attributes.modal.closeInset)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: webView.topAnchor, constant: inset.top),
            closeButton.trailingAnchor.constraint(equalTo: webView.trailingAnchor,
                                                  constant: -inset.end)
        ])
    }

    /// Width divided by height for a reward-campaign card. Measured, not chosen.
    static let widgetAspectRatio: CGFloat = 0.7

    func present(completion: (() -> Void)?) {
        willPresent()
        superview?.layoutIfNeeded()

        // Transparent rather than hidden. Every way of hiding a WKWebView lets the page load on
        // iOS — measured — so the choice is made on rendering instead: a transparent view stays in
        // the render tree and is composited, while `isHidden` leaves it out entirely, which is the
        // thing most likely to cost a blank frame on reveal.
        alpha = 0

        onReady = { [weak self] in
            guard let self = self else { return }
            MessageMotion.animate(duration: MessageMotion.fadeDuration,
                                  animations: { self.alpha = 1 },
                                  completion: {
                self.presented = true
                // The impression anchor. Not insertion: this view is in the hierarchy for seconds
                // before there is anything to have seen.
                self.didPresent()
                completion?()
            })
        }

        webView.load(URLRequest(url: url))

        let timeout = DispatchWorkItem { [weak self] in self?.settle(ready: false) }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyTimeout, execute: timeout)
    }

    func dismiss(completion: (() -> Void)?) {
        // Once, whoever asks: a second `didDismiss` would reach the presenter after it had moved
        // on to whatever shows next.
        guard !dismissing else { return }
        dismissing = true
        // Settled too, so a page that reports itself ready after it was closed cannot reveal it.
        settled = true
        timeoutWork?.cancel()
        willDismiss()

        let finish = { [weak self] in
            guard let self = self else { return }
            self.presented = false
            self.didDismiss()
            completion?()
        }

        guard !iamReduceMotionEnabled() else {
            finish()
            return
        }
        MessageMotion.animate(duration: MessageMotion.fadeDuration,
                              animations: { self.alpha = 0 },
                              completion: finish)
    }

    /// The close button and the scrim. Closing is a dismissal of the game, never a click.
    @objc private func handleClose() {
        dismiss(completion: nil)
    }

    // MARK: - Readiness

    /// Reports the outcome exactly once. `failure` says what went wrong when the game is not ready.
    private func settle(ready: Bool,
                        failure: String = "did not become ready within "
                            + "\(Int(GameballWidgetView.readyTimeout))s") {
        guard !settled else { return }
        settled = true
        timeoutWork?.cancel()

        if ready {
            onReady?()
        } else {
            iamLog("widget \(failure); taking the message away unshown")
            // Never counted an impression, so nothing is logged and the cap is untouched — the
            // campaign gets another go at its next trigger rather than being burned by a slow
            // network.
            onFailed?()
        }
    }
}

// MARK: - WKNavigationDelegate

extension GameballWidgetView: WKNavigationDelegate {

    /// A link tapped inside the game opens outside it, as the profile widget's do: a page that
    /// belongs to the widget loads in place, and anything else goes to the device browser while
    /// the game stays where it is. The device browser rather than an in-app one, because one
    /// presented from the host's controllers would sit beneath the message's own window.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url,
              !Self.staysInGame(target, widgetHost: url.host) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // The host only: the rest of a link can carry anything.
        iamLog("a link in the game to \(target.host ?? "another site") opened outside it")
        openOutside(target)
    }

    /// Whether `target` is part of the widget: no host at all (`about:srcdoc`, which the game's
    /// own frames use), gameball.app or any subdomain of it, or the host the widget was opened
    /// on, which a non-production `widgetUrlPrefix` can make something else. The leading dot in
    /// the suffix is what turns away a look-alike such as `evilgameball.app`.
    static func staysInGame(_ target: URL, widgetHost: String?) -> Bool {
        guard let host = target.host?.lowercased() else { return true }
        if let widgetHost = widgetHost?.lowercased(), host == widgetHost { return true }
        return host == "gameball.app" || host.hasSuffix(".gameball.app")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.readinessScript, completionHandler: nil)
    }

    /// Offline, the page never starts — this, not `didFail`, is what WebKit reports — and waiting
    /// out the readiness timeout would hold an invisible game for twelve seconds for nothing.
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        loadFailed(error)
    }

    /// Takes the game away unshown — never an impression, so the campaign keeps its next trigger.
    ///
    /// A navigation cancelled for another one, or refused by `decidePolicyFor`, is not a page that
    /// failed to load, and the page it gave way to may still draw.
    private func loadFailed(_ error: Error) {
        let failure = error as NSError
        let cancelled = (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
            || (failure.domain == "WebKitErrorDomain" && failure.code == Self.frameLoadInterrupted)
        guard !cancelled else { return }
        settle(ready: false, failure: "failed to load (\(failure.localizedDescription))")
    }

    /// WebKit's "frame load interrupted", sent when a navigation is replaced or refused by policy.
    private static let frameLoadInterrupted = 102
}

// MARK: - WKScriptMessageHandler

extension GameballWidgetView: WKScriptMessageHandler {

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "GBIamReady":
            settle(ready: (message.body as? String) == "ready")
        case "GBIamClose":
            // The page's own close is the customer leaving the game: a dismissal, never a click.
            dismiss(completion: nil)
        case "GBIamEvent":
            receiveWidgetEvent(message.body)
        default:
            break
        }
    }

    /// An event the page posted through `WidgetEvent.postEvent`.
    ///
    /// Only `gameCompleted` means anything here. Its `metadata.campaignType` is the widget's own
    /// name for the game (`spinTheWheel`), not the sync's (`wheel`), so nothing is matched on the
    /// metadata: the event came from this view, so it is about the game this view opened.
    private func receiveWidgetEvent(_ body: Any) {
        let type = GameballWidgetView.widgetEvent(from: body)?["type"] as? String
        let game = self.message.widget.map { "game \($0.gameCampaignId)" } ?? "the game"
        iamLog("\(game) reported \(type.map { "'\($0)'" } ?? "an event it could not read")")
        guard type == "gameCompleted" else { return }
        coordinator?.viewDidCompleteGame()
    }

    /// Reads what `WidgetEvent.postEvent` was handed: a JSON string, `{"type", "metadata"}`, or
    /// the object itself. `nil` for anything else.
    static func widgetEvent(from body: Any) -> [String: Any]? {
        if let event = body as? [String: Any] { return event }
        guard let text = body as? String, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }
}

// MARK: - The readiness script

extension GameballWidgetView {

    /// Injected once the page has navigated. Reports `ready` when the campaign is actually drawn.
    ///
    /// **Mirrored in the Flutter, React Native and Android SDKs.** It is inlined in each rather
    /// than shared, so the numbers below are repeated everywhere and must be changed everywhere.
    /// They were expensive to find; the comments are here so nobody tidies them away.
    ///
    /// Three things this encodes, all measured against the live widget:
    ///
    /// 1. **The content lives in `about:srcdoc` iframes.** A check that reads only the top
    ///    document sits at about 209 nodes with zero text indefinitely and never fires. srcdoc
    ///    inherits the parent's origin, so the frames stay reachable.
    ///
    /// 2. **The load passes through three stable plateaus**, so "the DOM stopped changing" cannot
    ///    mean "loaded": a skeleton at `7/209/1/0/0` holds still for a full second, a half-built
    ///    state at `6/254/1/0/35` for another, and only then the finished campaign at
    ///    `6/267/1/3/104`.
    ///
    /// 3. **`sizedCanvas` is 1 from the very first sample** — it is the skeleton's placeholder.
    ///    Including it in the content test made the predicate true throughout loading, and an OR
    ///    is only ever as strict as its weakest term. `imgDone` and `textLen` are both 0 across
    ///    the whole skeleton, which is why the test is `imgDone > 0 || textLen > 40`.
    ///
    /// The stability count is a secondary check, not the safeguard — no value of it can tell
    /// loading from loaded when the loading state holds still for a second.
    static let readinessScript = """
    (function () {
      if (window.__gbIamWatching) return;
      window.__gbIamWatching = true;

      function frames() {
        var out = [window];
        var els = document.querySelectorAll('iframe');
        for (var i = 0; i < els.length; i++) {
          try {
            var w = els[i].contentWindow;
            if (w && w.document) out.push(w);
          } catch (e) { /* cross-origin; nothing to read */ }
        }
        return out;
      }

      function shim(w) {
        try {
          if (w.__gbIamShimmed) return;
          w.__gbIamShimmed = true;
          var up = function (kind, raw) {
            try {
              if (kind === 'event') {
                window.webkit.messageHandlers.GBIamEvent.postMessage(String(raw));
              } else {
                window.webkit.messageHandlers.GBIamClose.postMessage('');
              }
            } catch (e) {}
          };
          w.WidgetEvent = w.WidgetEvent || {};
          w.WidgetEvent.postEvent = function (raw) { up('event', raw); };
          w.GameballWidget = w.GameballWidget || {};
          w.GameballWidget.closeWidget = function () { up('close', ''); };
        } catch (e) {}
      }

      function fingerprint() {
        var fs = frames();
        var nodes = 0, sizedCanvas = 0, imgDone = 0, textLen = 0;
        for (var f = 0; f < fs.length; f++) {
          var w = fs[f];
          shim(w);
          try {
            var d = w.document;
            nodes += d.querySelectorAll('*').length;
            var cv = d.querySelectorAll('canvas');
            for (var j = 0; j < cv.length; j++) {
              if (cv[j].clientWidth > 0 && cv[j].clientHeight > 0) sizedCanvas++;
            }
            var ims = d.querySelectorAll('img');
            for (var i = 0; i < ims.length; i++) {
              if (ims[i].complete && ims[i].naturalWidth > 0) imgDone++;
            }
            if (d.body) textLen += (d.body.innerText || '').trim().length;
          } catch (e) {}
        }
        return {
          key: fs.length + '/' + nodes + '/' + sizedCanvas + '/' + imgDone + '/' + textLen,
          drawn: imgDone > 0 || textLen > 40
        };
      }

      var last = null, stable = 0, started = Date.now();
      function tick() {
        var fp = fingerprint();
        if (fp.key === last) { stable++; } else { stable = 0; last = fp.key; }

        if (fp.drawn && stable >= 3) {
          try { window.webkit.messageHandlers.GBIamReady.postMessage('ready'); } catch (e) {}
          return;
        }
        if (Date.now() - started > 12000) {
          try { window.webkit.messageHandlers.GBIamReady.postMessage('timeout'); } catch (e) {}
          return;
        }
        setTimeout(tick, 250);
      }
      setTimeout(tick, 250);
    })();
    """
}
