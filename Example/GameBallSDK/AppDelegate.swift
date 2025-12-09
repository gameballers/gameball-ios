//
//  AppDelegate.swift
//  GameBallSDK
//
//  Created by Martin Sorsok on 07/23/2019.
//  Copyright (c) 2019 Martin Sorsok. All rights reserved.
//  Updated for v3.1.1 with modern SDK patterns
//
//  USAGE:
//  1. Initialize SDK with GameballConfig in application(_:didFinishLaunchingWithOptions:)
//  2. Store FCM token when received in messaging(_:didReceiveRegistrationToken:)
//  3. Extract referral codes from deep links in application(_:open:options:)
//  4. See ViewController.swift extension for 12+ usage examples
//

import UIKit
import Firebase
import Gameball
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    var window: UIWindow?
    var fcmToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {

        // Configure Firebase
        FirebaseApp.configure()

        // Initialize Gameball SDK v3.1.1+
        let config = GameballConfig(
            apiKey: "API_KEY_HERE",
            lang: "en"
        )

        GameballApp.getInstance().`init`(config: config) { error in
            if let error = error {
                print("❌ Gameball SDK initialization failed: \(error.localizedDescription)")
            } else {
                print("✅ Gameball SDK initialized successfully")
            }
        }

        // Register for push notifications
        registerForPushNotifications()

        return true
    }

    func registerForPushNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) {
                [weak self] granted, error in
                UNUserNotificationCenter.current().delegate = self
                Messaging.messaging().delegate = self
                guard granted else { return }
                self?.getNotificationSettings()
            }
    }

    func getNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        // TODO: Extract referral code from deep link URL
        // You are responsible for parsing the URL and extracting the referral code
        // Pass the extracted referral code to InitializeCustomerRequest

        print("Received deep link: \(url)")
        return true
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // TODO: Store FCM token to pass to InitializeCustomerRequest
        // You are responsible for retrieving and storing the device token
        // Pass this token when initializing the customer with push notifications enabled

        self.fcmToken = fcmToken
        print("FCM Token received: \(fcmToken ?? "nil")")
    }
}

