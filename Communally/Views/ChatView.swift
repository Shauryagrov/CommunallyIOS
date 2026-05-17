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
    @ObservedObject private var applicationManager = ApplicationManager.shared
    
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
    
    private var relationshipNote: String? {
        let completedCount = applicationManager.applications.filter { application in
            guard application.applicantId == conversation.applicantId,
                  application.status == .completed,
                  let opportunity = opportunityManager.opportunities.first(where: { $0.safeId == application.opportunityId }) else {
                return false
            }
            
            return opportunity.hirerId == conversation.hirerId
        }.count
        
        guard completedCount > 0 else { return nil }
        
        if authManager.currentUser?.id == conversation.hirerId {
            return completedCount == 1 ? "Worked for you before" : "Worked for you \(completedCount)x"
        }
        
        return completedCount == 1 ? "You worked for them before" : "You worked for them \(completedCount)x"
    }
    
    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient
                .ignoresSafeArea()
            
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
        }
        .navigationTitle(otherUserName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.white.opacity(0.96), for: .navigationBar)
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
                                    .stroke(CommunallyTheme.primaryGreen, lineWidth: 2)
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.2))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(otherUserName)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        if let relationshipNote {
                            Text(relationshipNote)
                                .font(.system(size: 11, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.messageGreen.opacity(0.95))
                                .lineLimit(1)
                        }
                    }
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
                        .fill(CommunallyTheme.primaryGreen.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: iconForJobType(opportunity.jobType))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(opportunity.title)
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(opportunity.statusColor)
                            .frame(width: 6, height: 6)
                        
                        Text(opportunity.statusDisplay)
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        
                        Text("•")
                            .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                        
                        Text(opportunity.displayPay)
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.96))
            
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

        messagesCollectionView.backgroundColor = UIColor(red: 0.96, green: 0.98, blue: 0.96, alpha: 1.0)
        messagesCollectionView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        if let layout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout {
            layout.setMessageIncomingAvatarSize(CGSize(width: 30, height: 30))
            layout.setMessageOutgoingAvatarSize(.zero)
            layout.minimumLineSpacing = 2
        }

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

        // Clean white bar with a subtle top border
        messageInputBar.backgroundView.backgroundColor = .white
        messageInputBar.separatorLine.backgroundColor = UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)

        // Text field
        messageInputBar.inputTextView.backgroundColor = UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1.0)
        messageInputBar.inputTextView.placeholderTextColor = UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1.0)
        messageInputBar.inputTextView.textColor = UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        messageInputBar.inputTextView.layer.cornerRadius = 18
        messageInputBar.inputTextView.layer.masksToBounds = true
        messageInputBar.inputTextView.font = UIFont.systemFont(ofSize: 16, weight: .regular)

        // Send button — brand green, large SF Symbol
        let brandGreen = UIColor(red: 0.18, green: 0.65, blue: 0.36, alpha: 1.0)
        messageInputBar.sendButton.setTitle("", for: .normal)
        messageInputBar.sendButton.title = nil
        messageInputBar.sendButton.image = UIImage(
            systemName: "arrow.up.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        )
        messageInputBar.sendButton.tintColor = brandGreen
        messageInputBar.sendButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 2)
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
    
    private func presentSendError(_ message: String) {
        let alert = UIAlertController(title: "Message Blocked", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
        return nil
    }

    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return NSAttributedString(
            string: formatter.string(from: message.sentDate),
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1.0)
            ]
        )
    }
}

// MARK: - MessagesLayoutDelegate

extension ChatViewController: MessagesLayoutDelegate {
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 0
    }

    func messageBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 14
    }

    func cellTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        // Show date header every 10 messages
        return indexPath.section % 10 == 0 ? 28 : 0
    }
}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message)
            ? UIColor(red: 0.18, green: 0.65, blue: 0.36, alpha: 1.0)   // rich brand green
            : UIColor.white
    }
    
    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .white : .black
    }
    
    func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
        let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
        return .bubbleTail(corner, .curved)
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard !isFromCurrentSender(message: message) else {
            avatarView.isHidden = true
            return
        }
        let otherImageData = conversation.otherUserImageData(currentUserId: currentUser?.id ?? "")
        if let data = otherImageData, let image = UIImage(data: data) {
            avatarView.image = image
        } else {
            avatarView.backgroundColor = UIColor(red: 0.18, green: 0.65, blue: 0.36, alpha: 0.14)
            avatarView.initials = String(message.sender.displayName.prefix(1)).uppercased()
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
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    inputBar.inputTextView.text = ""
                    inputBar.invalidatePlugins()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.reloadMessages()
                    }
                case .failure(let error):
                    self?.presentSendError(error.localizedDescription)
                }
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
