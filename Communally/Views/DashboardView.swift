//
//  DashboardView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import MapKit

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0
    @State private var showNotifications = false
    @State private var activeRole: UserType
    @State private var showRoleBanner = true
    
    init() {
        // Initialize activeRole based on the user's default type
        _activeRole = State(initialValue: AuthenticationManager.shared.currentUser?.userType ?? .jobSeeker)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab Content - Show the selected view based on active role
            Group {
                switch selectedTab {
                case 0:
                    MapTabView(activeRole: $activeRole)
                        .id("map-\(selectedTab)-\(activeRole.rawValue)")
                case 1:
                    if activeRole == .jobSeeker {
                        JobSeekerOpportunitiesView()
                            .id("opportunities-\(selectedTab)")
                    } else {
                        JobHirerOpportunitiesView()
                            .id("opportunities-\(selectedTab)")
                    }
                case 2:
                    if activeRole == .jobSeeker {
                        MyApplicationsView()
                            .id("applications-\(selectedTab)")
                    } else {
                        MessagingView()
                            .id("messages-\(selectedTab)")
                    }
                case 3:
                    if activeRole == .jobSeeker {
                        MessagingView()
                            .id("messages-\(selectedTab)")
                    } else {
                        ProfileView()
                            .id("profile-\(selectedTab)")
                    }
                case 4:
                    ProfileView()
                        .id("profile-\(selectedTab)")
                default:
                    MapTabView(activeRole: $activeRole)
                        .id("map-default")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Buttons - Top Right
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        RoleSwitcherButton(activeRole: $activeRole, showBanner: $showRoleBanner)
                        NotificationBellButton(showNotifications: $showNotifications)
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // Role Mode Banner - Shows temporarily when switching
            if showRoleBanner {
                VStack {
                    RoleModeBanner(activeRole: activeRole)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
            
            // Custom Floating Tab Bar
            FloatingTabBar(selectedTab: $selectedTab, userType: activeRole)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environmentObject(authManager)
        }
        .onAppear {
            // Start listening to messages and notifications when dashboard loads
            if let userId = authManager.currentUser?.id {
                MessageManager.shared.startListening(for: userId)
                NotificationManager.shared.startListening(for: userId)
            }
            
            // Show banner initially for 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showRoleBanner = false
                }
            }
        }
        .onChange(of: activeRole) {
            // Reset to map when switching roles for better UX
            selectedTab = 0
            
            // Show banner when role changes
            withAnimation {
                showRoleBanner = true
            }
            
            // Hide banner after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showRoleBanner = false
                }
            }
        }
    }
}

