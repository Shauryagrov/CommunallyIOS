//
//  PaymentManager.swift
//  Communally
//
//  Manages payments via Stripe Connect
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

class PaymentManager: ObservableObject {
    static let shared = PaymentManager()
    
    @Published var payments: [Payment] = []
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    
    private var hirerListener: ListenerRegistration?
    private var workerListener: ListenerRegistration?
    private var hirerPaymentsById: [String: QueryDocumentSnapshot] = [:]
    private var workerPaymentsById: [String: QueryDocumentSnapshot] = [:]
    
    private init() {}

    deinit {
        hirerListener?.remove()
        workerListener?.remove()
    }

    /// Wipes in-memory state + listeners. Used after account deletion.
    func clearLocalState() {
        hirerListener?.remove()
        workerListener?.remove()
        hirerListener = nil
        workerListener = nil
        hirerPaymentsById = [:]
        workerPaymentsById = [:]
        DispatchQueue.main.async { self.payments = [] }
    }
    
    // MARK: - Initialize
    
    func startListening(for userId: String) {
        guard let db = db else {
            print("⚠️ PaymentManager: Firebase not configured")
            return
        }
        
        hirerListener?.remove()
        workerListener?.remove()
        hirerPaymentsById = [:]
        workerPaymentsById = [:]

        hirerListener = db.collection("payments")
            .whereField("hirerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to payments: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                self.hirerPaymentsById = Dictionary(uniqueKeysWithValues: documents.map { ($0.documentID, $0) })
                self.refreshMergedPayments()
            }

        workerListener = db.collection("payments")
            .whereField("workerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Error listening to worker payments: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else { return }
                self.workerPaymentsById = Dictionary(uniqueKeysWithValues: documents.map { ($0.documentID, $0) })
                self.refreshMergedPayments()
            }
    }

    private func refreshMergedPayments() {
        let merged = hirerPaymentsById.merging(workerPaymentsById) { current, _ in current }
        self.payments = merged.values.compactMap { try? $0.data(as: Payment.self) }
            .sorted { $0.createdAt > $1.createdAt }
        print("✅ Loaded \(self.payments.count) payments for user")
    }
    
    // MARK: - Create Payment
    
