//
//  QuickLocationShareView.swift
//  Communally
//
//  Quick access view for sharing location
//

import SwiftUI

struct QuickLocationShareView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                            .frame(width: 120, height: 120)
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 16) {
                        Text("Share Your Location")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text("Let friends & family know where you are for safety")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(
                            icon: "message.fill",
                            title: "Share via Messages",
                            color: .green
                        )
                        FeatureRow(
                            icon: "paperplane.fill",
                            title: "Instagram, WhatsApp & More",
                            color: .purple
                        )
                        FeatureRow(
                            icon: "map.fill",
                            title: "Works with All Map Apps",
                            color: .blue
                        )
                        FeatureRow(
                            icon: "shield.fill",
                            title: "Stay Safe on Jobs",
                            color: .orange
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Share Button
                    if let userName = authManager.currentUser?.fullName {
                        LocationSharingButton(
                            userName: userName,
                            jobTitle: nil
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Safety Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(CommunallyTheme.primaryGreen)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
}

#Preview {
    QuickLocationShareView()
        .environmentObject(AuthenticationManager.shared)
}
