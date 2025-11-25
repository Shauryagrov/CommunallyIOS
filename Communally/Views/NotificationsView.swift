//
//  NotificationsView.swift
//  Communally
//
//  View showing all user notifications
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var selectedOpportunity: Opportunity?
    @State private var showClearAllConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack {
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
                
                if notificationManager.notifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if notificationManager.unreadCount > 0 {
                                markAllReadButton
                            }
                            
                            ForEach(notificationManager.notifications) { notification in
                                NotificationCard(notification: notification) {
                                    handleNotificationTap(notification)
                                }
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !notificationManager.notifications.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive, action: {
                                showClearAllConfirmation = true
                            }) {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                    }
                }
            }
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
            .alert("Clear All Notifications?", isPresented: $showClearAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task {
                        if let userId = authManager.currentUser?.id {
                            await notificationManager.clearAllNotifications(userId: userId)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete all your notifications.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.6))
            }
            
            Text("No Notifications")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray)
            
            Text("You're all caught up!\nNotifications will appear here when you have updates.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    private var markAllReadButton: some View {
        Button(action: {
            if let userId = authManager.currentUser?.id {
                notificationManager.markAllAsRead(userId: userId)
            }
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Mark All as Read")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(CommunallyTheme.primaryGreen)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.1))
            )
        }
    }
    
    // MARK: - Handle Tap
    
    private func handleNotificationTap(_ notification: AppNotification) {
        // Mark as read
        notificationManager.markAsRead(notificationId: notification.safeId)
        
        // Navigate based on type
        if let relatedId = notification.relatedId,
           let opportunity = opportunityManager.opportunities.first(where: { $0.safeId == relatedId }) {
            selectedOpportunity = opportunity
        }
    }
}

// MARK: - Notification Card

struct NotificationCard: View {
    let notification: AppNotification
    let onTap: () -> Void
    
    private var backgroundColor: Color {
        notification.isRead ? Color.white.opacity(0.6) : Color.white
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .newOpportunity: return Color.blue
        case .newApplication: return Color.purple
        case .applicationAccepted: return Color.green
        case .applicationRejected: return Color.red
        case .newMessage: return Color.orange
        case .paymentReceived: return Color.green
        case .paymentSent: return Color.blue
        case .paymentReleased: return Color.orange
        case .paymentRefunded: return Color.red
        case .ratingReceived: return Color.yellow
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: notification.iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(notification.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Spacer()
                        
                        if !notification.isRead {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(notification.message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        .lineLimit(2)
                    
                    Text(notification.timeAgo)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AuthenticationManager.shared)
}

