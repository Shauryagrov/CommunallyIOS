//
//  PostOpportunityView.swift
//  Communally
//
//  Created for minimalistic job posting
//

import SwiftUI
import MapKit

struct PostOpportunityView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    
    // Location
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var showLocationPicker = false
    
    // Pay
    @State private var isVolunteer = true
    @State private var payAmount: String = ""
    
    // Job Type
    @State private var selectedJobType: JobType = .other
    @State private var jobDescription: String = ""
    
    // Error handling
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum JobType: String, CaseIterable {
        case gardening = "Gardening"
        case petCare = "Pet Care"
        case tutoring = "Tutoring"
        case moving = "Moving Help"
        case painting = "Painting"
        case babysitting = "Babysitting"
        case eventHelp = "Event Help"
        case cleaning = "Cleaning"
        case delivery = "Delivery"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .gardening: return "leaf.fill"
            case .petCare: return "pawprint.fill"
            case .tutoring: return "book.fill"
            case .moving: return "box.truck.fill"
            case .painting: return "paintbrush.fill"
            case .babysitting: return "figure.2.and.child.holdinghands"
            case .eventHelp: return "calendar.badge.plus"
            case .cleaning: return "sparkles"
            case .delivery: return "shippingbox.fill"
            case .other: return "briefcase.fill"
            }
        }
    }

    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle("Post Opportunity")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(CommunallyTheme.darkGray)
                    }
                }
                .sheet(isPresented: $showLocationPicker) {
                    LocationPickerView(
                        selectedLocation: $selectedLocation,
                        locationName: $locationName,
                        isPresented: $showLocationPicker
                    )
                }
        }
    }
    
    private var mainContent: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    locationSection
                    paySection
                    jobTypeSection
                    descriptionSection
                    postButton
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Where?")
            
            locationButton
        }
    }
    
    private var locationButton: some View {
        Button(action: {
            showLocationPicker = true
        }) {
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 20))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                
                Text(locationName.isEmpty ? "Select Location" : locationName)
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(locationName.isEmpty ? CommunallyTheme.darkGray.opacity(0.5) : CommunallyTheme.darkGray)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Pay Section
    private var paySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("How Much?")
            
            VStack(spacing: 12) {
                volunteerButton
                paidButton
            }
        }
    }
    
    private var volunteerButton: some View {
        Button(action: {
            isVolunteer = true
            payAmount = ""
        }) {
            HStack {
                checkmarkIcon(isVolunteer)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Volunteer")
                        .font(CommunallyTheme.bodyFont)
                        .fontWeight(.semibold)
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Text("Unpaid opportunity")
                        .font(CommunallyTheme.captionFont)
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isVolunteer ? CommunallyTheme.primaryGreen : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var paidButton: some View {
        Button(action: {
            isVolunteer = false
        }) {
            HStack {
                checkmarkIcon(!isVolunteer)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid")
                        .font(CommunallyTheme.bodyFont)
                        .fontWeight(.semibold)
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    if !isVolunteer {
                        payAmountField
                    }
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(!isVolunteer ? CommunallyTheme.primaryGreen : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var payAmountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("$")
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(CommunallyTheme.darkGray)
                
                TextField("50", text: $payAmount)
                    .font(CommunallyTheme.bodyFont)
                    .keyboardType(.decimalPad)
                    .foregroundColor(CommunallyTheme.darkGray)
                    .frame(width: 80)
                
                Text("total")
                    .font(CommunallyTheme.captionFont)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            }
            
            // App fee note
            Text("+ 5% app fee at completion")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                .padding(.leading, 20)
        }
    }
    
    // MARK: - Job Type Section
    private var jobTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What Kind of Help?")
            
            jobTypeGrid
        }
    }
    
    private var jobTypeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(JobType.allCases, id: \.self) { type in
                jobTypeCard(type)
            }
        }
    }
    
    private func jobTypeCard(_ type: JobType) -> some View {
        Button(action: {
            selectedJobType = type
        }) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 28))
                    .foregroundColor(selectedJobType == type ? CommunallyTheme.primaryGreen : CommunallyTheme.darkGray.opacity(0.5))
                
                Text(type.rawValue)
                    .font(CommunallyTheme.captionFont)
                    .foregroundColor(CommunallyTheme.darkGray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedJobType == type ? CommunallyTheme.primaryGreen : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Details")
            
            descriptionField
        }
    }
    
    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            // White background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            if jobDescription.isEmpty {
                Text("Describe what you need help with...")
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(Color.gray.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            TextEditor(text: $jobDescription)
                .font(CommunallyTheme.bodyFont)
                .foregroundColor(.black)
                .frame(height: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }
    
    // MARK: - Post Button
    private var postButton: some View {
        Button(action: postOpportunity) {
            Text("Post Opportunity")
                .font(CommunallyTheme.bodyFont)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canPost ? CommunallyTheme.primaryGreen : CommunallyTheme.darkGray.opacity(0.3))
                .cornerRadius(12)
                .shadow(color: canPost ? CommunallyTheme.primaryGreen.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
        }
        .disabled(!canPost)
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Views
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(CommunallyTheme.titleFont)
            .fontWeight(.bold)
            .foregroundColor(CommunallyTheme.darkGray)
    }
    
    private func checkmarkIcon(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .foregroundColor(isSelected ? CommunallyTheme.primaryGreen : CommunallyTheme.darkGray.opacity(0.3))
    }
    
    // MARK: - Computed Properties
    private var canPost: Bool {
        selectedLocation != nil &&
        !locationName.isEmpty &&
        (isVolunteer || !payAmount.isEmpty) &&
        !jobDescription.isEmpty
    }
    
    // MARK: - Actions
    private func postOpportunity() {
        guard let selectedLocation = selectedLocation,
              let currentUser = authManager.currentUser else {
            print("❌ Missing required data")
            return
        }
        
        let location = Location(
            latitude: selectedLocation.latitude,
            longitude: selectedLocation.longitude,
            address: locationName
        )
        
        opportunityManager.postOpportunity(
            title: "\(selectedJobType.rawValue) Needed",
            description: jobDescription,
            location: location,
            locationName: locationName,
            isVolunteer: isVolunteer,
            payAmount: isVolunteer ? nil : payAmount,
            jobType: selectedJobType.rawValue,
            hirerId: currentUser.id,
            hirerName: currentUser.fullName,
            hirerImageData: currentUser.profileImageData
        )
        
        print("📤 Successfully posted opportunity!")
        dismiss()
    }
}

