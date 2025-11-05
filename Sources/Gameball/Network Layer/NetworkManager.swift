//
//  NetworkManager.swift
//  gameball_SDK
//
//  Created by Martin Sorsok on 2/3/19.
//  Copyright © 2019 Martin Sorsok. All rights reserved.
//

import Foundation
import UIKit

typealias JSON = [String: Any]

class NetworkManager:NSObject {
    let urlSession: URLSession
    var baseUrl: String
    var widgetUrl: String
    var APIKey: String
    var currentLanguage: Languages
    var customerId: String
    var clientBotSettings: Bool?
    
    private static var sharedManager:NetworkManager = {
        let sessionConfiguration = URLSessionConfiguration.default
        if #available(iOS 11.0, *) {
            sessionConfiguration.waitsForConnectivity = true
        } else {
            // Fallback on earlier versions
        }
        let urlSession = URLSession(configuration: sessionConfiguration)
        
        let APIKey = ""
        let customerId = ""
        let currentLanguage = Languages.english
        let networkManager = NetworkManager.init(
            urlSession: urlSession,
            baseUrl: APIEndPoints.base_URL,
            widgetUrl: APIEndPoints.widget_URL,
            APIKey: APIKey,
            customerId: customerId,
            currentLanguage: currentLanguage
        )
        return networkManager
    }()
    
    
    private init(
        urlSession: URLSession,
        baseUrl: String,
        widgetUrl: String,
        APIKey: String,
        customerId: String,
        currentLanguage: Languages
    ) {
        self.urlSession = urlSession
        self.baseUrl = baseUrl
        self.widgetUrl = widgetUrl
        self.APIKey = APIKey
        self.customerId = customerId
        self.currentLanguage = currentLanguage
    }
    
    
    static func shared() -> NetworkManager {
        return sharedManager
    }
    
    
    func isAPIKeySet() -> Bool {
        return (self.APIKey.count > 0) ? true : false
    }
    
    func isBotSettingsSet() -> Bool {
        return clientBotSettings ?? false
    }

    func isCustomerIdSet() -> Bool {
        return (self.customerId.count > 0) ? true : false
    }
    
    func loadDebug<T>(path: String, method: RequestMethod, params: JSON, modelType: T.Type, completion: @escaping (Any?, ServiceError?) -> ()) where T:Codable {

        guard Reachability.isConnectedToNetwork() else {
            //            completion(nil, ServiceError.noInternetConnection)
            return
        }

        var request = URLRequest(path: path, method: method, params: params)
        self.adaptRequest(urlRequest: &request, sessionToken: nil)
        // Sending request to the server.
        let task = self.urlSession.dataTask(with: request) { data, response, error in
            // Parsing incoming data
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case (200..<300):
                    if let data = data {
                        let JSONString = String(data: data, encoding: String.Encoding.utf8)
                        Helpers().dPrint(JSONString ?? "Could not print Json")
                    }
                case 403:
                    completion(nil, ServiceError.missingAPIKey)
                case 401:
                    completion(nil, ServiceError.invalidAPIKey)
                default:
                    completion(nil, ServiceError.serverError)
                }
            }
            
            if let httpResponse = response as? HTTPURLResponse, (200..<300) ~= httpResponse.statusCode {
                completion(nil, nil)
            } else {
                completion(nil, ServiceError.serverError)
            }
        }
        
        task.resume()
    }
    
    
    func load<T>(path: String, method: RequestMethod, params: JSON, modelType: T.Type, completion: @escaping (Any?, ServiceError?) -> ()) where T:Codable {

        guard Reachability.isConnectedToNetwork() else {
            // completion(nil, ServiceError.noInternetConnection)
            return
        }

        var request = URLRequest(path: path, method: method, params: params)
        self.adaptRequest(urlRequest: &request, sessionToken: nil)
        // Sending request to the server.
        let task = self.urlSession.dataTask(with: request) { data, response, error in
            var object: T? = nil
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case (200..<300):
                    // Parsing incoming data
                    //            var object: T? = nil
                    
                    //                    guard let data = data else { return }
                    //                    do {
                    //                        let decoder = JSONDecoder()
                    //                        let gitData = try decoder.decode(modelType.self, from: data)
                    //                        print(gitData)
                    //                        object = gitData
                    //                        completion(object, nil)
                    //
                    //                    } catch let err {
                    //                        print("Err", err)
                    //                    }
                    if let data = data {
                        guard let tempObject = try? JSONDecoder().decode(modelType.self, from: data) else {
                            let JSONString = String(data: data, encoding: String.Encoding.utf8)
                            Helpers().dPrint(JSONString ?? "Could not print Json")
                            completion(nil, ServiceError.malformedResponse)
                            return
                        }
                        object = tempObject
                        completion(object, nil)
                    }
                case 403:
                    completion(nil, ServiceError.missingAPIKey)
                case 401:
                    completion(nil, ServiceError.invalidAPIKey)
                default:
                    completion(nil, ServiceError.serverError)
                }
            }
        }
        
        task.resume()
    }
    
    
    func loadImage(path: String, completion: @escaping (UIImage?, ServiceError?) -> ()) {
        guard Reachability.isConnectedToNetwork() else {
            //            completion(nil, ServiceError.noInternetConnection)
            return
        }
        var modifiedPath = path
        if path.contains("~") {
            modifiedPath = path.replacingOccurrences(of: "~", with: "")
        }
        //        var request = URLRequest(path: modifiedPath)
        let url = URL(string: modifiedPath)
        guard let myUrl = url else {
            Helpers().dPrint("bad image url .......")
            return
        }
        var req = URLRequest(url: myUrl);
        //        var request = URLRequest(path: modifiedPath)
        self.adaptRequest(urlRequest: &req, sessionToken: nil)
        let task = URLSession.shared.dataTask(with: req) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse, (200..<300) ~= httpResponse.statusCode {
                if let imageData = data {
                    let image = UIImage(data: imageData)
                    completion(image, nil)
                }
                else {
                    let errorObject = ["ErrorMsg":"The image file seems to be corrupted, check the URL: \(String(describing: req.url?.absoluteString))"]
                    let error = ServiceError.init(json: errorObject)
                    completion(nil, error)
                }
            } else {
                completion(nil, ServiceError.serverError)
            }
        }
        task.resume()
        
        
        //        if let url = url {
        //
        //        }
        //
        //        self.adaptRequest(urlRequest: &request)
        //        let task = self.urlSession.dataTask(with: request) { data, response, error in
        //            if let httpResponse = response as? HTTPURLResponse, (200..<300) ~= httpResponse.statusCode {
        //                if let imageData = data {
        //                    let image = UIImage(data: imageData)
        //                    completion(image, nil)
        //                }
        //                else {
        //                    let errorObject = ["ErrorMsg":"The image file seems to be corrupted, check the URL: \(String(describing: request.url?.absoluteString))"]
        //                    let error = ServiceError.init(json: errorObject)
        //                    completion(nil, error)
        //                }
        //            } else {
        //                completion(nil, ServiceError.serverError)
        //            }
        //        }
        //        task.resume()
    }
    

    func sendEvent(
        event: Event,
        sessionToken: String?,
        completion: @escaping ((_ success: Bool, _ error: ServiceError?)->())
    ) {

        guard Reachability.isConnectedToNetwork() else {
            completion(false, ServiceError.noInternetConnection)
            return
        }

        // Encode the event object using Codable
        var params: JSON = [:]

        if let eventData = try? JSONEncoder().encode(event),
           let jsonObject = try? JSONSerialization.jsonObject(with: eventData),
           let eventDict = jsonObject as? JSON {
            params = eventDict
        } else {
            completion(false, ServiceError.malformedResponse)
            return
        }

        var request = URLRequest(path: APIEndPoints.sendEvent, method: .POST, params: params, sessionToken: sessionToken)
        self.adaptRequest(urlRequest: &request, sessionToken: sessionToken)
        let task = self.urlSession.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case (200..<300):
                    completion(true, nil)
                case 403:
                    completion(false, ServiceError.missingAPIKey)
                case 401:
                    completion(false, ServiceError.invalidAPIKey)
                case 400:
                    if let data = data,
                       let jsonObject = try? JSONSerialization.jsonObject(with: data),
                       let json = jsonObject as? [String: Any],
                       let errorMsg = json["errorMsg"] as? String {
                        completion(false, ServiceError.custom(errorMsg))
                    } else {
                        completion(false, ServiceError.serverError)
                    }
                default:
                    completion(false, ServiceError.serverError)
                }
            } else {
                completion(false, ServiceError.serverError)
            }
        }

        task.resume()
    }
    func initializeCustomer(
        request: InitializeCustomerRequest,
        sessionToken: String?,
        completion: @escaping ((_ response: InitializeCustomerResponse?, _ error: ServiceError?)->())) {

            guard Reachability.isConnectedToNetwork() else {
                completion(nil, ServiceError.noInternetConnection)
                return
            }

            // Encode the request object, handling customerAttributes specially for additionalAttributes
            var params: JSON = [:]

            if let requestData = try? JSONEncoder().encode(request),
               let jsonObject = try? JSONSerialization.jsonObject(with: requestData),
               var requestDict = jsonObject as? JSON {

                // Replace customerAttributes with properly mapped version
                if let customerAttributes = request.customerAttributes {
                    requestDict["customerAttributes"] = AttributesHelper.mapToRequestParams(customerAttributes)
                }

                params = requestDict
            } else {
                completion(nil, ServiceError.malformedResponse)
                return
            }

            var urlRequest = URLRequest(path: APIEndPoints.initializeCustomer, method: .POST, params: params, sessionToken: sessionToken)
            self.adaptRequest(urlRequest: &urlRequest, sessionToken: sessionToken)

            let task = self.urlSession.dataTask(with: urlRequest) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case (200..<300):
                        if let data = data,
                           let responseObject = try? JSONDecoder().decode(InitializeCustomerResponse.self, from: data) {
                            completion(responseObject, nil)
                        } else {
                            completion(nil, ServiceError.malformedResponse)
                        }

                    case 403:
                        completion(nil, ServiceError.missingAPIKey)
                    case 401:
                        completion(nil, ServiceError.invalidAPIKey)
                    case 402:
                        completion(nil, ServiceError.invalidReferrerCode)
                    default:
                        completion(nil, ServiceError.serverError)
                    }
                }
            }

            task.resume()
        }
    
    
    func adaptRequest(urlRequest: inout URLRequest, sessionToken: String?) {
        if NetworkManager.shared().APIKey.count > 0 {
            urlRequest.addValue(NetworkManager.shared().APIKey, forHTTPHeaderField: "APIKey")
            urlRequest.addValue(SDKInfo.userAgent, forHTTPHeaderField: "x-gb-agent")

            // Use LanguageHelper to resolve language with priority order
            let resolvedLanguage = LanguageHelper.resolveLanguage()
            urlRequest.addValue(resolvedLanguage, forHTTPHeaderField: "lang")

            // Add session token header if present
            if let sessionToken = sessionToken, !sessionToken.isEmpty {
                urlRequest.addValue(sessionToken, forHTTPHeaderField: "X-GB-TOKEN")
            }
        }
    }
    
    func registerAPIKey(APIKey: String,language: Languages  = .english) {
        NetworkManager.shared().APIKey = APIKey
        UserDefaults.standard.set(APIKey, forKey: UserDefaultsKeys.APIKey.rawValue)
        setLanguage(language: language)
    }
    
    func registerBaseUrl(baseUrl: String) {
        NetworkManager.shared().baseUrl = baseUrl
    }
    
    func registerWidgetUrl(widgetUrl: String) {
        NetworkManager.shared().widgetUrl = widgetUrl
    }
    
    func setLanguage(language: Languages) {
        GB_Localizator.sharedInstance.language = language
        NetworkManager.shared().currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: UserDefaultsKeys.LanguageKey.rawValue)
    }
    
    // FIXME: Temporarily commented out - rebuilding step by step
    /*
    func registerCustomer(
        request: InitializeCustomerRequest,
        completion: ((_ gameballId: Int?, _ error: String?) -> Void)?
    ) {
            NetworkManager.shared().customerId = request.customerId
            UserDefaults.standard.set(request.customerId, forKey: UserDefaultsKeys.customerId.rawValue)
            self.registerCustomerRequest(
                request: request) { (gameballId, error) in
                    if error != nil {
                        completion?(nil, error?.description)
                        Helpers().dPrint("failed to register user because \(error?.description ?? "")")
                    } else {
                        completion?(gameballId, nil)
                    }
                }
        }
    */
}

