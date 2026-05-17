//
//  BlockReportView.swift
//  Communally
//
//  UI for blocking users. Generic abuse-content reporting was removed; for
//  physical-safety emergencies see `SeriousSafetyReportView`.
//

import SwiftUI

// MARK: - Block User View
struct BlockUserView: View {
    let userId: String
    let userName: String
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var safetyManager = SafetyManager.shared
    
    @State private var reason = ""
    @State private var isBlocking = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Block User")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text("Block \(userName)?")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding()
                    
                    // What happens
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What happens when you block someone:")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            BlockConsequence(icon: "eye.slash.fill", text: "They won't see your jobs")
                            BlockConsequence(icon: "bubble.left.and.bubble.right.fill", text: "They can't message you")
                            BlockConsequence(icon: "doc.text.fill", text: "They can't apply to your posts")
                            BlockConsequence(icon: "person.fill.xmark", text: "You won't see their content")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal)
                    
                    // Optional Reason
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reason (Optional)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        TextEditor(text: $reason)
                            .foregroundColor(.black)
                            .scrollContentBackground(.hidden)
                            .frame(height: 80)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Block Button
                    Button(action: blockUser) {
                        if isBlocking {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.raised.fill")
                                Text("Block \(userName)")
                            }
                            .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .cornerRadius(25)
                    .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 5)
                    .disabled(isBlocking)
                    .padding(.horizontal)
                    
                    // Cancel Button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom)
                }
            }
            .background(CommunallyTheme.backgroundGradient)
            .navigationTitle("Block User")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("User Blocked", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("\(userName) has been blocked. You can unblock them anytime from your settings.")
        }
    }
    
    private func blockUser() {
        isBlocking = true
        
        let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
        
        safetyManager.blockUser(
            userId: userId,
            userName: userName,
            reason: trimmedReason.isEmpty ? nil : trimmedReason
        ) { success in
            isBlocking = false
            
            if success {
                showSuccess = true
                
                // Haptic feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.warning)
            }
        }
    }
}

// MARK: - Block Consequence Component
struct BlockConsequence: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .frame(width: 25)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(CommunallyTheme.darkGray)
        }
    }
}

// MARK: - Quick Action Buttons
struct UserSafetyButtons: View {
    let userId: String
    let userName: String
    let relatedJobId: String?
    let relatedJobTitle: String?

    @State private var showBlockSheet = false

    var body: some View {
        Button(action: {
            showBlockSheet = true
        }) {
            Label("Block", systemImage: "hand.raised.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.1))
                )
        }
        .sheet(isPresented: $showBlockSheet) {
            BlockUserView(userId: userId, userName: userName)
        }
    }
}

