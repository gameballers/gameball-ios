//
//  GB_WEBVIEWWIDGETViewController.swift
//  GameBallSDK
//
//  Created by Martin Sorsok on 1/28/21.
//

import UIKit
import WebKit
class GB_WEBVIEWWIDGETViewController: BaseViewController {
    
    @IBOutlet weak var webView: WKWebView!
    var customerId: String?
    var color: String? = ""
    var APIKEY = ""
    var lang: String? = ""
    var openDetail: String?
    var hideNavigation: Bool?
    var mobile: String?
    var email: String?
    var externalLinkCallback: ((String) -> Void)?
    var widgetEventCallback: (([String: Any]?) -> Void)?
    var showCloseBtn: Bool = true
    var closeButtonColor: String? = nil
    var pullToDismiss: Bool = false
    var widgetApiPrefix: String?
    var sessionToken: String?

    @IBOutlet weak var closeBtnRight: UIButton! {
        didSet {
            setupCloseButton(closeBtnRight)
        }
    }

    @IBOutlet weak var closeBtnLeft: UIButton! {
        didSet {
            setupCloseButton(closeBtnLeft)
        }
    }

    private var closeBtn: UIButton!

    private func setupCloseButton(_ button: UIButton) {
        // Draw the "X" as a stroked vector into a template image rather than loading a PNG,
        // so it stays crisp at any scale, ships no bundled asset, and is tinted by
        // `closeButtonColor` on a transparent background. This mirrors the Android SDK's
        // vector `ic_close` (two diagonals, thin stroke, #CECECE) and works on iOS 11+
        // (unlike SF Symbols, which require iOS 13). See `GB_WEBVIEWWIDGETViewController`.
        button.setImage(GB_WEBVIEWWIDGETViewController.closeXImage(), for: .normal)
        button.backgroundColor = .clear
        button.adjustsImageWhenHighlighted = false
        button.showsTouchWhenHighlighted = false

        // Apply close button color (default to #CECECE if not provided)
        let colorToUse = closeButtonColor ?? "#CECECE"
        button.tintColor = UIColor(hexString: colorToUse)
    }

