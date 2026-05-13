//
//  DashboardView.swift
//  Communally
//
//  Created by Madhur Grover 10/2/25.
//

import SwiftUI
import MapKit
import CoreLocation
import StoreKit
import FirebaseCore
import FirebaseAuth

extension Notification.Name {
    /// Posted from seeker empty-state quick actions to open Map & browse settings (radius, etc.).
    static let communallyOpenSeekerBrowseTools = Notification.Name("communallyOpenSeekerBrowseTools")
    /// Posted to open the notifications sheet from in-flow CTAs.
    static let communallyOpenNotifications = Notification.Name("communallyOpenNotifications")
}

@MainActor
private final class SeekerLocationSubtitleModel: ObservableObject {
    @Published var text: String = "Near you"
    private let geocoder = CLGeocoder()

    func update(location: CLLocation?) {
        geocoder.cancelGeocode()
        guard let location else {
            text = "Turn on location"
            return
        }
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let p = placemarks?.first else {
                    self.text = "United States"
                    return
                }
                let city = p.locality ?? p.subAdministrativeArea ?? ""
                let state = p.administrativeArea ?? ""
                if !city.isEmpty, !state.isEmpty {
                    self.text = "\(city), \(state)"
                } else if !city.isEmpty {
                    self.text = city
                } else {
                    self.text = "Near you"
                }
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var messageManager = MessageManager.shared
    @ObservedObject private var paymentManager = PaymentManager.shared
    @ObservedObject private var emergencyAlertService = EmergencyAlertService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @Environment(\.requestReview) private var requestReview
    @StateObject private var seekerLocationSubtitle = SeekerLocationSubtitleModel()
    @State private var selectedTab = 0
    /// Tracks the previous tab so the slide transition between tabs picks the
    /// right direction — going right (Map → Profile) feels different from
    /// going left (Profile → Map).
    @State private var previousTab = 0
    @State private var showNotifications = false
    @State private var showPaymentHistory = false
    @State private var showPaymentPocket = false
    @State private var showSeekerBrowseTools = false
    @State private var showHirerBrowseTools = false
    @State private var showDevModeBanner = false
    @State private var showAlertDetails = false
    @State private var showEnjoyingPrompt = false
    @AppStorage("communally_complete_profile_dismissed_v1") private var completeProfileDismissed = false
    @State private var showCompleteProfileEditor = false
    @AppStorage("communally_first_dashboard_rollup_shown_v1") private var firstDashboardRollupShown = false
    @State private var showFirstDashboardRollup = false
    @State private var showPostNewJob = false
    @State private var showCommunityFeed = false

    // Active role is based on user's actual type (no switching)
    private var activeRole: UserType {
        authManager.currentUser?.userType ?? .jobSeeker
    }
    
    private var isFirebaseConfigured: Bool {
        FirebaseApp.app() != nil
    }

    /// Profile tab index for the active role. Seekers have it at slot 4
    /// (after Map / Browse / Applications / Messages); hirers at slot 3
    /// (after Map / My Jobs / Messages).
    private var profileTabIndex: Int {
        activeRole == .jobSeeker ? 4 : 3
    }

    /// Messages tab index for the active role. Seekers: slot 3. Hirers: slot 2.
    /// Only that tab has a `.large` navigation title (taller nav bar), so the
    /// complete-profile overlay needs a bigger top buffer there.
    private var messagesTabIndex: Int {
        activeRole == .jobSeeker ? 3 : 2
    }

    /// Vertical offset *added on top of the device's top safe-area inset* for
    /// the "Finish your profile" overlay so it never disappears under the
    /// Dynamic Island / notch and never collides with the in-tab nav bar.
    ///   - Map (no nav bar): small buffer below the safe area.
    ///   - Messages (.large title): big buffer to clear the large title block.
    ///   - Other tabs (.inline title): mid buffer to clear the slim nav bar.
    private var completeProfileCardTopOffset: CGFloat {
        if selectedTab == 0 { return 8 }
        if selectedTab == messagesTabIndex { return 96 }
        return 52
    }

    /// Show the "Complete your profile" nudge when the user has no profile
    /// photo yet (we made photos optional at onboarding) and they haven't
    /// dismissed it. Hidden inside sheets/popups AND on the Profile tab
    /// itself, since the user is already on their profile and can change the
    /// photo directly from there.
    private var shouldShowCompleteProfileCard: Bool {
        guard let user = authManager.currentUser, user.hasCompletedOnboarding else { return false }
        if completeProfileDismissed { return false }
        if showPaymentPocket || showAlertDetails { return false }
        if selectedTab == profileTabIndex { return false }
        return user.profileImageData == nil
    }

    private var completeProfileCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCompleteProfileEditor = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.crop.circle.fill.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish your profile")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Add a photo so neighbors recognize you")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        completeProfileDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                        .padding(8)
                        .background(Circle().fill(Color.gray.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CommunallyTheme.primaryGreen.opacity(0.20), lineWidth: 1)
            )
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    private var hasActiveJob: Bool {
        guard let uid = authManager.currentUser?.id else { return false }
        if activeRole == .jobSeeker {
            return applicationManager.applications.contains { $0.applicantId == uid && $0.status == .accepted }
        } else {
            return opportunityManager.opportunities.contains { $0.hirerId == uid && $0.status == .inProgress }
        }
    }
    
