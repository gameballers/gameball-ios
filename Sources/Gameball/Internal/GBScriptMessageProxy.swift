//
//  GBScriptMessageProxy.swift
//  Gameball
//

import WebKit

/// Weak forwarder for `WKScriptMessageHandler`.
///
/// `WKUserContentController` retains its registered message handlers **strongly**.
/// Registering a view controller directly (`userContentController.add(self, name:)`)
/// creates a userContentController → handler → view-controller retain cycle that leaks the
/// widget every time it is shown. This proxy is held strongly by the content controller but
/// keeps only a `weak` reference to the real target, so the target deallocates normally.
final class GBScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
