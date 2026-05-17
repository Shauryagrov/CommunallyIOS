//
//  MessagingView.swift
//  Communally
//
//  Shows all active and archived chat conversations.
//  Chats auto-archive when the linked job is completed.
//

import SwiftUI

private let kArchivedConvIdsKey = "communally_archived_conv_ids"

private enum MessageFilter: String, CaseIterable {
    case active   = "Active"
    case archived = "Archived"
}

struct MessagingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var messageManager     = MessageManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var applicationManager = ApplicationManager.shared

    @State private var selectedConversation: Conversation?
    @State private var filter: MessageFilter = .active
    @State private var archivedIds: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: kArchivedConvIdsKey) ?? [])
    }()

    // MARK: - Filtering

    private func isJobCompleted(for conv: Conversation) -> Bool {
        applicationManager.applications.contains { app in
            app.opportunityId == conv.opportunityId &&
            app.applicantId   == conv.applicantId &&
            app.status        == .completed
        }
    }

    /// True when the same hirer/applicant pair have a fresh non-completed
    /// application — accepted, in progress, or even pending. Drives the
    /// archive override below so a chat snaps back to "Active" the moment
    /// they start working together again.
    private func hasLiveJobBetween(_ conv: Conversation) -> Bool {
        applicationManager.applications.contains { app in
            app.applicantId == conv.applicantId
                && (app.hirerIdSnapshot == conv.hirerId)
                && app.status != .completed
                && app.status != .rejected
                && app.status != .cancelled
        }
    }

    private func isArchived(_ conv: Conversation) -> Bool {
        // If they're working together again, every chat in their thread comes
        // back to life — even ones the user manually archived after a prior
        // completed gig. Auto-clears the stale UserDefaults flag too so the
        // override is durable and the chat doesn't bounce back to archived
        // when the new job finishes.
        if hasLiveJobBetween(conv) {
            if archivedIds.contains(conv.id) {
                archivedIds.remove(conv.id)
                UserDefaults.standard.set(Array(archivedIds), forKey: kArchivedConvIdsKey)
            }
            return false
        }
        return archivedIds.contains(conv.id) || isJobCompleted(for: conv)
    }

    private var displayed: [Conversation] {
        messageManager.conversations.filter {
            filter == .active ? !isArchived($0) : isArchived($0)
        }
    }

    private func archive(_ conv: Conversation) {
        archivedIds.insert(conv.id)
        UserDefaults.standard.set(Array(archivedIds), forKey: kArchivedConvIdsKey)
    }

    private func restore(_ conv: Conversation) {
        archivedIds.remove(conv.id)
        UserDefaults.standard.set(Array(archivedIds), forKey: kArchivedConvIdsKey)
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                CommunallyTheme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    filterBar
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 8)

                    if displayed.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            // Force the large title color black on every device — without this
            // some devices render it white/invisible against our light bg.
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.white, for: .navigationBar)
            .sheet(item: $selectedConversation) { conv in
                NavigationView {
                    ChatView(conversation: conv).environmentObject(authManager)
                }
            }
            .onAppear {
                if let uid = authManager.currentUser?.id, !messageManager.isListening {
                    messageManager.startListening(for: uid)
                }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(MessageFilter.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { filter = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(filter == tab ? .white : CommunallyTheme.darkGray.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(filter == tab ? CommunallyTheme.primaryGreen : Color.clear)
                                .shadow(color: filter == tab
                                        ? CommunallyTheme.primaryGreen.opacity(0.28) : .clear,
                                        radius: 6, x: 0, y: 3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.72))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        List {
            ForEach(displayed) { conv in
                ConversationCard(
                    conversation: conv,
                    currentUserId: authManager.currentUser?.id ?? "",
                    opportunity: opportunityManager.opportunities.first { $0.safeId == conv.opportunityId },
                    relationshipNote: relationshipNote(for: conv)
                ) {
                    selectedConversation = conv
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if filter == .active {
                        Button { withAnimation { archive(conv) } } label: {
                            Label("Archive", systemImage: "archivebox.fill")
                        }
                        .tint(.orange)
                    } else {
                        Button { withAnimation { restore(conv) } } label: {
                            Label("Restore", systemImage: "arrow.uturn.left.circle.fill")
                        }
                        .tint(CommunallyTheme.primaryGreen)
                    }
                }
            }
            Color.clear.frame(height: 72)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            if let uid = authManager.currentUser?.id {
                messageManager.stopListening()
                messageManager.startListening(for: uid)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        // Minimal: small icon + headline, vertically centered. No layered halo
        // circles, no marketing paragraph — just enough so the screen doesn't
        // feel empty.
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: filter == .active
                  ? "bubble.left.and.bubble.right"
                  : "archivebox")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.55))
            Text(filter == .active ? "No active chats" : "No archived chats")
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Relationship note

    private func relationshipNote(for conv: Conversation) -> String? {
        let n = applicationManager.applications.filter { app in
            guard app.applicantId == conv.applicantId,
                  app.status      == .completed,
                  let opp = opportunityManager.opportunities.first(where: { $0.safeId == app.opportunityId })
            else { return false }
            return opp.hirerId == conv.hirerId
        }.count
        guard n > 0 else { return nil }
        return authManager.currentUser?.id == conv.hirerId
            ? (n == 1 ? "Worked for you before" : "Worked for you \(n)×")
            : (n == 1 ? "You worked for them before" : "You worked for them \(n)×")
    }
}

// MARK: - Conversation Card

struct ConversationCard: View {
    let conversation: Conversation
    let currentUserId: String
    let opportunity: Opportunity?
    let relationshipNote: String?
    let onTap: () -> Void

    private var otherName: String { conversation.otherUserName(currentUserId: currentUserId) }
    private var otherImage: Data? { conversation.otherUserImageData(currentUserId: currentUserId) }
    private var hasUnread: Bool   { conversation.unreadCount > 0 }

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onTap() }) {
            VStack(spacing: 0) {

                // Main row
                HStack(spacing: 14) {
                    // Avatar + unread badge
                    ZStack(alignment: .topTrailing) {
                        avatarCircle
                            .frame(width: 52, height: 52)

                        if hasUnread {
                            ZStack {
                                Circle().fill(Color.red).frame(width: 20, height: 20)
                                Text("\(min(conversation.unreadCount, 99))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 4, y: -4)
                        }
                    }

                    // Text
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(otherName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                                .lineLimit(1)
                            Spacer()
                            Text(conversation.timeAgo)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.58, green: 0.58, blue: 0.60))
                        }

                        Text(conversation.lastMessage)
                            .font(.system(size: 14, weight: hasUnread ? .semibold : .regular))
                            .foregroundStyle(hasUnread
                                             ? Color(red: 0.12, green: 0.12, blue: 0.14)
                                             : Color(red: 0.50, green: 0.50, blue: 0.52))
                            .lineLimit(1)

                        if let note = relationshipNote {
                            Text(note)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CommunallyTheme.messageGreen.opacity(0.90))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                // Job footer
                if let opp = opportunity {
                    Rectangle()
                        .fill(Color(red: 0.92, green: 0.92, blue: 0.93))
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)

                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(CommunallyTheme.messageGreen.opacity(0.12))
                                .frame(width: 26, height: 26)
                            Image(systemName: iconForJobType(opp.jobType))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CommunallyTheme.messageGreen)
                        }

                        Text(opp.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.36, green: 0.36, blue: 0.38))
                            .lineLimit(1)

                        Spacer()

                        HStack(spacing: 4) {
                            Circle().fill(opp.statusColor).frame(width: 5, height: 5)
                            Text(opp.statusDisplay)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.50, green: 0.50, blue: 0.52))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarCircle: some View {
        Circle()
            .fill(CommunallyTheme.messageGreen.opacity(0.14))
            .overlay(
                Group {
                    if let data = otherImage, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(CommunallyTheme.messageGreen)
                    }
                }
            )
            .overlay(
                Circle().strokeBorder(
                    hasUnread ? CommunallyTheme.primaryGreen.opacity(0.50) : Color.clear,
                    lineWidth: 2
                )
            )
    }

    private func iconForJobType(_ type: String) -> String {
        switch type.lowercased() {
        case "gardening":   return "leaf.fill"
        case "pet care":    return "pawprint.fill"
        case "tutoring":    return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting":    return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help":  return "calendar.badge.plus"
        case "cleaning":    return "sparkles"
        default:            return "briefcase.fill"
        }
    }
}

#Preview {
    MessagingView().environmentObject(AuthenticationManager.shared)
}
