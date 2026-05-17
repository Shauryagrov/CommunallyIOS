//
//  PaymentView.swift
//  Communally
//

import SwiftUI
import FirebaseFirestore

struct PaymentConfirmationSheet: View {
    let opportunity: Opportunity
    let application: JobApplication
    /// Called after the Stripe charge captures successfully. Receives the
    /// Payment doc ID so the caller can refund it if a downstream step
    /// (like accepting the application) fails — without the ID, a failed
    /// post-payment step would leave the hirer's card charged with no
    /// recovery path.
    let onPaymentComplete: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var paymentManager = PaymentManager.shared

    @State private var isProcessing = false
    @State private var paymentSuccessful = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var amount: Double {
        Double(opportunity.payAmount ?? "0") ?? 0
    }

    private var breakdown: PaymentBreakdown {
        StripeConfig.getPaymentBreakdown(amount: amount)
    }

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 14) {
                    // MARK: Hero header (compact)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.07))
                                .frame(width: 76, height: 76)
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                                .frame(width: 60, height: 60)
                            Image(systemName: paymentSuccessful ? "checkmark.seal.fill" : "lock.shield.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        Text(paymentSuccessful ? "Payment Sent!" : "Confirm Payment")
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)

                        Text(paymentSuccessful
                             ? "Funds are held until the job is complete."
                             : "Review the breakdown before secure checkout.")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 4)

                    // MARK: Combined details + breakdown card
                    infoCard {
                        VStack(spacing: 10) {
                            detailRow(label: "Job", value: opportunity.title)
                            detailRow(label: "Worker", value: application.applicantName)

                            Divider().padding(.vertical, 2)

                            breakdownRow(
                                icon: "tag.fill",
                                iconColor: CommunallyTheme.primaryGreen,
                                label: "Job amount",
                                value: breakdown.formattedJobAmount,
                                valueColor: CommunallyTheme.darkGray,
                                bold: true
                            )
                            breakdownRow(
                                icon: "percent",
                                iconColor: Color(red: 0.55, green: 0.27, blue: 0.96),
                                label: "Platform fee (5%)",
                                value: "+ \(breakdown.formattedPlatformFee)",
                                valueColor: CommunallyTheme.darkGray.opacity(0.7)
                            )
                            breakdownRow(
                                icon: "creditcard",
                                iconColor: Color(red: 0.95, green: 0.55, blue: 0.1),
                                label: "Processing fee",
                                value: "+ \(breakdown.formattedStripeFee)",
                                valueColor: CommunallyTheme.darkGray.opacity(0.7)
                            )
                            Divider()
                            breakdownRow(
                                icon: "dollarsign.circle.fill",
                                iconColor: CommunallyTheme.darkGray,
                                label: "You pay",
                                value: breakdown.formattedTotalCharged,
                                valueColor: CommunallyTheme.darkGray,
                                bold: true,
                                largeValue: true
                            )
                        }
                    }

                    // MARK: Escrow pill (compact)
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Held in escrow until you mark the job complete")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.10))
                    )

                    Spacer(minLength: 0)

                    // MARK: CTA
                    VStack(spacing: 8) {
                        Button(action: processPayment) {
                            HStack(spacing: 10) {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                } else if paymentSuccessful {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                } else {
                                    Image(systemName: "lock.circle.fill")
                                        .font(.system(size: 18))
                                }
                                Text(isProcessing ? "Opening Stripe…" : paymentSuccessful ? "Payment Complete" : "Continue to Secure Payment")
                                    .font(.system(size: 17, weight: .bold, design: .default))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: CommunallyTheme.buttonHeight)
                            .background(
                                paymentSuccessful
                                    ? AnyView(CommunallyTheme.buttonGradient)
                                    : isProcessing
                                        ? AnyView(CommunallyTheme.primaryGreen.opacity(0.7))
                                        : AnyView(CommunallyTheme.buttonGradient)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing || paymentSuccessful)
                        .padding(.horizontal, 20)

                        Text("Secure checkout powered by Stripe")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.35))

                        if !paymentSuccessful {
                            Button("Cancel") { dismiss() }
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                        }
                    }
                    .padding(.bottom, 12)
                }
                .padding(.top, 4)
            }
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Payment Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Sub-views

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(CommunallyTheme.darkGray)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func breakdownRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        valueColor: Color,
        bold: Bool = false,
        largeValue: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(iconColor.opacity(0.1)))

            Text(label)
                .font(.system(size: bold ? 14 : 13, weight: bold ? .semibold : .regular, design: .default))
                .foregroundColor(bold ? CommunallyTheme.darkGray : CommunallyTheme.darkGray.opacity(0.65))

            Spacer()

            Text(value)
                .font(.system(size: largeValue ? 18 : 13, weight: bold ? .bold : .semibold, design: .default))
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Logic

    private func processPayment() {
        let amount = Double(opportunity.payAmount ?? "0") ?? 0

        guard let presentingViewController = topViewController() else {
            errorMessage = "Unable to present payment sheet"
            showError = true
            return
        }

        isProcessing = true

        // STEP 1: Create the Payment doc FIRST so the stripeWebhook can
        // find it (by applicationId metadata) the instant Stripe captures
        // the charge. Doing this AFTER the Stripe Sheet (old flow) raced
        // the webhook and silently lost the status-→-held update, which
        // is why so many payments were stuck at .pending forever.
        paymentManager.createPayment(for: application, opportunity: opportunity) { creationResult in
            DispatchQueue.main.async {
                switch creationResult {
                case .failure(let error):
                    isProcessing = false
                    errorMessage = "Couldn't create payment record: \(error.localizedDescription)"
                    showError = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)

                case .success(let payment):
                    // STEP 2: Present the Stripe Sheet now that the doc
                    // exists. We pass applicationId so the backend embeds
                    // it in PaymentIntent metadata — the webhook then
                    // uses that to find this doc and flip it to .held.
                    StripeService.shared.presentPaymentSheet(
                        from: presentingViewController,
                        amount: amount,
                        opportunityTitle: opportunity.title,
                        hirerId: opportunity.hirerId,
                        workerId: application.applicantId,
                        applicationId: application.id
                    ) { result in
                        DispatchQueue.main.async {
                            isProcessing = false

                            switch result {
                            case .success(let paymentIntentId):
                                // STEP 3: Charge succeeded. The webhook
                                // will flip status to .held server-side —
                                // we just set stripePaymentIntentId as a
                                // backup lookup key and link the
                                // application doc to this payment.
                                Firestore.firestore().collection("payments").document(payment.safeId).updateData([
                                    "stripePaymentIntentId": paymentIntentId
                                ])
                                Firestore.firestore().collection("applications").document(application.id).updateData([
                                    "paymentId": payment.safeId,
                                    "isPaid": true,
                                    "paidAt": Timestamp(date: Date())
                                ])
                                paymentSuccessful = true
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    dismiss()
                                    onPaymentComplete(payment.safeId)
                                }

                            case .failure(let error):
                                // Stripe didn't charge — clean up the doc
                                // we just created so it doesn't sit at
                                // .pending forever cluttering the seeker's
                                // Earnings UI as a fake pending payout.
                                let isCancel: Bool = {
                                    if let s = error as? StripeError,
                                       case .paymentCanceled = s { return true }
                                    return false
                                }()
                                let newStatus: PaymentStatus = isCancel ? .cancelled : .failed
                                Firestore.firestore().collection("payments").document(payment.safeId).updateData([
                                    "status": newStatus.rawValue,
                                    "failureReason": isCancel ? "Cancelled by hirer" : error.localizedDescription
                                ])
                                if !isCancel {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func topViewController(base: UIViewController? = {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }()) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}

// MARK: - Payment Row (legacy — kept for any external callsites)
struct PaymentRow: View {
    let label: String
    let amount: String
    let color: Color
    var isSubItem: Bool = false
    var isBold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: isBold ? 16 : 14, weight: isBold ? .bold : .regular))
                .foregroundColor(isSubItem ? CommunallyTheme.darkGray.opacity(0.55) : color)
                .padding(.leading, isSubItem ? 16 : 0)
            Spacer()
            Text(amount)
                .font(.system(size: isBold ? 18 : 14, weight: isBold ? .bold : .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Payment History View
struct PaymentHistoryView: View {
    @ObservedObject private var paymentManager = PaymentManager.shared
    @EnvironmentObject var authManager: AuthenticationManager

    private var userPayments: [Payment] {
        guard let userId = authManager.currentUser?.id else { return [] }
        return paymentManager.getPayments(for: userId)
    }

    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()

            if userPayments.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(CommunallyTheme.primaryGreen.opacity(0.08))
                            .frame(width: 120, height: 120)
                        Image(systemName: "creditcard")
                            .font(.system(size: 46, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.6))
                    }
                    Text("No Payments Yet")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Your payment history will appear here\nafter your first completed job.")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(userPayments) { payment in
                            PaymentHistoryRow(payment: payment)
                                .environmentObject(authManager)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Payment History Row
struct PaymentHistoryRow: View {
    let payment: Payment
    @EnvironmentObject var authManager: AuthenticationManager

    private var isHirer: Bool {
        authManager.currentUser?.id == payment.hirerId
    }

    private var statusColor: Color {
        switch payment.status {
        case .held: return Color(red: 0.95, green: 0.6, blue: 0.1)
        case .released: return CommunallyTheme.primaryGreen
        default: return CommunallyTheme.midGray
        }
    }

    private var counterpartyText: String {
        if isHirer { return "Paid to \(payment.workerName)" }
        if payment.status == .held { return "Awaiting release from \(payment.hirerName)" }
        return "Received from \(payment.hirerName)"
    }

    private var amountText: String {
        isHirer ? payment.formattedTotalCharged : payment.formattedWorkerPayout
    }

    private var amountColor: Color {
        if isHirer { return Color(red: 0.88, green: 0.28, blue: 0.25) }
        return statusColor
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: isHirer ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(payment.opportunityTitle)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .lineLimit(1)
                Text(counterpartyText)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    .lineLimit(1)
                Text(payment.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.38))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(amountText)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(amountColor)

                Text(payment.statusDisplay)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor.opacity(0.12)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }
}
