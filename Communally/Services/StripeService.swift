//
//  StripeService.swift
//  Communally
//
//  Handles all Stripe payment processing
//

import Foundation
import UIKit
import StripePaymentSheet
import StripeCore
import StripeUICore
import FirebaseAuth

class StripeService: ObservableObject {
    static let shared = StripeService()
    
    @Published var isConnectingBank = false
    @Published var isProcessingPayment = false
    
    private init() {
        // Configure Stripe with publishable key
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
        print("✅ Stripe SDK initialized with publishable key")
    }
    
    // MARK: - Stripe Connect (Workers connect bank accounts)
    
    /// Open Stripe Connect onboarding for workers to connect their bank account.
    /// `firstName`, `lastName`, and `dateOfBirth` are forwarded to the backend
    /// so it can prefill the Stripe account at creation time — the more we
    /// pass, the more screens Stripe's hosted form skips. All three are
    /// optional; backend tolerates missing values and falls back to splitting
    /// `userName` on whitespace.
    func connectBankAccount(
        for userId: String,
        userEmail: String,
        userName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        dateOfBirth: Date? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        print("🏦 Starting Stripe Connect onboarding for user: \(userName)")

        isConnectingBank = true

        // Fetch a fresh Firebase idToken — backend requires it to verify
        // that the caller is actually `userId` (not an attacker trying to
        // overwrite someone else's `stripeConnectAccountId`).
        guard let firUser = Auth.auth().currentUser else {
            isConnectingBank = false
            completion(.failure(NSError(
                domain: "StripeService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in to set up payouts."]
            )))
            return
        }