    /// Builds the close "X" as a template `UIImage`: a thin, gray, two-diagonal X that
    /// shares the visual language of the Android (`ic_close`, a #CECECE stroked X) and
    /// Flutter (`Icons.close`) SDKs, while keeping an iOS-native feel — rounded line caps
    /// in a balanced square box, the same treatment iOS system glyphs (e.g. SF `xmark`)
    /// use. Rendered as a template so the button's `tintColor` (`closeButtonColor`,
    /// default #CECECE) drives the color.
    private static func closeXImage(size: CGFloat = 16, lineWidth: CGFloat = 1.5) -> UIImage {
        let dimension = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: dimension)
        let image = renderer.image { context in
            let cg = context.cgContext
            // Inset by half the line width so the rounded caps sit fully inside the bounds.
            let inset = lineWidth / 2 + 1
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)               // iOS identity: rounded ends
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.black.cgColor) // overridden by template tint
            // Top-left → bottom-right
            cg.move(to: CGPoint(x: inset, y: inset))
            cg.addLine(to: CGPoint(x: size - inset, y: size - inset))
            // Top-right → bottom-left
            cg.move(to: CGPoint(x: size - inset, y: inset))
            cg.addLine(to: CGPoint(x: inset, y: size - inset))
            cg.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        // Default to right button (LTR)
        closeBtn = closeBtnRight

        // Handle close button visibility and position based on language direction
        if !showCloseBtn {
            closeBtnRight.isHidden = true
            closeBtnLeft.isHidden = true
        } else {
            let selectedLanguage = lang ?? LanguageHelper.resolveLanguage()

            if LanguageHelper.shouldHandleCloseButtonDirection(selectedLanguage: selectedLanguage) {
                // RTL language with LTR device or vice versa - show left button
                closeBtnRight.isHidden = true
                closeBtnLeft.isHidden = false
                closeBtn = closeBtnLeft
            } else {
                // Default - show right button
                closeBtnRight.isHidden = false
                closeBtnLeft.isHidden = true
                closeBtn = closeBtnRight
            }
        }

        let baseURL = widgetApiPrefix ?? NetworkManager.shared().widgetUrl
        var urlComponents = URLComponents(string: baseURL)
        var queryItems = [URLQueryItem]()

        if var color = color {
            if (color.first == "#") {
                color.remove(at: color.startIndex)
            }
            queryItems.append(URLQueryItem(name: "main", value: color))
        }

        queryItems.append(URLQueryItem(name: "customerId", value: customerId))
        queryItems.append(URLQueryItem(name: "lang", value: lang))
        queryItems.append(URLQueryItem(name: "apiKey", value: APIKEY))
        queryItems.append(URLQueryItem(name: "os", value: "iOS"))
        queryItems.append(URLQueryItem(name: "sdk", value: SDKInfo.version))
        if let openDetail = openDetail {
            queryItems.append(URLQueryItem(name: "openDetail", value: openDetail))
        }
        if let hideNavigation = hideNavigation {
            queryItems.append(URLQueryItem(name: "hideNavigation", value: hideNavigation ? "true" : "false"))
        }
        if let mobile = mobile, !mobile.isEmpty {
            queryItems.append(URLQueryItem(name: "mobile", value: mobile))
        }
        if let email = email, !email.isEmpty {
            queryItems.append(URLQueryItem(name: "email", value: email))
        }

        // Add session token to widget URL if present
        if let sessionToken = sessionToken, !sessionToken.isEmpty {
            queryItems.append(URLQueryItem(name: "sessionToken", value: sessionToken))
        }

        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedURL = URL(string: url) else {
            return
        }

        webView.navigationDelegate = self
        setupWidgetEventBridge()
        print("🌐 Loading URL: \(encodedURL)")
        webView.load(URLRequest(url: encodedURL))

        webView.allowsBackForwardNavigationGestures = true

        if (pullToDismiss) {
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            webView.scrollView.addGestureRecognizer(panGesture)
        }
   }

   @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
       let translation = gesture.translation(in: webView.scrollView)

       if translation.y > 0 && webView.scrollView.contentOffset.y <= 0 {
           if translation.y > 200 {
               dismiss(animated: true, completion: nil)
           }
       }
   }
    
    @IBAction func closeBtnAction(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    /// Exposes the widget→SDK bridges as document-start globals:
    ///   • `window.WidgetEvent.postEvent(rawJson)` → forwarded verbatim to `widgetEventCallback`.
    ///   • `window.GameballWidget.closeWidget()`   → dismisses this view controller.
    /// Each routes through a WKScriptMessageHandler. A weak `GBScriptMessageProxy` is used
    /// because `WKUserContentController` retains its handlers strongly — registering `self`
    /// directly would leak this view controller.
    private func setupWidgetEventBridge() {
        let contentController = webView.configuration.userContentController
        let shim = """
        window.WidgetEvent = window.WidgetEvent || {};
        window.WidgetEvent.postEvent = function (raw) {
            window.webkit.messageHandlers.widgetEvent.postMessage(raw);
        };
        window.GameballWidget = window.GameballWidget || {};
        window.GameballWidget.closeWidget = function () {
            window.webkit.messageHandlers.gameballClose.postMessage("");
        };
        """
        contentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        contentController.removeScriptMessageHandler(forName: "widgetEvent")
        contentController.add(GBScriptMessageProxy(target: self), name: "widgetEvent")
        contentController.removeScriptMessageHandler(forName: "gameballClose")
        contentController.add(GBScriptMessageProxy(target: self), name: "gameballClose")
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "widgetEvent")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "gameballClose")
    }
}

extension GB_WEBVIEWWIDGETViewController: WKNavigationDelegate {

    // Host that identifies Gameball widget content. Any subdomain of this (m., www.,
    // app., alpha., …) loads in-webview; everything else is treated as a cross-host link.
    private static let gameballHost = "gameball.app"
    private static let gameballHostSuffix = ".gameball.app"
    // Query marker the widget appends to a link it wants opened in the device browser.
    private static let externalBrowserFlag = "gbExternalBrowser=true"