    /// Direction the tab content should slide based on whether the new tab
    /// is to the left or right of the old one. Falls back to a fade when the
    /// indices are equal (e.g., when activeRole flips and selectedTab stays).
    private var tabSlideTransition: AnyTransition {
        if selectedTab == previousTab { return .opacity }
        let goingForward = selectedTab > previousTab
        return .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab Content - Show the selected view based on active role.
            // Each branch carries a unique `.id(...)` so SwiftUI treats them
            // as distinct identities, and a per-branch `.transition()` so the
            // slide animation actually fires on tab swap (attaching the
            // transition to the parent `Group` does NOT propagate to switch
            // children reliably in SwiftUI; the modifier has to live on the
            // view whose identity changes).
            Group {
                switch selectedTab {
                case 0:
                    MapTabView(activeRole: .constant(activeRole))
                        .id("map-\(selectedTab)-\(activeRole.rawValue)")
                        .transition(tabSlideTransition)
                case 1:
                    if activeRole == .jobSeeker {
                        JobSeekerOpportunitiesView()
                            .id("opportunities-\(selectedTab)")
                            .transition(tabSlideTransition)
                    } else {
                        MyJobsView()
                            .id("myjobs-\(selectedTab)")
                            .transition(tabSlideTransition)
                    }
                case 2:
                    if activeRole == .jobSeeker {
                        MyApplicationsView()
                            .id("applications-\(selectedTab)")
                            .transition(tabSlideTransition)
                    } else {
                        MessagingView()
                            .id("messages-\(selectedTab)")
                            .transition(tabSlideTransition)
                    }
                case 3:
                    if activeRole == .jobSeeker {
                        MessagingView()
                            .id("messages-\(selectedTab)")
                            .transition(tabSlideTransition)
                    } else {
                        NavigationView {
                            if let userId = authManager.currentUser?.id {
                                UserProfileView(userId: userId)
                                    .environmentObject(authManager)
                            }
                        }
                            .id("profile-\(selectedTab)")
                            .transition(tabSlideTransition)
                    }
                case 4:
                    NavigationView {
                        if let userId = authManager.currentUser?.id {
                            UserProfileView(userId: userId)
                                .environmentObject(authManager)
                        }
                    }
                        .id("profile-\(selectedTab)")
                        .transition(tabSlideTransition)
                default:
                    MapTabView(activeRole: .constant(activeRole))
                        .id("map-default")
                        .transition(tabSlideTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedTab)
            .onChange(of: selectedTab) { oldValue, _ in previousTab = oldValue }

            // Emergency Alert Banner - Top Center
            if emergencyAlertService.showAlertBanner, let alert = emergencyAlertService.currentBannerAlert {
                VStack {
                    EmergencyAlertBanner(
                        alert: alert,
                        onDismiss: {
                            emergencyAlertService.dismissBanner()
                        },
                        onViewDetails: {
                            showAlertDetails = true
                        }
                    )
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: emergencyAlertService.showAlertBanner)

                    Spacer()
                }
                .zIndex(100)
            }

            // "Complete your profile" nudge — appears at top of every non-profile
            // tab for users without a profile photo (now optional during
            // onboarding). Dismissable forever; reopens EditProfile on tap.
            // Position has to clear: status bar / Dynamic Island on every iPhone
            // AND the in-tab nav bar (none on Map, inline on My Jobs / Browse /
            // Applications, large-title on Messages). We use a GeometryReader to
            // read the actual top safe-area inset and stack a tab-specific
            // offset on top — so it lands cleanly on every device.
            if shouldShowCompleteProfileCard {
                GeometryReader { proxy in
                    VStack {
                        completeProfileCard
                            .padding(.top, proxy.safeAreaInsets.top + completeProfileCardTopOffset)
                            .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .top)
                }
                .zIndex(80)
                .allowsHitTesting(true)
            }

            // Payment summary: centered popup (seekers & hirers) — tap outside, X, or See more details
            if showPaymentPocket, let user = authManager.currentUser {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showPaymentPocket = false
                            }
                        }

                    PaymentSummaryCards(
                        user: user,
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showPaymentPocket = false
                            }
                        },
                        onSeeMoreDetails: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showPaymentPocket = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showPaymentHistory = true
                            }
                        }
                    )
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 24)
                }
                .zIndex(50)
                .transition(.opacity.combined(with: .scale(0.96)))
            }

            // Hirer top-right pill (mirrors seeker pill style)
            if activeRole != .jobSeeker {
                VStack {
                    HStack {
                        Spacer()
                        HStack(alignment: .center, spacing: 8) {
                            SeekerHeaderRoundToolButton(
                                systemImage: "person.3.fill",
                                accessibilityLabel: "Community feed",
                                action: {
                                    let g = UIImpactFeedbackGenerator(style: .light)
                                    g.impactOccurred()
                                    showCommunityFeed = true
                                }
                            )
                            SeekerHeaderRoundToolButton(
                                systemImage: "bell.fill",
                                accessibilityLabel: "Notifications",
                                action: {
                                    let g = UIImpactFeedbackGenerator(style: .light)
                                    g.impactOccurred()
                                    showNotifications = true
                                },
                                badgeCount: notificationManager.unreadCount
                            )
                            SeekerHeaderRoundToolButton(
                                systemImage: "gearshape.fill",
                                accessibilityLabel: "Payments and settings",
                                action: {
                                    let g = UIImpactFeedbackGenerator(style: .light)
                                    g.impactOccurred()
                                    showHirerBrowseTools = true
                                }
                            )
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.white.opacity(0.94))
                                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        )
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 56)
                    Spacer()
                }
            }

            
            // Development Mode Banner - Shows when Firebase not configured
            if showDevModeBanner && !isFirebaseConfigured {
                VStack {
                    DevelopmentModeBanner()
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }

            // Active Job Banner — floats above the tab bar when a job is in progress
            VStack {
                Spacer()
                ActiveJobBannerCard()
                    .environmentObject(authManager)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hasActiveJob)
            }

            // Custom Floating Tab Bar — with a detached "New Job" mini-dock
            // for hirers, sitting flush to its right. (Community moved to the
            // top-right header pill, not in the bottom dock.)
            HStack(spacing: 10) {
                FloatingTabBar(selectedTab: $selectedTab, userType: activeRole)
                if activeRole == .jobHirer {
                    NewJobDock { showPostNewJob = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            // Attach the sheets here (not on the outer body) so they don't
            // collide with the other .sheet modifiers further up the chain.
            .sheet(isPresented: $showPostNewJob) {
                PostOpportunityView()
                    .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $showCommunityFeed) {
                CommunityFeedView()
                    .environmentObject(authManager)
            }
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            if activeRole == .jobSeeker {
                SeekerMapBrowseHeaderBar(
                    selectedTab: selectedTab,
                    placeText: seekerLocationSubtitle.text,
                    onOpenNotifications: {
                        let g = UIImpactFeedbackGenerator(style: .light)
                        g.impactOccurred()
                        showNotifications = true
                    },
                    onOpenTools: { showSeekerBrowseTools = true },
                    onOpenCommunity: { showCommunityFeed = true }
                )
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.91, green: 0.99, blue: 0.94),
                            Color(red: 0.97, green: 1.0, blue: 0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.2)
                }
            }
        }
        .onReceive(locationManager.$location) { loc in
            seekerLocationSubtitle.update(location: loc)
        }
        .onReceive(NotificationCenter.default.publisher(for: .communallyOpenSeekerBrowseTools)) { _ in
            showSeekerBrowseTools = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .communallyOpenNotifications)) { _ in
            showNotifications = true
        }
        .sheet(isPresented: $showSeekerBrowseTools) {
            SeekerBrowseToolsSheet(
                selectedTab: selectedTab,
                showPaymentPocket: $showPaymentPocket,
                showPaymentHistory: $showPaymentHistory,
                isHirerMode: false
            )
            .environmentObject(authManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHirerBrowseTools) {
            SeekerBrowseToolsSheet(
                selectedTab: selectedTab,
                showPaymentPocket: $showPaymentPocket,
                showPaymentHistory: $showPaymentHistory,
                isHirerMode: true
            )
            .environmentObject(authManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showPaymentHistory) {
            NavigationView {
                PaymentHistoryView()
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showAlertDetails) {
            if let alert = emergencyAlertService.currentBannerAlert {
                EmergencyAlertDetailView(alert: alert)
            }
        }
        .sheet(isPresented: $showCompleteProfileEditor) {
            if let user = authManager.currentUser {
                EditProfileView(user: user)
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showFirstDashboardRollup) {
            OnboardingLoadingView {
                firstDashboardRollupShown = true
                showFirstDashboardRollup = false
            }
        }
        .alert("Enjoying Communally? 😊", isPresented: $showEnjoyingPrompt) {
            Button("Yes, Love It! ❤️") {
                requestReview()
                ReviewPromptManager.shared.markPrompted()
            }
            Button("Not Really") {
                ReviewPromptManager.shared.markPrompted()
                if let url = URL(string: "mailto:communallyapp@gmail.com?subject=Communally%20Feedback") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Maybe Later", role: .cancel) { }
        } message: {
            Text("We'd love to hear what you think! A quick rating helps us grow and improve.")
        }
        .onAppear {
            // Show development mode banner if Firebase not configured
            if !isFirebaseConfigured {
                showDevModeBanner = true
            }

            // First-launch hype rollup — shown once per device, right before
            // the user's first time on the dashboard.
            if !firstDashboardRollupShown && !showFirstDashboardRollup {
                showFirstDashboardRollup = true
            }

            // Ensure listeners are active when dashboard loads
            setupListeners()
            seekerLocationSubtitle.update(location: locationManager.location)

            // App Store review prompt — shows after 3 days + 4 launches
            ReviewPromptManager.shared.recordLaunch()
            if ReviewPromptManager.shared.shouldPrompt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showEnjoyingPrompt = true
                }
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupListeners() {
        guard let userId = authManager.currentUser?.id else { return }
        guard Auth.auth().currentUser?.uid == userId else {
            // Firebase custom-token session can finish slightly after app-level sign-in.
            // Delay listeners until request.auth.uid is ready to avoid permission-denied loops.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                setupListeners()
            }
            return
        }
        
        // Start notification listener
        if notificationManager.notifications.isEmpty {
            notificationManager.startListening(for: userId)
            print("✅ Started notification listener for user: \(userId)")
        }
        
        // Start message listener
        if !messageManager.isListening {
            messageManager.startListening(for: userId)
            print("✅ Started message listener for user: \(userId)")
        }

        ApplicationManager.shared.startListening(for: userId)
        print("✅ Started application listener for user: \(userId)")
        
        // Start safety listener
        SafetyManager.shared.startListening(for: userId)
        print("✅ Started safety listener for user: \(userId)")
        
        // Start payment listener
        PaymentManager.shared.startListening(for: userId)
        print("✅ Started payment listener for user: \(userId)")
    }
}

private struct PaymentSummaryCards: View {
    let user: User
    let onDismiss: () -> Void
    let onSeeMoreDetails: () -> Void
    @ObservedObject private var paymentManager = PaymentManager.shared

    private var primaryTitle: String {
        user.userType == .jobSeeker ? "Paid Out" : "Total Paid"
    }

    private var primaryAmount: Double {
        if user.userType == .jobSeeker {
            return paymentManager.getTotalEarnings(for: user.id)
        }
        return paymentManager.getTotalSpent(for: user.id)
    }

    private var pendingAmount: Double {
        if user.userType == .jobSeeker {
            return paymentManager.getPendingPayouts(for: user.id)
        }
        return paymentManager.getPendingCharges(for: user.id)
    }
    
    private var pendingTitle: String {
        user.userType == .jobSeeker ? "Awaiting Release" : "Held in Escrow"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Payments")
                        .font(.system(size: 17, weight: .bold, design: .default))
                }
                .foregroundStyle(Color.white)

                Spacer(minLength: 8)

                Button(action: {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.impactOccurred()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: 10) {
                paymentStatPill(title: primaryTitle, amount: primaryAmount)
                paymentStatPill(title: pendingTitle, amount: pendingAmount)
            }

            Button(action: {
                let g = UIImpactFeedbackGenerator(style: .medium)
                g.impactOccurred()
                onSeeMoreDetails()
            }) {
                HStack {
                    Text("See more details")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens payment history")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.78, blue: 0.48),
                            CommunallyTheme.primaryGreen,
                            CommunallyTheme.secondaryGreen,
                            Color(red: 0.06, green: 0.52, blue: 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 24, x: 0, y: 12)
    }

    private func paymentStatPill(title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(String(format: "$%.2f", amount))
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
    }
}

// MARK: - Seeker top bar & tools sheet
private struct SeekerHeaderRoundToolButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
    var badgeCount: Int = 0

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    )
                if badgeCount > 0 {
                    Text("\(min(badgeCount, 99))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 8, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SeekerMapBrowseHeaderBar: View {
    let selectedTab: Int
    let placeText: String
    let onOpenNotifications: () -> Void
    let onOpenTools: () -> Void
    let onOpenCommunity: () -> Void

    @ObservedObject private var notificationManager = NotificationManager.shared

    private var isMapTab: Bool { selectedTab == 0 }

    /// Community, emergency, safety, bell, gear — shared by map (with pill)
    /// and other seeker tabs (loose circles only).
    private var toolsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            EmergencyAlertIndicator(compact: true)
            SafetyStatusIndicator(compact: true)

            SeekerHeaderRoundToolButton(
                systemImage: "person.3.fill",
                accessibilityLabel: "Community feed",
                action: {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.impactOccurred()
                    onOpenCommunity()
                }
            )

            SeekerHeaderRoundToolButton(
                systemImage: "bell.fill",
                accessibilityLabel: "Notifications",
                action: onOpenNotifications,
                badgeCount: notificationManager.unreadCount
            )

            SeekerHeaderRoundToolButton(
                systemImage: "gearshape.fill",
                accessibilityLabel: "Map and browse settings",
                action: {
                    let g = UIImpactFeedbackGenerator(style: .light)
                    g.impactOccurred()
                    onOpenTools()
                }
            )
        }
    }

    /// White grouped pill — **Map tab only** for job seekers.
    private var toolsPill: some View {
        toolsRow
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isMapTab {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Searching near")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.45))
                    Text(placeText)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            if isMapTab {
                toolsPill
            } else {
                toolsRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct SeekerBrowseToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedTab: Int
    @Binding var showPaymentPocket: Bool
    @Binding var showPaymentHistory: Bool
    /// Hirers only see payments (no search radius).
    var isHirerMode: Bool = false
    @EnvironmentObject private var authManager: AuthenticationManager

    private var showRadiusSection: Bool {
        !isHirerMode && (selectedTab == 0 || selectedTab == 1)
    }

    private func afterDismiss(_ seconds: Double = 0.45, _ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Search radius (seekers on map/browse tabs only)
                        if showRadiusSection {
                            toolSection(header: "Search Radius") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Map pins and Browse only show jobs within this distance.")
                                        .font(.system(size: 13, weight: .medium, design: .default))
                                        .foregroundStyle(CommunallyTheme.darkGray.opacity(0.6))
                                    SeekerDiscoveryRadiusCompactControl()
                                        .padding(.vertical, 4)
                                }
                            }
                        } else if !isHirerMode {
                            toolSection(header: "Search Radius") {
                                Text("Switch to the Map or Browse tab to adjust your search distance.")
                                    .font(.system(size: 14, weight: .medium, design: .default))
                                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                            }
                        }

                        // Payments
                        toolSection(
                            header: "Payments",
                            footer: isHirerMode
                                ? "Summary shows pending charges and totals."
                                : "Summary shows pending payouts and totals."
                        ) {
                            VStack(spacing: 0) {
                                toolRow(
                                    icon: "dollarsign.circle.fill",
                                    iconColor: CommunallyTheme.primaryGreen,
                                    title: "Payment summary",
                                    subtitle: isHirerMode ? "View charges and held funds" : "View earnings and pending payouts",
                                    disabled: authManager.currentUser == nil
                                ) {
                                    let g = UIImpactFeedbackGenerator(style: .light)
                                    g.impactOccurred()
                                    afterDismiss {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            showPaymentPocket = true
                                        }
                                    }
                                }

                                Divider().padding(.leading, 58)

                                toolRow(
                                    icon: "list.bullet.rectangle.fill",
                                    iconColor: Color(red: 0.28, green: 0.52, blue: 0.95),
                                    title: "Payment history",
                                    subtitle: "See all past transactions",
                                    disabled: authManager.currentUser == nil
                                ) {
                                    let g = UIImpactFeedbackGenerator(style: .light)
                                    g.impactOccurred()
                                    afterDismiss { showPaymentHistory = true }
                                }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(isHirerMode ? "Tools" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                }
            }
        }
    }

    private func toolSection<Content: View>(
        header: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
                .padding(.leading, 4)

            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
                )

            if let footer {
                Text(footer)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
                    .padding(.leading, 4)
            }
        }
    }

    private func toolRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(disabled ? CommunallyTheme.darkGray.opacity(0.35) : CommunallyTheme.darkGray)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.25))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Floating Tab Bar
struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let userType: UserType
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var messageManager = MessageManager.shared
    @EnvironmentObject var authManager: AuthenticationManager
    
    private var acceptedApplicationsCount: Int {
        guard let userId = authManager.currentUser?.id else { return 0 }
        return applicationManager.getApplications(byUser: userId)
            .filter { $0.status == .accepted }
            .count
    }
    
    private var hirerActionItemsCount: Int {
        guard let userId = authManager.currentUser?.id else { return 0 }
        let userOpportunities = opportunityManager.getUserOpportunities(userId: userId)
        
        // Jobs needing review (open with applicants)
        let needsReview = userOpportunities.filter { opp in
            opp.status == .open && opp.applicantCount > 0
        }.count
        
        // Jobs in progress (need completion/payment)
        let inProgress = userOpportunities.filter { $0.status == .inProgress }.count
        
        return needsReview + inProgress
    }
    
    private var unreadMessagesCount: Int {
        guard let userId = authManager.currentUser?.id else { return 0 }
        return messageManager.conversations.reduce(0) { total, conversation in
            total + (conversation.participantIds.contains(userId) ? conversation.unreadCount : 0)
        }
    }
    
    /// All tab swaps go through here so the slide-between-tabs transition
    /// declared on the content `Group` in `DashboardView` reliably fires.
    /// (SwiftUI's `.animation(_:value:)` is sometimes inconsistent at picking
    /// up identity changes inside a `switch`; an explicit `withAnimation` is
    /// the safe path.)
    private func switchTab(_ newTab: Int) {
        guard selectedTab != newTab else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            selectedTab = newTab
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Map Tab
            FloatingTabItem(
                icon: selectedTab == 0 ? "map.fill" : "map",
                title: "Map",
                isSelected: selectedTab == 0
            ) {
                switchTab(0)
            }

            // Opportunities Tab / My Jobs Tab
            FloatingTabItem(
                icon: selectedTab == 1 ? "briefcase.fill" : "briefcase",
                title: userType == .jobSeeker ? "Browse" : "My Jobs",
                isSelected: selectedTab == 1,
                badgeCount: userType == .jobHirer ? hirerActionItemsCount : nil
            ) {
                switchTab(1)
            }

            // My Applications Tab (Job Seekers Only)
            if userType == .jobSeeker {
                FloatingTabItem(
                    icon: selectedTab == 2 ? "doc.text.fill" : "doc.text",
                    title: "Applications",
                    isSelected: selectedTab == 2,
                    badgeCount: acceptedApplicationsCount
                ) {
                    switchTab(2)
                }
            }

            // Messages Tab
            FloatingTabItem(
                icon: userType == .jobSeeker ?
                    (selectedTab == 3 ? "message.fill" : "message") :
                    (selectedTab == 2 ? "message.fill" : "message"),
                title: "Messages",
                isSelected: userType == .jobSeeker ? selectedTab == 3 : selectedTab == 2,
                badgeCount: unreadMessagesCount
            ) {
                switchTab(userType == .jobSeeker ? 3 : 2)
            }

            // Profile Tab
            FloatingTabItem(
                icon: userType == .jobSeeker ?
                    (selectedTab == 4 ? "person.crop.circle.fill" : "person.crop.circle") :
                    (selectedTab == 3 ? "person.crop.circle.fill" : "person.crop.circle"),
                title: "Profile",
                isSelected: userType == .jobSeeker ? selectedTab == 4 : selectedTab == 3
            ) {
                switchTab(userType == .jobSeeker ? 4 : 3)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 6)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.07), radius: 28, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

