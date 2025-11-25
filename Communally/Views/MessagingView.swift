//
//  MessagingView.swift
//  Communally
//
//  Shows all active chat conversations for accepted jobs
//

import SwiftUI

struct MessagingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var messageManager = MessageManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var selectedConversation: Conversation?
    @State private var isRefreshing = false
    
    private var conversations: [Conversation] {
        messageManager.conversations
    }
    
    private var totalUnreadCount: Int {
        guard let userId = authManager.currentUser?.id else { return 0 }
        return conversations.reduce(0) { sum, conv in
            sum + (conv.participantIds.contains(userId) ? conv.unreadCount : 0)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.97, green: 0.99, blue: 0.95),
                        Color.white,
                        Color(red: 0.98, green: 1.0, blue: 0.96)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if conversations.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Conversations list
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(conversations) { conversation in
                                ConversationCard(
                                    conversation: conversation,
                                    currentUserId: authManager.currentUser?.id ?? "",
                                    opportunity: opportunityManager.opportunities.first { $0.safeId == conversation.opportunityId }
                                ) {
                                    selectedConversation = conversation
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                    .refreshable {
                        await refreshConversations()
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedConversation) { conversation in
                NavigationView {
                    ChatView(conversation: conversation)
                        .environmentObject(authManager)
                }
            }
            .onAppear {
                // Start listening when view appears
                if let userId = authManager.currentUser?.id {
                    messageManager.startListening(for: userId)
                }
            }
            .onDisappear {
                // Keep listener active for real-time updates
                // Don't stop listening here
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
            
            VStack(spacing: 12) {
                Text("No Messages Yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                if authManager.currentUser?.userType == .jobSeeker {
                    Text("When a hirer accepts your application,\na chat will automatically be created here.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                } else {
                    Text("When you accept an applicant,\na chat will automatically be created here.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Refresh
    private func refreshConversations() async {
        isRefreshing = true
        
        // Give a small delay for user feedback
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Restart listener to force refresh
        if let userId = authManager.currentUser?.id {
            messageManager.stopListening()
            messageManager.startListening(for: userId)
        }
        
        isRefreshing = false
    }
}

// MARK: - Conversation Card
struct ConversationCard: View {
    let conversation: Conversation
    let currentUserId: String
    let opportunity: Opportunity?
    let onTap: () -> Void
    
    private var otherUserName: String {
        conversation.otherUserName(currentUserId: currentUserId)
    }
    
    private var otherUserImageData: Data? {
        conversation.otherUserImageData(currentUserId: currentUserId)
    }
    
    var body: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .light)
            impactMed.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    // Profile picture with unread badge
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2))
                            .frame(width: 56, height: 56)
                        
                        if let imageData = otherUserImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        }
                        
                        // Unread badge
                        if conversation.unreadCount > 0 {
                            VStack {
                                HStack {
                                    Spacer()
                                    ZStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 22, height: 22)
                                        
                                        Text("\(min(conversation.unreadCount, 99))")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                Spacer()
                            }
                            .frame(width: 56, height: 56)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(otherUserName)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(conversation.timeAgo)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                        }
                        
                        Text(conversation.lastMessage)
                            .font(.system(size: 14, weight: conversation.unreadCount > 0 ? .semibold : .medium, design: .rounded))
                            .foregroundColor(conversation.unreadCount > 0 ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.5, green: 0.5, blue: 0.5))
                            .lineLimit(2)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                
                // Job context footer
                if let opp = opportunity {
                    Rectangle()
                        .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                        .frame(height: 1)
                    
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: iconForJobType(opp.jobType))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        }
                        
                        Text(opp.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(opp.statusColor)
                                .frame(width: 6, height: 6)
                            
                            Text(opp.statusDisplay)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.08), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
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

#Preview {
    MessagingView()
        .environmentObject(AuthenticationManager.shared)
}
