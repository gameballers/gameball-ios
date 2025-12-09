//
//  ViewController.swift
//  Gameball
//
//  Created by Mahmoud Tarek on 29/07/2023.
//  Updated for v3.1.1 with Guest Mode support
//

import UIKit
import Gameball

class ViewController: UIViewController {

    // MARK: - Outlets

    @IBOutlet weak var launchWidgetBtn: UIButton!
    @IBOutlet weak var launchGuestWidgetBtn: UIButton!
    @IBOutlet weak var trackEventBtn: UIButton!

    @IBOutlet weak var apiKeyTextField: UITextField!
    @IBOutlet weak var apiUrlTextField: UITextField!
    @IBOutlet weak var widgetUrlTextField: UITextField!
    @IBOutlet weak var customerIdTextField: UITextField!
    @IBOutlet weak var langTextField: UITextField!
    @IBOutlet weak var shopTextField: UITextField!
    @IBOutlet weak var platformTextField: UITextField!
    @IBOutlet weak var openDetailTextField: UITextField!
    @IBOutlet weak var customerAttributesTextView: UITextView!
    @IBOutlet weak var hideNavigationSwitch: UISwitch!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Disable buttons until SDK is initialized
        launchWidgetBtn.isEnabled = false
        launchGuestWidgetBtn.isEnabled = true // Guest mode doesn't require initialization
        trackEventBtn.isEnabled = false

