//
//  JobCompletionView.swift
//  Communally
//
//  Job completion workflow - mark jobs complete, trigger ratings & payments
//

import SwiftUI

struct JobCompletionSheet: View {
    let opportunity: Opportunity
    let application: JobApplication
    var skipPIN: Bool = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var ratingManager = RatingManager.shared
    @ObservedObject private var pinService = PINVerificationService.shared

    @State private var isProcessing = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var selectedStars: Int = 0
    @State private var reviewText: String = ""
    @State private var isSubmittingRating = false
    @State private var hasAutoFinalized = false
    @State private var showRatingPopup = false

    private var isHirer: Bool {
        authManager.currentUser?.id == opportunity.hirerId
    }

    private var pinVerified: Bool {
        pinService.isVerified(jobId: opportunity.safeId, type: .jobCompletion)
    }

    private var activePIN: JobPIN? {
        pinService.getActivePIN(jobId: opportunity.safeId, type: .jobCompletion)
            ?? pinService.getPIN(jobId: opportunity.safeId, type: .jobCompletion)
    }

    /// Latest copy from the manager so listener-driven Firestore updates flow into this view.
    private var liveApp: JobApplication {
        applicationManager.applications.first(where: { $0.id == application.id }) ?? application
    }

    private var hirerHasConfirmed: Bool { liveApp.hirerConfirmedCompletionAt != nil }
    private var workerHasConfirmed: Bool { liveApp.workerConfirmedCompletionAt != nil }
    private var iHaveConfirmed: Bool { isHirer ? hirerHasConfirmed : workerHasConfirmed }
    private var otherHasConfirmed: Bool { isHirer ? workerHasConfirmed : hirerHasConfirmed }
    private var bothConfirmed: Bool { hirerHasConfirmed && workerHasConfirmed }