// MARK: - Floating Tab Bar
struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let userType: UserType
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @EnvironmentObject var authManager: AuthenticationManager
    
    private var acceptedApplicationsCount: Int {
        guard let userId = authManager.currentUser?.id else { return 0 }
        return applicationManager.getApplications(byUser: userId)
            .filter { $0.status == .accepted }
            .count
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Map Tab
            FloatingTabItem(
                icon: selectedTab == 0 ? "map.fill" : "map",
                title: "Map",
                isSelected: selectedTab == 0
            ) {
                if selectedTab != 0 {
                    selectedTab = 0
                }
            }
            
            // Opportunities Tab
            FloatingTabItem(
                icon: selectedTab == 1 ? "briefcase.fill" : "briefcase",
                title: userType == .jobSeeker ? "Browse" : "Opportunities",
                isSelected: selectedTab == 1
            ) {
                if selectedTab != 1 {
                    selectedTab = 1
                }
            }
            
            // My Applications Tab (Job Seekers Only)
            if userType == .jobSeeker {
                FloatingTabItem(
                    icon: selectedTab == 2 ? "doc.text.fill" : "doc.text",
                    title: "Applications",
                    isSelected: selectedTab == 2,
                    badgeCount: acceptedApplicationsCount
                ) {
                    if selectedTab != 2 {
                        selectedTab = 2
                    }
                }
            }
            
            // Messages Tab
            FloatingTabItem(
                icon: userType == .jobSeeker ? 
                    (selectedTab == 3 ? "message.fill" : "message") :
                    (selectedTab == 2 ? "message.fill" : "message"),
                title: "Messages",
                isSelected: userType == .jobSeeker ? selectedTab == 3 : selectedTab == 2
            ) {
                if userType == .jobSeeker {
                    if selectedTab != 3 {
                        selectedTab = 3
                    }
                } else {
                    if selectedTab != 2 {
                        selectedTab = 2
                    }
                }
            }
            
            // Profile Tab
            FloatingTabItem(
                icon: userType == .jobSeeker ?
                    (selectedTab == 4 ? "person.crop.circle.fill" : "person.crop.circle") :
                    (selectedTab == 3 ? "person.crop.circle.fill" : "person.crop.circle"),
                title: "Profile",
                isSelected: userType == .jobSeeker ? selectedTab == 4 : selectedTab == 3
            ) {
                if userType == .jobSeeker {
                    if selectedTab != 4 {
                        selectedTab = 4
                    }
                } else {
                    if selectedTab != 3 {
                        selectedTab = 3
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.1), radius: 30, x: 0, y: 15)
        )
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
                        .foregroundColor(isSelected ? CommunallyTheme.primaryGreen : Color.white.opacity(0.6))
                        .frame(height: 24)
                    
                    // Badge for notifications
                    if let count = badgeCount, count > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 16, height: 16)
                            
                            Text("\(min(count, 9))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 8, y: -4)
                    }
                }
                
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? CommunallyTheme.primaryGreen : Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? CommunallyTheme.primaryGreen.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MapTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var locationManager = LocationManager()
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @Binding var activeRole: UserType
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco fallback
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    ))
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var hasInitiallyCentered = false
    @State private var shouldCenterOnLocation = false
    @State private var selectedOpportunity: Opportunity?
    @State private var showOpportunityDetail = false
    
    var body: some View {
        ZStack {
            // Map View - Show opportunities for job seekers, only user location for hirers
            Map(position: $cameraPosition) {
                ForEach(allAnnotations) { annotation in
                    Annotation("", coordinate: annotation.coordinate) {
                        if let opportunity = annotation.opportunity {
                            // Opportunity pin
                            OpportunityPinView(opportunity: opportunity)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedOpportunity = opportunity
                                    }
                                }
                        } else {
                            // User location pin with profile picture
                            UserLocationPinView(user: annotation.user)
                        }
                    }
                }
            }
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
                                region.center = userLocation!
                                cameraPosition = .region(region)
                            }
                        }
                        
                        // Center if user explicitly requested it
                        if shouldCenterOnLocation {
                            shouldCenterOnLocation = false
                            withAnimation(.easeInOut(duration: 1.0)) {
                                region.center = userLocation!
                                cameraPosition = .region(region)
                            }
                        }
                    }
                }
                
                // Map Controls Overlay
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
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
                        .padding(.trailing, 20)
                        .padding(.bottom, 120) // Above floating tab bar
                    }
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
    }
    
    private func centerMapOnUserLocation() {
        if let userLocation = userLocation {
            // Set flag to center on next location update
            shouldCenterOnLocation = true
            // Center immediately if we have location
            withAnimation(.easeInOut(duration: 1.0)) {
                region.center = userLocation
                cameraPosition = .region(region)
            }
        } else {
            // Request location if not available
            shouldCenterOnLocation = true
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Computed Properties
    
    private var allAnnotations: [MapPinData] {
        var annotations: [MapPinData] = []
        
        // Add user location
        if let userLocation = userLocation {
            annotations.append(MapPinData(
                coordinate: userLocation,
                user: authManager.currentUser,
                opportunity: nil
            ))
        }
        
        // Add opportunities for job seekers only
        if activeRole == .jobSeeker {
            let opportunities = opportunityManager.getAllActiveOpportunities()
            for opportunity in opportunities {
                let coordinate = CLLocationCoordinate2D(
                    latitude: opportunity.location.latitude,
                    longitude: opportunity.location.longitude
                )
                annotations.append(MapPinData(
                    coordinate: coordinate,
                    user: nil,
                    opportunity: opportunity
                ))
            }
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
}

struct UserLocationPinView: View {
    let user: User?
    @State private var isAnimating = false
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Outer pulsing rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(CommunallyTheme.primaryGreen.opacity(0.3), lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(isPulsing ? 1.5 + Double(index) * 0.3 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.6)
                        .animation(
                            .easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: isPulsing
                        )
                }
                
                // Gradient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CommunallyTheme.primaryGreen.opacity(0.4),
                                CommunallyTheme.primaryGreen.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 45
                        )
                    )
                    .frame(width: 90, height: 90)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)
                
                // Profile Picture Container with enhanced styling
                ZStack {
                    // Shadow layer
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 72, height: 72)
                        .blur(radius: 8)
                        .offset(y: 4)
                    
                    // White border with gradient accent
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            CommunallyTheme.primaryGreen,
                                            CommunallyTheme.secondaryGreen
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                        )
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    // Profile Picture or Default Image
                    Group {
                        if let profileImageData = user?.profileImageData,
                           let uiImage = UIImage(data: profileImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            // Default profile image with gradient
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
                                    .font(.system(size: 32, weight: .semibold))
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
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                }
                .scaleEffect(isAnimating ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)
            }
            
            // Location indicator dot with enhanced pulsing
            ZStack {
                // Pulsing outer glow
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
                
                // White border
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                // Inner gradient dot
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
                    .frame(width: 12, height: 12)
            }
            .offset(y: -4)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = true
                isPulsing = true
            }
        }
    }
}