        firUser.getIDToken { [weak self] idToken, tokenErr in
            guard let self = self else { return }
            if let tokenErr = tokenErr {
                DispatchQueue.main.async {
                    self.isConnectingBank = false
                    completion(.failure(tokenErr))
                }
                return
            }
            guard let idToken = idToken else {
                DispatchQueue.main.async {
                    self.isConnectingBank = false
                    completion(.failure(StripeError.invalidResponse))
                }
                return
            }

            self.performConnectAccountRequest(
                userId: userId,
                userEmail: userEmail,
                userName: userName,
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dateOfBirth,
                idToken: idToken,
                completion: completion
            )
        }
    }

    private func performConnectAccountRequest(
        userId: String,
        userEmail: String,
        userName: String,
        firstName: String?,
        lastName: String?,
        dateOfBirth: Date?,
        idToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let url = "\(StripeConfig.backendURL)/createConnectAccount"
        guard let requestURL = URL(string: url) else {
            completion(.failure(StripeError.invalidURL))
            isConnectingBank = false
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // ISO 8601 day-precision string — the backend parses this into
        // Stripe's {day, month, year} payload. Omit entirely if no DOB.
        let isoDob: String? = dateOfBirth.map { date in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f.string(from: date)
        }

        var body: [String: Any] = [
            "userId": userId,
            "email": userEmail,
            "name": userName,
            "returnURL": "https://communally-a4cb3.web.app/stripe/return",
            "refreshURL": "https://communally-a4cb3.web.app/stripe/refresh",
            "idToken": idToken
        ]
        if let firstName, !firstName.isEmpty { body["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { body["lastName"] = lastName }
        if let isoDob { body["dateOfBirth"] = isoDob }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            isConnectingBank = false
            return
        }

        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isConnectingBank = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                print("❌ Stripe Connect HTTP \(httpResponse.statusCode): \(bodyText)")
                let serverMessage: String
                if let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                   let errorText = json["error"] as? String, !errorText.isEmpty {
                    serverMessage = errorText
                } else {
                    serverMessage = bodyText
                }
                DispatchQueue.main.async {
                    completion(.failure(StripeError.serverError(serverMessage)))
                }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accountId = json["accountId"] as? String,
                  let onboardingURL = json["url"] as? String else {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                print("❌ Stripe Connect invalid response: \(body)")
                DispatchQueue.main.async {
                    completion(.failure(StripeError.invalidResponse))
                }
                return
            }
            
            // Open Stripe Connect onboarding in Safari
            DispatchQueue.main.async {
                if let url = URL(string: onboardingURL) {
                    UIApplication.shared.open(url)
                }
                completion(.success(accountId))
            }
        }.resume()
    }
    
    // MARK: - Payment Sheet (Hirers pay for jobs)
    
    /// Present payment sheet for hirer to pay worker
    func presentPaymentSheet(
        from viewController: UIViewController,
        amount: Double,
        opportunityTitle: String,
        hirerId: String,
        workerId: String,
        applicationId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        print("💳 Creating payment sheet for \(String(format: "$%.2f", amount))")
        
        isProcessingPayment = true
        
        // Step 1: Create Payment Intent via backend
        createPaymentIntent(
            amount: amount,
            hirerId: hirerId,
            workerId: workerId,
            applicationId: applicationId,
            opportunityTitle: opportunityTitle
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let paymentIntentData):
                // Step 2: Present Stripe Payment Sheet
                var configuration = PaymentSheet.Configuration()
                configuration.merchantDisplayName = "Communally"
                configuration.customer = .init(
                    id: paymentIntentData.customerId,
                    ephemeralKeySecret: paymentIntentData.ephemeralKey
                )
                let totalCharged = StripeConfig.getPaymentBreakdown(amount: amount).totalCharged
                configuration.primaryButtonLabel = "Pay \(String(format: "$%.2f", totalCharged))"
                configuration.allowsDelayedPaymentMethods = false

                // Enable Apple Pay. Requires the merchant ID to be registered
                // in Apple Developer + Xcode entitlements AND in the Stripe
                // Dashboard (certificate uploaded). Without all three, Apple
                // Pay silently won't appear in the sheet.
                configuration.applePay = .init(
                    merchantId: StripeConfig.applePayMerchantId,
                    merchantCountryCode: StripeConfig.applePayMerchantCountryCode
                )

                // Configure appearance to make it clear both card and Apple Pay are available
                var appearance = PaymentSheet.Appearance()
                appearance.primaryButton.backgroundColor = UIColor.black
                configuration.appearance = appearance
                    
                let paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: paymentIntentData.clientSecret,
                    configuration: configuration
                )
                
                DispatchQueue.main.async {
                    paymentSheet.present(from: viewController) { [weak self] result in
                        self?.isProcessingPayment = false
                        
                        switch result {
                        case .completed:
                            print("✅ Payment completed!")
                            completion(.success(paymentIntentData.paymentIntentId))
                        case .canceled:
                            print("⚠️ Payment canceled by user")
                            completion(.failure(StripeError.paymentCanceled))
                        case .failed(let error):
                            print("❌ Payment failed: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isProcessingPayment = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Backend Communication
    
    private func createPaymentIntent(
        amount: Double,
        hirerId: String,
        workerId: String,
        applicationId: String,
        opportunityTitle: String,
        completion: @escaping (Result<PaymentIntentData, Error>) -> Void
    ) {
        // Need a fresh idToken — backend now verifies the caller is
        // actually `hirerId` AND recomputes the canonical amount from
        // the opportunity doc. So the iOS-computed `amount` is treated
        // as informational only; the server's number is authoritative.
        guard let firUser = Auth.auth().currentUser else {
            completion(.failure(NSError(
                domain: "StripeService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in to start payment."]
            )))
            return
        }

        firUser.getIDToken { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }
            guard let idToken = idToken else {
                completion(.failure(StripeError.invalidResponse))
                return
            }

            self.performCreatePaymentIntent(
                amount: amount,
                hirerId: hirerId,
                workerId: workerId,
                applicationId: applicationId,
                opportunityTitle: opportunityTitle,
                idToken: idToken,
                completion: completion
            )
        }
    }

    private func performCreatePaymentIntent(
        amount: Double,
        hirerId: String,
        workerId: String,
        applicationId: String,
        opportunityTitle: String,
        idToken: String,
        completion: @escaping (Result<PaymentIntentData, Error>) -> Void
    ) {
        let url = "\(StripeConfig.backendURL)/createPaymentIntent"
        guard let requestURL = URL(string: url) else {
            completion(.failure(StripeError.invalidURL))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Note: backend now recomputes amount/jobAmount/platformFee/
        // stripeFee server-side from the opportunity doc. Anything we
        // send here is informational telemetry only — won't affect the
        // actual charge amount.
        let breakdown = StripeConfig.getPaymentBreakdown(amount: amount)

        let body: [String: Any] = [
            "amount": Int(breakdown.totalCharged * 100), // informational; server recomputes
            "currency": "usd",
            "hirerId": hirerId,
            "workerId": workerId,
            "applicationId": applicationId,
            "description": "Payment for: \(opportunityTitle)",
            "jobAmount": breakdown.jobAmount,
            "platformFee": breakdown.platformFee,
            "stripeFee": breakdown.stripeFee,
            "idToken": idToken
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown server error"
                let serverMessage: String
                
                if let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                   let errorText = json["error"] as? String,
                   !errorText.isEmpty {
                    serverMessage = errorText
                } else {
                    serverMessage = bodyText
                }
                
                completion(.failure(StripeError.serverError(serverMessage)))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clientSecret = json["clientSecret"] as? String,
                  let customerId = json["customerId"] as? String,
                  let ephemeralKey = json["ephemeralKey"] as? String,
                  let paymentIntentId = json["paymentIntentId"] as? String else {
                completion(.failure(StripeError.invalidResponse))
                return
            }
            
            let paymentData = PaymentIntentData(
                clientSecret: clientSecret,
                customerId: customerId,
                ephemeralKey: ephemeralKey,
                paymentIntentId: paymentIntentId
            )
            
            completion(.success(paymentData))
        }.resume()
    }
    
    func releaseHeldPayment(
        paymentId: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard let firUser = Auth.auth().currentUser else {
            completion(.failure(NSError(
                domain: "StripeService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in."]
            )))
            return
        }

        firUser.getIDToken { idToken, tokenErr in
            if let tokenErr = tokenErr {
                completion(.failure(tokenErr))
                return
            }
            guard let idToken = idToken else {
                completion(.failure(StripeError.invalidResponse))
                return
            }

            let url = "\(StripeConfig.backendURL)/releasePayment"
            guard let requestURL = URL(string: url) else {
                completion(.failure(StripeError.invalidURL))
                return
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "paymentId": paymentId,
                    "idToken": idToken
                ])
            } catch {
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown server error"
                    let serverMessage: String
                    if let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                       let errorText = json["error"] as? String,
                       !errorText.isEmpty {
                        serverMessage = errorText
                    } else {
                        serverMessage = bodyText
                    }
                    completion(.failure(StripeError.serverError(serverMessage)))
                    return
                }

                let json = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]) ?? [:]
                completion(.success(json["transferId"] as? String))
            }.resume()
        }
    }
    
    // MARK: - Check Stripe Connect Account Status
    
    func checkConnectAccountStatus(
        accountId: String,
        completion: @escaping (Result<ConnectAccountStatus, Error>) -> Void
    ) {
        let url = "\(StripeConfig.backendURL)/connectAccountStatus"
        guard let requestURL = URL(string: url) else {
            completion(.failure(StripeError.invalidURL))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["accountId": accountId]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let detailsSubmitted = json["detailsSubmitted"] as? Bool,
                  let chargesEnabled = json["chargesEnabled"] as? Bool,
                  let payoutsEnabled = json["payoutsEnabled"] as? Bool else {
                completion(.failure(StripeError.invalidResponse))
                return
            }
            
            let status = ConnectAccountStatus(
                detailsSubmitted: detailsSubmitted,
                chargesEnabled: chargesEnabled,
                payoutsEnabled: payoutsEnabled,
                disabledReason: json["disabledReason"] as? String,
                currentlyDue: json["currentlyDue"] as? [String] ?? [],
                pastDue: json["pastDue"] as? [String] ?? [],
                pendingVerification: json["pendingVerification"] as? [String] ?? []
            )
            
            completion(.success(status))
        }.resume()
    }
}

// MARK: - Data Models

struct PaymentIntentData {
    let clientSecret: String
    let customerId: String
    let ephemeralKey: String
    let paymentIntentId: String
}

struct ConnectAccountStatus {
    let detailsSubmitted: Bool
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let disabledReason: String?
    let currentlyDue: [String]
    let pastDue: [String]
    let pendingVerification: [String]
    
    var isReadyForPayouts: Bool {
        chargesEnabled && payoutsEnabled
    }
    
    var hasOutstandingRequirements: Bool {
        !currentlyDue.isEmpty || !pastDue.isEmpty
    }
}

enum StripeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case paymentCanceled
    case connectFailed
    case backendNotConfigured
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .paymentCanceled:
            return "Payment was canceled"
        case .connectFailed:
            return "Failed to connect bank account"
        case .backendNotConfigured:
            return "Backend server is not configured. Please set up Firebase Functions."
        case .serverError(let message):
            return message
        }
    }
}
