//
//  PlaceholderViews.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var showAccountView = false
    @State private var showEditProfile = false
    @State private var showPaymentHistory = false
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
            
                ScrollView {
                    VStack(spacing: 24) {
                        profileHeaderSection
                        quickActionsSection
                        Spacer(minLength: 100)
                    }
                    .padding(CommunallyTheme.padding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showEditProfile = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                    }
                }
            }
            .sheet(isPresented: $showAccountView) {
                AccountView()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showEditProfile) {
                if let user = authManager.currentUser {
                    EditProfileView(user: user)
                        .environmentObject(authManager)
                }
            }
            .sheet(isPresented: $showPaymentHistory) {
                NavigationView {
                    PaymentHistoryView()
                        .environmentObject(authManager)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var profileImageView: some View {
        Group {
            if let profileImageData = authManager.currentUser?.profileImageData,
               let uiImage = UIImage(data: profileImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 4))
        .overlay(Circle().stroke(CommunallyTheme.primaryGreen, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private var profileHeaderSection: some View {
        VStack(spacing: 16) {
            profileImageView
            
            VStack(spacing: 8) {
                Text("\(authManager.currentUser?.firstName ?? "") \(authManager.currentUser?.lastName ?? "")")
                    .font(CommunallyTheme.titleFont)
                    .fontWeight(.bold)
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Text(authManager.currentUser?.userType == .jobSeeker ? "Job Seeker" : "Job Hirer")
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                
                if let user = authManager.currentUser {
                    ageDisplayView(age: user.resolvedAge)
                }
            }
            
            if let description = authManager.currentUser?.description, !description.isEmpty {
                bioSectionView(description: description)
            }
        }
        .padding(CommunallyTheme.padding)
        .background(Color.white)
        .cornerRadius(CommunallyTheme.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private func ageDisplayView(age: Int) -> some View {
        Text("Age: \(age)")
            .font(CommunallyTheme.captionFont)
            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CommunallyTheme.primaryGreen.opacity(0.1))
            )
    }
    
    private func bioSectionView(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About Me")
                .font(CommunallyTheme.subtitleFont)
                .fontWeight(.semibold)
                .foregroundColor(CommunallyTheme.darkGray)
            
            Text(description)
                .font(CommunallyTheme.bodyFont)
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.8))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.8))
        )
    }
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            // Payment summary
            if let user = authManager.currentUser {
                ProfilePaymentSummaryRow(user: user, onTap: { showPaymentHistory = true })
            }

            Button(action: { showAccountView = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account")
                            .font(CommunallyTheme.subtitleFont)
                            .fontWeight(.semibold)
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text("Manage your profile and settings")
                            .font(CommunallyTheme.captionFont)
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            
            signOutButton
        }
        .padding(CommunallyTheme.padding)
        .background(Color.white)
        .cornerRadius(CommunallyTheme.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private var signOutButton: some View {
        Button(action: {
            authManager.signOut()
            dismiss()
        }) {
            Text("Sign Out")
                .font(CommunallyTheme.bodyFont)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: CommunallyTheme.buttonHeight)
                .background(CommunallyTheme.buttonGradient)
                .cornerRadius(CommunallyTheme.cornerRadius)
        }
    }
}

