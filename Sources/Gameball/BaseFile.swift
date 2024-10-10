//
//  baseFile.swift
//  gameball_SDK
//
//  Created by Martin Sorsok on 2/2/19.
//  Updated by Mahmoud Tarek on 1/8/23.
//  Copyright © 2019 Martin Sorsok. All rights reserved.
//

import UIKit
import UserNotifications

open class Gameball {
    
    static var clientBotStyle: ClientBotStyle?
    var holdReference: String?
    
    private var apiKey: String
    private var lang: String?
    private var shop: String?
    private var platform: String?
    
    private var playerUniqueId: String?
    
    public init(
        apiKey: String,
        lang: String? = nil,
        shop: String? = nil,
        platform: String? = nil,
        apiPrefix: String? = nil,
        widgetUrlPrefix: String? = nil,
        completion: (() -> Void)? = nil) {
            self.apiKey = apiKey
            self.lang = lang
            self.shop = shop
            self.platform = platform
            
            if let baseUrl = apiPrefix, !baseUrl.isEmpty, baseUrl != "" {
                NetworkManager.shared().registerBaseUrl(baseUrl: baseUrl)
            }
            
            if let widgetUrl = widgetUrlPrefix, !widgetUrl.isEmpty, widgetUrl != "" {
                NetworkManager.shared().registerWidgetUrl(widgetUrl: widgetUrl)
            }
            
            var language = Languages.english
            
            if lang == "ar" {
                language = Languages.arabic
            }
            
            NetworkManager.shared().registerAPIKey(APIKey: apiKey, language: language)
            
            if let completion = completion {
                loadBotSettings(completion: completion)
            }
        }
    
    private func loadBotSettings(completion: @escaping (() -> Void)) {
        NetworkManager.shared().load(path: APIEndPoints.getBotStyle, method: RequestMethod.GET, params: [:], modelType: GetClientBotStyleResponse.self) { (data, error) in
            completion()
            if data != nil {
                Gameball.clientBotStyle = (data as? GetClientBotStyleResponse)?.response
                NetworkManager.shared().clientBotSettings = true
            }
        }
    }
    
    // Returns player Gameball ID
    public func registerPlayer(
        playerUniqueId: String,
        playerTypeId: String = "",
        deviceToken: String = "",
        mobile: String? = nil,
        email: String? = nil,
        referrerCode: String? = nil,
        playerAttributes: [String: Any] = [:],
        completion: ((_ gameballId: Int?, _ error: String?) -> Void)?
    ) {
        self.playerUniqueId = playerUniqueId
        NetworkManager.shared().registerPlayer(
            playerUniqueId: playerUniqueId,
            categoryId: playerTypeId,
            playerAttributes: playerAttributes,
            withDeviceToken: deviceToken,
            mobile: mobile,
            email: email,
            referrerCode: referrerCode,
            completion: completion
        )
    }
    
    public func showProfile(
        playerUniqueId: String,
        openDetail: String? = nil,
        hideNavigation: Bool? = nil,
        showCloseBtn: Bool = true,
        pullToDismiss: Bool = false,
        completion:  ((_ viewController: UIViewController?, _ errorMessage: String?)->())
    ) {
        let GB_ViewController = self.prepareGBVC(
            withAPIKEY: apiKey,
            withPlayerUniqueId: playerUniqueId,
            withColor: Gameball.clientBotStyle?.botMainColor,
            withLang: lang,
            openDetail: openDetail,
            hideNavigation: hideNavigation,
            showCloseBtn: showCloseBtn,
            pullToDismiss: pullToDismiss
        )
        
        completion(GB_ViewController, nil)
    }
    
    
    private func prepareGBVC(withAPIKEY: String,withPlayerUniqueId: String,withColor: String?, withLang:String?, openDetail: String? = nil, hideNavigation: Bool? = nil, showCloseBtn: Bool, pullToDismiss: Bool) -> UIViewController {
        var bundle: Bundle?
        #if COCOAPODS
            bundle = Bundle(for: GB_WEBVIEWWIDGETViewController.self)
        #else
            bundle = Bundle.module
        #endif
        let GB_ViewController = GB_WEBVIEWWIDGETViewController(nibName: String(describing: GB_WEBVIEWWIDGETViewController.self), bundle: bundle)
        GB_ViewController.APIKEY = withAPIKEY
        GB_ViewController.playerID = withPlayerUniqueId
        GB_ViewController.color = withColor
        GB_ViewController.lang = withLang
        GB_ViewController.openDetail = openDetail
        GB_ViewController.hideNavigation = hideNavigation
        GB_ViewController.showCloseBtn = showCloseBtn
        GB_ViewController.pullToDismiss = pullToDismiss
        return GB_ViewController
    }
    
    public func recievedDynamicLink(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else { return }
        for queryItem in queryItems{
            Helpers().dPrint("Parameter \(queryItem.name) has value of \(queryItem.value ?? "")")
            if queryItem.name == "GBReferral" {
                NetworkManager.shared().referalCode = (queryItem.value ?? "")
            }
        }
    }
    
    // Friend Referral
    public func friendReferral(playerUniqueId: String,playerAttributes: [String:Any] = [:], completion: @escaping (String) -> Void)  {
        return NetworkManager.shared().friendReferral(playerUniqueId: playerUniqueId,playerAttributes: playerAttributes, completion: completion)
    }
    
    public func sendEvents(
        playerUniqueId: String,
        events: [Event],
        completion: ((_ success: String?, _ errorDescription: Any?)->())? = nil
    ) {
        NetworkManager.shared().sendEvent(playerUniqueId: playerUniqueId, events: events) { (responseObject, error) in
            if error == nil {
                Helpers().dPrint("done ..sendAction..")
                completion?("Success", nil)
            }
            else {
                Helpers().dPrint("failed sendAction")
                completion?("Failure", error?.description)
            }
        }
    }
    
    //    public func configureFireBase() {
    //        if let filePath = Bundle.init(for: type(of: self)).path(forResource: "GameBallSDK-Info", ofType: "plist") {
    //
    //
    //            let manualOptions = FirebaseOptions.init(googleAppID: "1:252563989296:ios:070bea370ad08516", gcmSenderID: "550082315977")
    //            manualOptions.bundleID = "org.cocoapods.GameBallSDK"
    //            manualOptions.apiKey = "AIzaSyBuUTVn-JHAPOBk7SJla8V0lqdbFcBdv0Q"
    //            manualOptions.projectID = "gameballsdk"
    ////            manualOptions.clientID = "252563989296-ldf2tn2hp97vklt576kl4ao109bf7js8.apps.googleusercontent.com"
    //            FirebaseApp.configure(name: "GameballSDK", options: manualOptions)
    //        }
    //    }
    
    //    public func configureFirebaseTest() {
    //        let manualOptions = FirebaseOptions.init(googleAppID: "1:6155436118:ios:5f6ec0ebbfd46fca", gcmSenderID: "6155436118")
    //        manualOptions.bundleID = "abodeif.gameball"
    //        manualOptions.apiKey = "AIzaSyAckaZGugjHFE5vVpT6fED7yD7JD8MEnYc"
    //        manualOptions.projectID = "gameballios"
    //        FirebaseApp.configure(options: manualOptions)
    //    }
    
    //    public func getFirebaseApp() -> [String : FirebaseApp]? {
    //        return FirebaseApp.allApps
    //    }
}