/// Detached single-cell mini-dock that sits flush to the right of the main
/// `FloatingTabBar` for hirers. Same visual chrome (ultra-thin material,
/// soft white-gradient overlay, green-tinted shadow) so the two read as a
/// pair while remaining visibly separate.
struct NewJobDock: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 26)

                Text("New Job")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 6)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.07), radius: 28, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.7), Color.white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // Make the whole rounded rect tappable, not just the icon/text
            // glyphs (PlainButtonStyle leaves transparent background pixels
            // non-interactive otherwise).
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        // Keep the dock at its intrinsic width so the FloatingTabBar's
        // `.frame(maxWidth: .infinity)` items don't squeeze it to zero in
        // the parent HStack.
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Post a new job")
    }
}

struct FloatingTabItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void
    
    init(icon: String, title: String, isSelected: Bool, badgeCount: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.badgeCount = badgeCount
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            let impactLight = UIImpactFeedbackGenerator(style: .light)
            impactLight.impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected
                                ? LinearGradient(colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color(red: 0.60, green: 0.61, blue: 0.64), Color(red: 0.60, green: 0.61, blue: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 26)
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)

                    if let count = badgeCount, count > 0 {
                        let label = count > 9 ? "9+" : "\(count)"
                        Text(label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, label.count > 1 ? 5 : 0)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 10, y: -5)
                    }
                }

                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .default))
                    .foregroundColor(isSelected ? CommunallyTheme.primaryGreen : Color(red: 0.60, green: 0.61, blue: 0.64))
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(
                                colors: [CommunallyTheme.primaryGreen.opacity(0.26), CommunallyTheme.secondaryGreen.opacity(0.13)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Seeker map + browse: single-row radius (1–5 mi). Same `SeekerDiscoveryRadiusStore` filters map pins and list.
private struct SeekerDiscoveryRadiusCompactControl: View {
    @ObservedObject private var store = SeekerDiscoveryRadiusStore.shared

    private var mileBinding: Binding<Double> {
        Binding(
            get: { store.miles },
            set: { store.setMilesFromSlider($0) }
        )
    }

    private var selectedMile: Int {
        min(
            Int(SeekerDiscoverySettings.maxMiles),
            max(Int(SeekerDiscoverySettings.minMiles), Int(store.miles.rounded()))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                    .accessibilityHidden(true)
                Text("Radius")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.22))
                Spacer(minLength: 8)
                Text("\(selectedMile) mi")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                    .monospacedDigit()
            }

            // Full-width slider with explicit min/max labels — the previous
            // 112pt-wide `.controlSize(.small)` slider was effectively
            // un-draggable for a 1–5 mile range, which made the radius
            // appear stuck at 5.
            Slider(
                value: mileBinding,
                in: SeekerDiscoverySettings.minMiles...SeekerDiscoverySettings.maxMiles,
                step: 1
            )
            .tint(CommunallyTheme.primaryGreen)
            .frame(maxWidth: .infinity)

            HStack {
                Text("\(Int(SeekerDiscoverySettings.minMiles)) mi")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
                Spacer()
                Text("\(Int(SeekerDiscoverySettings.maxMiles)) mi")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search radius")
        .accessibilityValue("\(selectedMile) miles")
    }
}

struct MapTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var seekerDiscoveryRadius = SeekerDiscoveryRadiusStore.shared
    @Binding var activeRole: UserType
    @State private var region = MKCoordinateRegion(
        center: GeoAppConstants.usMapCenter,
        span: GeoAppConstants.usMapSpan
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: GeoAppConstants.usMapCenter,
        span: GeoAppConstants.usMapSpan
    ))
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var hasInitiallyCentered = false
    @State private var shouldCenterOnLocation = false
    @State private var selectedOpportunity: Opportunity?
    @State private var showOpportunityDetail = false

    private var allOpportunities: [Opportunity] {
        opportunityManager.getAllActiveOpportunities()
    }
    
    /// US-only; seekers also filter jobs by the adjustable search radius when location is available.
    private var mapOpportunities: [Opportunity] {
        let usOnly = allOpportunities.filter {
            GeoAppConstants.isLocationInUS(latitude: $0.location.latitude, longitude: $0.location.longitude)
        }
        guard activeRole == .jobSeeker,
              let coord = userLocation,
              GeoAppConstants.isCoordinateInUS(coord) else {
            return usOnly
        }
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let radiusM = seekerDiscoveryRadius.radiusMeters
        return usOnly.filter {
            let o = CLLocation(latitude: $0.location.latitude, longitude: $0.location.longitude)
            return here.distance(from: o) <= radiusM
        }
    }
    
    var body: some View {
        ZStack {
            // Map View - Show opportunities for job seekers, only user location for hirers
            Map(position: $cameraPosition) {
                ForEach(allAnnotations) { annotation in
                    Annotation("", coordinate: annotation.coordinate, anchor: .bottom) {
                        if annotation.isHomePin {
                            HomePinView()
                        } else if let opportunity = annotation.opportunity {
                            OpportunityPinView(opportunity: opportunity)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedOpportunity = opportunity
                                    }
                                }
                        } else {
                            UserLocationPinView(user: annotation.user, compactStyle: activeRole == .jobSeeker)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .automatic, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false))
            .onMapCameraChange { context in
                region = context.region
            }
            .ignoresSafeArea()
                .onAppear {
                    requestLocationPermission()
                }
                .onReceive(locationManager.$location) { location in
                    if let location = location {
                        // Update user location but don't auto-center unless it's the first time
                        userLocation = CLLocationCoordinate2D(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                        
                        // Only center automatically on first location update
                        if !hasInitiallyCentered {
                            hasInitiallyCentered = true
                            withAnimation(.easeInOut(duration: 1.0)) {
                                let c = userLocation!
                                if GeoAppConstants.isCoordinateInUS(c) {
                                    region = MKCoordinateRegion(
                                        center: c,
                                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                                    )
                                } else {
                                    region = MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: GeoAppConstants.usMapSpan)
                                }
                                cameraPosition = .region(region)
                            }
                        }
                        
                        // Center if user explicitly requested it
                        if shouldCenterOnLocation {
                            shouldCenterOnLocation = false
                            withAnimation(.easeInOut(duration: 1.0)) {
                                let c = userLocation!
                                if GeoAppConstants.isCoordinateInUS(c) {
                                    region = MKCoordinateRegion(
                                        center: c,
                                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                                    )
                                } else {
                                    region = MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: GeoAppConstants.usMapSpan)
                                }
                                cameraPosition = .region(region)
                            }
                        }
                    }
                }
                
                // Map Controls Overlay
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom, spacing: 12) {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            // Enhanced Location Button
                            Button(action: {
                                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                impactMed.impactOccurred()
                                centerMapOnUserLocation()
                            }) {
                                ZStack {
                                    // Outer glow
                                    Circle()
                                        .fill(CommunallyTheme.primaryGreen.opacity(0.3))
                                        .frame(width: 62, height: 62)
                                        .blur(radius: 8)

                                    // Main button
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    CommunallyTheme.primaryGreen,
                                                    CommunallyTheme.secondaryGreen
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

                                    // Icon
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }

                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 120) // Above floating tab bar
                }
            
            // Compact opportunity preview popup
            VStack {
                Spacer()
                
                if let opportunity = selectedOpportunity {
                    CompactOpportunityPreview(opportunity: opportunity) {
                        // Open full detail
                        showOpportunityDetail = true
                    } onClose: {
                        // Close preview
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedOpportunity = nil
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 120) // Above floating tab bar
                    .padding(.horizontal, 16)
                }
            }
            .allowsHitTesting(selectedOpportunity != nil)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedOpportunity != nil)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showOpportunityDetail) {
            if let opportunity = selectedOpportunity {
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func requestLocationPermission() {
        print("🗺️ MapTabView: Requesting location permission")
        locationManager.requestLocationPermissionWithoutCompletion()
        locationManager.startLocationUpdates()
    }
    
    private func centerMapOnUserLocation() {
        if let userLocation = userLocation {
            // Set flag to center on next location update
            shouldCenterOnLocation = true
            // Center and zoom out to default view
            withAnimation(.easeInOut(duration: 1.0)) {
                if GeoAppConstants.isCoordinateInUS(userLocation) {
                    region = MKCoordinateRegion(
                        center: userLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                    )
                } else {
                    region = MKCoordinateRegion(center: GeoAppConstants.usMapCenter, span: GeoAppConstants.usMapSpan)
                }
                cameraPosition = .region(region)
            }
        } else {
            // Request location if not available
            shouldCenterOnLocation = true
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Computed Properties

    /// Coordinate to plot on the public discovery map. Hirers and the
    /// already-accepted applicant see the exact location; everyone else gets
    /// a deterministic jitter (~0–0.005°, roughly 0–550m) seeded by the opp
    /// id so the pin never moves between renders. Address text is already
    /// trimmed to "City, State" by `CompactOpportunityPreview`.
    private func approximateCoordinate(for opportunity: Opportunity) -> CLLocationCoordinate2D {
        let exact = CLLocationCoordinate2D(
            latitude: opportunity.location.latitude,
            longitude: opportunity.location.longitude
        )
        guard let uid = authManager.currentUser?.id else { return exact }
        if opportunity.hirerId == uid { return exact }
        let isAccepted = ApplicationManager.shared.applications.contains {
            $0.opportunityId == opportunity.safeId
                && $0.applicantId == uid
                && $0.status == .accepted
        }
        if isAccepted { return exact }

        let seed = UInt64(bitPattern: Int64(opportunity.safeId.hashValue))
        let latShare = Double(seed % 1_000) / 1_000.0       // 0..<1
        let lonShare = Double((seed / 1_000) % 1_000) / 1_000.0
        let latOffset = (latShare - 0.5) * 0.005             // ±~280m
        let lonOffset = (lonShare - 0.5) * 0.005
        return CLLocationCoordinate2D(
            latitude: exact.latitude + latOffset,
            longitude: exact.longitude + lonOffset
        )
    }

    private var allAnnotations: [MapPinData] {
        var annotations: [MapPinData] = []

        // Opportunities first so the user pin is drawn last and stays on top.
        if activeRole == .jobSeeker {
            for opportunity in mapOpportunities {
                annotations.append(MapPinData(
                    coordinate: approximateCoordinate(for: opportunity),
                    user: nil,
                    opportunity: opportunity
                ))
            }
        }

        // Home pin for hirers (verified home address)
        if activeRole == .jobHirer,
           let lat = authManager.currentUser?.verifiedHomeLatitude,
           let lon = authManager.currentUser?.verifiedHomeLongitude {
            annotations.append(MapPinData(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                user: nil,
                opportunity: nil,
                isHomePin: true
            ))
        }

        if let userLocation = userLocation {
            annotations.append(MapPinData(
                coordinate: userLocation,
                user: authManager.currentUser,
                opportunity: nil
            ))
        }

        return annotations
    }
}

// MARK: - Supporting Data Structures

struct MapPinData: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let user: User?
    let opportunity: Opportunity?
    var isHomePin: Bool = false
}

// MARK: - Home Pin

struct HomePinView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            Circle()
                .strokeBorder(CommunallyTheme.primaryGreen, lineWidth: 2.5)
                .frame(width: 42, height: 42)
            Image(systemName: "house.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CommunallyTheme.primaryGreen)
        }
    }
}