struct OpportunityPinView: View {
    let opportunity: Opportunity
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Icon background with job type icon
            ZStack {
                // Outer pulsing glow
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.4))
                    .frame(width: 68, height: 68)
                    .blur(radius: 10)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0.3 : 0.6)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isPulsing)
                
                // Gradient ring
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
                    .frame(width: 56, height: 56)
                    .blur(radius: 3)
                
                // Main circle with gradient border
                Circle()
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .strokeBorder(
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
                    )
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 8, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                
                // Job type icon with gradient
                Image(systemName: iconForJobType(opportunity.jobType))
                    .font(.system(size: 24, weight: .semibold))
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
            
            // Enhanced pointer triangle
            ZStack {
                // Shadow for triangle
                Triangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 16, height: 10)
                    .offset(y: -1)
                    .blur(radius: 2)
                
                Triangle()
                    .fill(Color.white)
                    .frame(width: 14, height: 9)
                    .overlay(
                        Triangle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        CommunallyTheme.primaryGreen,
                                        CommunallyTheme.secondaryGreen
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2.5
                            )
                    )
                    .offset(y: -2)
            }
        }
        .onAppear {
            isPulsing = true
        }
    }
    
    private func iconForJobType(_ type: String) -> String {
        switch type.lowercased() {
        case "gardening": return "leaf.fill"
        case "pet care": return "pawprint.fill"
        case "tutoring": return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting": return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help": return "calendar.badge.plus"
        case "cleaning": return "sparkles"
        case "delivery": return "shippingbox.fill"
        default: return "briefcase.fill"
        }
    }
}

// Triangle shape for pin pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}


struct JobSeekerOpportunitiesView: View {
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var searchText = ""
    @State private var selectedOpportunity: Opportunity?
    @State private var showFilters = false
    @State private var isSearchFocused = false
    
    // Filter states
    @State private var selectedJobTypes: Set<String> = []
    @State private var minPay: Double = 0
    @State private var maxPay: Double = 1000
    @State private var maxDistance: Double = 50 // miles
    @State private var selectedCategories: Set<String> = []
    
    private var allOpportunities: [Opportunity] {
        opportunityManager.getAllActiveOpportunities()
    }
    