struct AccountView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showDeleteApplicationsConfirmation = false
    @State private var isDeletingApplications = false
    @State private var showEditProfile = false
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        accountManagementSection
                        appSettingsSection
                        // Developer-only data-wipe controls. NEVER ship to the
                        // App Store: a tap clears all opportunities/applications
                        // in production Firebase. Gated behind DEBUG so the
                        // release build cannot even compile the section.
                        #if DEBUG
                        developerOptionsSection
                        #endif
                        Spacer(minLength: 100)
                    }
                    .padding(CommunallyTheme.padding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let user = authManager.currentUser {
                    EditProfileView(user: user)
                        .environmentObject(authManager)
                }
            }
            .alert("Clear All Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    Task {
                        isDeleting = true
                        await OpportunityManager.shared.deleteAllOpportunities()
                        isDeleting = false
                    }
                }
            } message: {
                Text("This will permanently delete all opportunities from Firebase. This action cannot be undone.")
            }
            .alert("Clear All Applications?", isPresented: $showDeleteApplicationsConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    Task {
                        isDeletingApplications = true
                        await ApplicationManager.shared.deleteAllApplications()
                        isDeletingApplications = false
                    }
                }
            } message: {
                Text("This will permanently delete all job applications from Firebase. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var accountManagementSection: some View {
        VStack(spacing: 12) {
            ProfileOptionRow(icon: "person.fill", title: "Edit Profile", action: {
                showEditProfile = true
            })
            ProfileOptionRow(icon: "bookmark.fill", title: "Saved Posts", action: {})
            ProfileOptionRow(icon: "clock.fill", title: "Applied Posts", action: {})
            ProfileOptionRow(icon: "bell.fill", title: "Notifications", action: {})
            ProfileOptionRow(icon: "lock.fill", title: "Privacy & Security", action: {})
            
            Divider()
                .padding(.vertical, 4)
            
            Button(action: {
                authManager.signOut()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                    
                    Text("Sign Out")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .padding(CommunallyTheme.padding)
        .background(Color.white)
        .cornerRadius(CommunallyTheme.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private var appSettingsSection: some View {
        VStack(spacing: 12) {
            ProfileOptionRow(icon: "gear", title: "Settings", action: {})
            ProfileOptionRow(icon: "questionmark.circle", title: "Help & Support", action: {})
            ProfileOptionRow(icon: "info.circle", title: "About", action: {})
        }
        .padding(CommunallyTheme.padding)
        .background(Color.white)
        .cornerRadius(CommunallyTheme.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private var developerOptionsSection: some View {
        VStack(spacing: 16) {
            Text("Developer Options")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            deleteOpportunitiesButton
            deleteApplicationsButton
        }
        .padding(CommunallyTheme.padding)
        .background(Color.white.opacity(0.5))
        .cornerRadius(CommunallyTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 3)
    }
    
    private var deleteOpportunitiesButton: some View {
        Button(action: {
            showDeleteConfirmation = true
        }) {
            HStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear All Opportunities")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(.red)
                    
                    Text("Delete all posted opportunities from Firebase")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                Spacer()
                
                if isDeleting {
                    ProgressView()
                        .tint(.red)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .disabled(isDeleting)
        .buttonStyle(PlainButtonStyle())
    }
    
    private var deleteApplicationsButton: some View {
        Button(action: {
            showDeleteApplicationsConfirmation = true
        }) {
            HStack {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear All Applications")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(.orange)
                    
                    Text("Delete all job applications from Firebase")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                Spacer()
                
                if isDeletingApplications {
                    ProgressView()
                        .tint(.orange)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .disabled(isDeletingApplications)
        .buttonStyle(PlainButtonStyle())
    }
    
}

struct ProfileOptionRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .frame(width: 24)
                
                Text(title)
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(CommunallyTheme.darkGray)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            }
            .padding(.vertical, 12)
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // App Logo and Info
                        VStack(spacing: 16) {
                            Image("CommunallyLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                            
                            Text("Communally")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Text("Connect locally. Help globally.")
                                .font(CommunallyTheme.subtitleFont)
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(CommunallyTheme.padding)
                        .background(Color.white)
                        .cornerRadius(CommunallyTheme.cornerRadius)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
                        
                        // App Info
                        VStack(alignment: .leading, spacing: 16) {
                            Text("About Communally")
                                .font(CommunallyTheme.subtitleFont)
                                .fontWeight(.semibold)
                                .foregroundColor(CommunallyTheme.darkGray)
                            
                            Text("Communally is a platform that connects people in their local community for jobs and volunteer opportunities. Whether you're looking for work or want to help others, Communally makes it easy to find meaningful connections in your area.")
                                .font(CommunallyTheme.bodyFont)
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.8))
                                .lineSpacing(4)
                        }
                        .padding(CommunallyTheme.padding)
                        .background(Color.white)
                        .cornerRadius(CommunallyTheme.cornerRadius)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
                        
                        // Links
                        VStack(spacing: 12) {
                            AboutLinkRow(title: "Terms of Service", action: {})
                            AboutLinkRow(title: "Privacy Policy", action: {})
                            AboutLinkRow(title: "Contact Us", action: {})
                        }
                        .padding(CommunallyTheme.padding)
                        .background(Color.white)
                        .cornerRadius(CommunallyTheme.cornerRadius)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
                        
                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                    .padding(CommunallyTheme.padding)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                }
            }
        }
    }
}

struct AboutLinkRow: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(CommunallyTheme.bodyFont)
                    .foregroundColor(CommunallyTheme.primaryGreen)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            }
            .padding(.vertical, 8)
        }
    }
}

struct NewPostView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Create New Post")
                        .font(CommunallyTheme.titleFont)
                        .fontWeight(.bold)
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Text("This feature will be available soon!")
                        .font(CommunallyTheme.bodyFont)
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
                .padding(CommunallyTheme.padding)
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                }
            }
        }
    }
}

// MARK: - Profile Payment Summary Row

struct ProfilePaymentSummaryRow: View {
    let user: User
    let onTap: () -> Void
    @ObservedObject private var paymentManager = PaymentManager.shared

    private var primaryLabel: String { user.userType == .jobSeeker ? "Paid Out" : "Total Paid" }
    private var pendingLabel: String { user.userType == .jobSeeker ? "Awaiting Release" : "Held in Escrow" }
    private var primaryAmount: Double {
        user.userType == .jobSeeker
            ? paymentManager.getTotalEarnings(for: user.id)
            : paymentManager.getTotalSpent(for: user.id)
    }
    private var pendingAmount: Double {
        user.userType == .jobSeeker
            ? paymentManager.getPendingPayouts(for: user.id)
            : paymentManager.getPendingCharges(for: user.id)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24))
                    .foregroundColor(CommunallyTheme.primaryGreen)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments")
                        .font(CommunallyTheme.subtitleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(CommunallyTheme.darkGray)

                    HStack(spacing: 12) {
                        Text("\(primaryLabel): \(String(format: "$%.2f", primaryAmount))")
                            .font(CommunallyTheme.captionFont)
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                        if pendingAmount > 0 {
                            Text("\(pendingLabel): \(String(format: "$%.2f", pendingAmount))")
                                .font(CommunallyTheme.captionFont)
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthenticationManager.shared)
}
