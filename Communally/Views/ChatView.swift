//
//  ChatView.swift
//  Communally
//
//  MessageKit-powered chat interface for accepted job applications
//

import SwiftUI
import MessageKit
import InputBarAccessoryView

struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var messageManager = MessageManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    
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
            
            // MessageKit Chat View
            MessageKitChatViewController(
                conversation: conversation,
                currentUser: authManager.currentUser,
                messageManager: messageManager
            )
            .ignoresSafeArea(.all, edges: .bottom)
        }
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
        .onAppear {
            // Mark conversation as read
            if let userId = authManager.currentUser?.id {
                messageManager.markAsRead(conversationId: conversation.id, userId: userId)
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

// MARK: - MessageKit UIViewController Wrapper

struct MessageKitChatViewController: UIViewControllerRepresentable {
    let conversation: Conversation
    let currentUser: User?
    let messageManager: MessageManager
    
    func makeUIViewController(context: Context) -> ChatViewController {
        let vc = ChatViewController(
            conversation: conversation,
            currentUser: currentUser,
            messageManager: messageManager
        )
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ChatViewController, context: Context) {
        uiViewController.reloadMessages()
    }
}

// MARK: - ChatViewController (MessageKit)

class ChatViewController: MessagesViewController {
    let conversation: Conversation
    let currentUser: User?
    let messageManager: MessageManager
    
    private var messages: [MessageType] {
        return messageManager.getMessages(for: conversation.id)
    }
    
    init(conversation: Conversation, currentUser: User?, messageManager: MessageManager) {
        self.conversation = conversation
        self.currentUser = currentUser
        self.messageManager = messageManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureMessageCollectionView()
        configureMessageInputBar()
        
        // Listen for message updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadMessages),
            name: NSNotification.Name("MessagesUpdated"),
            object: nil
        )
    }
    
    private func configureMessageCollectionView() {
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        
        // Styling
        messagesCollectionView.backgroundColor = UIColor(red: 0.97, green: 0.99, blue: 0.95, alpha: 1.0)
        
        // Avatar
        if let layout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout {
            layout.setMessageIncomingAvatarSize(CGSize(width: 36, height: 36))
            layout.setMessageOutgoingAvatarSize(CGSize(width: 0, height: 0))
        }
        
        // Scroll to bottom on load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.messages.isEmpty else { return }
            let lastSection = self.messages.count - 1
            self.messagesCollectionView.scrollToItem(
                at: IndexPath(item: 0, section: lastSection),
                at: .bottom,
                animated: false
            )
        }
    }
    
    private func configureMessageInputBar() {
        messageInputBar.delegate = self
        
        // Styling
        messageInputBar.backgroundView.backgroundColor = .white
        messageInputBar.inputTextView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        messageInputBar.inputTextView.placeholderTextColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        messageInputBar.inputTextView.layer.cornerRadius = 20
        messageInputBar.inputTextView.layer.masksToBounds = true
        messageInputBar.inputTextView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        
        // Send button styling
        messageInputBar.sendButton.setTitleColor(UIColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 1.0), for: .normal)
        messageInputBar.sendButton.setTitle("", for: .normal)
        messageInputBar.sendButton.image = UIImage(systemName: "arrow.up.circle.fill")
        messageInputBar.sendButton.title = nil
        messageInputBar.sendButton.tintColor = UIColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 1.0)
    }
    
    @objc func reloadMessages() {
        messagesCollectionView.reloadData()
        
        // Scroll to last message
        guard !messages.isEmpty else { return }
        let lastSection = messages.count - 1
        DispatchQueue.main.async { [weak self] in
            self?.messagesCollectionView.scrollToItem(
                at: IndexPath(item: 0, section: lastSection),
                at: .bottom,
                animated: true
            )
        }
    }
}

// MARK: - MessagesDataSource

extension ChatViewController: MessagesDataSource {
    var currentSender: MessageKit.SenderType {
        guard let user = currentUser else {
            return Sender(senderId: "unknown", displayName: "Unknown")
        }
        return Sender(senderId: user.id, displayName: user.fullName)
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessageKit.MessagesCollectionView) -> MessageKit.MessageType {
        return messages[indexPath.section]
    }
    
    func numberOfSections(in messagesCollectionView: MessageKit.MessagesCollectionView) -> Int {
        return messages.count
    }
    
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let name = message.sender.displayName
        return NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.gray
            ]
        )
    }
    
    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let dateString = formatter.string(from: message.sentDate)
        
        return NSAttributedString(
            string: dateString,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
        )
    }
}

// MARK: - MessagesLayoutDelegate

extension ChatViewController: MessagesLayoutDelegate {
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 20
    }
    
    func messageBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 16
    }
}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ?
            UIColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 1.0) :
            UIColor.white
    }
    
    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .white : .black
    }
    
    func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
        let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
        return .bubbleTail(corner, .curved)
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        // Get other user's image data
        let otherUserImageData = conversation.otherUserImageData(currentUserId: currentUser?.id ?? "")
        
        if !isFromCurrentSender(message: message), let imageData = otherUserImageData, let image = UIImage(data: imageData) {
            avatarView.image = image
        } else {
            // Placeholder avatar
            avatarView.backgroundColor = UIColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 0.2)
            avatarView.initials = String(message.sender.displayName.prefix(1))
        }
    }
}

// MARK: - MessageCellDelegate

extension ChatViewController: MessageCellDelegate {
    func didTapMessage(in cell: MessageCollectionViewCell) {
        // Handle message tap if needed
    }
}

// MARK: - InputBarAccessoryViewDelegate

extension ChatViewController: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty,
              let user = currentUser else {
            return
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Send message
        messageManager.sendMessage(
            conversationId: conversation.id,
            senderId: user.id,
            senderName: user.fullName,
            text: trimmedText
        )
        
        // Clear input
        inputBar.inputTextView.text = ""
        inputBar.invalidatePlugins()
        
        // Reload and scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.reloadMessages()
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