    private var filteredOpportunities: [Opportunity] {
        var opportunities = allOpportunities
        
        // Apply search filter
        if !searchText.isEmpty {
            opportunities = opportunities.filter { opportunity in
                opportunity.title.localizedCaseInsensitiveContains(searchText) ||
                opportunity.description.localizedCaseInsensitiveContains(searchText) ||
                opportunity.locationName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply job type filter
        if !selectedJobTypes.isEmpty {
            // Add filtering logic when job types are added to Opportunity model
        }
        
        // Apply pay range filter
        opportunities = opportunities.filter { opportunity in
            guard let payAmountString = opportunity.payAmount,
                  let payAmountDouble = Double(payAmountString) else {
                // Include volunteer opportunities or those without pay amount
                return opportunity.isVolunteer || minPay == 0
            }
            return payAmountDouble >= minPay && payAmountDouble <= maxPay
        }
        
        // Apply category filter
        if !selectedCategories.isEmpty {
            // Add filtering logic when categories are added to Opportunity model
        }
        
        return opportunities
    }
    
    private var hasActiveFilters: Bool {
        !selectedJobTypes.isEmpty || minPay > 0 || maxPay < 1000 || !selectedCategories.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Enhanced Search Bar with Filter Button
                    HStack(spacing: 12) {
                        // Search Icon with pulse animation
                        ZStack {
                            if isSearchFocused {
                                Circle()
                                    .fill(CommunallyTheme.primaryGreen.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .scaleEffect(1.2)
                                    .opacity(0.5)
                            }
                            
                            Image(systemName: isSearchFocused ? "magnifyingglass.circle.fill" : "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSearchFocused)
                        
                        TextField("Search opportunities...", text: $searchText)
                            .font(CommunallyTheme.bodyFont)
                            .foregroundColor(CommunallyTheme.darkGray)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isSearchFocused = true
                                }
                            }
                            .onChange(of: searchText) {
                                if searchText.isEmpty {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isSearchFocused = false
                                    }
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    searchText = ""
                                    isSearchFocused = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Filter Button with badge
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                showFilters.toggle()
                            }
                            
                            // Haptic feedback
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                        }) {
                            ZStack(alignment: .topTrailing) {
                                // Filter icon with gradient background
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: hasActiveFilters ? 
                                                    [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)] :
                                                    [Color.white, Color.white],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(hasActiveFilters ? .white : CommunallyTheme.primaryGreen)
                                }
                                .shadow(color: hasActiveFilters ? CommunallyTheme.primaryGreen.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                                .scaleEffect(showFilters ? 0.95 : 1.0)
                                .rotationEffect(.degrees(showFilters ? 180 : 0))
                                
                                // Active filter badge
                                if hasActiveFilters {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: isSearchFocused ? 16 : 12)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: isSearchFocused ? 16 : 12)
                                    .stroke(
                                        isSearchFocused ? 
                                            CommunallyTheme.primaryGreen.opacity(0.6) : 
                                            CommunallyTheme.primaryGreen.opacity(0.3), 
                                        lineWidth: isSearchFocused ? 2 : 1
                                    )
                            )
                    )
                    .shadow(
                        color: isSearchFocused ? CommunallyTheme.primaryGreen.opacity(0.15) : .black.opacity(0.08), 
                        radius: isSearchFocused ? 12 : 8, 
                        x: 0, 
                        y: isSearchFocused ? 6 : 4
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSearchFocused)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasActiveFilters)
                    