extension URL {
    init(path: String, params: JSON, method: RequestMethod, sessionToken: String? = nil) {
        var components = URLComponents(string: NetworkManager.shared().baseUrl)

        // Build final path with version-aware concatenation
        var finalPath: String

        // Check if this is a versioned integrations endpoint
        if path.hasPrefix("/events") || path.hasPrefix("/customers") {
            // Determine which API version to use based on session token
            if let sessionToken = sessionToken, !sessionToken.isEmpty {
                // Has token → use v4.1
                finalPath = APIEndPoints.api_v4_1 + path
            } else {
                // No token → use v4.0
                finalPath = APIEndPoints.api_v4_0 + path
            }
        } else {
            // Non-versioned endpoint (like getBotStyle) - use as-is
            finalPath = path
        }

        components?.path += finalPath
        if params.count > 0 {
            switch method {
            case .GET, .DELETE:
                components?.queryItems = params.map {
                    URLQueryItem(name: $0.key, value: String(describing: $0.value))
                }
            default:
                break
            }
        }
        Helpers().dPrint((components?.url)!)
        self = (components?.url)!
    }
}

extension URLRequest {
    init(path: String, method: RequestMethod = .GET, params: JSON = [:], sessionToken: String? = nil) {
        let url = URL(path: path, params: params, method: method, sessionToken: sessionToken)
        self.init(url: url)
        httpMethod = method.rawValue
        switch method {
        case .POST, .PUT:
            httpBody = try! JSONSerialization.data(withJSONObject: params, options: [])
            setValue("application/json", forHTTPHeaderField: "Content-Type")

        default:
            break
        }
    }

}