    // Navigation precedence:
    //   1) Gameball host (gameball.app or any *.gameball.app) → load in-webview (widget
    //      content never leaves the webview, regardless of any flag).
    //   2) Cross-host link:
    //      a) gbExternalBrowser=true → device browser
    //      b) else if externalLinkCallback set → delegate to it
    //      c) else → device browser (safety net)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, !isGameballHost(url) {
            handleExternalBrowserLink(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    // True when the URL belongs to Gameball — host is "gameball.app" or ends with
    // ".gameball.app" (so m./www./app./alpha. etc. all match). The suffix check with the
    // leading dot rejects look-alikes such as "evilgameball.app". A URL with no host
    // (about:blank, data:) is also treated as in-widget so the widget renders normally.
    private func isGameballHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return true
        }
        return host == GB_WEBVIEWWIDGETViewController.gameballHost
            || host.hasSuffix(GB_WEBVIEWWIDGETViewController.gameballHostSuffix)
    }

    // Handle a cross-host link (never loads in-widget):
    //   1) gbExternalBrowser=true → device browser (flag outranks the callback)
    //   2) else if externalLinkCallback set → delegate to it
    //   3) else → device browser (safety net)
    private func handleExternalBrowserLink(_ url: URL) {
        if url.absoluteString.contains(GB_WEBVIEWWIDGETViewController.externalBrowserFlag) {
            openInDeviceBrowser(url)
        } else if let externalLinkCallback = externalLinkCallback {
            externalLinkCallback(url.absoluteString)
        } else {
            openInDeviceBrowser(url)
        }
    }

    private func openInDeviceBrowser(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

extension GB_WEBVIEWWIDGETViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension GB_WEBVIEWWIDGETViewController: WKScriptMessageHandler {
    /// Receives messages posted by the widget bridges:
    ///   • "widgetEvent"   → JSON parsed into a [type, metadata] dictionary for `widgetEventCallback`.
    ///   • "gameballClose" → dismiss the widget.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "widgetEvent":
            guard let raw = message.body as? String, let data = raw.data(using: .utf8) else {
                widgetEventCallback?(nil)
                return
            }
            let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            widgetEventCallback?(event)
        case "gameballClose":
            dismiss(animated: true, completion: nil)
        default:
            break
        }
    }
}

// MARK: - UIColor Hex Extension
extension UIColor {
    /// Initializes a UIColor from a hex color string
    /// - Parameter hexString: Hex color string (e.g., "#FF0000", "FF0000", "#FFAA0088")
    /// - Returns: UIColor from hex string, or light gray (#CECECE) if parsing fails
    ///
    /// Supports 6-character RGB format (#RRGGBB) and 8-character RGBA format (#RRGGBBAA)
    /// The '#' prefix is optional and will be stripped if present
    /// Returns default light gray color (#CECECE) if hex string is invalid
    ///
    /// Examples:
    /// - "#FF0000" → Red color (RGB)
    /// - "00FF00" → Green color (RGB without #)
    /// - "#0000FFAA" → Blue color with 66% opacity (RGBA)
    /// - "invalid" → Light gray (fallback to #CECECE)
    convenience init(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        let length = hexSanitized.count
        let r, g, b, a: CGFloat

        if Scanner(string: hexSanitized).scanHexInt64(&rgb) {
            if length == 6 {
                r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
                g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
                b = CGFloat(rgb & 0x0000FF) / 255.0
                a = 1.0
            } else if length == 8 {
                r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
                g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
                b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
                a = CGFloat(rgb & 0x000000FF) / 255.0
            } else {
                // Invalid format - use default light gray
                self.init(red: 0.807, green: 0.807, blue: 0.807, alpha: 1.0) // #CECECE
                return
            }
        } else {
            // Parsing failed - use default light gray
            self.init(red: 0.807, green: 0.807, blue: 0.807, alpha: 1.0) // #CECECE
            return
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
