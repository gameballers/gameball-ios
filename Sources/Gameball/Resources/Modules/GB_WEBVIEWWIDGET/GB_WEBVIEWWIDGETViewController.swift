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
    var customerId = ""  // Renamed from playerID/customerID for consistency
    var color: String? = ""
    var APIKEY = ""
    var lang: String? = ""
    var openDetail: String?
    var hideNavigation: Bool?
    var showCloseBtn: Bool = true
    var closeButtonColor: String? = nil
    var pullToDismiss: Bool = false
    var widgetApiPrefix: String?

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
        var origImage: UIImage?
#if COCOAPODS
        origImage = UIImage(named: "icon_outline_14px_close@2x.png")
#else
        origImage = UIImage(named: "icon_outline_14px_close@2x.png", in: Bundle.module, compatibleWith: nil)
#endif
        button.setImage(origImage, for: .normal)
        button.backgroundColor = .clear
        button.adjustsImageWhenHighlighted = false
        button.showsTouchWhenHighlighted = false

        // Apply close button color (default to #CECECE if not provided)
        let colorToUse = closeButtonColor ?? "#CECECE"
        button.tintColor = UIColor(hexString: colorToUse)
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

        queryItems.append(URLQueryItem(name: "playerid", value: customerId))
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

        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedURL = URL(string: url) else {
            return
        }

        webView.navigationDelegate = self
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
}

extension GB_WEBVIEWWIDGETViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        if let url = navigationAction.request.url,
           let urlComponents = URLComponents(string: url.absoluteString),
           let openExternal = urlComponents.queryItems?.first(where: { $0.name == "openInExternalBrowser" })?.value,
           openExternal == "true",
           UIApplication.shared.canOpenURL(url) {

            UIApplication.shared.open(url)

            return decisionHandler(.cancel)
        }

        decisionHandler(.allow)
    }
}

extension GB_WEBVIEWWIDGETViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
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