struct UserLocationPinView: View {
    let user: User?
    /// Seekers: smaller anchor and no large pulsing rings (avoids a “big green circle” on the map).
    var compactStyle: Bool = false
    @State private var isAnimating = false
    @State private var isPulsing = false
    
    private var avatarSize: CGFloat { compactStyle ? 48 : 56 }
    /// White + stroke diameter; large enough that a 3pt stroke’s inner edge clears the photo.
    private var ringPlateDiameter: CGFloat { avatarSize + 14 }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !compactStyle {
                    // Soft pulse only *outside* the avatar (no fill over the face)
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(CommunallyTheme.primaryGreen.opacity(0.28), lineWidth: 2)
                            .frame(
                                width: ringPlateDiameter + 20,
                                height: ringPlateDiameter + 20
                            )
                            .scaleEffect(isPulsing ? 1.35 + Double(index) * 0.12 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.55)
                            .animation(
                                .easeOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                                value: isPulsing
                            )
                    }
                }
                
                // Avatar + ring: photo on top, stroke sits on a slightly larger circle *behind* the image
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: ringPlateDiameter, height: ringPlateDiameter)
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    CommunallyTheme.primaryGreen,
                                    CommunallyTheme.secondaryGreen
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: ringPlateDiameter, height: ringPlateDiameter)
                    
                    Group {
                        if let profileImageData = user?.profileImageData,
                           let uiImage = UIImage(data: profileImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                CommunallyTheme.primaryGreen.opacity(0.2),
                                                CommunallyTheme.secondaryGreen.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Image(systemName: "person.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                CommunallyTheme.primaryGreen,
                                                CommunallyTheme.secondaryGreen
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                }
                .scaleEffect(isAnimating ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)
            }
            
            // Location anchor dot
            ZStack {
                if !compactStyle {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .scaleEffect(isPulsing ? 1.8 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
                }
                
                Circle()
                    .fill(Color.white)
                    .frame(width: compactStyle ? 14 : 18, height: compactStyle ? 14 : 18)
                    .shadow(color: .black.opacity(0.2), radius: compactStyle ? 2 : 4, x: 0, y: 2)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.secondaryGreen
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compactStyle ? 9 : 12, height: compactStyle ? 9 : 12)
            }
            .offset(y: -4)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = true
                if !compactStyle {
                    isPulsing = true
                }
            }
        }
    }
}