    /// Create payment when job is accepted
    func createPayment(
        for application: JobApplication,
        opportunity: Opportunity,
        completion: @escaping (Result<Payment, Error>) -> Void
    ) {
        guard let db = db else {
            completion(.failure(NSError(domain: "PaymentManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            return
        }

        // Idempotency guard — if a Payment already exists for this
        // application id, return it instead of creating a duplicate.
        // Previously a retry (network blip, double-tap accept, Apple-Pay
        // crash mid-flow) would write a SECOND Payment doc with the same
        // applicationId, and the seeker would see two identical earnings
        // rows ("$47.50 Pet Care · Waiting on hirer payment ×2"). Now
        // any subsequent attempt short-circuits to the existing payment.
        if let existing = payments.first(where: { $0.applicationId == application.id }) {
            print("ℹ️ PaymentManager: payment already exists for application \(application.id), reusing.")
            completion(.success(existing))
            return
        }

        // Calculate fees
        let amount = Double(opportunity.payAmount ?? "0") ?? 0
        let breakdown = StripeConfig.getPaymentBreakdown(amount: amount)
        
        let payment = Payment(
            id: nil,
            applicationId: application.id,
            opportunityId: opportunity.safeId,
            opportunityTitle: opportunity.title,
            hirerId: opportunity.hirerId,
            hirerName: opportunity.hirerName,
            workerId: application.applicantId,
            workerName: application.applicantName,
            jobAmount: breakdown.jobAmount,
            platformFee: breakdown.platformFee,
            workerFee: breakdown.workerFee,
            stripeFee: breakdown.stripeFee,
            totalCharged: breakdown.totalCharged,
            workerPayout: breakdown.workerPayout,
            stripePaymentIntentId: nil, // Will be set when payment is processed
            stripeTransferId: nil,
            stripeCustomerId: nil,
            status: .pending, // Starts as pending
            createdAt: Date(),
            chargedAt: nil,
            releasedAt: nil,
            refundedAt: nil,
            failureReason: nil,
            refundReason: nil
        )
        
        // Pre-allocate the doc reference so we have a stable ID BEFORE the
        // network write. Previously this used `addDocument(from:)` followed
        // by a `getDocument` round-trip — if that round-trip didn't return
        // cleanly (eventual consistency, network blip, decode mismatch),
        // the completion handler returned a Payment with `id = nil`, which
        // made `payment.safeId` fall back to a random UUID. Downstream
        // `updateData` calls then hit a phantom doc, silently no-op'd, and
        // the real payment stayed at `.pending` forever — the exact bug
        // that's been making payments look "Waiting on hirer payment" even
        // after the hirer paid.
        let docRef = db.collection("payments").document()

        var paymentWithId = payment
        paymentWithId.id = docRef.documentID

        do {
            try docRef.setData(from: paymentWithId) { error in
                if let error = error {
                    print("❌ Error creating payment: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Payment record created (\(docRef.documentID)):")
                    print("   Job amount: \(breakdown.formattedJobAmount)")
                    print("   Platform fee — hirer side (5%): \(breakdown.formattedPlatformFee)")
                    print("   Platform fee — worker side (5%): \(breakdown.formattedWorkerFee)")
                    print("   Stripe fee: \(breakdown.formattedStripeFee)")
                    print("   TOTAL to charge hirer: \(breakdown.formattedTotalCharged)")
                    print("   Worker will receive: \(breakdown.formattedWorkerPayout)")
                    completion(.success(paymentWithId))
                }
            }
        } catch {
            print("❌ Error creating payment: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    // MARK: - Process Payment (Charge hirer)
    
    /// Charge the hirer's card and update payment status
    func processPayment(
        paymentId: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let db = db else {
            completion(false)
            return
        }
        
        guard let payment = payments.first(where: { $0.safeId == paymentId }) else {
            print("❌ Payment not found")
            completion(false)
            return
        }
        
        // In production, this would call Stripe API via backend
        // For now, simulate successful charge
        
        if StripeConfig.useMockPayments {
            // Simulate payment processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                db.collection("payments").document(paymentId).updateData([
                    "status": PaymentStatus.held.rawValue,
                    "chargedAt": Timestamp(date: Date()),
                    "stripePaymentIntentId": "pi_test_\(UUID().uuidString)"
                ]) { error in
                    if let error = error {
                        print("❌ Error updating payment: \(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    
                    Log.debug("✅ Payment charged (simulated): \(payment.formattedTotalCharged)")
                    completion(true)
                }
            }
        } else {
            // TODO: Call Stripe API through StripeService
            completion(false)
        }
    }
    
    // MARK: - Release Payment
    
    /// Release payment to worker when job is completed
    func releasePayment(
        paymentId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard db != nil else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "PaymentManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            }
            return
        }
        
        guard let payment = payments.first(where: { $0.safeId == paymentId }) else {
            print("❌ Payment not found")
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "PaymentManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Payment not found"])))
            }
            return
        }
        
