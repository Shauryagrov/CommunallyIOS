//
//  ChatView.swift
//  Communally
//
//  1-on-1 chat for accepted job applications
//

import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var messageManager = MessageManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isTextFieldFocused: Bool
    
    private var messages: [Message] {
        messageManager.getMessages(for: conversation.id)
    }
    
    private var opportunity: Opportunity? {
        opportunityManager.opportunities.first { $0.safeId == conversation.opportunityId }
    }
    
    private var otherUserName: String {
        guard let currentUserId = authManager.currentUser?.id else { return "" }
        return conversation.otherUserName(currentUserId: currentUserId)
    }
    
    private var otherUserImageData: Data? {
        guard let currentUserId = authManager.currentUser?.id else { return nil }
        return conversation.otherUserImageData(currentUserId: currentUserId)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Job context header
            if let opp = opportunity {
                jobContextHeader(opp)
            }
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isCurrentUser: message.senderId == authManager.currentUser?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                    markAsRead()
                }
                .onChange(of: messages.count) {
                    scrollToBottom()
                }
            }
            
            // Input bar
            messageInputBar
        }
        .background(
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
        )
        .navigationTitle(otherUserName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    // Profile picture
                    if let imageData = otherUserImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 0.6, green: 0.4, blue: 1.0), lineWidth: 2)
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        }
                    }
                    
                    Text(otherUserName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                }
            }
        }
    }
    
    // MARK: - Job Context Header
    private func jobContextHeader(_ opportunity: Opportunity) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: iconForJobType(opportunity.jobType))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(opportunity.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(opportunity.statusColor)
                            .frame(width: 6, height: 6)
                        
                        Text(opportunity.statusDisplay)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        
                        Text("•")
                            .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                        
                        Text(opportunity.displayPay)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            
            Rectangle()
                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                .frame(height: 1)
        }
    }
    
    // MARK: - Message Input Bar
    private var messageInputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                .frame(height: 1)
            
            HStack(spacing: 12) {
                // Text field
                HStack(spacing: 10) {
                    TextField("Type a message...", text: $messageText, axis: .vertical)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .lineLimit(1...5)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                )
                
                // Send button
                Button(action: sendMessage) {
                    ZStack {
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
                            .frame(width: 44, height: 44)
                            .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }
    
    // MARK: - Helper Functions
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let currentUser = authManager.currentUser else { return }
        
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        
        messageManager.sendMessage(
            conversationId: conversation.id,
            senderId: currentUser.id,
            senderName: currentUser.fullName,
            text: trimmedText
        )
        
        messageText = ""
    }
    
    private func scrollToBottom() {
        if let lastMessage = messages.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func markAsRead() {
        guard let userId = authManager.currentUser?.id else { return }
        messageManager.markAsRead(conversationId: conversation.id, userId: userId)
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

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(isCurrentUser ? .white : Color(red: 0.15, green: 0.15, blue: 0.15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                isCurrentUser ?
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.4, blue: 1.0),
                                        Color(red: 0.7, green: 0.5, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white, Color.white],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: isCurrentUser ?
                                Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3) :
                                Color.black.opacity(0.08),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    )
                
                Text(message.timeString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    .padding(.horizontal, 4)
            }
            
            if !isCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
}

#Preview {
    NavigationView {
        ChatView(conversation: Conversation(
            id: "1",
            opportunityId: "opp1",
            hirerId: "hirer1",
            hirerName: "John Doe",
            hirerImageData: nil,
            applicantId: "applicant1",
            applicantName: "Jane Smith",
            applicantImageData: nil,
            participantIds: ["hirer1", "applicant1"],
            lastMessage: "Hello!",
            lastMessageAt: Date(),
            unreadCount: 0,
            createdAt: Date()
        ))
    }
    .environmentObject(AuthenticationManager.shared)
}