struct OpportunityPinView: View {
    let opportunity: Opportunity
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Emoji
            Text(JobTypeHelper.emoji(for: opportunity.jobType))
                .font(.system(size: 32))
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPulsing)
            
            // Text box with job info
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.title)
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(opportunity.displayPay)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CommunallyTheme.primaryGreen)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
        }
        .onAppear {
            isPulsing = true
        }
    }
    
    private func iconForJobType(_ type: String) -> String {
        return JobTypeHelper.icon(for: type)
    }
}

// Triangle shape for pin pointer
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Seeker Browse empty state: quick actions + pull-to-refresh (no giant icon stack).
private struct SeekerOpportunitiesDiscoveryEmptyState: View {
    let allOpportunitiesEmpty: Bool
    let onEditProfile: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                        .frame(width: 72, height: 72)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(CommunallyTheme.primaryGreen.opacity(0.8))
                }

                Text(allOpportunitiesEmpty ? "Nothing nearby yet" : "Nothing in your radius yet")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)

                Text(
                    allOpportunitiesEmpty
                        ? "New local gigs show up here when hirers post. Pull down to refresh."
                        : "Widen your search in the gear menu, or check the Map tab. Pull down to refresh."
                )
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick actions")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)

                discoveryCard(
                    icon: "person.crop.circle",
                    title: "Polish your profile",
                    subtitle: "Add a photo, skills, and a short bio.",
                    action: onEditProfile
                )

                discoveryCard(
                    icon: "slider.horizontal.3",
                    title: "Adjust search radius",
                    subtitle: "Tap the gear — set distance from 1 to 5 miles.",
                    action: {
                        NotificationCenter.default.post(name: .communallyOpenSeekerBrowseTools, object: nil)
                    }
                )

                discoveryCard(
                    icon: "bell",
                    title: "Stay in the loop",
                    subtitle: "Enable notifications for new opportunities.",
                    action: {
                        NotificationCenter.default.post(name: .communallyOpenNotifications, object: nil)
                    }
                )
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func discoveryCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(CommunallyTheme.primaryGreen.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Color(red: 0.48, green: 0.48, blue: 0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.65, green: 0.65, blue: 0.65))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct JobSeekerOpportunitiesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var seekerDiscoveryRadius = SeekerDiscoveryRadiusStore.shared
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @State private var selectedOpportunity: Opportunity?
    @State private var showBankSetup = false
    @State private var showEditProfile = false
    @State private var selectedJobType: OpportunityCategory? = nil

    /// O(1) lookup of "did I already apply to this job?" — built once per
    /// render from the seeker's current applications list.
    private var appliedOpportunityIds: Set<String> {
        guard let uid = authManager.currentUser?.id else { return [] }
        return Set(applicationManager.applications
            .filter { $0.applicantId == uid }
            .map { $0.opportunityId })
    }

    // TODO: Set this back to true if we want bank setup to gate browsing again later.
    // Keep real payout/payment security in the payment flow itself.
    /// Gate the seeker browse list behind bank-account setup. Until they
    /// connect a payout account, the real list is replaced with a fixed
    /// stack of decoy locked cards so they can't even tell whether jobs
    /// exist nearby — pushes them to finish payout setup before browsing.
    private let requiresBankSetupToBrowse = true

    private var allOpportunities: [Opportunity] {
        opportunityManager.getAllActiveOpportunities()
    }

    private var visibleOpportunities: [Opportunity] {
        let us = allOpportunities.filter {
            GeoAppConstants.isLocationInUS(latitude: $0.location.latitude, longitude: $0.location.longitude)
        }
        let byRadius: [Opportunity]
        if let loc = locationManager.location, GeoAppConstants.isCoordinateInUS(loc.coordinate) {
            let radiusM = seekerDiscoveryRadius.radiusMeters
            byRadius = us.filter {
                let o = CLLocation(latitude: $0.location.latitude, longitude: $0.location.longitude)
                return loc.distance(from: o) <= radiusM
            }
        } else {
            byRadius = us
        }
        guard let category = selectedJobType else { return byRadius }
        return byRadius.filter { $0.jobType == category.rawValue }
    }
    
    private var hasBankAccount: Bool {
        authManager.currentUser?.hasBankAccount ?? false
    }
    
    private var shouldLockOpportunities: Bool {
        requiresBankSetupToBrowse && !hasBankAccount
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Beautiful green-to-white gradient background
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // (Top "Jobs are locked" banner removed — the
                        // `LockedDecoyOpportunityList` further down already
                        // carries the lock CTA, so the top banner was redundant.)

                        // Job type filter chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "All" chip
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { selectedJobType = nil }
                                } label: {
                                    Text("All")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(selectedJobType == nil ? .white : CommunallyTheme.darkGray)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedJobType == nil ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.12))
                                        )
                                }

                                ForEach(OpportunityCategory.allCases) { category in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedJobType = selectedJobType == category ? nil : category
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(category.emoji)
                                                .font(.system(size: 13))
                                            Text(category.rawValue)
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .foregroundColor(selectedJobType == category ? .white : CommunallyTheme.darkGray)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedJobType == category ? category.color : Color.gray.opacity(0.12))
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal, -20)

                        // Opportunities List (US + within chosen radius when location known) — same compact rows as My Jobs.
                        // Bank-gate short-circuit: fixed decoy stack so the
                        // seeker can't infer whether real jobs exist.
                        if shouldLockOpportunities {
                            LockedDecoyOpportunityList(onUnlockTap: { showBankSetup = true })
                        } else if visibleOpportunities.isEmpty {
                            if selectedJobType != nil {
                                Text("No \(selectedJobType!.rawValue.lowercased()) opportunities nearby.")
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else {
                            SeekerOpportunitiesDiscoveryEmptyState(
                                allOpportunitiesEmpty: allOpportunities.isEmpty,
                                onEditProfile: { showEditProfile = true }
                            )
                            }
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visibleOpportunities) { opportunity in
                                    ZStack {
                                        OpportunityCompactListRow(
                                            opportunity: opportunity,
                                            subtitle: opportunity.compactListSubtitleSeeker,
                                            showApplicantBadge: opportunity.applicantCount > 0,
                                            onTap: {
                                                if !shouldLockOpportunities {
                                                    selectedOpportunity = opportunity
                                                } else {
                                                    showBankSetup = true
                                                }
                                            },
                                            onDelete: nil
                                        )
                                        .blur(radius: shouldLockOpportunities ? 1.5 : 0)
                                        .opacity(shouldLockOpportunities ? 0.68 : 1)

                                        if shouldLockOpportunities {
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(Color.black.opacity(0.28))
                                                .allowsHitTesting(false)
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.white)
                                                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                        
                        Spacer(minLength: 120) // Space for floating tab bar
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    locationManager.requestLocation()
                    await opportunityManager.fetchOpportunities()
                }
            }
            .navigationTitle("Opportunities")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
            .sheet(isPresented: $showBankSetup) {
                BankSetupSheet()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showEditProfile) {
                NavigationView {
                    if let user = authManager.currentUser {
                        EditProfileView(user: user)
                            .environmentObject(authManager)
                    }
                }
            }
            .onAppear {
                locationManager.requestLocationPermissionWithoutCompletion()
                locationManager.startLocationUpdates()
            }
        }
    }
}

