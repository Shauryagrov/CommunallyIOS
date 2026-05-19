//
//  OpportunityDetailView.swift
//  Communally
//
//  Detail view for opportunities with apply/manage options
//

import SwiftUI
import MapKit
import FirebaseFirestore

struct OpportunityDetailView: View {
    let opportunity: Opportunity
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var ratingManager = RatingManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    
    @State private var showingApplicants = false
    @State private var showingCompletionConfirm = false
    @State private var selectedApplicant: JobApplication?
    @State private var showingAcceptConfirm = false
    @State private var showingRatingView = false
    @State private var acceptedJobSeeker: JobApplication?
    @State private var showingPaymentSheet = false
    @State private var selectedApplicationForPayment: JobApplication?
    @State private var isProcessingPayment = false
    @State private var paymentError: String?
    @State private var showPaymentError = false
    @State private var showBankSetupForApply = false
    @State private var showingRateHirerSheet = false
    @State private var showOpportunityShareSheet = false
    @State private var showActiveJobAlert = false
    @State private var showRescheduleSheet = false
    @State private var showDeleteJobConfirm = false
    /// Hirer's identity-verification state, fetched live on appear. nil while
    /// loading; falls back to "not verified" UI when nil after the fetch.
    @State private var hirerIsVerified: Bool? = nil

    private var isHirer: Bool {
        authManager.currentUser?.id == opportunity.hirerId
    }
    
