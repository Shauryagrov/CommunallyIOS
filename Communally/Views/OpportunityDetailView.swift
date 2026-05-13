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
    
    /// Paid jobs require Stripe Connect ready so payouts work after acceptance; volunteer jobs can apply without.
    private var seekerPayoutReady: Bool {
        authManager.currentUser?.canReceivePayments ?? false
    }
    
    private var needsBankSetupToApply: Bool {
        !opportunity.isVolunteer && !seekerPayoutReady
    }

    /// Worker rates hirer once per completed job (same `ratings` doc rules as hirer→worker).
    private var canSeekerRateHirer: Bool {
        guard !isHirer, opportunity.status == .completed else { return false }
        guard let app = currentUserApplication, app.status == .completed else { return false }
        guard let uid = authManager.currentUser?.id else { return false }
        return !ratingManager.hasRated(opportunityId: opportunity.safeId, raterId: uid)
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
                    onPaymentComplete: {
                        applicationManager.acceptApplication(applicationId: application.id) { success, message in
                            if success {
                                acceptedJobSeeker = application
                                _ = PINVerificationService.shared.generatePIN(
                                    jobId: opportunity.safeId,
                                    type: .jobStart,
                                    hirerId: opportunity.hirerId,
                                    workerId: application.applicantId
                                )
                                print("✅ Accepted applicant with payment hold: \(application.applicantName)")
                            } else {
                                paymentError = message
                                showPaymentError = true
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

                    HStack(spacing: 6) {
                        Text(isHirer
                             ? "Posted by you · \(opportunity.timeAgo)"
                             : "Posted by \(opportunity.hirerName) · \(opportunity.timeAgo)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            .lineLimit(1)
                        if !isHirer {
                            hirerVerificationBadge
                        }
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

        if !opportunity.isVolunteer && !user.canReceivePayments {
            showBankSetupForApply = true
            return
        }

        applicationManager.applyToOpportunity(
            opportunityId: opportunity.safeId,
            applicantId: user.id,
            applicantName: user.fullName,
            applicantImageData: user.profileImageData
        )
        
        print("✅ Applied to job: \(opportunity.title)")
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
                    print("✅ Accepted volunteer applicant: \(application.applicantName)")
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
/// past-start-time banner. Single date + start + end picker; saves via
/// `OpportunityManager.rescheduleOpportunity`. Times must end up in the
/// future or the save is blocked.
struct RescheduleOpportunitySheet: View {
    let opportunity: Opportunity
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var selectedStart: Date
    @State private var selectedEnd: Date
    @State private var isSaving = false
    @State private var inlineError: String?

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        // Seed pickers with "tomorrow at the original time" so the hirer
        // doesn't have to start from scratch.
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let originalStart = opportunity.scheduledStartDateTime ?? tomorrow
        let originalEnd = opportunity.scheduledEndDateTime
            ?? cal.date(byAdding: .hour, value: 2, to: originalStart) ?? originalStart
        _selectedDate = State(initialValue: tomorrow)
        _selectedStart = State(initialValue: originalStart)
        _selectedEnd = State(initialValue: originalEnd)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                    DatePicker("Start", selection: $selectedStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $selectedEnd, displayedComponents: .hourAndMinute)
                } header: {
                    Text("New schedule")
                } footer: {
                    if let inlineError {
                        Text(inlineError).foregroundColor(.red)
                    } else {
                        Text("Pick a future date + time. The end time must be after the start.")
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
                        .disabled(isSaving)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func save() {
        // Merge picker date with picker times.
        let cal = Calendar.current
        let dateParts = cal.dateComponents([.year, .month, .day], from: selectedDate)
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
            inlineError = "Couldn't read the date or time. Try again."
            return
        }
        if mergedStart < Date() {
            inlineError = "Pick a start time in the future."
            return
        }
        if mergedEnd <= mergedStart {
            inlineError = "End time must be after the start time."
            return
        }

        let f = DateFormatter()
        f.timeStyle = .short
        let startString = f.string(from: mergedStart)
        let endString = f.string(from: mergedEnd)

        isSaving = true
        OpportunityManager.shared.rescheduleOpportunity(
            id: opportunity.safeId,
            newDate: selectedDate,
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