                    // Quick Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            FilterChip(title: "All", isSelected: true) {}
                            FilterChip(title: "Volunteer", isSelected: false) {}
                            FilterChip(title: "Remote", isSelected: false) {}
                        }
                    }
                    
                    // Opportunities List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Available Opportunities")
                                .font(CommunallyTheme.titleFont)
                                .fontWeight(.bold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Spacer()
                            
                            Text("\(filteredOpportunities.count) found")
                                .font(CommunallyTheme.captionFont)
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                        }
                        
                        if filteredOpportunities.isEmpty {
                            EmptyStateView(
                                title: searchText.isEmpty && !hasActiveFilters ? "No opportunities yet" : "No matches found",
                                message: searchText.isEmpty && !hasActiveFilters ? 
                                    "Check back later for new job postings in your area" :
                                    "Try adjusting your search or filters",
                                actionTitle: hasActiveFilters ? "Clear Filters" : "Refresh",
                                action: {
                                    if hasActiveFilters {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            clearFilters()
                                        }
                                    }
                                }
                            )
                        } else {
                            ForEach(filteredOpportunities) { opportunity in
                                Button(action: {
                                    selectedOpportunity = opportunity
                                }) {
                                    PostedOpportunityCard(opportunity: opportunity)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
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
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheetView(
                    selectedJobTypes: $selectedJobTypes,
                    minPay: $minPay,
                    maxPay: $maxPay,
                    maxDistance: $maxDistance,
                    selectedCategories: $selectedCategories,
                    onClear: clearFilters
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func clearFilters() {
        selectedJobTypes = []
        minPay = 0
        maxPay = 1000
        maxDistance = 50
        selectedCategories = []
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CommunallyTheme.captionFont)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : CommunallyTheme.primaryGreen)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? CommunallyTheme.buttonGradient : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(CommunallyTheme.primaryGreen, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FilterSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedJobTypes: Set<String>
    @Binding var minPay: Double
    @Binding var maxPay: Double
    @Binding var maxDistance: Double
    @Binding var selectedCategories: Set<String>
    let onClear: () -> Void
    
    let jobTypes = ["Paid", "Volunteer", "Internship", "Part-Time", "Full-Time", "Contract"]
    let categories = ["Technology", "Healthcare", "Education", "Retail", "Food Service", "Construction", "Creative", "Other"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header with animated icon
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 56, height: 56)
                                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 12, x: 0, y: 6)
                            
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Filter Opportunities")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Text("Find your perfect match")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Job Type Section
                    FilterSection(title: "Job Type", icon: "briefcase.fill") {
                        FlowLayout(spacing: 10) {
                            ForEach(jobTypes, id: \.self) { type in
                                FilterTag(
                                    title: type,
                                    isSelected: selectedJobTypes.contains(type)
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if selectedJobTypes.contains(type) {
                                            selectedJobTypes.remove(type)
                                        } else {
                                            selectedJobTypes.insert(type)
                                        }
                                    }
                                    
                                    // Haptic feedback
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Pay Range Section
                    FilterSection(title: "Pay Range", icon: "dollarsign.circle.fill") {
                        VStack(spacing: 16) {
                            HStack {
                                Text("$\(Int(minPay))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .frame(minWidth: 60, alignment: .leading)
                                
                                Spacer()
                                
                                Text("$\(Int(maxPay))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                            
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Text("Min")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                                        .frame(width: 40, alignment: .leading)
                                    
                                    Slider(value: $minPay, in: 0...maxPay, step: 5)
                                        .tint(CommunallyTheme.primaryGreen)
                                }
                                
                                HStack(spacing: 12) {
                                    Text("Max")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                                        .frame(width: 40, alignment: .leading)
                                    
                                    Slider(value: $maxPay, in: minPay...1000, step: 5)
                                        .tint(CommunallyTheme.primaryGreen)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Distance Section
                    FilterSection(title: "Maximum Distance", icon: "location.circle.fill") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("\(Int(maxDistance)) miles")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                
                                Spacer()
                                
                                Text(maxDistance >= 50 ? "Any distance" : "Nearby")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            }
                            
                            Slider(value: $maxDistance, in: 1...50, step: 1)
                                .tint(CommunallyTheme.primaryGreen)
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Categories Section
                    FilterSection(title: "Categories", icon: "square.grid.2x2.fill") {
                        FlowLayout(spacing: 10) {
                            ForEach(categories, id: \.self) { category in
                                FilterTag(
                                    title: category,
                                    isSelected: selectedCategories.contains(category)
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if selectedCategories.contains(category) {
                                            selectedCategories.remove(category)
                                        } else {
                                            selectedCategories.insert(category)
                                        }
                                    }
                                    
                                    // Haptic feedback
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.bottom, 100)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onClear()
                        }
                        
                        // Haptic feedback
                        let notification = UINotificationFeedbackGenerator()
                        notification.notificationOccurred(.success)
                    }) {
                        Text("Clear All")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Apply Button
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        dismiss()
                    }
                    
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Text("Apply Filters")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.97, green: 0.97, blue: 0.97), Color(red: 0.97, green: 0.97, blue: 0.97).opacity(0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 120)
                    .offset(y: 20)
                )
            }
        }
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
            }
            
            content
        }
        .padding(.horizontal, 20)
    }
}

struct FilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : CommunallyTheme.primaryGreen)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ? 
                            LinearGradient(
                                colors: [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white, Color.white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(CommunallyTheme.primaryGreen, lineWidth: isSelected ? 0 : 1.5)
                    )
                    .shadow(
                        color: isSelected ? CommunallyTheme.primaryGreen.opacity(0.3) : .clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// Flow Layout for wrapping tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        
        for row in rows {
            var x = bounds.minX
            
            for index in row.indices {
                let subview = subviews[index]
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            
            y += row.height + spacing
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [(indices: [Int], height: CGFloat)] {
        var rows: [(indices: [Int], height: CGFloat)] = []
        var currentRow: [Int] = []
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? 0
        
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentRowWidth + size.width > maxWidth && !currentRow.isEmpty {
                rows.append((indices: currentRow, height: currentRowHeight))
                currentRow = []
                currentRowWidth = 0
                currentRowHeight = 0
            }
            
            currentRow.append(index)
            currentRowWidth += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        if !currentRow.isEmpty {
            rows.append((indices: currentRow, height: currentRowHeight))
        }
        
        return rows
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
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
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
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                
                                Text("Create a job or volunteer posting")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
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
                    .buttonStyle(PlainButtonStyle())
                    
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
                                Color(red: 0.6, green: 0.4, blue: 1.0),   // Purple
                                Color(red: 0.7, green: 0.5, blue: 1.0)    // Light purple
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
                                .buttonStyle(PlainButtonStyle())
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
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
    
    var cardColor: Color {
        switch opportunity.jobType.lowercased() {
        case "gardening": return Color(red: 0.4, green: 0.8, blue: 0.5)        // Green
        case "pet care": return Color(red: 1.0, green: 0.6, blue: 0.4)         // Orange
        case "tutoring": return Color(red: 0.4, green: 0.7, blue: 1.0)         // Blue
        case "cleaning": return Color(red: 0.6, green: 0.4, blue: 1.0)         // Purple
        case "moving help": return Color(red: 1.0, green: 0.5, blue: 0.5)      // Red
        default: return Color(red: 0.5, green: 0.8, blue: 0.9)                 // Teal
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
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(cardColor)
                        
                        Text(opportunity.locationName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Pay amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(opportunity.displayPay)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            opportunity.isVolunteer ? 
                            LinearGradient(
                                colors: [cardColor, cardColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.1, blue: 0.1), Color(red: 0.2, green: 0.2, blue: 0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text(opportunity.timeAgo)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
            
            // Description
            Text(opportunity.description)
                .font(.system(size: 14, weight: .regular, design: .rounded))
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(opportunity.statusColor.opacity(0.15))
                )
                
                Spacer()
                
                // Job type icon
                ZStack {
                    Circle()
                        .fill(cardColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: iconForJobType(opportunity.jobType))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(cardColor)
                }
                
                // Applicants count
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(cardColor)
                    
                    Text("\(opportunity.applicantCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
                .fill(Color.white)
                .shadow(color: cardColor.opacity(0.25), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
    }
    
    private func iconForJobType(_ type: String) -> String {
        switch type.lowercased() {
        case "gardening": return "leaf.fill"
        case "pet care": return "pawprint.fill"
        case "tutoring": return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting": return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help": return "calendar.badge.plus"
        case "cleaning": return "sparkles"
        case "delivery": return "shippingbox.fill"
        default: return "briefcase.fill"
        }
    }
}

// MARK: - Compact Opportunity Preview (Map Popup)
struct CompactOpportunityPreview: View {
    let opportunity: Opportunity
    let onViewDetails: () -> Void
    let onClose: () -> Void
    
    private var cardColor: Color {
        switch opportunity.jobType.lowercased() {
        case "gardening": return Color(red: 0.4, green: 0.8, blue: 0.5)
        case "pet care": return Color(red: 1.0, green: 0.6, blue: 0.4)
        case "tutoring": return Color(red: 0.4, green: 0.7, blue: 1.0)
        case "cleaning": return Color(red: 0.6, green: 0.4, blue: 1.0)
        case "moving help": return Color(red: 1.0, green: 0.5, blue: 0.5)
        default: return Color(red: 0.5, green: 0.8, blue: 0.9)
        }
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(cardColor)
                        
                        Text(opportunity.locationName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Job type icon
                ZStack {
                    Circle()
                        .fill(cardColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: iconForJobType(opportunity.jobType))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(cardColor)
                }
                
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
                    Image(systemName: opportunity.isVolunteer ? "heart.fill" : "dollarsign.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(cardColor)
                    
                    Text(opportunity.displayPay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
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
        switch type.lowercased() {
        case "gardening": return "leaf.fill"
        case "pet care": return "pawprint.fill"
        case "tutoring": return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting": return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help": return "calendar.badge.plus"
        case "cleaning": return "sparkles"
        case "delivery": return "shippingbox.fill"
        default: return "briefcase.fill"
        }
    }
}

// MARK: - Role Mode Banner
struct RoleModeBanner: View {
    let activeRole: UserType
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activeRole == .jobSeeker ? "person.fill" : "briefcase.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Text(activeRole == .jobSeeker ? "Finding Jobs" : "Posting Jobs")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(CommunallyTheme.primaryGreen.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Role Switcher Button
struct RoleSwitcherButton: View {
    @Binding var activeRole: UserType
    @Binding var showBanner: Bool
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                activeRole = activeRole == .jobSeeker ? .jobHirer : .jobSeeker
                isAnimating = true
                showBanner = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = false
            }
        }) {
            ZStack {
                // Background Circle
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.2), radius: 15, x: 0, y: 8)
                
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
}

// MARK: - Notification Bell Button
struct NotificationBellButton: View {
    @Binding var showNotifications: Bool
    @ObservedObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            showNotifications = true
        }) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.2), radius: 15, x: 0, y: 8)
                
                Image(systemName: "bell.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 50, height: 50)
                
                // Notification Badge
                if notificationManager.unreadCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                        
                        Text("\(min(notificationManager.unreadCount, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
