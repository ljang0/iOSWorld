import SwiftUI

struct PostCardView: View {
    @EnvironmentObject private var appState: AppState
    let post: Post
    @State private var isExpanded: Bool = false
    @State private var showDetail: Bool = false
    @State private var showProfile: Bool = false
    @State private var showCopied: Bool = false
    @State private var isHidden: Bool = false
    @State private var showOwnPostActions: Bool = false
    @State private var showContextActions: Bool = false
    @State private var showReactionPicker: Bool = false

    private var livePost: Post {
        appState.posts.first(where: { $0.id == post.id }) ?? post
    }

    private let maxCollapsedLines = 4
    private let maxCollapsedChars = 200

    var body: some View {
        if !isHidden {
        VStack(alignment: .leading, spacing: 0) {
            // Connection context (e.g., "Junwon Seo likes this")
            if let context = post.connectionContext {
                HStack(spacing: 6) {
                    AvatarView(
                        initials: String(context.prefix(1)),
                        topHex: "0x444444",
                        bottomHex: "0x888888",
                        size: 16
                    )
                    Text(context)
                        .font(.system(size: 12))
                        .foregroundColor(LockedInTheme.secondaryText)
                    Spacer()
                    Button(action: { showContextActions = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                    Button(action: { withAnimation { isHidden = true } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            // Sponsored: only show ... on top-right
            if post.isSponsored && post.connectionContext == nil {
                HStack {
                    Spacer()
                    Button(action: { showContextActions = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Author row
            HStack(alignment: .top, spacing: 10) {
                Button {
                    showProfile = true
                } label: {
                    AvatarView(
                        name: post.authorName,
                        initials: post.authorInitials,
                        topHex: post.authorAvatarTopHex,
                        bottomHex: post.authorAvatarBottomHex,
                        size: 48
                    )
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Button {
                            showProfile = true
                        } label: {
                            Text(post.authorName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(LockedInTheme.primaryText)
                        }
                        if !post.isSponsored && post.authorId != appState.currentUser.id {
                            Text("\u{2022} \(post.connectionDegree ?? "2nd")")
                                .font(.system(size: 13))
                                .foregroundColor(LockedInTheme.secondaryText)
                        }
                    }

                    Text(post.authorHeadline)
                        .font(.system(size: 12))
                        .foregroundColor(LockedInTheme.secondaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(post.timestamp.linkedInTimeAgo())
                            .font(.system(size: 12))
                            .foregroundColor(LockedInTheme.secondaryText)
                        if post.scheduledDate != nil {
                            Text("Scheduled")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(LockedInTheme.linkedInBlue))
                                .accessibilityIdentifier("post_scheduled_badge_\(post.id)")
                        } else {
                            Text("\u{2022}")
                                .font(.system(size: 8))
                                .foregroundColor(LockedInTheme.secondaryText)
                            if post.isSponsored {
                                Text("Promoted")
                                    .font(.system(size: 12))
                                    .foregroundColor(LockedInTheme.secondaryText)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundColor(LockedInTheme.secondaryText)
                            }
                        }
                    }
                }

                Spacer()

                if post.connectionContext == nil && !post.isSponsored {
                    if post.authorId != appState.currentUser.id {
                        if appState.followedAuthors.contains(post.authorId) {
                            Button(action: { appState.toggleFollow(post.authorId) }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Following")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(LockedInTheme.secondaryText)
                            }
                        } else {
                            Button(action: { appState.toggleFollow(post.authorId) }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Follow")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(LockedInTheme.linkedInBlue)
                            }
                        }
                    } else {
                        Button(action: { showOwnPostActions = true }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14))
                                .foregroundColor(LockedInTheme.secondaryText)
                        }
                        .confirmationDialog("", isPresented: $showOwnPostActions) {
                            Button("Edit post") { showDetail = true }
                            Button("Delete post", role: .destructive) { withAnimation { isHidden = true } }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, post.connectionContext != nil ? 0 : 12)

            // Post content with ...more
            postContent
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Link preview
            if let link = post.linkPreview {
                linkPreviewCard(link)
                    .padding(.top, 8)
            }

            // Image placeholder
            if post.hasImage {
                Rectangle()
                    .fill(Color(hex: 0xE8E8E8))
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: 0xBBBBBB))
                            if let desc = post.imageDescription {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundColor(LockedInTheme.secondaryText)
                            }
                        }
                    }
                    .padding(.top, 8)
            }

            // Video placeholder
            if post.hasVideo {
                Rectangle()
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.9))
                            if let duration = post.videoDuration {
                                Text(duration)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                            }
                        }
                    }
                    .padding(.top, 8)
            }

            // Attachments
            if !post.attachments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(post.attachments) { attachment in
                        postAttachmentCard(attachment)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Poll
            if let poll = post.poll {
                pollCard(poll)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Reaction summary
            if livePost.reactionCount > 0 || post.commentCount > 0 {
                HStack(spacing: 4) {
                    HStack(spacing: -2) {
                        ForEach(livePost.topReactions.prefix(3), id: \.self) { reaction in
                            reactionIcon(reaction)
                        }
                    }

                    Text(livePost.reactionCount.abbreviatedString())
                        .font(.system(size: 12))
                        .foregroundColor(LockedInTheme.secondaryText)

                    Spacer()

                    if post.commentCount > 0 {
                        Text("\(post.commentCount) comments")
                            .font(.system(size: 12))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                    if post.repostCount > 0 {
                        if post.commentCount > 0 {
                            Text("\u{2022}")
                                .font(.system(size: 6))
                                .foregroundColor(LockedInTheme.tertiaryText)
                        }
                        Text("\(post.repostCount) reposts")
                            .font(.system(size: 12))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .onTapGesture { showDetail = true }
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Action buttons with user avatar
            HStack(spacing: 0) {
                AvatarView(
                    name: appState.currentUser.fullName,
                    initials: appState.currentUser.avatarInitials,
                    topHex: appState.currentUser.avatarTopHex,
                    bottomHex: appState.currentUser.avatarBottomHex,
                    size: 24
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Circle().fill(Color(hex: 0x666666)))
                        .offset(x: 2, y: 2)
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)

                actionButton(
                    icon: livePost.selectedReaction?.sfSymbol ?? "hand.thumbsup",
                    label: livePost.selectedReaction?.label ?? "Like",
                    isActive: livePost.userHasLiked,
                    activeColor: livePost.selectedReaction.map { Color(hexString: $0.iconColor) }
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.toggleLike(postId: post.id)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showReactionPicker = true
                        }
                )

                actionButton(icon: "bubble.left", label: "Comment") {
                    showDetail = true
                }

                actionButton(
                    icon: "arrow.2.squarepath",
                    label: "Repost",
                    isActive: appState.repostedPosts.contains(post.id)
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.toggleRepost(post.id)
                }

                actionButton(icon: "paperplane", label: "Send") {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let url = "https://lockedin.example/feed/update/\(post.id)"
                    UIPasteboard.general.string = url
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                }
            }
            .padding(.trailing, 8)
            .padding(.vertical, 2)
        }
        .background(LockedInTheme.cardBackground)
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("Link copied to clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .transition(.opacity)
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .overlay(alignment: .bottomLeading) {
            if showReactionPicker {
                HStack(spacing: 4) {
                    ForEach(PostReactionType.allCases, id: \.self) { reaction in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            appState.reactToPost(postId: post.id, reaction: reaction)
                            showReactionPicker = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hexString: reaction.iconColor))
                                    .frame(width: 40, height: 40)
                                Image(systemName: reaction.sfSymbol)
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .scaleEffect(showReactionPicker ? 1 : 0.3)
                        }
                        .accessibilityIdentifier("reaction_\(reaction.rawValue)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                )
                .padding(.leading, 16)
                .padding(.bottom, 48)
                .transition(.scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showReactionPicker)
        .onTapGesture {
            if showReactionPicker { showReactionPicker = false }
        }
        .confirmationDialog("", isPresented: $showContextActions) {
            Button("Save post") { appState.toggleSavePost(post.id) }
            Button("Unfollow \(post.authorName)") { appState.toggleFollow(post.authorId) }
            Button("I don't want to see this") { withAnimation { isHidden = true } }
            Button("Report post", role: .destructive) { withAnimation { isHidden = true } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showDetail) {
            PostDetailView(post: post)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(
                connection: appState.connections.first(where: { $0.id == post.authorId }),
                isCurrentUser: post.authorId == appState.currentUser.id
            )
        }
        }
    }

    // MARK: - Post Content with ...more

    @ViewBuilder
    private var postContent: some View {
        let shouldTruncate = post.content.count > maxCollapsedChars && !isExpanded

        if shouldTruncate {
            VStack(alignment: .leading, spacing: 0) {
                let truncated = String(post.content.prefix(maxCollapsedChars))
                let lastNewline = truncated.lastIndex(of: "\n") ?? truncated.endIndex
                let displayText = String(truncated[truncated.startIndex..<min(lastNewline, truncated.endIndex)])

                HStack(alignment: .bottom, spacing: 0) {
                    Text(displayText.hasSuffix("\n") ? String(displayText.dropLast()) : displayText)
                        .font(.system(size: 14))
                        .foregroundColor(LockedInTheme.primaryText)
                        .lineSpacing(3)

                    Spacer(minLength: 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    } label: {
                        Text("...more")
                            .font(.system(size: 14))
                            .foregroundColor(LockedInTheme.secondaryText)
                            .padding(.leading, 4)
                            .background(LockedInTheme.cardBackground)
                    }
                }
            }
        } else {
            Text(post.content)
                .font(.system(size: 14))
                .foregroundColor(LockedInTheme.primaryText)
                .lineSpacing(3)
        }
    }

    // MARK: - Link Preview

    @ViewBuilder
    private func linkPreviewCard(_ link: LinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(hex: 0xE8E8E8))
                .frame(height: 150)
                .overlay {
                    Image(systemName: "link")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: 0xBBBBBB))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(link.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LockedInTheme.primaryText)
                    .lineLimit(2)
                Text(link.source)
                    .font(.system(size: 12))
                    .foregroundColor(LockedInTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xF3F2EF))
        }
        .overlay(
            Rectangle()
                .stroke(LockedInTheme.separator, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
    }

    @ViewBuilder
    private func postAttachmentCard(_ attachment: PostAttachment) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(attachmentTint(attachment.attachmentType))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: attachmentIcon(attachment.attachmentType))
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LockedInTheme.primaryText)
                Text(attachment.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(LockedInTheme.secondaryText)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: 0xF3F2EF))
        )
        .accessibilityIdentifier("post_attachment_\(attachment.id)")
    }

    private func attachmentIcon(_ type: PostAttachmentType) -> String {
        switch type {
        case .photo: return "photo.fill"
        case .document: return "doc.richtext.fill"
        case .link: return "link"
        case .event: return "calendar"
        }
    }

    private func attachmentTint(_ type: PostAttachmentType) -> Color {
        switch type {
        case .photo: return Color(hex: 0x0A66C2)
        case .document: return Color(hex: 0xCC1016)
        case .link: return Color(hex: 0x057642)
        case .event: return Color(hex: 0xB24020)
        }
    }

    @ViewBuilder
    private func pollCard(_ poll: PostPoll) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(poll.options) { option in
                ZStack(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0xDCE6F1))
                            .frame(width: geo.size.width * CGFloat(option.percentage) / 100)
                    }
                    HStack {
                        Text(option.text)
                            .font(.system(size: 14))
                            .foregroundColor(LockedInTheme.primaryText)
                        Spacer()
                        Text("\(option.percentage)%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(LockedInTheme.primaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(LockedInTheme.separator, lineWidth: 1)
                )
            }

            HStack {
                Text("\(poll.totalVotes.abbreviatedString()) votes")
                    .font(.system(size: 12))
                    .foregroundColor(LockedInTheme.secondaryText)
                Text("\u{2022}")
                    .font(.system(size: 6))
                    .foregroundColor(LockedInTheme.tertiaryText)
                Text(poll.endsIn)
                    .font(.system(size: 12))
                    .foregroundColor(LockedInTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func reactionIcon(_ type: PostReactionType) -> some View {
        ZStack {
            Circle()
                .fill(Color(hexString: type.iconColor))
                .frame(width: 18, height: 18)
            Image(systemName: type.sfSymbol)
                .font(.system(size: 9))
                .foregroundColor(.white)
        }
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, isActive: Bool = false, activeColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundColor(isActive ? (activeColor ?? LockedInTheme.likedBlue) : LockedInTheme.actionText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(LockedInButtonStyle())
        .accessibilityIdentifier("post_action_\(label.lowercased())")
    }
}