    private var hasApplied: Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        return applicationManager.hasApplied(opportunityId: opportunity.safeId, applicantId: userId)
    }
    
    private var currentUserApplication: JobApplication? {
        guard let userId = authManager.currentUser?.id else { return nil }
        return applicationManager.applications.first {
            $0.opportunityId == opportunity.safeId && $0.applicantId == userId
        }
    }
    
    private var isAcceptedApplicant: Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        return opportunity.acceptedApplicantId == userId
    }
    
    private var canSeeExactLocation: Bool {
        // Hirer can always see exact location
        // Accepted applicant can see exact location
        // Others cannot
        return isHirer || isAcceptedApplicant
    }
    
    private var pendingApplications: [JobApplication] {
        applicationManager.getPendingApplications(forOpportunity: opportunity.safeId)
    }
    
    /// Live count from synced applications (stays accurate if applicants delete accounts).
    private var liveApplicationCountForOpportunity: Int {
        applicationManager.getApplications(forOpportunity: opportunity.safeId).count
    }
    
    private var applicationsSectionSubtitle: String {
        let total = liveApplicationCountForOpportunity
        let pending = pendingApplications.count
        guard total > 0 else { return "No applicants yet" }
        if pending == total {
            return "\(total) \(total == 1 ? "applicant" : "applicants")"
        }
        return "\(pending) to review · \(total) total"
    }
    
    /// Whether the seeker has finished Stripe Connect onboarding. Kept for
    /// callers that want to *prompt* (not gate) on bank setup.
    private var seekerPayoutReady: Bool {
        authManager.currentUser?.canReceivePayments ?? false
    }

    /// Bank setup is no longer required to apply — seekers can work jobs
    /// first and cash out from their in-app balance whenever they're ready.
    /// Hard-coded false so the "Set Up Payouts" gate section and the
    /// hidden Apply button never trigger off it.
    private var needsBankSetupToApply: Bool { false }

    /// Worker rates hirer once per completed job (same `ratings` doc rules as hirer→worker).
    private var canSeekerRateHirer: Bool {
        guard !isHirer, opportunity.status == .completed else { return false }
        guard let app = currentUserApplication, app.status == .completed else { return false }
        guard let uid = authManager.currentUser?.id else { return false }
        return !ratingManager.hasRated(opportunityId: opportunity.safeId, raterId: uid)
    }
    
    /// Tiny circular avatar (22pt) the seeker sees in the "Posted by"
    /// line. Falls back to a green person icon when the hirer has no
    /// profile image. Kept in sync visually with the chevron + green
    /// text in the NavigationLink so the whole row reads as one tappable
    /// affordance.
    @ViewBuilder
    private var hirerInlineAvatar: some View {
        if let data = opportunity.hirerImageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(CommunallyTheme.primaryGreen.opacity(0.30), lineWidth: 1)
                )
        } else {
            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.20))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                )
        }
    }

    @ViewBuilder
    private var hirerSelfAvatar: some View {
        let imageData = authManager.currentUser?.profileImageData ?? opportunity.hirerImageData
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
        } else {
            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                )
        }
    }
    
    /// True when the hirer's open job is past its scheduled start with no
    /// one accepted yet (or accepted but never started). Drives the
    /// `pastStartTimeBanner` so the hirer doesn't leave a stale post live.
    private var isPastStartTime: Bool {
        guard isHirer,
              opportunity.status == .open,
              let start = opportunity.scheduledStartDateTime
        else { return false }
        return start < Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSummaryCard

                if isPastStartTime {
                    pastStartTimeBanner
                }

                if opportunity.status == .open {
                    if isHirer {
                        hirerActionButtons
                        applicationsSection
                    } else {
                        if needsBankSetupToApply && !hasApplied {
                            seekerPayoutSetupSection
                        }
                        seekerActionSection
                        seekerApplicationsInsightSection
                    }
                } else if isHirer {
                    hirerActionButtons
                } else {
                    seekerActionSection
                }

                locationSection
                descriptionSection

                Spacer(minLength: 32)
            }
            .padding(20)
        }
        .background(
            CommunallyTheme.backgroundGradient
                .ignoresSafeArea()
        )
        .navigationTitle("Opportunity Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showOpportunityShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showOpportunityShareSheet) {
            let payText: String = {
                if opportunity.isVolunteer { return "a volunteer gig 🙌" }
                guard let amount = opportunity.payAmount, !amount.isEmpty else { return "a gig" }
                let suffix = opportunity.payIsHourly == true ? "/hr" : ""
                return "a $\(amount)\(suffix) gig"
            }()
            let opener: String = {
                if isHirer {
                    return "hey, just posted \(payText) on Communally 👋"
                } else if authManager.currentUser?.userType == .jobSeeker {
                    return "saw \(payText) on Communally 👀"
                } else {
                    return "spotted \(payText) on Communally 👋"
                }
            }()
            let body = """
\(opener)
📍 \(opportunity.locationName)

grab it here 👉 https://apps.apple.com/app/communally
"""
            ShareSheet(activityItems: [body])
        }
        .sheet(isPresented: $showingApplicants) {
            ApplicantsListView(opportunity: opportunity)
        }
        .sheet(isPresented: $showingPaymentSheet) {
            if let application = selectedApplicationForPayment {
                PaymentConfirmationSheet(
                    opportunity: opportunity,
                    application: application,
                    onPaymentComplete: { paymentId in
                        applicationManager.acceptApplication(applicationId: application.id) { success, message in
                            if success {
                                acceptedJobSeeker = application
                                _ = PINVerificationService.shared.generatePIN(
                                    jobId: opportunity.safeId,
                                    type: .jobStart,
                                    hirerId: opportunity.hirerId,
                                    workerId: application.applicantId
                                )
                                Log.debug("✅ Accepted applicant with payment hold: \(application.applicantName)")
                                // Auto-close the opportunity detail sheet so
                                // the hirer lands back on their jobs list /
                                // dashboard instead of staring at a stale
                                // applicants list with the just-accepted
                                // worker still showing up as "pending". The
                                // brief delay lets the PaymentConfirmationSheet
                                // finish its own dismiss animation first so
                                // the transition looks clean instead of two
                                // sheets racing to disappear at once.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                    showingPaymentSheet = false
                                    selectedApplicationForPayment = nil
                                    dismiss()
                                }
                            } else {
                                // CRITICAL: the hirer's card is already
                                // charged at this point (Stripe captured
                                // the moment the Sheet succeeded). If we
                                // bail out here with just an alert, the
                                // money sits in Communally's platform
                                // balance with no path to release —
                                // hirer paid for nothing. Auto-refund the
                                // captured charge so the worst case is a
                                // failed booking, not lost money.
                                PaymentManager.shared.refundPayment(
                                    paymentId: paymentId,
                                    reason: "Booking failed after payment captured: \(message ?? "unknown")"
                                ) { refunded in
                                    paymentError = refunded
                                        ? "We couldn't book \(application.applicantName) for this job. Your card has been refunded automatically — try accepting again or pick a different applicant."
                                        : "We couldn't book the worker AND the auto-refund failed. Please contact support@communallyapp.com with this job's title so we can refund you manually."
                                    showPaymentError = true
                                }
                            }
                        }
                    }
                )
                .environmentObject(authManager)
            }
        }
        .alert("Already On a Job", isPresented: $showActiveJobAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can only work one job at a time. Complete your current job before applying to another.")
        }
        .alert("Complete Job?", isPresented: $showingCompletionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Mark as Complete") {
                // This alert is only shown for volunteer jobs now
                completeJob()
            }
        } message: {
            Text("Mark this job as completed? You'll be asked to rate the worker.")
        }
        .sheet(isPresented: $showingRatingView) {
            if let jobSeeker = acceptedJobSeeker {
                RateUserView(opportunity: opportunity, jobSeeker: jobSeeker)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showingRateHirerSheet) {
            if let app = currentUserApplication {
                RateHirerView(opportunity: opportunity, application: app)
                    .environmentObject(authManager)
            }
        }
        .alert("Payment Error", isPresented: $showPaymentError) {
            Button("OK") { }
        } message: {
            Text(paymentError ?? "An unknown error occurred")
        }
        .onAppear {
            loadAcceptedJobSeeker()
            loadHirerVerificationStatus()
        }
        .sheet(isPresented: $showBankSetupForApply) {
            BankSetupSheet()
                .environmentObject(authManager)
        }
    }
    
    // MARK: - Header Summary Card
    /// Compact at-a-glance card. Replaced the old three-card stack
    /// (title, when, compensation) with one tighter card so the apply button
    /// can sit closer to the fold. Just the essentials: who/what, money, time.
    private var headerSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row — emoji + job title + tiny posted-by line
            HStack(spacing: 12) {
                Text(JobTypeHelper.emoji(for: opportunity.jobType))
                    .font(.system(size: 38))

                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.title)
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .lineLimit(2)

                    // "Posted by" line. Hirer sees a flat label; seekers get
                    // a tappable row with the hirer's avatar + chevron so
                    // they can dig into the hirer's profile (ratings, past
                    // jobs, verification) before applying. Time-ago suffix
                    // removed — for scheduled jobs the actual start time
                    // below is the only "when" that matters, and the time
                    // ago made the row visually noisier without adding
                    // useful info.
                    if isHirer {
                        Text("Posted by you")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            .lineLimit(1)
                    } else {
                        NavigationLink {
                            UserProfileView(userId: opportunity.hirerId)
                                .environmentObject(authManager)
                        } label: {
                            HStack(spacing: 6) {
                                hirerInlineAvatar
                                Text("Posted by \(opportunity.hirerName)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .lineLimit(1)
                                hirerVerificationBadge
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // "You worked for them before" surfaces when the seeker
                    // and hirer have a completed gig together.
                    if !isHirer {
                        WorkedTogetherBadge(
                            currentUserId: authManager.currentUser?.id,
                            otherUserId: opportunity.hirerId
                        )
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.5)

            // Money on the left, date + time on the right.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.displayPay)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.primaryGreen)

                    if let hourly = opportunity.derivedHourlyPay {
                        Text("≈ $\(hourly)/hr")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.75))
                    }
                }

                Spacer(minLength: 8)

                if opportunity.scheduledDate != nil || opportunity.scheduledTime != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let date = opportunity.scheduledDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                        }
                        if let start = opportunity.scheduledTime, !start.isEmpty {
                            let timeText: String = {
                                if let end = opportunity.scheduledEndTime, !end.isEmpty {
                                    return "\(start) – \(end)"
                                }
                                return start
                            }()
                            Text(timeText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.75))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.12), radius: 14, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Old Status Badge (not used)
    private var statusBadge: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let imageData = opportunity.hirerImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.4, blue: 1.0),
                                        Color(red: 0.7, green: 0.5, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2),
                                    Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Posted by")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                
                Text(opportunity.hirerName)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                
                Text("Description")
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Text(opportunity.description)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CommunallyTheme.cardGradient)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.08), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: canSeeExactLocation ? "mappin.circle.fill" : "lock.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))

                    if canSeeExactLocation {
                        Text(opportunity.locationName)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    } else {
                        Text(generalLocationName)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    }

                    if let dist = distanceEstimate {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            Text(dist)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                    }
                }

                Spacer()
            }

            // Only show the privacy notice to users who haven't applied yet
            if !canSeeExactLocation && !hasApplied && !isHirer {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    Text("Exact address disclosed after acceptance")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CommunallyTheme.primaryGreen.opacity(0.08))
                )
            }

            // Map preview
            locationMapView
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Location Map View
    private var locationMapView: some View {
        Map(position: .constant(.region(MKCoordinateRegion(
            center: canSeeExactLocation ? 
                CLLocationCoordinate2D(latitude: opportunity.location.latitude, longitude: opportunity.location.longitude) :
                approximateLocation,
            span: canSeeExactLocation ? 
                MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) :
                MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))) {
            if canSeeExactLocation {
                // Show exact pin for authorized users
                Marker(opportunity.locationName, coordinate: CLLocationCoordinate2D(
                    latitude: opportunity.location.latitude,
                    longitude: opportunity.location.longitude
                ))
                .tint(CommunallyTheme.primaryGreen)
            } else {
                Marker(generalLocationName, coordinate: approximateLocation)
                    .tint(CommunallyTheme.primaryGreen.opacity(0.85))
            }
        }
        .frame(height: 200)
        .cornerRadius(12)
        .disabled(true) // Make map non-interactive
    }
    
    // MARK: - Distance Estimate
    private var distanceEstimate: String? {
        guard let userLoc = locationManager.location else { return nil }
        let jobCoord = canSeeExactLocation
            ? CLLocationCoordinate2D(latitude: opportunity.location.latitude, longitude: opportunity.location.longitude)
            : approximateLocation
        let miles = userLoc.coordinate.distanceMiles(to: jobCoord)
        if miles < 0.1 { return "Under 0.1 mi away" }
        if miles < 10  { return String(format: "~%.1f mi away", miles) }
        return String(format: "~%.0f mi away", miles)
    }

    // MARK: - Computed Properties for Location Privacy
    private var generalLocationName: String {
        // Extract city/area from full location name
        // e.g., "123 Main St, San Francisco, CA" -> "San Francisco, CA"
        let components = opportunity.locationName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count >= 2 {
            // Return last 2 components (usually City, State)
            return components.suffix(2).joined(separator: ", ")
        }
        return opportunity.locationName
    }
    
    private var approximateLocation: CLLocationCoordinate2D {
        // Stable jitter from job id so the pin doesn’t jump on every redraw (~up to ~0.01°)
        var h: UInt64 = 5381
        for b in opportunity.safeId.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(b)
        }
        let latJitter = (Double(h % 2000) / 200_000.0) - 0.005
        let lonJitter = (Double((h / 2000) % 2000) / 200_000.0) - 0.005
        return CLLocationCoordinate2D(
            latitude: opportunity.location.latitude + latJitter,
            longitude: opportunity.location.longitude + lonJitter
        )
    }
    
    /// Shown first for paid jobs when the seeker still needs Stripe Connect — before Applications / location.
    private var seekerPayoutSetupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                Text("Connect your bank so you can get paid on this job. You can apply after payouts are set up.")
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: {
                showBankSetupForApply = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Set Up Payouts")
                        .font(.system(size: 17, weight: .bold, design: .default))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen,
                            CommunallyTheme.secondaryGreen
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    /// Same card pattern as the hirer applications block, read-only for seekers.
    private var seekerApplicationsInsightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Applications")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    if liveApplicationCountForOpportunity == 0 {
                        Text("No one has applied yet — you could be first.")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                    } else {
                        Text("\(liveApplicationCountForOpportunity) \(liveApplicationCountForOpportunity == 1 ? "person has" : "people have") applied")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                        Text("The hirer reviews applicants before choosing someone.")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Applications Section
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    Text(applicationsSectionSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                Spacer()
            }
            
            if liveApplicationCountForOpportunity == 0 {
                // Empty state with better design
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                    
                    Text("No applications yet")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    Text("Applications will appear here when job seekers apply")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                )
            } else if pendingApplications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.85))
                    Text("Nothing pending to review")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                    Text("Applications are up to date for this job.")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                )
            } else {
                // Show applicants inline
                VStack(spacing: 12) {
                    ForEach(pendingApplications) { application in
                        InlineApplicantCard(
                            application: application,
                            onAccept: {
                                selectedApplicant = application
                                showingAcceptConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .alert("Accept Applicant?", isPresented: $showingAcceptConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(opportunity.isVolunteer ? "Accept" : "Continue to Payment", role: .destructive) {
                if let applicant = selectedApplicant {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    acceptApplicant(applicant)
                }
            }
        } message: {
            if let applicant = selectedApplicant {
                if opportunity.isVolunteer {
                    Text("Accept \(applicant.applicantName) for this job?\n\nAll other applications will be automatically rejected and the opportunity will close to new applicants.")
                } else {
                    Text("Accept \(applicant.applicantName)?\n\nYou'll continue to payment hold (escrow). Payment is released when job is completed.")
                }
            }
        }
    }
    
    // MARK: - Seeker actions (same scroll layout as hirer)
    private var seekerActionSection: some View {
        VStack(spacing: 14) {
            if isAcceptedApplicant && opportunity.status == .inProgress {
                PINVerificationCard(
                    jobId: opportunity.safeId,
                    type: .jobStart,
                    isHirer: false,
                    jobCoordinate: CLLocationCoordinate2D(
                        latitude: opportunity.location.latitude,
                        longitude: opportunity.location.longitude
                    )
                )
            }
            
            if opportunity.status == .open && !hasApplied {
                if !needsBankSetupToApply {
                    Button(action: {
                        applyToJob()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Apply for This Job")
                                .font(.system(size: 17, weight: .bold, design: .default))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    CommunallyTheme.primaryGreen,
                                    CommunallyTheme.secondaryGreen
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 14, x: 0, y: 8)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    }
                    .pulsingButton()
                    .buttonStyle(.plain)
                }
            } else if let application = currentUserApplication {
                applicantStatusCardInline(for: application)

                if canSeekerRateHirer {
                    Button {
                        showingRateHirerSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Rate the hirer")
                                .font(.system(size: 17, weight: .bold, design: .default))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color.orange.opacity(0.35), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Hirer Action Buttons
    /// Intentionally empty now — both the start-job PIN exchange and the
    /// "Complete & Release Payment" flow have been moved to dedicated views
    /// (ActiveJobView for the in-progress lifecycle, JobCompletionView for
    /// completion). The Opportunity detail screen is now purely informational
    /// once the job is in progress.
    private var hirerActionButtons: some View {
        EmptyView()
    }

    // MARK: - Past start-time banner (hirer only)
    /// Shown when an open job sits past its scheduled start. Prompts the
    /// hirer to either bump the schedule or delete the post — otherwise
    /// stale jobs clutter the discovery feed for seekers.
    private var pastStartTimeBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start time has passed")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Bump the schedule so neighbors can apply, or delete this post.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showRescheduleSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .bold))
                        Text("Change time")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showDeleteJobConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Delete job")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.red.opacity(0.10)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.55, blue: 0.10).opacity(0.40), lineWidth: 1)
        )
        .sheet(isPresented: $showRescheduleSheet) {
            RescheduleOpportunitySheet(opportunity: opportunity)
                .environmentObject(authManager)
        }
        .alert("Delete this job?", isPresented: $showDeleteJobConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                OpportunityManager.shared.deleteOpportunity(id: opportunity.safeId)
                dismiss()
            }
        } message: {
            Text("Pending applicants won't be able to take this job. This can't be undone.")
        }
    }
    
    // MARK: - Helper Functions
    private func iconForJobType(_ type: String) -> String {
        return JobTypeHelper.icon(for: type)
    }
    
    private func applyToJob() {
        guard let user = authManager.currentUser else { return }

        if applicationManager.activeAcceptedApplication(for: user.id) != nil {
            showActiveJobAlert = true
            return
        }

        // No Stripe Connect gate here — earnings from this job will accrue
        // in the seeker's in-app Communally balance and be cashed out via
        // the EarningsView whenever they're ready to connect a payout
        // account. See PaymentManager.claimEarnings + EarningsView.

        applicationManager.applyToOpportunity(
            opportunityId: opportunity.safeId,
            applicantId: user.id,
            applicantName: user.fullName,
            applicantImageData: user.profileImageData
        )

        Log.debug("✅ Applied to job: \(opportunity.title)")
    }

    private func completeJob() {
        guard let accepted = acceptedJobSeeker else {
            paymentError = "No accepted worker found for completion."
            showPaymentError = true
            return
        }

        // Non-volunteer jobs must release held escrow payment on completion.
        if !opportunity.isVolunteer {
            guard let payment = PaymentManager.shared.getPayment(for: accepted.id) else {
                paymentError = "Payment hold not found for this job."
                showPaymentError = true
                return
            }

            PaymentManager.shared.releasePayment(paymentId: payment.safeId) { result in
                switch result {
                case .success:
                    finalizeJobCompletion()
                case .failure(let error):
                    paymentError = error.localizedDescription
                    showPaymentError = true
                }
            }
        } else {
            finalizeJobCompletion()
        }
    }
    
    private func acceptApplicant(_ application: JobApplication) {
        if let existingJob = applicationManager.activeAcceptedApplication(
            for: application.applicantId,
            excludingOpportunityId: opportunity.safeId
        ) {
            let jobTitle = existingJob.opportunityTitleSnapshot ?? "another job"
            paymentError = "\(application.applicantName) is already accepted for \(jobTitle). They can only have one active job at a time."
            showPaymentError = true
            return
        }
        
        if opportunity.isVolunteer {
            applicationManager.acceptApplication(applicationId: application.id) { success, message in
                if success {
                    acceptedJobSeeker = application
                    _ = PINVerificationService.shared.generatePIN(
                        jobId: opportunity.safeId,
                        type: .jobStart,
                        hirerId: opportunity.hirerId,
                        workerId: application.applicantId
                    )
                    Log.debug("✅ Accepted volunteer applicant: \(application.applicantName)")
                } else {
                    paymentError = message
                    showPaymentError = true
                }
            }
        } else {
            selectedApplicationForPayment = application
            showingPaymentSheet = true
        }
    }

    @ViewBuilder
    private func applicantStatusCardInline(for application: JobApplication) -> some View {
        let config = applicantStatusConfiguration(for: application)
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: config.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(config.color)
                
                Text(config.title)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Spacer()
            }
            
            Text(config.message)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(config.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(config.color.opacity(0.22), lineWidth: 1)
        )
    }
    
    private func applicantStatusConfiguration(for application: JobApplication) -> (title: String, message: String, icon: String, color: Color) {
        switch application.status {
        case .pending:
            return (
                "Application Sent",
                "Your application is in. Now you wait for the hirer to review it.",
                "paperplane.fill",
                CommunallyTheme.primaryGreen
            )
        case .accepted:
            if opportunity.status == .completed {
                return (
                    "Job Completed",
                    "This job is finished. Nice work.",
                    "checkmark.circle.fill",
                    .green
                )
            }
            return (
                "You're Booked",
                "You got the job. Use the PIN card above to check in when you arrive.",
                "briefcase.fill",
                .green
            )
        case .completed:
            return (
                "Job Completed",
                "This job is finished. Payment and rating details will appear in your account.",
                "checkmark.circle.fill",
                .green
            )
        case .rejected:
            return (
                "Not Selected",
                "This hirer chose someone else for this job.",
                "xmark.circle.fill",
                .red
            )
        case .cancelled:
            return (
                "Application Cancelled",
                "This application is no longer active.",
                "slash.circle.fill",
                .orange
            )
        }
    }

    private func finalizeJobCompletion() {
        applicationManager.completeJob(opportunityId: opportunity.safeId)

        // Show rating view after completion
        if acceptedJobSeeker != nil {
            if !ratingManager.hasRated(opportunityId: opportunity.safeId, raterId: authManager.currentUser?.id ?? "") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingRatingView = true
                }
            } else {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
    
    private func loadAcceptedJobSeeker() {
        if opportunity.status == .inProgress || opportunity.status == .completed {
            if let acceptedId = opportunity.acceptedApplicantId {
                acceptedJobSeeker = applicationManager.applications.first {
                    $0.opportunityId == opportunity.safeId && $0.applicantId == acceptedId
                }
            }
        }
    }

    /// Fetches the hirer's Stripe Identity status so seekers viewing the post
    /// see a verified / not-verified trust badge next to "Posted by …".
    private func loadHirerVerificationStatus() {
        guard hirerIsVerified == nil else { return }
        UserDatabase.shared.fetchUserFromFirebase(byUserId: opportunity.hirerId) { fetched in
            DispatchQueue.main.async {
                hirerIsVerified = (fetched?.isStripeIdentityVerified ?? false)
            }
        }
    }

    /// Compact informational badge shown next to "Posted by …" so seekers can
    /// see at a glance whether the hirer cleared Stripe Identity. Not tappable.
    @ViewBuilder
    private var hirerVerificationBadge: some View {
        if let verified = hirerIsVerified {
            if verified {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Verified")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(CommunallyTheme.primaryGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.14))
                )
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Not verified")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Color(red: 0.55, green: 0.45, blue: 0.0))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color(red: 1.0, green: 0.95, blue: 0.78))
                )
            }
        }
    }
}

// MARK: - Inline Applicant Card
struct InlineApplicantCard: View {
    let application: JobApplication
    let onAccept: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ClickableProfilePhoto(
                userId: application.applicantId,
                userImageData: application.applicantImageData,
                size: 52,
                showRatingBadge: true
            )
            
            NavigationLink(
                destination: UserProfileView(userId: application.applicantId)
                    .environmentObject(AuthenticationManager.shared)
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.applicantName)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.85))
                        
                        Text("Applied \(application.timeAgo)")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
                onAccept()
            }) {
                Label {
                    Text("Accept")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .labelStyle(.titleAndIcon)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen,
                            CommunallyTheme.secondaryGreen
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.08), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Reschedule sheet

/// Small composer sheet shown when the hirer taps "Change time" on the
/// past-start-time banner. Same-day-only: the calendar day is locked to the
/// opportunity's original scheduled day; only start/end times can move,
/// within the 7 AM – 7 PM window on that day. Saves via
/// `OpportunityManager.rescheduleOpportunity`.
struct RescheduleOpportunitySheet: View {
    let opportunity: Opportunity
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    /// Locked calendar day — same as the original posted date. If the
    /// opportunity has no scheduledDate (legacy posts), fall back to today.
    private let lockedDay: Date
    @State private var selectedStart: Date
    @State private var selectedEnd: Date
    @State private var isSaving = false
    @State private var inlineError: String?

    /// Mirrors PostOpportunityView.testingMode. While true, drops the
    /// 7 AM – 7 PM curfew (allows any hour), shrinks the lead time to
    /// 5 min, and shrinks the minimum job duration to 5 min — so reschedule
    /// matches the loosened rules new jobs are being created under. Flip
    /// both files back to `false` together when shipping prod-real rules.
    ///
    /// PRODUCTION SETTING: must be `false` for App Store submission.
    // Production setting. Keep `false` for App Store. Mirrors
    // PostOpportunityView.testingMode — flip both together if testing.
    private static let testingMode: Bool = false

    /// Day window — 24h while testing, 7 AM – 7 PM in production.
    private static let dayStartHour: Int = testingMode ? 0 : 7
    private static let dayEndHour: Int = testingMode ? 23 : 19
    private static let dayEndMinute: Int = testingMode ? 59 : 0
    /// Lead time floor: 2 min while testing, 30 min in production.
    /// Duration floor: 2 min while testing (so a dev can rip through the
    /// full start → both-confirm → cash-out flow in a couple of minutes
    /// per cycle), 30 min in production.
    private static let minimumLeadTimeSeconds: TimeInterval = testingMode ? 2 * 60 : 30 * 60
    private static let minimumJobDurationSeconds: TimeInterval = testingMode ? 2 * 60 : 30 * 60

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        let cal = Calendar.current
        // Lock to the original calendar day. Falls back to today if the
        // opportunity has no scheduledDate (legacy / corrupt rows).
        let day = opportunity.scheduledDate ?? Date()
        self.lockedDay = day

        // Seed start with the original time if it's still in the future,
        // otherwise "now + 30 min" rounded into the day's window.
        let now = Date()
        let originalStart = opportunity.scheduledStartDateTime
            ?? cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let dayStart = cal.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: day) ?? day
        let dayEnd = cal.date(bySettingHour: Self.dayEndHour, minute: Self.dayEndMinute, second: 0, of: day) ?? day
        let earliest = max(dayStart, now.addingTimeInterval(Self.minimumLeadTimeSeconds))
        let seedStart = min(max(originalStart, earliest), dayEnd)

        let originalEnd = opportunity.scheduledEndDateTime
            ?? cal.date(byAdding: .hour, value: 2, to: seedStart) ?? seedStart
        let seedEnd = min(max(originalEnd, seedStart.addingTimeInterval(Self.minimumJobDurationSeconds)), dayEnd)

        _selectedStart = State(initialValue: seedStart)
        _selectedEnd = State(initialValue: seedEnd)
    }

    /// Allowed start-time window on the locked day. Lower bound bumped to
    /// "now + minimum lead time" so the user can't pick a slot that's
    /// already past or violates the lead-time rule. Upper bound is the
    /// day-end curfew (production) or 23:59 (testing).
    private var startWindow: ClosedRange<Date> {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: lockedDay) ?? lockedDay
        let dayEnd = cal.date(bySettingHour: Self.dayEndHour, minute: Self.dayEndMinute, second: 0, of: lockedDay) ?? lockedDay
        let earliest = max(dayStart, Date().addingTimeInterval(Self.minimumLeadTimeSeconds))
        // Clamp to a non-empty range so SwiftUI doesn't crash on inversion
        // (window has already closed for today).
        return min(earliest, dayEnd)...dayEnd
    }

    /// End-time picker range: from start time onward, capped at the day-end
    /// curfew. Always clamped to a non-empty range.
    private var endWindow: ClosedRange<Date> {
        let cap = startWindow.upperBound
        let lower = min(selectedStart, cap)
        return lower...cap
    }

    /// True when the locked day's window has fully closed — no room left
    /// for a minimum-duration job starting after the lead time. Save is
    /// disabled in that case.
    private var dayHasNoValidSlot: Bool {
        let cap = startWindow.upperBound
        let earliest = startWindow.lowerBound
        return earliest.addingTimeInterval(Self.minimumJobDurationSeconds) > cap
    }

    /// Minutes derived from the seconds constants — used everywhere the UI
    /// has to render a human-readable "X minutes" copy that matches the
    /// active mode (5 in testing, 30 in production).
    private static var minimumLeadMinutes: Int { Int(minimumLeadTimeSeconds / 60) }
    private static var minimumJobMinutes: Int { Int(minimumJobDurationSeconds / 60) }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: lockedDay)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(dayLabel)
                            .foregroundColor(.secondary)
                    }
                    DatePicker("Start", selection: $selectedStart, in: startWindow, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $selectedEnd, in: endWindow, displayedComponents: .hourAndMinute)
                } header: {
                    Text("New time")
                } footer: {
                    if let inlineError {
                        Text(inlineError).foregroundColor(.red)
                    } else if dayHasNoValidSlot {
                        Text(Self.testingMode
                             ? "Today's window has closed. Delete this job and post a new one for a future day."
                             : "Today's 7 AM – 7 PM window has closed. Delete this job and post a new one for a future day.")
                            .foregroundColor(.red)
                    } else {
                        Text(Self.testingMode
                             ? "🚧 Testing: same day only, any hour, at least \(Self.minimumLeadMinutes) min from now, and the job must last at least \(Self.minimumJobMinutes) min."
                             : "Same day only. Times must be between 7 AM and 7 PM, at least \(Self.minimumLeadMinutes) minutes from now, and the job must last at least \(Self.minimumJobMinutes) minutes.")
                    }
                }
            }
            .navigationTitle("Change time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || dayHasNoValidSlot)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func save() {
        // Merge locked day with picker times so the stored timestamps don't
        // drift if the user spun the time picker across midnight.
        let cal = Calendar.current
        let dateParts = cal.dateComponents([.year, .month, .day], from: lockedDay)
        let startParts = cal.dateComponents([.hour, .minute], from: selectedStart)
        let endParts = cal.dateComponents([.hour, .minute], from: selectedEnd)

        var startComps = DateComponents()
        startComps.year = dateParts.year
        startComps.month = dateParts.month
        startComps.day = dateParts.day
        startComps.hour = startParts.hour
        startComps.minute = startParts.minute

        var endComps = DateComponents()
        endComps.year = dateParts.year
        endComps.month = dateParts.month
        endComps.day = dateParts.day
        endComps.hour = endParts.hour
        endComps.minute = endParts.minute

        guard let mergedStart = cal.date(from: startComps),
              let mergedEnd = cal.date(from: endComps) else {
            inlineError = "Couldn't read the time. Try again."
            return
        }
        // Belt-and-suspenders against the DatePicker bounds.
        let window = startWindow
        if mergedStart < window.lowerBound {
            inlineError = "Start must be at least \(Self.minimumLeadMinutes) minutes from now."
            return
        }
        if mergedEnd > window.upperBound {
            inlineError = Self.testingMode
                ? "End time must be 11:59 PM or earlier."
                : "End time must be 7 PM or earlier."
            return
        }
        if mergedEnd.timeIntervalSince(mergedStart) < Self.minimumJobDurationSeconds {
            inlineError = "Jobs must be at least \(Self.minimumJobMinutes) minutes long."
            return
        }

        let f = DateFormatter()
        f.timeStyle = .short
        let startString = f.string(from: mergedStart)
        let endString = f.string(from: mergedEnd)

        isSaving = true
        OpportunityManager.shared.rescheduleOpportunity(
            id: opportunity.safeId,
            newDate: lockedDay,
            newStartTime: startString,
            newEndTime: endString
        ) { success in
            isSaving = false
            if success {
                dismiss()
            } else {
                inlineError = "Couldn't save the new schedule. Try again."
            }
        }
    }
}

#Preview {
    NavigationView {
        OpportunityDetailView(opportunity: Opportunity(
            id: "1",
            title: "Gardening Needed",
            description: "Need help with lawn mowing and weeding",
            hirerId: "hirer123",
            hirerName: "John Smith",
            hirerImageData: nil,
            location: Location(latitude: 37.7749, longitude: -122.4194, address: "San Francisco"),
            locationName: "San Francisco, CA",
            isVolunteer: false,
            payAmount: "50",
            jobType: "Gardening",
            createdAt: Date(),
            isActive: true,
            applicantCount: 3,
            status: .open,
            acceptedApplicantId: nil,
            scheduledDate: Date(),
            scheduledTime: "Morning (8AM - 12PM)"
        ))
    }
    .environmentObject(AuthenticationManager.shared)
}