        StripeService.shared.releaseHeldPayment(paymentId: paymentId) { result in
            switch result {
            case .success:
                Log.debug("✅ Payment released: \(payment.formattedWorkerPayout) → \(payment.workerName)")
                Log.debug("   Platform earnings: \(payment.formattedPlatformFee)")
                
                NotificationManager.shared.sendPaymentReleasedNotification(
                    payment: payment
                )
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                
            case .failure(let error):
                print("❌ Error releasing payment: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Claim Earnings (worker cashes out their in-app balance)

    /// Drains every `payable` payment for the signed-in worker by issuing
    /// real Stripe transfers to their Connect account. This is the backend
    /// for the "Cash Out $X" CTA on the Earnings screen.
    ///
    /// `requiresBankSetup` in the result tells the caller to open the
    /// BankSetupSheet instead of showing a generic error — happens when the
    /// worker has piled up earnings but never started Stripe Connect.
    enum ClaimEarningsResult {
        case success(transferredCount: Int, transferredCents: Int)
        case requiresBankSetup(message: String)
        case failure(Error)
    }

    func claimEarnings(completion: @escaping (ClaimEarningsResult) -> Void) {
        guard let firUser = Auth.auth().currentUser else {
            completion(.failure(NSError(
                domain: "PaymentManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in to cash out."]
            )))
            return
        }

        firUser.getIDToken { idToken, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let idToken = idToken else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "PaymentManager",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Could not authenticate cash-out request."]
                    )))
                }
                return
            }

            let url = "\(StripeConfig.backendURL)/claimEarnings"
            guard let requestURL = URL(string: url) else {
                DispatchQueue.main.async {
                    completion(.failure(StripeError.invalidURL))
                }
                return
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            guard let body = try? JSONSerialization.data(withJSONObject: [
                "idToken": idToken
            ]) else {
                DispatchQueue.main.async {
                    completion(.failure(StripeError.invalidResponse))
                }
                return
            }
            request.httpBody = body

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]) ?? [:]

                if httpStatus == 400, let requires = json["requiresBankSetup"] as? Bool, requires {
                    let msg = (json["error"] as? String) ?? "Connect a bank account to cash out."
                    DispatchQueue.main.async {
                        completion(.requiresBankSetup(message: msg))
                    }
                    return
                }

                if !(200...299).contains(httpStatus) {
                    let msg = (json["error"] as? String)
                        ?? String(data: data ?? Data(), encoding: .utf8)
                        ?? "Cash out failed"
                    DispatchQueue.main.async {
                        completion(.failure(StripeError.serverError(msg)))
                    }
                    return
                }

                let transferredCount = (json["transferredCount"] as? Int) ?? 0
                let transferredCents = (json["transferredCents"] as? Int) ?? 0
                DispatchQueue.main.async {
                    completion(.success(
                        transferredCount: transferredCount,
                        transferredCents: transferredCents
                    ))
                }
            }.resume()
        }
    }

    // MARK: - Refund Payment

    /// Refund the Stripe charge and mark the payment as refunded in
    /// Firestore. The backend requires a Firebase idToken and verifies
    /// the caller is either the hirer or worker on the specific payment
    /// — without this, a forged direct API call could refund someone
    /// else's payment. Also: the backend rejects refund attempts on
    /// `.payable` and `.released` statuses (post-completion = worker
    /// earned the money), so this should only be invoked for active
    /// `.pending` / `.processing` / `.held` payments.
    func refundPayment(
        paymentId: String,
        reason: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let firUser = Auth.auth().currentUser else {
            print("❌ refundPayment: not signed in")
            DispatchQueue.main.async { completion(false) }
            return
        }

        firUser.getIDToken { idToken, error in
            if let error = error {
                print("❌ refundPayment: idToken fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard let idToken = idToken else {
                print("❌ refundPayment: nil idToken")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let url = "\(StripeConfig.backendURL)/refundPayment"
            guard let requestURL = URL(string: url) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            guard let body = try? JSONSerialization.data(withJSONObject: [
                "paymentId": paymentId,
                "reason": reason,
                "idToken": idToken
            ]) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            request.httpBody = body

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Error refunding payment: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let msg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                    print("❌ Refund failed (\(httpResponse.statusCode)): \(msg)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                print("✅ Payment refunded: \(paymentId)")
                DispatchQueue.main.async { completion(true) }
            }.resume()
        }
    }
    
    // MARK: - Get Payments
    
    func getPayment(for applicationId: String) -> Payment? {
        return payments.first { $0.applicationId == applicationId }
    }
    
    func getPayments(for userId: String) -> [Payment] {
        return payments.filter { $0.hirerId == userId || $0.workerId == userId }
    }
    
    // MARK: - Stats
    
    func getTotalEarnings(for workerId: String) -> Double {
        return payments
            .filter { $0.workerId == workerId && $0.status == .released }
            .reduce(0) { $0 + $1.workerPayout }
    }

    /// Everything the seeker has earned that isn't yet in their bank and
    /// isn't a terminal failure. Three states share this bucket because
    /// from the seeker's POV they all mean "money coming":
    ///   • `.pending` / `.processing` — hirer started the payment flow but
    ///     Stripe hasn't finished charging yet (webhook pending).
    ///   • `.held` — hirer charged, escrowed on the platform balance,
    ///     waiting on both parties to confirm completion.
    /// `.payable` is intentionally NOT included here — that's what the
    /// Cash Out button gates on. See `getClaimableEarnings`.
    func getPendingPayouts(for workerId: String) -> Double {
        return payments
            .filter {
                $0.workerId == workerId
                    && ($0.status == .pending
                        || $0.status == .processing
                        || $0.status == .held)
            }
            .reduce(0) { $0 + $1.workerPayout }
    }

    /// Earnings that are fully released by both parties and sitting in this
    /// worker's in-app Communally balance — they can cash these out as soon
    /// as they finish Stripe Connect onboarding.
    ///
    /// Surfaced on the Earnings screen as the big "Cash Out $X" number.
    func getClaimableEarnings(for workerId: String) -> Double {
        return payments
            .filter { $0.workerId == workerId && $0.status == .payable }
            .reduce(0) { $0 + $1.workerPayout }
    }

    /// Number of separate jobs whose earnings are sitting in the worker's
    /// balance waiting to be cashed out. Used in the Cash Out CTA copy
    /// ("Cash out 3 jobs · $145.20").
    func getClaimableJobCount(for workerId: String) -> Int {
        return payments
            .filter { $0.workerId == workerId && $0.status == .payable }
            .count
    }
    
    func getTotalSpent(for hirerId: String) -> Double {
        return payments
            .filter { $0.hirerId == hirerId && ($0.status == .held || $0.status == .released) }
            .reduce(0) { $0 + $1.totalCharged }
    }

    /// Charges currently held from this hirer awaiting job completion.
    func getPendingCharges(for hirerId: String) -> Double {
        return payments
            .filter { $0.hirerId == hirerId && $0.status == .held }
            .reduce(0) { $0 + $1.totalCharged }
    }

    /// Refund held funds for a cancelled application.
    func autoRefundForCancelledApplication(
        applicationId: String,
        reason: String = "Job cancelled"
    ) {
        guard let payment = getPayment(for: applicationId), payment.status == .held else {
            return
        }

        refundPayment(paymentId: payment.safeId, reason: reason) { success in
            if success {
                print("✅ Auto-refunded held payment for cancelled application: \(applicationId)")
            } else {
                print("❌ Auto-refund failed for cancelled application: \(applicationId)")
            }
        }
    }
    
    func getPlatformRevenue() -> Double {
        return payments
            .filter { $0.status == .released }
            .reduce(0) { $0 + $1.platformFee }
    }
}

// MARK: - Notification Extension
extension NotificationManager {
    func sendPaymentReleasedNotification(payment: Payment) {
        let notification = AppNotification(
            id: nil,
            type: .paymentReceived,
            title: "Payment Received! 💰",
            message: "You've been paid \(payment.formattedWorkerPayout) for '\(payment.opportunityTitle)'",
            userId: payment.workerId,
            relatedId: payment.applicationId,
            senderName: payment.hirerName,
            senderImageData: nil,
            createdAt: Date(),
            isRead: false
        )
        
        saveNotification(notification)
        sendPushNotification(notification)
        
        print("✅ Sent payment received notification")
    }
}