// MARK: - Location Picker View
struct LocationPickerView: View {
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map View
                mapView
                
                // Dimmed overlay when searching
                if isSearching && !searchResults.isEmpty {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            searchText = ""
                            searchResults = []
                            isSearching = false
                        }
                }
                
                // Overlay UI
                VStack(spacing: 0) {
                    // Welcome hint card (shows briefly)
                    if selectedLocation == nil && searchText.isEmpty {
                        welcomeHintCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Search Bar at top
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, selectedLocation == nil && searchText.isEmpty ? 8 : 8)
                        .zIndex(100)
                    
                    // Search Results
                    if isSearching && !searchResults.isEmpty {
                        searchResultsList
                            .zIndex(99)
                    }
                    
                    Spacer()
                    
                    // Location info card
                    if selectedLocation != nil && !isSearching {
                        locationInfoCard
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Instruction text with animation
                    if !isSearching {
                        instructionText
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Confirm button
                    if !isSearching {
                        confirmButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSearching)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedLocation != nil)
                
                // Quick action buttons
                if !isSearching {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                currentLocationButton
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 240)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                            
                            Text("Select Location")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                        
                        Text("Drag map or search for a place")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                    }
                }
            }
            .onAppear {
                centerOnUserLocation()
            }
        }
    }
    
    // MARK: - Welcome Hint Card
    private var welcomeHintCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Tip!")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text("Search above or drag the map to select your location")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Map View
    private var mapView: some View {
        Map(position: $cameraPosition)
            .onMapCameraChange { context in
                region = context.region
            }
            .ignoresSafeArea()
            .overlay(centerPin)
    }
    
    private var centerPin: some View {
        VStack(spacing: 0) {
            ZStack {
                // Animated rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), lineWidth: 3)
                        .frame(width: CGFloat(60 + index * 30), height: CGFloat(60 + index * 30))
                        .scaleEffect(1.0 + (Double(index) * 0.2))
                        .opacity(0.4 - (Double(index) * 0.1))
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: selectedLocation != nil
                        )
                }
                
                // Outer pulsing glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4),
                                Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(selectedLocation != nil ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: selectedLocation != nil)
                
                // Pin background circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4), radius: 12, x: 0, y: 6)
                
                // Pin icon with bounce animation
                Image(systemName: selectedLocation != nil ? "mappin.circle.fill" : "mappin.circle")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0),
                                Color(red: 0.7, green: 0.5, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .scaleEffect(selectedLocation != nil ? 1.0 : 1.15)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: selectedLocation != nil)
            }
            
            // Animated pin shadow/point
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 12
                    )
                )
                .frame(width: 28, height: 12)
                .blur(radius: 3)
                .offset(y: -5)
                .scaleEffect(selectedLocation != nil ? 1.0 : 1.1)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: selectedLocation != nil)
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Search icon with gradient background and pulse
                ZStack {
                    // Pulse effect
                    if searchText.isEmpty {
                        Circle()
                            .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3))
                            .frame(width: 44, height: 44)
                            .scaleEffect(1.1)
                            .opacity(0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: searchText.isEmpty)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0),
                                    Color(red: 0.7, green: 0.5, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "magnifyingglass.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: searchText.isEmpty)
                }
                
                // Text field
                TextField("🔍 Search: IKEA, Starbucks, or address...", text: $searchText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .onChange(of: searchText) {
                        if !searchText.isEmpty {
                            performSearch(query: searchText)
                        } else {
                            searchResults = []
                            isSearching = false
                        }
                    }
                
                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                        isSearching = false
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                                .frame(width: 30, height: 30)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3),
                                        Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.25), radius: 18, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
            )
        }
    }
    
    // MARK: - Search Results List
    private var searchResultsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(searchResults, id: \.self) { item in
                    Button(action: {
                        selectSearchResult(item)
                    }) {
                        HStack(spacing: 14) {
                            // Location icon
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                            }
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name ?? "Unknown Location")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                
                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            // Arrow icon
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.98))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Location Info Card
    private var locationInfoCard: some View {
        HStack(spacing: 14) {
            // Animated checkmark icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Circle()
                    .stroke(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)
                    .scaleEffect(1.2)
                    .opacity(0.5)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: locationName.isEmpty)
                
                Image(systemName: locationName.isEmpty ? "location.magnifyingglass" : "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: locationName.isEmpty)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(locationName.isEmpty ? "Finding address..." : "Location Ready!")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                
                Text(locationName.isEmpty ? "Move map to select" : locationName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            
            Spacer()
            
            // Edit icon
            if !locationName.isEmpty {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.2), radius: 15, x: 0, y: 8)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        )
    }
    
    // MARK: - Instruction Text
    private var instructionText: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: selectedLocation != nil ? "hand.thumbsup.fill" : "hand.tap.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedLocation != nil ? "Great! Location selected" : "How to select")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text(selectedLocation != nil ? "Tap 'Confirm' below to continue" : "Drag map to move pin • Search for specific place")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.15), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Current Location Button
    private var currentLocationButton: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            centerOnUserLocation()
        }) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2))
                    .frame(width: 58, height: 58)
                    .blur(radius: 8)
                
                // Button background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 0.98, green: 0.98, blue: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                
                Image(systemName: "location.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Confirm Button
    private var confirmButton: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .heavy)
            impactMed.impactOccurred()
            confirmLocation()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Location")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    
                    if selectedLocation != nil && !locationName.isEmpty {
                        Text("Tap to continue")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .opacity(0.85)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(
                Group {
                    if selectedLocation != nil && !locationName.isEmpty {
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.8, blue: 0.4),
                                Color(red: 0.4, green: 0.85, blue: 0.5)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.7, blue: 0.7),
                                Color(red: 0.75, green: 0.75, blue: 0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .cornerRadius(20)
            .shadow(
                color: selectedLocation != nil ? Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.5) : Color.gray.opacity(0.3),
                radius: 20,
                x: 0,
                y: 10
            )
            .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
        }
        .disabled(selectedLocation == nil || locationName.isEmpty)
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedLocation != nil)
    }
    
    // MARK: - Helper Functions
    private func performSearch(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let response = response {
                searchResults = response.mapItems
                isSearching = true
            }
        }
    }
    
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        
        // Animate to location
        withAnimation(.easeInOut(duration: 0.5)) {
            region.center = coordinate
            cameraPosition = .region(region)
        }
        
        selectedLocation = coordinate
        locationName = item.name ?? item.placemark.title ?? ""
        
        // Clear search
        searchText = ""
        searchResults = []
        isSearching = false
    }
    
    private func centerOnUserLocation() {
        if let location = locationManager.location {
            withAnimation(.easeInOut(duration: 0.5)) {
                region.center = location.coordinate
                cameraPosition = .region(region)
            }
            selectedLocation = location.coordinate
            updateLocationName(for: location.coordinate)
        }
    }
    
    private func updateLocationName(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                var components: [String] = []
                if let name = placemark.name {
                    components.append(name)
                }
                if let locality = placemark.locality {
                    components.append(locality)
                }
                locationName = components.joined(separator: ", ")
            }
        }
    }
    
    private func confirmLocation() {
        if selectedLocation == nil {
            selectedLocation = region.center
            updateLocationName(for: region.center)
        }
        isPresented = false
    }
}

// MARK: - Preview
#Preview {
    PostOpportunityView()
}
