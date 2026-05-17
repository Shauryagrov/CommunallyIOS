//
//  MessageManager.swift
//  Communally
//
//  Manages messaging between hirers and accepted applicants using MessageKit
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine
import MessageKit
import UIKit

class MessageManager: ObservableObject {
    static let shared = MessageManager()
    
    @Published var conversations: [Conversation] = []
    @Published var messages: [String: [MessageType]] = [:] // conversationId -> MessageKit messages
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    private var conversationListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]

    var isListening: Bool { conversationListener != nil }

    private init() {
        // Listeners started when user logs in
    }
    
    deinit {
        conversationListener?.remove()
        messageListeners.values.forEach { $0.remove() }
    }
    
    // MARK: - Start Listening
    
    func startListening(for userId: String) {
        print("📨 Starting message listener for user: \(userId)")
        
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            return
        }
        
        // Stop existing listeners
        stopListening()
        
        // Listen to conversations where user is a participant.
        // No .order() here — that would require a composite Firestore index which may
        // not exist. We sort in memory after parsing so the listener works out of the box.
        conversationListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Error listening to conversations: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("ℹ️ No conversations found")
                    return
                }

                self.conversations = documents.compactMap { doc -> Conversation? in
                    let data = doc.data()
                    
                    guard let opportunityId = data["opportunityId"] as? String,
                          let hirerId = data["hirerId"] as? String,
                          let hirerName = data["hirerName"] as? String,
                          let applicantId = data["applicantId"] as? String,
                          let applicantName = data["applicantName"] as? String,
                          let participantIds = data["participantIds"] as? [String],
                          let rawLastMessage = data["lastMessage"] as? String,
                          let lastMessageAtTimestamp = data["lastMessageAt"] as? Timestamp,
                          let createdAtTimestamp = data["createdAt"] as? Timestamp else {
                        return nil
                    }
                    let lastMessage = MessageEncryptionService.decrypt(rawLastMessage)
                    
                    let hirerImageData = OpportunityManager.shared.opportunities
                        .first { $0.hirerId == hirerId }?.hirerImageData
                    let applicantImageData = ApplicationManager.shared.applications
                        .first { $0.applicantId == applicantId && $0.opportunityId == opportunityId }?.applicantImageData
                    
                    let unreadCount = data["unreadCount_\(userId)"] as? Int ?? 0
                    
                    return Conversation(
                        id: doc.documentID,
                        opportunityId: opportunityId,
                        hirerId: hirerId,
                        hirerName: hirerName,
                        hirerImageData: hirerImageData,
                        applicantId: applicantId,
                        applicantName: applicantName,
                        applicantImageData: applicantImageData,
                        participantIds: participantIds,
                        lastMessage: lastMessage,
                        lastMessageAt: lastMessageAtTimestamp.dateValue(),
                        unreadCount: unreadCount,
                        createdAt: createdAtTimestamp.dateValue()
                    )
                }
                
                // Sort newest-first in memory (avoids requiring a composite Firestore index)
                self.conversations.sort { $0.lastMessageAt > $1.lastMessageAt }

                print("✅ Synced \(self.conversations.count) conversations")

                // Remove any base64 image data stored in Firestore docs (causes >1 MB writes)
                if let docs = snapshot?.documents {
                    self.repairOversizedConversations(documents: docs)
                }

                // Start listening to messages for each conversation
                for conversation in self.conversations {
                    self.startListeningToMessages(conversationId: conversation.id, currentUserId: userId)
                }
            }
    }
    
    func stopListening() {
        conversationListener?.remove()
        conversationListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        messages.removeAll()
    }

    /// Wipes in-memory state + listeners. Used after account deletion so the
    /// next sign-in starts clean instead of flashing old conversations.
    func clearLocalState() {
        stopListening()
        DispatchQueue.main.async {
            self.conversations = []
            self.messages = [:]
        }
    }

    // Strips base64 image fields from any conversation doc that has them.
    // These were stored historically and cause documents to exceed Firestore's 1 MB write limit.
    private func repairOversizedConversations(documents: [QueryDocumentSnapshot]) {
        let oversized = documents.filter { doc in
            let d = doc.data()
            return d["hirerImageData"] != nil || d["applicantImageData"] != nil
        }
        guard !oversized.isEmpty, let db = db else { return }

        Task {
            for doc in oversized {
                do {
                    try await db.collection("conversations").document(doc.documentID).updateData([
                        "hirerImageData": FieldValue.delete(),
                        "applicantImageData": FieldValue.delete()
                    ])
                    print("✅ Stripped image data from conversation: \(doc.documentID)")
                } catch {
                    // updateData may still fail if the doc is already > 1 MB; fall back to delete + recreate
                    var clean = doc.data()
                    clean.removeValue(forKey: "hirerImageData")
                    clean.removeValue(forKey: "applicantImageData")
                    do {
                        try await db.collection("conversations").document(doc.documentID).delete()
                        try await db.collection("conversations").document(doc.documentID).setData(clean)
                        print("✅ Repaired oversized conversation: \(doc.documentID)")
                    } catch {
                        print("❌ Error repairing conversation \(doc.documentID): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Messages
    
    private func startListeningToMessages(conversationId: String, currentUserId: String) {
        // Don't create duplicate listeners
        guard messageListeners[conversationId] == nil else { return }
        
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            return
        }
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "sentAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to messages: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                // Convert Firebase messages to MessageKit messages
                let messageKitMessages: [MessageType] = documents.compactMap { doc -> MessageType? in
                    let data = doc.data()
                    
                    guard let senderId = data["senderId"] as? String,
                          let senderName = data["senderName"] as? String,
                          let rawText = data["text"] as? String,
                          let sentAtTimestamp = data["sentAt"] as? Timestamp else {
                        return nil
                    }

                    let text = MessageEncryptionService.decrypt(rawText)
                    let sender = Sender(senderId: senderId, displayName: senderName)
                    let messageId = doc.documentID
                    let sentDate = sentAtTimestamp.dateValue()

                    return ChatMessage(
                        messageId: messageId,
                        sender: sender,
                        sentDate: sentDate,
                        kind: .text(text)
                    )
                }
                
                self.messages[conversationId] = messageKitMessages
                
                // Post notification to update UI
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("MessagesUpdated"), object: nil)
                }
                
                print("✅ Synced \(messageKitMessages.count) messages for conversation \(conversationId)")
            }
        
        messageListeners[conversationId] = listener
    }
    
    // MARK: - Create Conversation
    
    func createConversation(
        opportunityId: String,
        hirerId: String,
        hirerName: String,
        hirerImageData: Data?,
        applicantId: String,
        applicantName: String,
        applicantImageData: Data?
    ) async -> String? {
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            return nil
        }
        
        let contextUpdateData: [String: Any] = [
            "opportunityId": opportunityId,
            "hirerName": hirerName,
            "applicantName": applicantName,
            "participantIds": [hirerId, applicantId]
        ]
        
        // Reuse the same thread for the same hirer/applicant pair.
        if let existing = conversations.first(where: {
            $0.hirerId == hirerId &&
            $0.applicantId == applicantId
        }) {
            do {
                try await db.collection("conversations").document(existing.id).updateData(contextUpdateData)
            } catch {
                print("⚠️ Error refreshing conversation context: \(error.localizedDescription)")
            }
            
            print("ℹ️ Conversation already exists: \(existing.id)")
            return existing.id
        }
        
        let conversationId = UUID().uuidString
        
        let conversationData: [String: Any] = [
            "opportunityId": opportunityId,
            "hirerId": hirerId,
            "hirerName": hirerName,
            "applicantId": applicantId,
            "applicantName": applicantName,
            "participantIds": [hirerId, applicantId],
            "lastMessage": "Chat created! Start discussing job details.",
            "lastMessageAt": Timestamp(date: Date()),
            "unreadCount_\(hirerId)": 0,
            "unreadCount_\(applicantId)": 0,
            "createdAt": Timestamp(date: Date())
        ]

        do {
            try await db.collection("conversations").document(conversationId).setData(conversationData)
            print("✅ Created conversation: \(conversationId)")
            return conversationId
        } catch {
            print("❌ Error creating conversation: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Send Message
    
    func sendMessage(
        conversationId: String,
        senderId: String,
        senderName: String,
        text: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            completion?(.failure(NSError(domain: "MessageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            return
        }
        
        if let moderationError = ContentModerationService.shared.validateMessage(text) {
            completion?(.failure(moderationError))
            return
        }
        
        let messageId = UUID().uuidString
        let now = Timestamp(date: Date())
        let encryptedText = MessageEncryptionService.encrypt(text)

        let messageData: [String: Any] = [
            "senderId": senderId,
            "senderName": senderName,
            "text": encryptedText,
            "sentAt": now
        ]
        
        // Add message to subcollection
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .setData(messageData) { error in
                if let error = error {
                    print("❌ Error sending message: \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }
                
                print("✅ Message sent")
                completion?(.success(()))
            }
        
        // Update conversation's last message
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return }
        
        let otherUserId = conversation.participantIds.first { $0 != senderId } ?? ""
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "lastMessage": encryptedText,
                "lastMessageAt": now,
                "unreadCount_\(otherUserId)": FieldValue.increment(Int64(1))
            ]) { error in
                if let error = error {
                    print("❌ Failed to update conversation lastMessage: \(error.localizedDescription)")
                }
            }
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(conversationId: String, userId: String) {
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            return
        }
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "unreadCount_\(userId)": 0
            ]) { error in
                if let error = error {
                    print("❌ Error marking as read: \(error.localizedDescription)")
                } else {
                    print("✅ Marked conversation as read")
                }
            }
    }
    
    // MARK: - Get Messages
    
    func getMessages(for conversationId: String) -> [MessageType] {
        return messages[conversationId] ?? []
    }
    
    // MARK: - Get Sender
    
    func getSender(for userId: String, name: String) -> SenderType {
        return Sender(senderId: userId, displayName: name)
    }
    
    // MARK: - Profile Sync
    
    func updateUserProfile(userId: String, name: String, imageData: Data?) async {
        guard let db = db else {
            print("⚠️ MessageManager: Firebase not configured")
            return
        }
        
        print("🔄 Updating user profile in conversations for user: \(userId)")
        
        // Get all conversations where this user is a participant
        let userConversations = conversations.filter { $0.participantIds.contains(userId) }
        
        for conversation in userConversations {
            var updateData: [String: Any] = [:]
            
            // Determine if user is hirer or applicant in this conversation
            if conversation.hirerId == userId {
                updateData["hirerName"] = name
            } else if conversation.applicantId == userId {
                updateData["applicantName"] = name
            }
            
            if !updateData.isEmpty {
                do {
                    try await db.collection("conversations").document(conversation.id).updateData(updateData)
                    print("✅ Updated conversation \(conversation.id) with new profile")
                } catch {
                    print("❌ Error updating conversation \(conversation.id): \(error.localizedDescription)")
                }
            }
        }
        
        print("✅ Updated \(userConversations.count) conversations with new profile")
    }
}

// MARK: - MessageKit Models

// Sender for MessageKit
struct Sender: SenderType {
    var senderId: String
    var displayName: String
}

// ChatMessage for MessageKit
struct ChatMessage: MessageType {
    var messageId: String
    var sender: SenderType
    var sentDate: Date
    var kind: MessageKind
}

// MARK: - Conversation Model

struct Conversation: Identifiable, Codable {
    let id: String
    let opportunityId: String
    let hirerId: String
    let hirerName: String
    let hirerImageData: Data?
    let applicantId: String
    let applicantName: String
    let applicantImageData: Data?
    let participantIds: [String]
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int
    let createdAt: Date
    
    func otherUserName(currentUserId: String) -> String {
        return currentUserId == hirerId ? applicantName : hirerName
    }
    
    func otherUserImageData(currentUserId: String) -> Data? {
        return currentUserId == hirerId ? applicantImageData : hirerImageData
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastMessageAt, relativeTo: Date())
    }
}
