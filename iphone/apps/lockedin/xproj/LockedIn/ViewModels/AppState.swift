import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private let persistence: AppPersistence

    // MARK: - Navigation
    @Published var selectedTab: AppTab = .home
    @Published var showCreatePost: Bool = false

    // MARK: - User Profile
    @Published var currentUser: LockedInProfile

    // MARK: - Feed
    @Published var posts: [Post]

    // MARK: - Network
    @Published var connections: [Connection]
    @Published var invitations: [ConnectionInvitation]
    @Published var selectedNetworkTab: NetworkTab = .grow

    // MARK: - Jobs
    @Published var jobs: [Job]
    @Published var jobNotifications: [JobNotification]

    // MARK: - Notifications
    @Published var notifications: [LockedInNotification]
    @Published var selectedNotificationFilter: NotificationFilter = .all

    // MARK: - Messaging
    @Published var conversations: [Conversation]
    @Published var showMessaging: Bool = false

    // MARK: - Search
    @Published var searchQuery: String = ""
    @Published var showSearch: Bool = false

    // MARK: - Job Alerts
    @Published var jobAlertEnabled: Bool = false

    // MARK: - Connection Requests & Social
    @Published var sentConnectionRequests: Set<String> = []
    @Published var congratsSent: Set<String> = []
    @Published var followedAuthors: Set<String> = []

    // MARK: - Job Application State
    @Published var appliedJobs: Set<String> = []

    // MARK: - Post Comments
    @Published var postComments: [String: [PostComment]] = [:]

    // MARK: - Init

    init(persistence: AppPersistence = AppPersistence()) {
        self.persistence = persistence
        self.currentUser = SeedDataFactory.currentUserProfile
        self.posts = SeedDataFactory.makePosts()
        self.connections = SeedDataFactory.connections
        self.invitations = SeedDataFactory.invitations
        self.jobs = SeedDataFactory.jobs
        self.jobNotifications = SeedDataFactory.jobNotifications
        self.notifications = SeedDataFactory.allNotifications
        self.conversations = SeedDataFactory.makeConversations()
        self.postComments = SeedDataFactory.makeSeedComments(for: self.posts, connections: self.connections)

        loadPersistedState()
    }

    // MARK: - Post Actions

    func toggleLike(postId: String) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[index].userHasLiked.toggle()
        posts[index].userReaction = posts[index].userHasLiked ? .like : nil
        if posts[index].userHasLiked {
            posts[index].reactionCount += 1
        } else {
            posts[index].reactionCount = max(0, posts[index].reactionCount - 1)
        }
        saveState()
    }

    func reactToPost(postId: String, reaction: PostReactionType) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        if !posts[index].userHasLiked {
            posts[index].userHasLiked = true
            posts[index].reactionCount += 1
        }
        posts[index].userReaction = reaction
        // Move this reaction to the front of topReactions
        var reactions = posts[index].topReactions
        reactions.removeAll { $0 == reaction }
        reactions.insert(reaction, at: 0)
        posts[index].topReactions = Array(reactions.prefix(3))
        saveState()
    }

    func createPost(content: String, attachments: [PostAttachment] = [], scheduledDate: Date? = nil) {
        let now = Date()
        let photoAttachment = attachments.first(where: { $0.attachmentType == .photo })
        let newPost = Post(
            id: "post_user_\(Int(now.timeIntervalSince1970))",
            authorId: currentUser.id,
            authorName: currentUser.fullName,
            authorHeadline: currentUser.headline,
            authorInitials: currentUser.avatarInitials,
            authorAvatarTopHex: currentUser.avatarTopHex,
            authorAvatarBottomHex: currentUser.avatarBottomHex,
            content: content,
            timestamp: now,
            reactionCount: 0,
            commentCount: 0,
            repostCount: 0,
            topReactions: [],
            hasImage: photoAttachment != nil,
            imageDescription: photoAttachment?.title,
            linkPreview: nil,
            isSponsored: false,
            connectionContext: nil,
            connectionDegree: nil,
            userHasLiked: false,
            attachments: attachments,
            scheduledDate: scheduledDate
        )
        posts.insert(newPost, at: 0)
        saveState()
    }

    // MARK: - Connection Actions

    func acceptInvitation(_ invitationId: String) {
        guard let index = invitations.firstIndex(where: { $0.id == invitationId }) else { return }
        let invitation = invitations[index]
        let newConnection = Connection(
            id: "conn_\(invitation.firstName.lowercased())_\(invitation.lastName.lowercased())",
            firstName: invitation.firstName,
            lastName: invitation.lastName,
            headline: invitation.headline,
            avatarInitials: invitation.avatarInitials,
            avatarTopHex: invitation.avatarTopHex,
            avatarBottomHex: invitation.avatarBottomHex,
            degree: .first,
            mutualConnections: invitation.mutualConnections,
            isFollowing: false,
            company: "",
            location: ""
        )
        connections.append(newConnection)
        invitations.remove(at: index)
        currentUser.connectionCount += 1
        saveState()
    }

    func declineInvitation(_ invitationId: String) {
        invitations.removeAll { $0.id == invitationId }
        saveState()
    }

    // MARK: - Job Actions

    func toggleSaveJob(_ jobId: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[index].isSaved.toggle()
        saveState()
    }

    // MARK: - Messaging Actions

    func sendMessage(in conversationId: String, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let message = LockedInMessage(
            id: "msg_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))",
            senderId: currentUser.id,
            content: content,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        conversations[index].messages.append(message)
    }

    func generateReply(in conversationId: String, userMessage: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let convo = conversations[index]

        let history = convo.messages.dropLast().map {
            (role: $0.isFromCurrentUser ? "user" : "participant", content: $0.content)
        }

        let llm = LLMService.shared
        let participantName = convo.participantName
        let participantHeadline = convo.participantHeadline
        let userName = currentUser.fullName
        let userHeadline = currentUser.headline

        guard llm.isAvailable else {
            let reply = Self.fallbackReply(for: userMessage, participantName: participantName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.insertReply(in: conversationId, content: reply)
            }
            return
        }

        llm.generateReply(
            participantName: participantName,
            participantHeadline: participantHeadline,
            currentUserName: userName,
            currentUserHeadline: userHeadline,
            conversationHistory: history,
            userMessage: userMessage
        ) { [weak self] reply in
            DispatchQueue.main.async {
                let text = reply ?? Self.fallbackReply(for: userMessage, participantName: participantName)
                self?.insertReply(in: conversationId, content: text)
            }
        }
    }

    private func insertReply(in conversationId: String, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let msg = LockedInMessage(
            id: "msg_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))",
            senderId: "participant",
            content: content,
            timestamp: Date(),
            isFromCurrentUser: false
        )
        conversations[index].messages.append(msg)
    }

    private static func fallbackReply(for userMessage: String, participantName: String) -> String {
        let firstName = participantName.components(separatedBy: " ").first ?? participantName
        let lower = userMessage.lowercased()
        if lower.contains("thanks") || lower.contains("thank you") {
            return "Of course, happy to help anytime!"
        }
        if lower.contains("connect") || lower.contains("network") {
            return "Absolutely, always great to expand the network! Looking forward to staying in touch."
        }
        if lower.contains("opportunity") || lower.contains("job") || lower.contains("role") {
            return "That sounds like a great opportunity! I'd love to hear more details when you have a chance."
        }
        if lower.contains("coffee") || lower.contains("meet") || lower.contains("chat") {
            return "I'd love that! Let me check my calendar and get back to you with some times that work."
        }
        let fallbacks = [
            "That's a great point, thanks for sharing!",
            "Appreciate you reaching out, \(firstName). Let me think about that and get back to you.",
            "Thanks for the message! I'll follow up on this soon.",
            "Great to hear from you! Let's definitely keep this conversation going."
        ]
        let idx = abs(userMessage.hashValue) % fallbacks.count
        return fallbacks[idx]
    }

    func markConversationRead(_ conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].unreadCount = 0
    }

    var unreadMessageCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Connection Request Actions

    func sendConnectionRequest(_ personId: String) {
        sentConnectionRequests.insert(personId)
        // Simulate the other person accepting after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.completeConnectionRequest(personId)
        }
    }

    private func completeConnectionRequest(_ personId: String) {
        guard sentConnectionRequests.contains(personId) else { return }
        sentConnectionRequests.remove(personId)
        // Update the connection's degree to .first
        if let index = connections.firstIndex(where: { $0.id == personId }) {
            connections[index].degree = .first
            currentUser.connectionCount += 1
        }
        saveState()
    }

    func sendCongrats(_ itemId: String) {
        congratsSent.insert(itemId)
    }

    func toggleFollow(_ authorId: String) {
        if followedAuthors.contains(authorId) {
            followedAuthors.remove(authorId)
        } else {
            followedAuthors.insert(authorId)
        }
        // Also update the connection's isFollowing property if it exists
        if let index = connections.firstIndex(where: { $0.id == authorId }) {
            connections[index].isFollowing.toggle()
        }
    }

    // MARK: - Company Follow Actions

    @Published var followedCompanies: Set<String> = []

    func toggleFollowCompany(_ company: String) {
        if followedCompanies.contains(company) {
            followedCompanies.remove(company)
        } else {
            followedCompanies.insert(company)
        }
    }

    // MARK: - Job Application Actions

    func applyToJob(_ jobId: String) {
        appliedJobs.insert(jobId)
        saveState()
    }

    @Published var savedPosts: Set<String> = []

    func toggleSavePost(_ postId: String) {
        if savedPosts.contains(postId) {
            savedPosts.remove(postId)
        } else {
            savedPosts.insert(postId)
        }
    }

    @Published var repostedPosts: Set<String> = []

    func toggleRepost(_ postId: String) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        if repostedPosts.contains(postId) {
            repostedPosts.remove(postId)
            posts[index].repostCount = max(0, posts[index].repostCount - 1)
        } else {
            repostedPosts.insert(postId)
            posts[index].repostCount += 1
        }
    }

    // MARK: - Comment Actions

    func addComment(postId: String, content: String) {
        let comment = PostComment(
            id: "comment_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))",
            authorName: currentUser.fullName,
            authorHeadline: currentUser.headline,
            authorInitials: currentUser.avatarInitials,
            authorAvatarTopHex: currentUser.avatarTopHex,
            authorAvatarBottomHex: currentUser.avatarBottomHex,
            content: content,
            timestamp: Date(),
            likeCount: 0
        )
        postComments[postId, default: []].insert(comment, at: 0)
        if let index = posts.firstIndex(where: { $0.id == postId }) {
            posts[index].commentCount += 1
        }
    }

    // MARK: - New Conversation

    func startNewConversation(with connection: Connection) -> String {
        let existingConvo = conversations.first(where: { $0.participantName == connection.fullName })
        if let existing = existingConvo {
            return existing.id
        }
        let newConvo = Conversation(
            id: "convo_new_\(Int(Date().timeIntervalSince1970))",
            participantName: connection.fullName,
            participantInitials: connection.avatarInitials,
            participantAvatarTopHex: connection.avatarTopHex,
            participantAvatarBottomHex: connection.avatarBottomHex,
            participantHeadline: connection.headline,
            messages: [],
            isActive: false,
            isInMail: false,
            isSponsored: false,
            unreadCount: 0
        )
        conversations.insert(newConvo, at: 0)
        return newConvo.id
    }

    // MARK: - Notification Actions

    func markNotificationRead(_ notifId: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notifId }) else { return }
        notifications[index].isRead = true
        saveState()
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var filteredNotifications: [LockedInNotification] {
        switch selectedNotificationFilter {
        case .all:
            return notifications
        case .jobs:
            return notifications.filter { $0.type == .jobAlert }
        case .myPosts:
            return notifications.filter { $0.type == .postReaction || $0.type == .postComment }
        case .mentions:
            return notifications.filter { $0.type == .mention }
        }
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let savedJobIds = persistence.loadSavedJobIds() {
            for i in jobs.indices {
                jobs[i].isSaved = savedJobIds.contains(jobs[i].id)
            }
        }
        let userReactions = persistence.loadUserReactions()
        if let likedPostIds = persistence.loadLikedPostIds() {
            for i in posts.indices {
                let liked = likedPostIds.contains(posts[i].id)
                if liked != posts[i].userHasLiked {
                    posts[i].reactionCount = max(0, posts[i].reactionCount + (liked ? 1 : -1))
                }
                posts[i].userHasLiked = liked
                posts[i].userReaction = liked ? userReactions[posts[i].id] : nil
            }
        }
        if let dismissedInvIds = persistence.loadDismissedInvitationIds() {
            invitations.removeAll { dismissedInvIds.contains($0.id) }
        }
    }

    private func saveState() {
        let savedJobIds = Set(jobs.filter { $0.isSaved }.map { $0.id })
        persistence.persistSavedJobIds(savedJobIds)

        let likedPostIds = Set(posts.filter { $0.userHasLiked }.map { $0.id })
        persistence.persistLikedPostIds(likedPostIds)
        persistence.persistUserReactions(Dictionary(uniqueKeysWithValues: posts.compactMap { post in
            post.selectedReaction.map { (post.id, $0) }
        }))
    }

    func resetState() {
        persistence.clearAll()
        currentUser = SeedDataFactory.currentUserProfile
        posts = SeedDataFactory.makePosts()
        connections = SeedDataFactory.connections
        invitations = SeedDataFactory.invitations
        jobs = SeedDataFactory.jobs
        jobNotifications = SeedDataFactory.jobNotifications
        notifications = SeedDataFactory.allNotifications
        conversations = SeedDataFactory.makeConversations()
        selectedTab = .home
        selectedNotificationFilter = .all
        selectedNetworkTab = .grow
        searchQuery = ""
        sentConnectionRequests = []
        congratsSent = []
        followedAuthors = []
        followedCompanies = []
        appliedJobs = []
        postComments = SeedDataFactory.makeSeedComments(for: posts, connections: connections)
    }
}