        // Set placeholder values for demo
        apiKeyTextField.placeholder = "Enter your API Key"
        customerIdTextField.placeholder = "Enter Customer ID"
        langTextField.placeholder = "en"
        shopTextField.placeholder = "Optional"
        platformTextField.placeholder = "iOS"
        openDetailTextField.placeholder = "rewards, achievements, etc."
    }

    // MARK: - Actions

    @IBAction func didTapInitSDK(_ sender: UIButton) {
        guard let apiKey = apiKeyTextField.text, !apiKey.isEmpty else {
            displayAlert(title: "Error", message: "Please enter API Key")
            return
        }

        guard let customerId = customerIdTextField.text, !customerId.isEmpty else {
            displayAlert(title: "Error", message: "Please enter Customer ID")
            return
        }

        // Step 1: Initialize SDK with GameballConfig
        let config = GameballConfig(
            apiKey: apiKey,
            lang: langTextField.text?.isEmpty == false ? langTextField.text! : "en",
            platform: platformTextField.text?.isEmpty == false ? platformTextField.text : nil,
            shop: shopTextField.text?.isEmpty == false ? shopTextField.text : nil,
            apiPrefix: apiUrlTextField.text?.isEmpty == false ? apiUrlTextField.text : nil
        )

        // Initialize SDK (completion is optional in v3.1.0+)
        GameballApp.getInstance().`init`(config: config) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.displayAlert(title: "SDK Init Failed", message: error.localizedDescription)
                }
                return
            }

            print("✅ SDK initialized successfully")

            // Step 2: Initialize Customer with throwing initializer
            self.initializeCustomer(customerId: customerId)
        }
    }

    private func initializeCustomer(customerId: String) {
        // Parse customer attributes from text view
        let attributes = parseCustomerAttributes()

        do {
            // Create InitializeCustomerRequest with throwing initializer
            let request = try InitializeCustomerRequest(
                customerId: customerId,
                email: "customer@example.com",  // Optional
                mobile: "1234567890",           // Optional
                deviceToken: "fcm_token_here",  // Optional - for push notifications
                pushProvider: .firebase,        // Optional - .firebase or .huawei
                customerAttributes: attributes, // Optional
                referralCode: nil,              // Optional
                isGuest: false                  // Optional - defaults to false
            )

            // Send initialization request
            GameballApp.getInstance().initializeCustomer(request) { [weak self] response, errorMessage in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let errorMessage = errorMessage {
                        self.displayAlert(title: "Customer Init Failed", message: errorMessage)
                    } else {
                        print("✅ Customer initialized successfully")
                        if let gameballId = response?.gameballId {
                            print("Gameball ID: \(gameballId)")
                        }

                        // Enable buttons after successful initialization
                        self.launchWidgetBtn.isEnabled = true
                        self.trackEventBtn.isEnabled = true
                    }
                }
            }
        } catch GameballError.emptyCustomerId {
            displayAlert(title: "Validation Error", message: "Customer ID cannot be empty")
        } catch GameballError.missingDeviceToken {
            displayAlert(title: "Validation Error", message: "Device token required when push provider is set")
        } catch GameballError.missingPushProvider {
            displayAlert(title: "Validation Error", message: "Push provider required when device token is set")
        } catch {
            displayAlert(title: "Error", message: error.localizedDescription)
        }
    }

    @IBAction func didTapLaunchWidget(_ sender: UIButton) {
        guard let customerId = customerIdTextField.text, !customerId.isEmpty else {
            displayAlert(title: "Error", message: "Please enter Customer ID")
            return
        }

        // Create ShowProfileRequest (non-throwing in v3.1.1+)
        let profileRequest = ShowProfileRequest(
            customerId: customerId,
            openDetail: openDetailTextField.text?.isEmpty == false ? openDetailTextField.text : nil,
            hideNavigation: hideNavigationSwitch.isOn,
            showCloseButton: true,
            closeButtonColor: "#FF6B6B",  // Custom color
            widgetUrlPrefix: widgetUrlTextField.text?.isEmpty == false ? widgetUrlTextField.text : nil
        )

        // Show profile widget
        GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
    }

    @IBAction func didTapLaunchGuestWidget(_ sender: UIButton) {
        // FIXED in v3.1.1: Guest Mode - No customer ID required!
        let guestRequest = ShowProfileRequest(
            openDetail: openDetailTextField.text?.isEmpty == false ? openDetailTextField.text : nil,
            hideNavigation: hideNavigationSwitch.isOn,
            showCloseButton: true,
            closeButtonColor: "#4CAF50"  // Green color for guest mode
        )

        // Show profile widget in guest mode
        GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .fullScreen)

        displayAlert(
            title: "Guest Mode",
            message: "Opening widget in guest mode - no authentication required!"
        )
    }

    @IBAction func didTapTrackEvent(_ sender: UIButton) {
        guard let customerId = customerIdTextField.text, !customerId.isEmpty else {
            displayAlert(title: "Error", message: "Please enter Customer ID")
            return
        }

        do {
            // Create Event with throwing initializer
            let event = try Event(
                events: [
                    "purchase": [
                        "amount": 100.00,
                        "currency": "USD",
                        "product_id": "prod_123",
                        "category": "electronics",
                        "quantity": 2,
                        "discount": 10.00,
                        "payment_method": "credit_card"
                    ]
                ],
                customerId: customerId,
                email: "customer@example.com",  // Optional
                mobile: "1234567890"            // Optional
            )

            // Send event
            GameballApp.getInstance().sendEvent(event) { [weak self] success, errorMessage in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if success {
                        self.displayAlert(title: "Success", message: "Event sent successfully!")
                    } else if let errorMessage = errorMessage {
                        self.displayAlert(title: "Event Failed", message: errorMessage)
                    }
                }
            }
        } catch GameballError.emptyCustomerId {
            displayAlert(title: "Validation Error", message: "Customer ID cannot be empty")
        } catch GameballError.emptyEvents {
            displayAlert(title: "Validation Error", message: "Events dictionary cannot be empty")
        } catch {
            displayAlert(title: "Error", message: error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    private func parseCustomerAttributes() -> CustomerAttributes? {
        guard let text = customerAttributesTextView.text,
              !text.isEmpty,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Create CustomerAttributes from JSON
        return CustomerAttributes(
            displayName: json["displayName"] as? String,
            firstName: json["firstName"] as? String,
            lastName: json["lastName"] as? String,
            email: json["email"] as? String,
            gender: json["gender"] as? String,
            mobile: json["mobile"] as? String,
            dateOfBirth: json["dateOfBirth"] as? String,
            joinDate: json["joinDate"] as? String,
            preferredLanguage: json["preferredLanguage"] as? String,
            customAttributes: json["customAttributes"] as? [String: String],
            additionalAttributes: json["additionalAttributes"] as? [String: String]
        )
    }

    private func displayAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Simple Usage Examples
// These methods demonstrate common SDK usage patterns

extension ViewController {

    // EXAMPLE 1: Simple Customer Initialization
    func example_simpleCustomerInit() {
        do {
            let request = try InitializeCustomerRequest(
                customerId: "customer_123",
                email: "user@example.com"
            )

            GameballApp.getInstance().initializeCustomer(request) { response, error in
                if let error = error {
                    print("❌ Error: \(error)")
                } else {
                    print("✅ Customer initialized: \(response?.gameballId ?? "")")
                }
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 2: Customer with Attributes
    func example_customerWithAttributes() {
        do {
            let attributes = CustomerAttributes(
                displayName: "John Doe",
                firstName: "John",
                lastName: "Doe",
                mobile: "1234567890",
                customAttributes: ["tier": "gold", "city": "New York"]
            )

            let request = try InitializeCustomerRequest(
                customerId: "customer_456",
                email: "john@example.com",
                customerAttributes: attributes
            )

            GameballApp.getInstance().initializeCustomer(request) { response, error in
                if let error = error {
                    print("❌ Error: \(error)")
                } else {
                    print("✅ Customer with attributes initialized")
                }
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 3: Track Purchase Event
    func example_trackPurchase() {
        do {
            let event = try Event(
                events: [
                    "purchase": [
                        "amount": 99.99,
                        "currency": "USD",
                        "product_id": "prod_123"
                    ]
                ],
                customerId: "customer_123"
            )

            GameballApp.getInstance().sendEvent(event) { success, error in
                if success {
                    print("✅ Purchase event tracked")
                } else {
                    print("❌ Error: \(error ?? "Unknown")")
                }
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 4: Track Custom Event
    func example_trackCustomEvent() {
        do {
            let event = try Event(
                events: [
                    "video_watched": [
                        "video_id": "vid_789",
                        "duration": 120,
                        "category": "tutorial"
                    ]
                ],
                customerId: "customer_123"
            )

            GameballApp.getInstance().sendEvent(event) { success, error in
                print(success ? "✅ Event tracked" : "❌ Failed: \(error ?? "")")
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 5: Show Authenticated Profile Widget
    func example_showAuthenticatedProfile() {
        let request = ShowProfileRequest(
            customerId: "customer_123",
            showCloseButton: true,
            closeButtonColor: "#4CAF50"
        )

        GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)
    }

    // EXAMPLE 6: Show Guest Profile Widget (v3.1.1+)
    func example_showGuestProfile() {
        let request = ShowProfileRequest(
            showCloseButton: true,
            closeButtonColor: "#FF6B6B"
        )

        GameballApp.getInstance().showProfile(request, presentationStyle: .pageSheet)
    }

    // EXAMPLE 7: Conditional Widget Display
    func example_conditionalWidget() {
        // Check if user is logged in
        if let customerId = UserDefaults.standard.string(forKey: "customerId") {
            // Show authenticated widget
            let request = ShowProfileRequest(customerId: customerId)
            GameballApp.getInstance().showProfile(request)
        } else {
            // Show guest mode widget
            let guestRequest = ShowProfileRequest()
            GameballApp.getInstance().showProfile(guestRequest)
        }
    }

    // EXAMPLE 8: Initialize with Push Notifications
    func example_initWithPushNotifications(fcmToken: String) {
        do {
            let request = try InitializeCustomerRequest(
                customerId: "customer_123",
                deviceToken: fcmToken,
                pushProvider: .firebase
            )

            GameballApp.getInstance().initializeCustomer(request) { response, error in
                print(error == nil ? "✅ Push enabled" : "❌ Error: \(error ?? "")")
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 9: Initialize with Referral Code
    func example_initWithReferral(referralCode: String) {
        do {
            let request = try InitializeCustomerRequest(
                customerId: "customer_789",
                email: "newuser@example.com",
                referralCode: referralCode
            )

            GameballApp.getInstance().initializeCustomer(request) { response, error in
                print(error == nil ? "✅ Referral applied" : "❌ Error: \(error ?? "")")
            }
        } catch {
            print("❌ Validation error: \(error)")
        }
    }

    // EXAMPLE 10: SDK with Session Token (v3.1.0+)
    func example_initWithSessionToken() {
        let config = GameballConfig(
            apiKey: "your_api_key",
            lang: "en",
            sessionToken: "your_session_token"
        )

        GameballApp.getInstance().`init`(config: config) { error in
            print(error == nil ? "✅ SDK initialized with token" : "❌ Error: \(error?.localizedDescription ?? "")")
        }
    }

    // EXAMPLE 11: Override Session Token per Request
    func example_overrideSessionToken() {
        do {
            let request = try InitializeCustomerRequest(
                customerId: "customer_123"
            )

            // Override global session token for this specific request
            GameballApp.getInstance().initializeCustomer(
                request,
                completion: { response, error in
                    print("✅ Request completed with custom token")
                },
                sessionToken: "custom_token_for_this_request"
            )
        } catch {
            print("❌ Error: \(error)")
        }
    }

    // EXAMPLE 12: Show Widget with Specific Section
    func example_showWidgetSection() {
        let request = ShowProfileRequest(
            customerId: "customer_123",
            openDetail: "rewards", // Opens directly to rewards section
            showCloseButton: true
        )

        GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)
    }
}
