//
//  GameballApp.swift
//  Gameball
//

import Foundation
import UIKit

/// Main Gameball SDK class with thread-safe singleton pattern
public class GameballApp {

    // MARK: - Singleton

    private static let shared = GameballApp()

    /// Get singleton instance
    public static func getInstance() -> GameballApp {
        return shared
    }

    // MARK: - Internal Bot Style (for UI components)

    /// Shared bot style configuration - used internally by UI components
    /// This is populated during SDK initialization
    static var clientBotStyle: ClientBotStyle?

    // MARK: - Private Properties

    private var isInitialized = false
    private var config: GameballConfig?
    private var customerId: String?
    private var sessionToken: String?

    private let queue = DispatchQueue(label: "com.gameball.sdk", qos: .utility)
    private let networkManager = NetworkManager.shared()
    private let logger = GameballLogger.shared

    private init() {}

    // MARK: - Public API

    /// Initialize the Gameball SDK
    /// - Parameters:
    ///   - config: SDK configuration
    ///   - completion: Optional completion handler called on main queue
    public func `init`(config: GameballConfig, completion: ((Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if self.isInitialized && self.config?.apiKey == config.apiKey {
                DispatchQueue.main.async {
                    completion?(nil)
                }
                return
            }

            self.config = config
            if let baseUrl = config.apiPrefix, !baseUrl.isEmpty {
                self.networkManager.registerBaseUrl(baseUrl: baseUrl)
            }

            // Save global preferred language
            if config.lang.count == 2 {
                UserDefaults.standard.set(config.lang, forKey: UserDefaultsKeys.globalPreferredLanguage.rawValue)
            }

            // Store session token in memory (no persistence)
            self.sessionToken = config.sessionToken

            var language = Languages.english
            if config.lang == "ar" {
                language = Languages.arabic
            }

            self.networkManager.registerAPIKey(APIKey: config.apiKey, language: language)

            // Mark as initialized immediately
            self.isInitialized = true

            // Record the init call (full config as-is).
            self.logger.log("sdk.init", params: GameballLogger.compact([
                "apiKey": config.apiKey,
                "lang": config.lang,
                "platform": config.platform,
                "shop": config.shop,
                "apiPrefix": config.apiPrefix,
                "sessionToken": config.sessionToken
            ]))

            // Fire bot settings request in background (fire-and-forget)
            self.loadBotSettings { _ in
                // Settings loaded in background, no action needed
            }

            DispatchQueue.main.async {
                completion?(nil)
            }
        }
    }

    /// Initialize customer with the SDK
    /// - Parameters:
    ///   - request: Customer initialization request
    ///   - completion: Completion handler with response object or error string
    ///   - sessionToken: Optional session token to override global token
    public func initializeCustomer(_ request: InitializeCustomerRequest,
                                   completion: @escaping (InitializeCustomerResponse?, String?) -> Void,
                                   sessionToken: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil, nil)
                }
                return
            }

            guard self.isInitialized else {
                DispatchQueue.main.async {
                    completion(nil, ServiceError.notInitialized.description)
                }
                return
            }

            // Set session token if provided, otherwise set to nil
            self.sessionToken = sessionToken

            self.customerId = request.customerId

            // Save customer preferred language if provided
            if let preferredLanguage = request.customerAttributes?.preferredLanguage,
               !preferredLanguage.isEmpty,
               preferredLanguage.count == 2 {
                UserDefaults.standard.set(preferredLanguage, forKey: UserDefaultsKeys.customerPreferredLanguage.rawValue)
            }

            self.networkManager.initializeCustomer(
                request: request,
                sessionToken: self.sessionToken,
                completion: { response, error in
                    DispatchQueue.main.async {
                        completion(response, error?.description)
                    }
                }
            )
            // Fire telemetry immediately after dispatching the request.
            self.logger.log("sdk.initializeCustomer", params: GameballLogger.dict(request))
        }
    }

    /// Show profile widget with automatic presentation
    /// - Parameters:
    ///   - request: Profile display request
    ///   - presentationStyle: Modal presentation style (default: .fullScreen)
    ///   - sessionToken: Optional session token to override global token
    public func showProfile(_ request: ShowProfileRequest, presentationStyle: UIModalPresentationStyle = .fullScreen, sessionToken: String? = nil) {
        // Set session token if provided (on background queue for thread safety)
        queue.async { [weak self] in
            self?.sessionToken = sessionToken
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard self.isInitialized, let config = self.config else {
                print("Error: SDK not initialized")
                return
            }

            // Resolve language using priority order
            let resolvedLanguage = LanguageHelper.resolveLanguage()

            let viewController = self.prepareProfileViewController(
                apiKey: config.apiKey,
                customerId: request.customerId,
                lang: resolvedLanguage,
                openDetail: request.openDetail,
                hideNavigation: request.hideNavigation,
                showCloseButton: request.showCloseButton,
                closeButtonColor: request.closeButtonColor,
                widgetUrlPrefix: request.widgetUrlPrefix,
                mobile: request.mobile,
                email: request.email,
                externalLinkCallback: request.externalLinkCallback,
                widgetEventCallback: request.widgetEventCallback,
                sessionToken: self.sessionToken
            )

            viewController.modalPresentationStyle = presentationStyle

            var rootVC: UIViewController?

            if #available(iOS 13.0, *) {
                rootVC = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }?.rootViewController
            } else {
                rootVC = UIApplication.shared.keyWindow?.rootViewController
            }

            rootVC?.present(viewController, animated: true)

            // showProfile opens a webview (never hits the backend), so it is invisible server-side — log it here.
            // Full request as-is (externalLinkCallback omitted — not serializable).
            self.logger.log("sdk.showProfile", params: GameballLogger.compact([
                "customerId": request.customerId,
                "openDetail": request.openDetail,
                "hideNavigation": request.hideNavigation,
                "showCloseButton": request.showCloseButton,
                "closeButtonColor": request.closeButtonColor,
                "widgetUrlPrefix": request.widgetUrlPrefix,
                "mobile": request.mobile,
                "email": request.email
            ]))
        }
    }

    // MARK: - Configuration Access

    public var currentConfig: GameballConfig? {
        return queue.sync {
            return config
        }
    }

    public var currentCustomerId: String? {
        return queue.sync {
            return customerId
        }
    }

    public var initialized: Bool {
        return queue.sync {
            return isInitialized
        }
    }


    // MARK: - Private Implementation

    private func loadBotSettings(completion: @escaping (Error?) -> Void) {
        // Use only the path - the base URL is added automatically by the URL extension
        let path = APIEndPoints.getBotStyle
        let params: [String: Any] = ["c": "mobile"]
        networkManager.load(path: path, method: RequestMethod.GET, params: params, modelType: GetClientBotStyleResponse.self) { (data, error) in
            if data != nil {
                GameballApp.clientBotStyle = (data as? GetClientBotStyleResponse)?.response
                self.networkManager.clientBotSettings = true
            }
            completion(error)
        }
    }

    private func prepareProfileViewController(
        apiKey: String,
        customerId: String?,
        lang: String,
        openDetail: String?,
        hideNavigation: Bool?,
        showCloseButton: Bool?,
        closeButtonColor: String?,
        widgetUrlPrefix: String?,
        mobile: String?,
        email: String?,
        externalLinkCallback: ((String) -> Void)?,
        widgetEventCallback: (([String: Any]?) -> Void)?,
        sessionToken: String?
    ) -> UIViewController {
        var bundle: Bundle?
        #if COCOAPODS
            bundle = Bundle(for: GB_WEBVIEWWIDGETViewController.self)
        #else
            bundle = Bundle.module
        #endif

        let viewController = GB_WEBVIEWWIDGETViewController(nibName: String(describing: GB_WEBVIEWWIDGETViewController.self), bundle: bundle)
        viewController.APIKEY = apiKey
        viewController.customerId = customerId
        viewController.color = GameballApp.clientBotStyle?.botMainColor
        viewController.lang = lang
        viewController.openDetail = openDetail
        viewController.hideNavigation = hideNavigation
        viewController.showCloseBtn = showCloseButton ?? true
        viewController.closeButtonColor = closeButtonColor
        viewController.pullToDismiss = false
        viewController.widgetApiPrefix = widgetUrlPrefix
        viewController.mobile = mobile
        viewController.email = email
        viewController.externalLinkCallback = externalLinkCallback
        viewController.widgetEventCallback = widgetEventCallback
        viewController.sessionToken = sessionToken

        return viewController
    }
}

// MARK: - Convenience Extensions

extension GameballApp {

    /// Quick SDK initialization
    public func `init`(apiKey: String, language: String, completion: ((Error?) -> Void)? = nil) {
        let config = GameballConfig(apiKey: apiKey, lang: language)
        self.`init`(config: config, completion: completion)
    }


    /// Send event
    /// - Parameters:
    ///   - event: Event to send
    ///   - completion: Completion handler with success flag and error string
    ///   - sessionToken: Optional session token to override global token
    public func sendEvent(_ event: Event, completion: @escaping (Bool, String?) -> Void, sessionToken: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(false, nil)
                }
                return
            }

            guard self.isInitialized else {
                DispatchQueue.main.async {
                    completion(false, ServiceError.notInitialized.description)
                }
                return
            }

            // Set session token if provided, otherwise set to nil
            self.sessionToken = sessionToken

            self.networkManager.sendEvent(event: event, sessionToken: self.sessionToken) { success, error in
                DispatchQueue.main.async {
                    completion(success, error?.description)
                }
            }
            // Fire telemetry immediately after dispatching the request.
            self.logger.log("sdk.sendEvent", params: GameballLogger.dict(event))
        }
    }

}