struct BankSetupPromoBanner: View {
    @Binding var showBankSetup: Bool
    
    var body: some View {
        Button(action: {
            showBankSetup = true
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.15, green: 0.7, blue: 0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Jobs are locked")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))

                    Text("Connect your payout account to see what's nearby")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 1.0, blue: 0.96), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(
                                CommunallyTheme.primaryGreen.opacity(0.22),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LockedOpportunityCard: View {
    let opportunity: Opportunity
    let isLocked: Bool
    
    var body: some View {
        ZStack {
            PostedOpportunityCard(opportunity: opportunity, showExactLocation: false)
                .opacity(isLocked ? 0.6 : 1.0)
                .blur(radius: isLocked ? 2 : 0)
            
            if isLocked {
                // Lock overlay
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.5), radius: 15, x: 0, y: 8)
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 6) {
                        Text("Payment Setup Required")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        
                        Text("Tap to set up payments & unlock")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundColor(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.75))
                        .blur(radius: 20)
                )
            }
        }
    }
}

/// Bank-gate placeholder shown to seekers without a payout account. Renders
/// a fixed stack of decoy "job" cards so the seeker can't tell whether real
/// jobs exist nearby — the count, titles, and pay are all faked. Tapping
/// anywhere opens the bank-setup sheet via `onUnlockTap`.
struct LockedDecoyOpportunityList: View {
    let onUnlockTap: () -> Void

    /// Static decoy cards. Picked to be plausibly varied across categories
    /// (gardening, errands, tutoring, pets) so the blur shape doesn't read
    /// as identical rows. Pay numbers stay generic.
    private let decoys: [(emoji: String, title: String, pay: String)] = [
        ("🌿", "Yard cleanup",       "$45"),
        ("📦", "Help moving boxes",  "$60"),
        ("🐕", "Dog walk",           "$25"),
        ("📚", "Tutoring session",   "$35")
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                ForEach(decoys.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Text(decoys[i].emoji)
                            .font(.system(size: 26))
                            .frame(width: 46, height: 46)
                            .background(
                                Circle().fill(CommunallyTheme.primaryGreen.opacity(0.10))
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(decoys[i].title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                            HStack(spacing: 6) {
                                Image(systemName: "location.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                                Text("Nearby")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                            }
                        }
                        Spacer()
                        Text(decoys[i].pay)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                    )
                }
            }
            .blur(radius: 7)
            .opacity(0.55)
            .allowsHitTesting(false)

            // Centered lock + CTA
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.45), radius: 16, x: 0, y: 8)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(spacing: 4) {
                    Text("Connect a payout account to unlock")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .multilineTextAlignment(.center)
                    Text("Real jobs near you stay hidden until your bank info is in.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                Button(action: onUnlockTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Set up payouts")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.40), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 18)
        }
        // Whole stack tappable so even the blurred regions trigger the gate.
        .contentShape(Rectangle())
        .onTapGesture { onUnlockTap() }
    }
}

struct JobHirerOpportunitiesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var showPostOpportunity = false
    @State private var selectedOpportunity: Opportunity?
    
    private var userOpportunities: [Opportunity] {
        guard let userId = authManager.currentUser?.id else { return [] }
        return opportunityManager.getUserOpportunities(userId: userId)
    }
    
    private var totalApplicants: Int {
        userOpportunities.reduce(0) { $0 + $1.applicantCount }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Enhanced Post New Opportunity Button with fun design
                    Button(action: {
                        showPostOpportunity = true
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                // Outer glow
                                Circle()
                                    .fill(Color(red: 1.0, green: 0.5, blue: 0.3).opacity(0.3))
                                    .frame(width: 62, height: 62)
                                    .blur(radius: 8)
                                
                                // Icon background
                                Circle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Post New Opportunity")
                                    .font(.system(size: 20, weight: .bold, design: .default))
                                
                                Text("Create a job or volunteer posting")
                                    .font(.system(size: 14, weight: .medium, design: .default))
                                    .opacity(0.9)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .opacity(0.9)
                        }
                        .foregroundColor(.white)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.45, blue: 0.3),  // Coral
                                            Color(red: 1.0, green: 0.6, blue: 0.4)    // Light coral
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color(red: 1.0, green: 0.5, blue: 0.3).opacity(0.4), radius: 20, x: 0, y: 10)
                                .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                        )
                    }
                    .pulsingButton()
                    
                    // Quick Stats Cards with fun colors
                    HStack(spacing: 16) {
                        FunStatCard(
                            title: "Active Posts",
                            value: "\(userOpportunities.count)",
                            icon: "briefcase.fill",
                            gradientColors: [
                                Color(red: 0.4, green: 0.7, blue: 1.0),   // Sky blue
                                Color(red: 0.5, green: 0.8, blue: 1.0)    // Light blue
                            ]
                        )
                        
                        FunStatCard(
                            title: "Applications",
                            value: "\(totalApplicants)",
                            icon: "person.2.fill",
                            gradientColors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.lightGreen
                            ]
                        )
                    }
                    
                    // Posted Opportunities Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Your Posted Opportunities")
                                .font(CommunallyTheme.titleFont)
                                .fontWeight(.bold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Spacer()
                            
                            if !userOpportunities.isEmpty {
                                Button(action: {}) {
                                    Text("View All")
                                        .font(CommunallyTheme.captionFont)
                                        .fontWeight(.medium)
                                        .foregroundColor(CommunallyTheme.primaryGreen)
                                }
                            }
                        }
                        
                        if userOpportunities.isEmpty {
                            EmptyStateView(
                                title: "No opportunities posted",
                                message: "Create your first job posting to get started and connect with local talent",
                                actionTitle: "Refresh",
                                action: {}
                            )
                        } else {
                            ForEach(userOpportunities) { opportunity in
                                Button(action: {
                                    selectedOpportunity = opportunity
                                }) {
                                    PostedOpportunityCard(opportunity: opportunity)
                                }
                                .smoothButton()
                            }
                        }
                    }
                    
                    Spacer(minLength: 120) // Space for floating tab bar
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Opportunities")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showPostOpportunity) {
                PostOpportunityView()
            }
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(CommunallyTheme.darkGray)
            
            Text(title)
                .font(CommunallyTheme.captionFont)
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct FunStatCard: View {
    let title: String
    let value: String
    let icon: String
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(gradientColors[0].opacity(0.3))
                    .frame(width: 56, height: 56)
                    .blur(radius: 12)
                
                // Icon background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: gradientColors[0].opacity(0.2), radius: 15, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
}