    private var otherName: String {
        isHirer ? application.applicantName : opportunity.hirerName
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if skipPIN {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Completing job…")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if isHirer {
                        hirerContent
                    } else {
                        seekerContent
                    }
                }
                .padding(.bottom, 40)
            }
            .background(CommunallyTheme.backgroundGradient)
            .navigationTitle("Complete Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                    }
                }
            }
            .onAppear {
                guard !skipPIN else { return }
                pinService.observePIN(jobId: opportunity.safeId, type: .jobCompletion)
                pinService.fetchPIN(jobId: opportunity.safeId, type: .jobCompletion) { pin in
                    if isHirer && pin == nil {
                        _ = pinService.generatePIN(
                            jobId: opportunity.safeId,
                            type: .jobCompletion,
                            hirerId: opportunity.hirerId,
                            workerId: application.applicantId
                        )
                    }
                }
                // If I confirmed last session and the other side has now caught up,
                // finish the job the moment this sheet opens.
                if bothConfirmed && iHaveConfirmed && !hasAutoFinalized {
                    hasAutoFinalized = true
                    finalizeJob()
                }
            }
            .onChange(of: bothConfirmed) { confirmed in
                guard confirmed, iHaveConfirmed, !hasAutoFinalized else { return }
                hasAutoFinalized = true
                finalizeJob()
            }
            .task {
                guard skipPIN else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
                directComplete()
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showRatingPopup) {
            ratingPopup
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Rating popup (mini sheet shown after the user taps Confirm)

    private var ratingPopup: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(isHirer
                     ? "How was working with \(application.applicantName)?"
                     : "How was working with \(opportunity.hirerName)?")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Text("A quick rating helps your neighborhood know who's reliable.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedStars = star
                    } label: {
                        Image(systemName: selectedStars >= star ? "star.fill" : "star")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(selectedStars >= star
                                ? Color(red: 1.00, green: 0.78, blue: 0.30)
                                : Color.gray.opacity(0.30))
                            .shadow(color: selectedStars >= star
                                    ? Color(red: 1.00, green: 0.78, blue: 0.30).opacity(0.45)
                                    : .clear,
                                    radius: 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $reviewText)
                    .foregroundColor(.black)
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(8)
                    .onChange(of: reviewText) { newValue in
                        if newValue.count > 500 { reviewText = String(newValue.prefix(500)) }
                    }
                if reviewText.isEmpty {
                    Text("Optional — say a few words")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.50, green: 0.50, blue: 0.50))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
            )
            .padding(.horizontal, 20)

            Button {
                showRatingPopup = false
                // After dismissal animation, kick the same confirm flow —
                // selectedStars > 0 means it goes straight to submitRating.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    confirmCompletion()
                }
            } label: {
                Text(selectedStars > 0 ? "Submit & confirm" : "Skip & confirm")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(CommunallyTheme.buttonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white)
    }

    // MARK: - Hirer Content

    private var hirerContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did \(application.applicantName) finish?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text(opportunity.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            if !opportunity.isVolunteer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Payment Release")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)

                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(CommunallyTheme.primaryGreen)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount to release")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            Text(opportunity.displayPay)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    )

                    Text("Payment will be released to \(application.applicantName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CommunallyTheme.accentGreen)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
            }

            hirerPinSection

            if iHaveConfirmed {
                waitingPanel
            } else {
                completionSteps(for: .hirer)
                confirmButton
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom)
            }
        }
    }

    private var canConfirm: Bool {
        // The hirer generated the PIN and is the one *attesting* completion;
        // they don't need their own client to also receive the seeker's PIN
        // verification snapshot. (We've seen real cases where the hirer's
        // listener never catches the verified state and the job gets stuck.)
        // Seekers still need pinVerified — that's the actual "I showed up"
        // proof since they had to know the code from the hirer.
        let pinOk = isHirer ? true : pinVerified
        // Rating is collected in a popup AFTER tapping Confirm now (keeps
        // the PIN sheet compact and removes the long scroll). So we no
        // longer block the Confirm button on `selectedStars > 0`.
        return !iHaveConfirmed
            && pinOk
            && !isProcessing
            && !isSubmittingRating
    }

    // MARK: - Inline Hirer PIN

    private var hirerPinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion PIN")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)

            if pinVerified {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    Text("PIN verified by \(application.applicantName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.10))
                )
            } else if let pin = activePIN, !pin.isExpired, pin.status != .failed {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ForEach(Array(pin.pin.enumerated()), id: \.offset) { _, digit in
                            Text(String(digit))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                                .frame(width: 56, height: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(CommunallyTheme.primaryGreen.opacity(0.35), lineWidth: 2)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text("Share this PIN with \(application.applicantName) to verify completion.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("If \(application.applicantName) has already entered the PIN, you can still tap Confirm Completion below — verification status sometimes lags.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)

                    Button(action: regenerateHirerPIN) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Generate new PIN")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
            } else {
                Button(action: regenerateHirerPIN) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text(activePIN == nil ? "Generate PIN" : "Generate new PIN")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CommunallyTheme.primaryGreen)
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private func regenerateHirerPIN() {
        _ = pinService.generatePIN(
            jobId: opportunity.safeId,
            type: .jobCompletion,
            hirerId: opportunity.hirerId,
            workerId: application.applicantId
        )
    }

    // MARK: - Seeker Content

    private var seekerContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enter the hirer's PIN to confirm")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text(opportunity.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            if !opportunity.isVolunteer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Payment")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)

                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(CommunallyTheme.primaryGreen)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount you'll receive")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            Text(opportunity.displayPay)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    )

                    Text("Once both sides confirm, this lands in your Communally balance. Cash out to your bank anytime.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
            }

            VStack(spacing: 16) {
                Text("Enter Hirer's PIN")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                PINVerificationCard(
                    jobId: opportunity.safeId,
                    type: .jobCompletion,
                    isHirer: false,
                    hirerId: opportunity.hirerId,
                    workerId: application.applicantId
                )
            }

            if iHaveConfirmed {
                waitingPanel
            } else {
                completionSteps(for: .seeker)
                confirmButton
                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Inline Rating Section

    private var ratingSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(isHirer
                     ? "Rate \(application.applicantName)"
                     : "Rate \(opportunity.hirerName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("How was working together?")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedStars = star
                        }) {
                            Image(systemName: star <= selectedStars ? "star.fill" : "star")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(star <= selectedStars ? .yellow : Color.gray.opacity(0.25))
                        }
                        .scaleEffect(star == selectedStars ? 1.12 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedStars)
                    }
                }

                if selectedStars > 0 {
                    Text(ratingDescription)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ratingColor)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Leave a review (optional)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $reviewText)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .scrollContentBackground(.hidden)   // hide TextEditor's dark-mode bg
                        .frame(height: 80)
                        .padding(8)
                        .onChange(of: reviewText) { text in
                            if text.count > 500 { reviewText = String(text.prefix(500)) }
                        }
                    if reviewText.isEmpty {
                        Text("What did you think?")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(CommunallyTheme.primaryGreen.opacity(0.25), lineWidth: 1)
                        )
                )

                Text("\(reviewText.count)/500")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Confirm button + waiting panel (shared by both roles)

    private var confirmButton: some View {
        Button(action: confirmCompletion) {
            Group {
                if isProcessing || isSubmittingRating {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Confirm Completion")
                    }
                    .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: CommunallyTheme.buttonHeight)
            .background(CommunallyTheme.buttonGradient)
            .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 10, x: 0, y: 5)
            .opacity(canConfirm ? 1.0 : 0.5)
        }
        .disabled(!canConfirm)
        .padding(.horizontal)
    }

    private var waitingPanel: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                Text("You're done — waiting on \(otherName)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)
                Text("Both sides have to confirm before the payment is released. We'll notify you the moment they do.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 20)

            Button { dismiss() } label: {
                Text("Close")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: CommunallyTheme.buttonHeight)
                    .background(CommunallyTheme.buttonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Shared components

    private enum Role { case hirer, seeker }

    private func completionSteps(for role: Role) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happens next?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray)

            VStack(alignment: .leading, spacing: 8) {
                if role == .hirer {
                    CompletionStep(icon: "dollarsign.circle.fill", text: "Payment added to \(application.applicantName)'s Communally balance", color: .green)
                    CompletionStep(icon: "bell.fill",              text: "Worker notified of completion", color: .blue)
                    CompletionStep(icon: "checkmark.seal.fill",    text: "Job marked as completed", color: CommunallyTheme.primaryGreen)
                } else {
                    CompletionStep(icon: "checkmark.shield.fill",  text: "Your PIN confirms you completed the work", color: CommunallyTheme.primaryGreen)
                    CompletionStep(icon: "dollarsign.circle.fill", text: "Earnings land in your Communally balance", color: .green)
                    CompletionStep(icon: "arrow.down.to.line.circle.fill", text: "Cash out to your bank whenever you're ready", color: .blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
    }

    // MARK: - Rating helpers

    private var ratingDescription: String {
        switch selectedStars {
        case 5: return "Excellent!"
        case 4: return "Very Good"
        case 3: return "Good"
        case 2: return "Fair"
        case 1: return "Poor"
        default: return ""
        }
    }

    private var ratingColor: Color {
        switch selectedStars {
        case 5: return .green
        case 4: return Color(red: 0.6, green: 0.8, blue: 0.3)
        case 3: return .yellow
        case 2: return .orange
        case 1: return .red
        default: return .gray
        }
    }

    private func submitRating(then onSuccess: @escaping () -> Void) {
        guard let user = authManager.currentUser, selectedStars > 0 else {
            onSuccess()
            return
        }
        isSubmittingRating = true

        let trimmed = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReview = trimmed.isEmpty ? nil : String(trimmed.prefix(500))

        let ratedUserId   = isHirer ? application.applicantId   : opportunity.hirerId
        let ratedUserName = isHirer ? application.applicantName : opportunity.hirerName

        ratingManager.submitRating(
            opportunityId: opportunity.safeId,
            applicationId: application.id,
            raterId: user.id,
            raterName: user.fullName,
            ratedUserId: ratedUserId,
            ratedUserName: ratedUserName,
            score: Double(selectedStars),
            review: finalReview,
            jobTitle: opportunity.title
        ) { success in
            isSubmittingRating = false
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess()
            } else {
                errorMessage = "Couldn't save your rating. Please try again."
                showErrorAlert = true
            }
        }
    }

    // MARK: - Dual confirmation

    private func confirmCompletion() {
        // Re-entry safety: don't double-write a timestamp or re-submit the rating.
        if iHaveConfirmed {
            if otherHasConfirmed && !hasAutoFinalized {
                hasAutoFinalized = true
                finalizeJob()
            }
            return
        }

        // If they haven't picked a rating yet, surface the rating popup.
        // The popup's submit button calls back into this same function and
        // takes the rating-already-set path the next time around.
        if selectedStars == 0 {
            showRatingPopup = true
            return
        }

        submitRating {
            recordMyConfirmation()
        }
    }

    private func recordMyConfirmation() {
        let onResult: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard ok else {
                    errorMessage = "Couldn't save your confirmation. Try again."
                    showErrorAlert = true
                    return
                }
                if otherHasConfirmed && !hasAutoFinalized {
                    hasAutoFinalized = true
                    finalizeJob()
                }
                // else: button area flips to waitingPanel via re-render
            }
        }

        if isHirer {
            applicationManager.markHirerConfirmedCompletion(applicationId: application.id, completion: onResult)
        } else {
            applicationManager.markWorkerConfirmedCompletion(applicationId: application.id, completion: onResult)
        }
    }

    // MARK: - Direct completion (bypasses PIN — used for stale jobs)

    private func directComplete() {
        SafetyMonitoringService.shared.stopMonitoring(reason: "Job completed successfully")
        applicationManager.completeJob(opportunityId: opportunity.safeId, applicationId: application.id)
        let payment = PaymentManager.shared.getPayment(for: application.id)
        if let payment, payment.status == .held {
            PaymentManager.shared.releasePayment(paymentId: payment.safeId) { _ in
                DispatchQueue.main.async {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }

    // MARK: - Finalize (called only when both sides have confirmed)

    private func finalizeJob() {
        isProcessing = true
        SafetyMonitoringService.shared.stopMonitoring(reason: "Job completed successfully")

        let payment = PaymentManager.shared.getPayment(for: application.id)

        if let payment, payment.status == .held {
            PaymentManager.shared.releasePayment(paymentId: payment.safeId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        applicationManager.completeJob(opportunityId: opportunity.safeId, applicationId: application.id)
                        isProcessing = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    case .failure(let error):
                        isProcessing = false
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        } else {
            isProcessing = false
            applicationManager.completeJob(opportunityId: opportunity.safeId, applicationId: application.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

// MARK: - Completion Step Component

struct CompletionStep: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 30)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(CommunallyTheme.darkGray)
            Spacer()
        }
    }
}

// MARK: - Quick Complete Button (for lists)

struct MarkCompleteButton: View {
    let opportunity: Opportunity
    let application: JobApplication
    @State private var showCompletionSheet = false

    var body: some View {
        Button { showCompletionSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                Text("Mark Complete").font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CommunallyTheme.primaryGreen)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showCompletionSheet) {
            JobCompletionSheet(opportunity: opportunity, application: application)
        }
    }
}
