//
//  NotificationManager.swift
//  Communally
//
//  Manages in-app and push notifications
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UserNotifications

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    private var listener: ListenerRegistration?
    private var hasLoadedInitialSnapshot = false
    private var seenNotificationIds: Set<String> = []
    
    override init() {
        super.init()
        requestNotificationPermission()
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Push Notification Permissions
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("⚠️ Notification permission denied")
            }
        }
    }
    
    // MARK: - Listen to Notifications
    
    func startListening(for userId: String) {
        print("🔔 Starting notification listener for user: \(userId)")
        
        guard let db = db else {
            print("⚠️ NotificationManager: Firebase not configured")
            return
        }
        
        listener?.remove()
        hasLoadedInitialSnapshot = false
        seenNotificationIds = []
        
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching notifications: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("ℹ️ No notifications found")
                    return
                }
                
                self.notifications = documents.compactMap { document -> AppNotification? in
                    try? document.data(as: AppNotification.self)
                }
                
                self.unreadCount = self.notifications.filter { !$0.isRead }.count
                
                let currentIds = Set(self.notifications.map(\.safeId))
                let newNotifications = self.hasLoadedInitialSnapshot
                    ? self.notifications.filter { !self.seenNotificationIds.contains($0.safeId) && !$0.isRead }
                    : []
                self.seenNotificationIds = currentIds
                self.hasLoadedInitialSnapshot = true
                
                print("✅ Loaded \(self.notifications.count) notifications (\(self.unreadCount) unread)")
                
                // Update app badge
                DispatchQueue.main.async {
                    UNUserNotificationCenter.current().setBadgeCount(self.unreadCount) { error in
                        if let error = error {
                            print("❌ Error setting badge count: \(error.localizedDescription)")
                        }
                    }
                    
                    for notification in newNotifications {
                        self.sendPushNotification(notification)
                    }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Wipes in-memory state. Used after account deletion.
    func clearLocalState() {
        stopListening()
        DispatchQueue.main.async {
            self.notifications = []
            self.unreadCount = 0
        }
    }
    
    // MARK: - Send Notifications
    
    /// Send notification when a new opportunity is posted (notify all job seekers)
    func sendNewOpportunityNotification(opportunity: Opportunity) {
        // Get all job seeker user IDs from UserDatabase
        let jobSeekers = UserDatabase.shared.getAllUsers().filter { $0.userType == .jobSeeker }
        
        for jobSeeker in jobSeekers {
            let notification = AppNotification(
                id: nil,
                type: .newOpportunity,
                title: "New Job Posted! 🎉",
                message: "\(opportunity.title) - \(opportunity.displayPay)",
                userId: jobSeeker.id,
                relatedId: opportunity.safeId,
                senderName: opportunity.hirerName,
                senderImageData: opportunity.hirerImageData,
                createdAt: Date(),
                isRead: false
            )
            
            saveNotification(notification)
        }
        
        print("✅ Sent new opportunity notification to \(jobSeekers.count) job seekers")
    }
    
    /// Send notification when someone applies to a job (notify the hirer)
    func sendNewApplicationNotification(application: JobApplication, hirerId: String, applicantName: String, opportunityTitle: String) {
        let notification = AppNotification(
            id: nil,
            type: .newApplication,
            title: "New Application Received! 📋",
            message: "\(applicantName) applied to \(opportunityTitle)",
            userId: hirerId,
            relatedId: application.opportunityId,
            senderName: applicantName,
            senderImageData: application.applicantImageData,
            createdAt: Date(),
            isRead: false
        )
        
        saveNotification(notification)
        
        print("✅ Sent new application notification to hirer")
    }
    
    /// Send notification to job seeker when their application is accepted
    func sendApplicationAcceptedNotification(application: JobApplication, opportunityTitle: String) {
        let notification = AppNotification(
            id: nil,
            type: .applicationAccepted,
            title: "You Got The Job! 🎉",
            message: "You're hired for \(opportunityTitle). Open the job to see your next step.",
            userId: application.applicantId,
            relatedId: application.opportunityId,
            senderName: nil,
            senderImageData: nil,
            createdAt: Date(),
            isRead: false
        )
        
        saveNotification(notification)
        
        print("✅ Sent application accepted notification to job seeker")
    }
    
    /// Send notification to hirer when they accept an application.
    ///
    /// Intentionally a no-op since the C11 firestore.rules tightening:
    /// `notifications.create` now requires `userId != request.auth.uid`
    /// to block self-spam, and the hirer is BOTH the creator and the
    /// target here — so the write would always be denied. The hirer
    /// just tapped Accept; they already see the confirmation in the
    /// UI. Keeping the method (instead of removing every call site) so
    /// existing call sites don't have to change.
    func sendHirerAcceptedNotification(hirerId: String, applicantName: String, opportunityId: String, opportunityTitle: String, applicantImageData: Data?) {
        // Suppressed by design — see doc comment above.
        _ = (hirerId, applicantName, opportunityId, opportunityTitle, applicantImageData)
    }
    
    /// Send notification when application is rejected
    func sendApplicationRejectedNotification(application: JobApplication, opportunityTitle: String) {
        let notification = AppNotification(
            id: nil,
            type: .applicationRejected,
            title: "Application Status Update",
            message: "Your application for \(opportunityTitle) was not selected this time.",
            userId: application.applicantId,
            relatedId: application.opportunityId,
            senderName: nil,
            senderImageData: nil,
            createdAt: Date(),
            isRead: false
        )
        
        saveNotification(notification)
        
        print("✅ Sent application rejected notification")
    }
    
    /// Send notification when user receives a rating
    func sendRatingReceivedNotification(rating: Rating, recipientId: String) {
        let notification = AppNotification(
            id: nil,
            type: .ratingReceived,
            title: "New Rating ⭐",
            message: "\(rating.raterName) rated you \(rating.scoreDisplay) stars for \(rating.jobTitle)",
            userId: recipientId,
            relatedId: rating.safeId,
            senderName: rating.raterName,
            senderImageData: nil,
            createdAt: Date(),
            isRead: false
        )
        
        saveNotification(notification)
        
        print("✅ Sent rating received notification")
    }
    
    // MARK: - Save to Firebase
    
    func saveNotification(_ notification: AppNotification) {
        guard let db = db else {
            print("⚠️ NotificationManager: Firebase not configured")
            return
        }

        do {
            let docId = UUID().uuidString
            // Completion-handler form so server-side rejections (rule denials,
            // network failures) are visible. Without it, `setData(from:)`
            // accepts the local cache write and lets server errors disappear.
            try db.collection("notifications").document(docId).setData(from: notification) { error in
                if let error = error {
                    print("❌ saveNotification rejected by server: \(error.localizedDescription)")
                } else {
                    print("✅ Saved notification to Firestore")
                }
            }
        } catch {
            print("❌ Error encoding notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Local Push Notifications
    
    func sendPushNotification(_ notification: AppNotification) {
        guard AuthenticationManager.shared.currentUser?.id == notification.userId else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = .default
        content.badge = NSNumber(value: unreadCount + 1)
        
        // Add user info for handling tap
        content.userInfo = [
            "notificationId": notification.safeId,
            "type": notification.type.rawValue,
            "relatedId": notification.relatedId ?? ""
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("✅ Push notification scheduled")
            }
        }
    }
    
    // MARK: - FCM Token

    func saveFCMToken(_ token: String) {
        guard let uid = AuthenticationManager.shared.currentUser?.id, let db = db else { return }
        db.collection("users").document(uid).updateData(["fcmToken": token]) { error in
            if let error {
                print("❌ Failed to save FCM token: \(error.localizedDescription)")
            } else {
                print("✅ FCM token saved")
            }
        }
    }

    // MARK: - Mark as Read
    
    func markAsRead(notificationId: String) {
        guard let db = db else {
            print("⚠️ NotificationManager: Firebase not configured")
            return
        }
        
        db.collection("notifications").document(notificationId).updateData([
            "isRead": true
        ]) { error in
            if let error = error {
                print("❌ Error marking notification as read: \(error.localizedDescription)")
            } else {
                print("✅ Marked notification as read")
            }
        }
    }
    
    func markAllAsRead(userId: String) {
        let unreadNotifications = notifications.filter { !$0.isRead }
        
        for notification in unreadNotifications {
            markAsRead(notificationId: notification.safeId)
        }
        
        print("✅ Marked \(unreadNotifications.count) notifications as read")
    }
    
    // MARK: - Delete Notification
    
    func deleteNotification(notificationId: String) {
        guard let db = db else {
            print("⚠️ NotificationManager: Firebase not configured")
            return
        }
        
        db.collection("notifications").document(notificationId).delete { error in
            if let error = error {
                print("❌ Error deleting notification: \(error.localizedDescription)")
            } else {
                print("✅ Deleted notification")
            }
        }
    }
    
    // MARK: - Clear All Notifications
    
    func clearAllNotifications(userId: String) async {
        guard let db = db else {
            print("⚠️ NotificationManager: Firebase not configured")
            return
        }
        
        do {
            let snapshot = try await db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            print("✅ Cleared all notifications for user")
        } catch {
            print("❌ Error clearing notifications: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Log.debug("📱 Notification tapped: \(userInfo)")
        
        // Handle navigation based on notification type
        if let type = userInfo["type"] as? String,
           let relatedId = userInfo["relatedId"] as? String {
            // Post notification to handle navigation in app
            NotificationCenter.default.post(
                name: NSNotification.Name("HandleNotificationTap"),
                object: nil,
                userInfo: ["type": type, "relatedId": relatedId]
            )
        }
        
        completionHandler()
    }
}