struct PostedOpportunityCard: View {
    let opportunity: Opportunity
    var showExactLocation: Bool = true // Default to showing exact location
    
    var cardColor: Color {
        return JobTypeHelper.color(for: opportunity.jobType)
    }
    
    // General location name (city/state only)
    var displayLocationName: String {
        if showExactLocation {
            return opportunity.locationName
        } else {
            // Extract city/area from full location name
            let components = opportunity.locationName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count >= 2 {
                return components.suffix(2).joined(separator: ", ")
            }
            return opportunity.locationName
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header - Profile + Title/Location + Pay
            HStack(spacing: 14) {
                // Profile picture
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(cardColor.opacity(0.3))
                        .frame(width: 66, height: 66)
                        .blur(radius: 8)
                    
                    if let imageData = opportunity.hirerImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [cardColor, cardColor.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: cardColor.opacity(0.4), radius: 8, x: 0, y: 4)
                    } else {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [cardColor, cardColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 58, height: 58)
                                .shadow(color: cardColor.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Title and location
                VStack(alignment: .leading, spacing: 6) {
                    Text(opportunity.title)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: showExactLocation ? "mappin.circle.fill" : "location.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(cardColor)
                        
                        Text(displayLocationName)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Pay amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(opportunity.displayPay)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text(opportunity.timeAgo)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
            
            // Description
            Text(opportunity.description)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                .lineLimit(2)
                .lineSpacing(4)
            
            // Footer - Status + Job Icon + Applicants
            HStack(spacing: 12) {
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(opportunity.statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(opportunity.statusDisplay)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(opportunity.statusColor.opacity(0.15))
                )
                
                Spacer()
                
                // Job type emoji
                Text(JobTypeHelper.emoji(for: opportunity.jobType))
                    .font(.system(size: 28))
                
                // Applicants count
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(cardColor)
                    
                    Text("\(opportunity.applicantCount)")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(cardColor.opacity(0.15))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color(red: 0.99, green: 1.0, blue: 0.99)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: cardColor.opacity(0.2), radius: 20, x: 0, y: 10)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.1), radius: 15, x: 0, y: 8)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
    
    private func iconForJobType(_ type: String) -> String {
        return JobTypeHelper.icon(for: type)
    }
}

// MARK: - Compact Opportunity Preview (Map Popup)
struct CompactOpportunityPreview: View {
    let opportunity: Opportunity
    let onViewDetails: () -> Void
    let onClose: () -> Void
    
    private var cardColor: Color {
        return JobTypeHelper.color(for: opportunity.jobType)
    }
    
    // General location name (city/state only) for privacy
    private var displayLocationName: String {
        let components = opportunity.locationName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count >= 2 {
            return components.suffix(2).joined(separator: ", ")
        }
        return opportunity.locationName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Hirer profile picture
                if let imageData = opportunity.hirerImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(cardColor, lineWidth: 2.5)
                        )
                } else {
                    ZStack {
                        Circle()
                            .fill(cardColor.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(cardColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(opportunity.title)
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(cardColor)

                        Text(displayLocationName)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                            .lineLimit(1)
                    }

                    // Privacy reassurance — the map pin is intentionally
                    // jittered until the seeker is accepted.
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(cardColor.opacity(0.85))
                        Text("Exact address shared after you're accepted")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Job type emoji
                Text(JobTypeHelper.emoji(for: opportunity.jobType))
                    .font(.system(size: 32))
                
                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                }
            }
            .padding(16)
            
            // Divider
            Rectangle()
                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                .frame(height: 1)
            
            // Details section
            HStack(spacing: 16) {
                // Pay
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    
                    Text(opportunity.displayPay)
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
                
                Spacer()
                
                // View Details button
                Button(action: {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    onViewDetails()
                }) {
                    HStack(spacing: 6) {
                        Text("View Details")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [cardColor, cardColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: cardColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                .shadow(color: cardColor.opacity(0.2), radius: 15, x: 0, y: 8)
        )
    }
    
    private func iconForJobType(_ type: String) -> String {
        return JobTypeHelper.icon(for: type)
    }
}

// MARK: - Role Mode Banner
// MARK: - Development Mode Banner
struct DevelopmentModeBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            // Warning icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Development Mode")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                Text("Local data only • No Firebase")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange,
                            Color.orange.opacity(0.85)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct RoleModeBanner: View {
    let activeRole: UserType
    @State private var isShimmering = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: activeRole == .jobSeeker ? "person.fill" : "briefcase.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activeRole == .jobSeeker ? "Finding Jobs Mode" : "Posting Jobs Mode")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                Text(activeRole == .jobSeeker ? "Browse & Apply" : "Post & Manage")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen,
                            CommunallyTheme.primaryGreen.opacity(0.85)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isShimmering = true
            }
        }
    }
}

// MARK: - Role Switcher Button
struct RoleSwitcherButton: View {
    @Binding var activeRole: UserType
    @Binding var showBanner: Bool
    @State private var isAnimating = false
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: switchRole) {
            ZStack {
                // Background Circle with pulse effect
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.2), radius: 15, x: 0, y: 8)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)
                
                // Icon with role indicator
                VStack(spacing: 2) {
                    Image(systemName: activeRole == .jobSeeker ? "person.fill" : "briefcase.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    
                    // Swap arrows indicator
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.6))
                }
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func switchRole() {
        // Haptic feedback
        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
        impactHeavy.impactOccurred()
        
        // Animate pulse
        withAnimation(.easeInOut(duration: 0.15)) {
            isPulsing = true
        }
        
        // Switch role with rotation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            activeRole = activeRole == .jobSeeker ? .jobHirer : .jobSeeker
            isAnimating = true
            showBanner = true
        }
        
        // Reset animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                isAnimating = false
                isPulsing = false
            }
        }
    }
}

// MARK: - Notification Bell Button
struct NotificationBellButton: View {
    @Binding var showNotifications: Bool
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var isWiggling = false
    @State private var previousUnreadCount = 0
    
    var body: some View {
        Button(action: openNotifications) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.15), radius: 10, x: 0, y: 6)
                
                Image(systemName: notificationManager.unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(isWiggling ? -10 : 0))
                
                // Notification Badge
                if notificationManager.unreadCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.red.opacity(0.5), radius: 4, x: 0, y: 2)
                        
                        Text("\(min(notificationManager.unreadCount, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onChange(of: notificationManager.unreadCount) { oldValue, newValue in
            // Wiggle animation when new notification arrives
            if newValue > oldValue && newValue > 0 {
                wiggleBell()
            }
        }
    }
    
    private func openNotifications() {
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        showNotifications = true
    }
    
    private func wiggleBell() {
        // Wiggle animation
        withAnimation(.easeInOut(duration: 0.1).repeatCount(4, autoreverses: true)) {
            isWiggling = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                isWiggling = false
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
