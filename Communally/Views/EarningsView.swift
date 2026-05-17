//
//  EarningsView.swift
//  Communally
//
//  Seeker-facing earnings dashboard. Designed around the "DoorDash pattern":
//  the worker does jobs first, money piles up in their in-app balance, and
//  only when they want to cash out do we send them through Stripe Connect.
//
//  Three numbers matter:
//    • Cash Out balance   — `.payable` payments. Already earned, just waiting
//                            for the worker to connect a bank to actually
//                            move the money. THE incentive UI.
//    • In escrow          — `.held` payments. Job not complete by both
//                            parties yet. Will roll into Cash Out once both
//                            sides confirm.
//    • Lifetime earnings  — `.released` payments. Already in their bank.
//

import SwiftUI

struct EarningsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var paymentManager = PaymentManager.shared

    @State private var isClaiming = false
    @State private var showBankSetup = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var userId: String? { authManager.currentUser?.id }

    private var claimable: Double {
        guard let userId else { return 0 }
        return paymentManager.getClaimableEarnings(for: userId)
    }

    private var inEscrow: Double {
        guard let userId else { return 0 }
        return paymentManager.getPendingPayouts(for: userId)
    }

    private var lifetime: Double {
        guard let userId else { return 0 }
        return paymentManager.getTotalEarnings(for: userId)
    }

    private var claimableJobCount: Int {
        guard let userId else { return 0 }
        return paymentManager.getClaimableJobCount(for: userId)
    }

    private var workerPayments: [Payment] {
        guard let userId else { return [] }
        return paymentManager.payments
            .filter { $0.workerId == userId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var hasBank: Bool {
        authManager.currentUser?.hasBankAccount == true
            || authManager.currentUser?.stripeConnectActive == true
    }

    /// Drives the "ask a parent to fill this out" hint. US Stripe Connect
    /// can't onboard minors, so under-18 seekers without a bank set up
    /// see this note pointing them at the parent-as-account-holder path.
    private var isUnder18: Bool {
        (authManager.currentUser?.resolvedAge ?? 99) < 18
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 1.0, blue: 0.96),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        balanceHero
                        cashOutCTA
                        if isUnder18 && !hasBank {
                            parentCanFillThisOutNote
                        }
                        if !hasBank && claimable == 0 {
                            firstEarningTeaser
                        }
                        secondaryStats
                        recentActivitySection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Your Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color.gray.opacity(0.55))
                    }
                }
            }
            .sheet(isPresented: $showBankSetup, onDismiss: {
                // If the user just finished Stripe onboarding (we can tell
                // because `hasBankAccount` flipped true while the sheet was
                // up), immediately drain their balance — no extra tap.
                if hasBank && claimable > 0 {
                    runCashOut()
                }
            }) {
                BankSetupSheet()
                    .environmentObject(authManager)
            }
            .alert("Cashed Out!", isPresented: $showSuccessAlert) {
                Button("Done", role: .cancel) { dismiss() }
            } message: {
                Text(successMessage)
            }
            .alert("Cash Out Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Balance Hero

    /// Total in-flight (in escrow + ready to claim) — used for the hero
    /// subtitle, not the headline number.
    private var pendingTotal: Double { claimable + inEscrow }

    /// Headline number = lifetime earnings (money that has actually
    /// landed in the worker's bank). This is the "trophy" number — the
    /// one the worker is proud of and that doesn't yo-yo between
    /// payment states. In-flight totals live in the smaller stat tiles
    /// and the Cash Out button copy below.
    private var heroAmount: Double { lifetime }

    private var heroLabel: String { "Total earned" }

    private var balanceHero: some View {
        VStack(spacing: 10) {
            Text(heroLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .textCase(.uppercase)
                .tracking(0.5)

            Text(String(format: "$%.2f", heroAmount))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            // Subtitle adapts to whichever state the user is in — but
            // always frames the lifetime number, never replaces it.
            Group {
                if lifetime == 0 && pendingTotal == 0 {
                    Text("Earn from your first job to fill this up")
                } else if lifetime == 0 && pendingTotal > 0 {
                    Text(String(
                        format: "$%.2f on the way from your first job%@",
                        pendingTotal,
                        pendingTotal > 0 && claimableJobCount + Int(inEscrow > 0 ? 1 : 0) == 1 ? "" : "s"
                    ))
                } else if pendingTotal > 0 {
                    Text(String(
                        format: "Paid to your bank · $%.2f more on the way",
                        pendingTotal
                    ))
                } else {
                    Text("Paid to your bank from completed jobs")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.78, blue: 0.45),
                            CommunallyTheme.primaryGreen,
                            Color(red: 0.05, green: 0.55, blue: 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.40),
                        radius: 22, x: 0, y: 12)
        )
    }

    // MARK: - Cash Out CTA

    private var cashOutCTA: some View {
        VStack(spacing: 8) {
            Button(action: cashOutTapped) {
                HStack(spacing: 12) {
                    if isClaiming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: hasBank
                              ? "arrow.down.to.line.circle.fill"
                              : "building.columns.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text(cashOutTitle)
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(claimable > 0 || !hasBank
                              ? CommunallyTheme.buttonGradient
                              : LinearGradient(
                                  colors: [Color.gray.opacity(0.45),
                                           Color.gray.opacity(0.30)],
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing
                              ))
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35),
                                radius: 14, x: 0, y: 6)
                )
            }
            .buttonStyle(.plain)
            .disabled(isClaiming || (claimable == 0 && hasBank))
            .accessibilityLabel(cashOutTitle)

            // Permanent timing reassurance — shown whenever a bank is
            // connected so the user always knows the deposit isn't
            // instant before they tap (and isn't broken after they tap).
            if hasBank {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Funds land in your bank within 1–2 business days")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
            }
        }
    }

    private var cashOutTitle: String {
        if !hasBank && claimable == 0 {
            return "Set up payouts (2 min)"
        }
        if !hasBank {
            return "Set up payouts to cash out " + String(format: "$%.2f", claimable)
        }
        if claimable == 0 {
            // Distinguish "you've never earned anything" from "you have
            // earnings but they're still pending on the hirer/escrow side".
            // Without this, a user who just connected their bank sees
            // "Nothing to cash out yet" and assumes the bank setup didn't
            // work — when really the hirer just hasn't released the money.
            if inEscrow > 0 {
                return String(format: "$%.2f pending — lands here when released", inEscrow)
            }
            return "Nothing to cash out yet"
        }
        return "Cash out " + String(format: "$%.2f", claimable)
    }

    // MARK: - Parent-can-fill-this-out note

    /// Surfaces the parent-as-account-holder path right under the Cash Out
    /// button so under-18 seekers know they don't have to own a bank
    /// account themselves. Matches the orange notice inside BankSetupSheet
    /// — repeated here so teens don't have to tap through and read all
    /// the way down to find out it's an option.
    private var parentCanFillThisOutNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.85, green: 0.50, blue: 0.10))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Don't have a bank? A parent can do it.")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.20, blue: 0.20))

                Text("Stripe needs the account holder to be 18+. Ask a parent or guardian to tap Set up payouts and fill it out with their info — payouts go to their bank, you still track your earnings here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.40, green: 0.40, blue: 0.40))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.65, blue: 0.20).opacity(0.50), lineWidth: 1)
        )
    }

    // MARK: - First-earning teaser

    /// Shown when the user has no bank AND no earnings yet — sets the
    /// expectation that they can start jobs without setup friction.
    private var firstEarningTeaser: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(CommunallyTheme.primaryGreen)
                .padding(12)
                .background(
                    Circle().fill(CommunallyTheme.primaryGreen.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Start earning — no setup needed")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Text("Apply to jobs now. We'll hold your earnings here until you're ready to cash out.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Secondary Stats

    private var secondaryStats: some View {
        HStack(spacing: 12) {
            statTile(
                icon: "clock.arrow.circlepath",
                tint: Color.orange,
                label: "In escrow",
                amount: inEscrow,
                hint: "Waiting on hirer to release"
            )
            statTile(
                icon: "dollarsign.arrow.circlepath",
                tint: CommunallyTheme.primaryGreen,
                label: "Ready",
                amount: claimable,
                hint: claimable > 0 ? "Tap Cash Out above" : "Nothing to cash out yet"
            )
        }
    }

    private func statTile(icon: String, tint: Color, label: String,
                          amount: Double, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
            }
            Text(String(format: "$%.2f", amount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(hint)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.50))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent earnings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            if workerPayments.isEmpty {
                emptyActivityCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workerPayments.prefix(8).enumerated()),
                            id: \.element.safeId) { idx, payment in
                        EarningsRow(payment: payment)
                        if idx < min(workerPayments.count, 8) - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
            }
        }
    }

    private var emptyActivityCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "briefcase")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.35))
            Text("No earnings yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)
            Text("Browse jobs near you to get started")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Actions

    private func cashOutTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Path A: no bank yet → kick them into BankSetup. The sheet's
        // onDismiss handler picks up the cash-out flow once they finish.
        if !hasBank {
            showBankSetup = true
            return
        }
        // Path B: bank connected, real claim flow.
        runCashOut()
    }

    private func runCashOut() {
        guard !isClaiming else { return }
        guard claimable > 0 else { return }

        isClaiming = true
        paymentManager.claimEarnings { result in
            isClaiming = false
            switch result {
            case .success(let count, let cents):
                if count == 0 {
                    errorMessage = "We couldn't find any earnings to cash out. Try again in a moment."
                    showErrorAlert = true
                    return
                }
                let dollars = Double(cents) / 100.0
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                successMessage = String(
                    format: "We sent $%.2f to your bank. Most banks post the deposit within 1–2 business days.",
                    dollars
                )
                showSuccessAlert = true

            case .requiresBankSetup:
                // Edge case: hasBank thought we were good but Stripe says
                // payouts aren't enabled (mid-verification, account paused).
                // Bounce them back to BankSetup so the existing status card
                // tells them exactly what's missing.
                showBankSetup = true

            case .failure(let error):
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Earnings row

private struct EarningsRow: View {
    let payment: Payment

    private var iconName: String {
        switch payment.status {
        case .pending, .processing: return "hourglass"
        case .payable:  return "dollarsign.arrow.circlepath"
        case .released: return "checkmark.circle.fill"
        case .held:     return "clock.fill"
        case .refunded: return "arrow.uturn.backward.circle.fill"
        case .failed:   return "exclamationmark.triangle.fill"
        default:        return "circle"
        }
    }

    private var iconColor: Color {
        switch payment.status {
        case .pending, .processing: return .orange
        case .payable:  return CommunallyTheme.primaryGreen
        case .released: return CommunallyTheme.primaryGreen
        case .held:     return .orange
        case .refunded: return Color.purple
        case .failed:   return .red
        default:        return .gray
        }
    }

    private var subtitle: String {
        switch payment.status {
        case .pending:    return "Waiting on hirer payment"
        case .processing: return "Processing payment"
        case .payable:    return "In your balance"
        case .released:   return "Paid to bank"
        case .held:       return "Awaiting completion"
        case .refunded:   return "Refunded"
        case .failed:     return "Payment failed"
        default:          return payment.statusDisplay
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: payment.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(payment.opportunityTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(iconColor)
                    Text("·")
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.30))
                    Text(relativeDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                }
            }
            Spacer(minLength: 8)

            Text(payment.formattedWorkerPayout)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(payment.status == .refunded || payment.status == .failed
                                 ? CommunallyTheme.darkGray.opacity(0.45)
                                 : CommunallyTheme.darkGray)
                .strikethrough(payment.status == .refunded || payment.status == .failed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#Preview {
    EarningsView()
        .environmentObject(AuthenticationManager.shared)
}
