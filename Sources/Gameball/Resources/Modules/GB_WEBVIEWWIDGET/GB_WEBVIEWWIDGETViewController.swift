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
    var pullToDismiss: Bool = false

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

        let baseURL = NetworkManager.shared().widgetUrl
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
