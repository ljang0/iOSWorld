import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let post: Post
    @State private var commentText: String = ""
    @State private var showCopied: Bool = false
    @State private var toastMessage: String = ""
    @State private var showPostActions: Bool = false
    @State private var showReportConfirm: Bool = false
    @FocusState private var commentFieldFocused: Bool
    @State private var selectedAuthorConnection: Connection?

    private var livePost: Post {
        appState.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var comments: [PostComment] {
        appState.postComments[post.id] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Author row
                        HStack(alignment: .top, spacing: 10) {
                            AvatarView(
                                name: post.authorName,
                                initials: post.authorInitials,
                                topHex: post.authorAvatarTopHex,
                                bottomHex: post.authorAvatarBottomHex,
                                size: 48
                            )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(post.authorName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(LockedInTheme.primaryText)
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
                                            .accessibilityIdentifier("detail_scheduled_badge_\(post.id)")
                                    } else {
                                        Text("\u{2022}")
                                            .font(.system(size: 8))
                                            .foregroundColor(LockedInTheme.secondaryText)
                                        Image(systemName: "globe")
                                            .font(.system(size: 10))
                                            .foregroundColor(LockedInTheme.secondaryText)
                                    }
                                }
                            }

                            Spacer()

                            if post.authorId != appState.currentUser.id {
                                Button(action: {
                                    appState.toggleFollow(post.authorId)
                                }) {
                                    HStack(spacing: 2) {
                                        if appState.followedAuthors.contains(post.authorId) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                            Text("Following")
                                                .font(.system(size: 14, weight: .bold))
                                        } else {
                                            Image(systemName: "plus")
                                                .font(.system(size: 13, weight: .bold))
                                            Text("Follow")
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .foregroundColor(appState.followedAuthors.contains(post.authorId) ? LockedInTheme.secondaryText : LockedInTheme.linkedInBlue)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // Full post content
                        Text(post.content)
                            .font(.system(size: 14))
                            .foregroundColor(LockedInTheme.primaryText)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        // Link preview
                        if let link = post.linkPreview {
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
                                    Text(link.source)
                                        .font(.system(size: 12))
                                        .foregroundColor(LockedInTheme.secondaryText)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: 0xF3F2EF))
                            }
                            .padding(.top, 10)
                        }

                        // Attachments
                        if !post.attachments.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(post.attachments) { attachment in
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(detailAttachmentTint(attachment.attachmentType))
                                            .frame(width: 50, height: 50)
                                            .overlay {
                                                Image(systemName: detailAttachmentIcon(attachment.attachmentType))
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
                                    .accessibilityIdentifier("detail_attachment_\(attachment.id)")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        }

                        // Reaction summary (tappable)
                        if livePost.reactionCount > 0 {
                            Button(action: { commentFieldFocused = true }) {
                                HStack(spacing: 4) {
                                    HStack(spacing: -2) {
                                        ForEach(livePost.topReactions.prefix(3), id: \.self) { reaction in
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hexString: reaction.iconColor))
                                                    .frame(width: 18, height: 18)
                                                Image(systemName: reaction.sfSymbol)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white)
                                            }
                                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                        }
                                    }
                                    Text(livePost.reactionCount.abbreviatedString())
                                        .font(.system(size: 12))
                                        .foregroundColor(LockedInTheme.secondaryText)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        }

                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Action buttons
                        HStack(spacing: 0) {
                            detailActionButton(
                                icon: livePost.selectedReaction?.sfSymbol ?? "hand.thumbsup",
                                label: livePost.selectedReaction?.label ?? "Like",
                                isActive: livePost.userHasLiked,
                                activeColor: livePost.selectedReaction.map { Color(hexString: $0.iconColor) }
                            ) {
                                appState.toggleLike(postId: post.id)
                            }
                            detailActionButton(icon: "bubble.left", label: "Comment") {
                                commentFieldFocused = true
                            }
                            detailActionButton(
                                icon: "arrow.2.squarepath",
                                label: "Repost",
                                isActive: appState.repostedPosts.contains(post.id)
                            ) {
                                appState.toggleRepost(post.id)
                            }
                            detailActionButton(icon: "paperplane", label: "Send") {
                                let url = "https://lockedin.example/feed/update/\(post.id)"
                                UIPasteboard.general.string = url
                                toastMessage = "Link copied to clipboard"
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopied = false
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        Divider()
                            .padding(.horizontal, 16)

                        // Commenter avatars
                        if !comments.isEmpty {
                            HStack(spacing: -8) {
                                ForEach(comments.prefix(3)) { comment in
                                    AvatarView(
                                        initials: comment.authorInitials,
                                        topHex: comment.authorAvatarTopHex,
                                        bottomHex: comment.authorAvatarBottomHex,
                                        size: 32,
                                        showBorder: true
                                    )
                                }

                                if comments.count > 3 {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: 0xE8E8E8))
                                            .frame(width: 32, height: 32)
                                        Text("+\(comments.count - 3)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(LockedInTheme.secondaryText)
                                    }
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        // Comments area
                        if !comments.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(comments.prefix(10)) { comment in
                                    commentRow(comment)
                                }
                            }
                            .padding(.top, 12)
                        } else if post.commentCount == 0 {
                            VStack(spacing: 16) {
                                Spacer().frame(height: 20)

                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 48))
                                    .foregroundColor(Color(hex: 0xCCCCCC))

                                Text("Be the first to comment")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(LockedInTheme.primaryText)

                                Button(action: {
                                    commentFieldFocused = true
                                }) {
                                    Text("Comment")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(LockedInTheme.linkedInBlue)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(LockedInTheme.linkedInBlue, lineWidth: 1)
                                        )
                                }

                                Spacer().frame(height: 40)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // Comment input bar
                Divider()
                HStack(spacing: 10) {
                    AvatarView(
                        name: appState.currentUser.fullName,
                        initials: appState.currentUser.avatarInitials,
                        topHex: appState.currentUser.avatarTopHex,
                        bottomHex: appState.currentUser.avatarBottomHex,
                        size: 32
                    )

                    HStack {
                        TextField("Leave your thoughts here...", text: $commentText)
                            .font(.system(size: 14))
                            .focused($commentFieldFocused)
                            .onSubmit { submitComment() }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(LockedInTheme.separator, lineWidth: 1)
                    )

                    Button(action: { submitComment() }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LockedInTheme.secondaryText : LockedInTheme.linkedInBlue)
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(LockedInTheme.cardBackground)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPostActions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundColor(LockedInTheme.secondaryText)
                    }
                }
            }
            .confirmationDialog("", isPresented: $showPostActions) {
                Button("Save post") {
                    appState.toggleSavePost(post.id)
                    toastMessage = "Post saved"
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                }
                Button("Copy link") {
                    UIPasteboard.general.string = "https://lockedin.example/feed/update/\(post.id)"
                    toastMessage = "Link copied to clipboard"
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                }
                Button("Report post", role: .destructive) {
                    showReportConfirm = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Report Submitted", isPresented: $showReportConfirm) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Thank you for your report. We'll review this post and take action if it violates our Professional Community Policies.")
            }
            .overlay(alignment: .bottom) {
                if showCopied {
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .transition(.opacity)
                        .padding(.bottom, 60)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopied)
            .sheet(item: $selectedAuthorConnection) { connection in
                ProfileView(connection: connection, isCurrentUser: false)
            }
        }
    }

    // MARK: - Comment Row

    @ViewBuilder
    private func commentRow(_ comment: PostComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                selectedAuthorConnection = appState.connections.first(where: { $0.fullName == comment.authorName })
            } label: {
                AvatarView(
                    initials: comment.authorInitials,
                    topHex: comment.authorAvatarTopHex,
                    bottomHex: comment.authorAvatarBottomHex,
                    size: 32
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        selectedAuthorConnection = appState.connections.first(where: { $0.fullName == comment.authorName })
                    } label: {
                        Text(comment.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(LockedInTheme.primaryText)
                    }
                    .buttonStyle(.plain)

                    Text(comment.authorHeadline)
                        .font(.system(size: 11))
                        .foregroundColor(LockedInTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Text(comment.content)
                    .font(.system(size: 13))
                    .foregroundColor(LockedInTheme.primaryText)
                    .lineSpacing(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    Text(comment.timestamp.linkedInTimeAgo())
                        .font(.system(size: 11))
                        .foregroundColor(LockedInTheme.secondaryText)

                    if comment.likeCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.system(size: 10))
                                .foregroundColor(LockedInTheme.secondaryText)
                            Text("\(comment.likeCount)")
                                .font(.system(size: 11))
                                .foregroundColor(LockedInTheme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: 0xF2F2F2))
            )

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Submit Comment

    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addComment(postId: post.id, content: trimmed)
        commentText = ""
    }

    // MARK: - Action Button

    @ViewBuilder
    private func detailActionButton(icon: String, label: String, isActive: Bool = false, activeColor: Color? = nil, action: @escaping () -> Void) -> some View {
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

    // MARK: - Attachment Helpers

    private func detailAttachmentIcon(_ type: PostAttachmentType) -> String {
        switch type {
        case .photo: return "photo.fill"
        case .document: return "doc.richtext.fill"
        case .link: return "link"
        case .event: return "calendar"
        }
    }

    private func detailAttachmentTint(_ type: PostAttachmentType) -> Color {
        switch type {
        case .photo: return Color(hex: 0x0A66C2)
        case .document: return Color(hex: 0xCC1016)
        case .link: return Color(hex: 0x057642)
        case .event: return Color(hex: 0xB24020)
        }
    }
}
