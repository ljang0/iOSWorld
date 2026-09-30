import SwiftUI

struct ChannelDetailView: View {
    @StateObject private var viewModel: ChannelDetailViewModel
    let focusMessageId: String?

    @State private var draftText: String = ""
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var threadMessageId: String?
    @State private var showHuddleSheet = false

    init(store: WorkspaceStore, channelId: String, focusMessageId: String? = nil) {
        _viewModel = StateObject(wrappedValue: ChannelDetailViewModel(store: store, channelId: channelId))
        self.focusMessageId = focusMessageId
    }

    var body: some View {
        ZStack {
            TeamChatPalette.screen.ignoresSafeArea()

            VStack(spacing: 0) {
                if let channel = viewModel.channel {
                    if channel.messages.isEmpty {
                        emptyChannelState(channel: channel)
                    } else {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Pinned items: \(channel.pinnedItemsPlaceholderCount)")
                                    .font(.caption)
                                    .foregroundStyle(TeamChatPalette.subtleText)
                                    .accessibilityIdentifier("channel_pinned_banner")
                                Spacer()
                                Button("Huddle") {
                                    showHuddleSheet = true
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(TeamChatPalette.row, in: Capsule())
                                .accessibilityIdentifier("huddle_placeholder_button_channel")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                            if channel.bookmarks.isEmpty == false {
                                bookmarksBar(bookmarks: channel.bookmarks)
                            }

                            Divider().overlay(TeamChatPalette.divider)

                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        if let unreadMessageId = channel.messages.first(where: { $0.isUnread })?.id {
                                            Button("Jump to unread") {
                                                withAnimation {
                                                    proxy.scrollTo(unreadMessageId, anchor: .center)
                                                }
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(TeamChatPalette.avatarRing, in: Capsule())
                                            .padding(.horizontal)
                                            .padding(.top, 8)
                                            .accessibilityIdentifier("jump_to_unread_button")
                                        }

                                        ForEach(viewModel.channelMessages) { message in
                                            MessageRowView(
                                                message: message,
                                                showThreadButton: true,
                                                mentionCurrentUser: message.mentionUserIds.contains(viewModel.store.activeWorkspace?.currentUserId ?? ""),
                                                onToggleReaction: { emoji in
                                                    viewModel.toggleMessageReaction(messageId: message.id, emoji: emoji)
                                                },
                                                onOpenThread: {
                                                    threadMessageId = message.id
                                                }
                                            )
                                            .id(message.id)
                                            .padding(.horizontal)
                                            .background(message.id == focusMessageId ? Color.yellow.opacity(0.18) : Color.clear)
                                        }
                                    }
                                }
                                .onAppear {
                                    if let focusMessageId {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation {
                                                proxy.scrollTo(focusMessageId, anchor: .center)
                                            }
                                        }
                                    } else if let lastMessage = viewModel.channelMessages.last {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                                .onChange(of: viewModel.channelMessages.count) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        if let lastMessage = viewModel.channelMessages.last {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Channel not found", systemImage: "exclamationmark.bubble")
                        .accessibilityIdentifier("channel_not_found_state")
                }

                Divider().overlay(TeamChatPalette.divider)

                composer
            }
        }
        .navigationTitle(viewModel.channel?.displayName ?? "Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Mark read") {
                        viewModel.markRead()
                    }
                    .accessibilityIdentifier("mark_channel_read_button")

                    Button("Mark unread") {
                        viewModel.markUnread()
                    }
                    .accessibilityIdentifier("mark_channel_unread_button")

                    Button((viewModel.channel?.isMuted ?? false) ? "Unmute" : "Mute") {
                        viewModel.toggleMute()
                    }
                    .accessibilityIdentifier("toggle_channel_mute_button")

                    Button((viewModel.channel?.isStarred ?? false) ? "Remove star" : "Star channel") {
                        viewModel.toggleStar()
                    }
                    .accessibilityIdentifier("toggle_channel_star_button")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                }

                NavigationLink {
                    ChannelInfoView(viewModel: viewModel)
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("channel_info_button")
            }
        }
        .toolbarBackground(TeamChatPalette.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: Binding(
            get: {
                threadMessageId.map { IdentifiedString(id: $0) }
            },
            set: { value in
                threadMessageId = value?.id
            }
        )) { value in
            NavigationStack {
                ThreadView(store: viewModel.store, channelId: viewModel.channelId, dmId: nil, messageId: value.id)
            }
        }
        .sheet(isPresented: $showHuddleSheet) {
            NavigationStack {
                HuddlePlaceholderView(
                    title: "Huddle",
                    contextName: viewModel.channel?.displayName ?? "Channel",
                    participantNames: viewModel.members.map(\.displayName),
                    accessibilityPrefix: "channel_huddle_placeholder"
                )
            }
        }
        .hidesRootChrome()
        .onAppear {
            viewModel.markRead()
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if pendingAttachments.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(pendingAttachments) { attachment in
                            Text(attachment.title)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(TeamChatPalette.row, in: Capsule())
                                .accessibilityIdentifier("composer_attachment_chip_\(attachment.id)")
                        }
                    }
                }
                .accessibilityIdentifier("composer_attachment_scroll")
            }

            formattingToolbar

            HStack(spacing: 8) {
                // A bounded editor avoids repeated intrinsic-height negotiation
                // between a growing multiline TextField and this horizontal row.
                TextEditor(text: $draftText)
                    .frame(height: 88)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .overlay(alignment: .topLeading) {
                        if draftText.isEmpty {
                            Text("Message #\(viewModel.channel?.channelName ?? "channel")")
                                .foregroundStyle(TeamChatPalette.subtleText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(TeamChatPalette.row))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TeamChatPalette.divider, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit {
                        if viewModel.sendMessage(text: draftText, attachments: pendingAttachments) {
                            draftText = ""
                            pendingAttachments.removeAll()
                        }
                    }
                    .accessibilityIdentifier("composer_text_field")
                    .accessibilityLabel("Message #\(viewModel.channel?.channelName ?? "channel")")

                Menu {
                    Button("Attach image") {
                        pendingAttachments.append(
                            MessageAttachment(
                                id: "draft_image_\(UUID().uuidString)",
                                attachmentType: .image,
                                title: "Screenshot.png",
                                subtitle: "Local attachment",
                                localPath: "Resources/draft_image.png"
                            )
                        )
                    }
                    .accessibilityIdentifier("composer_add_image_attachment")
                    Button("Attach PDF") {
                        pendingAttachments.append(
                            MessageAttachment(
                                id: "draft_pdf_\(UUID().uuidString)",
                                attachmentType: .pdf,
                                title: "Document.pdf",
                                subtitle: "Local attachment",
                                localPath: "Resources/draft.pdf"
                            )
                        )
                    }
                    .accessibilityIdentifier("composer_add_pdf_attachment")
                    Button("Attach link") {
                        pendingAttachments.append(
                            MessageAttachment(
                                id: "draft_link_\(UUID().uuidString)",
                                attachmentType: .link,
                                title: "Shared link",
                                subtitle: "internal://local/link",
                                localPath: "Resources/draft.link"
                            )
                        )
                    }
                    .accessibilityIdentifier("composer_add_link_attachment")
                } label: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(TeamChatPalette.row, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer_add_attachment_button")

                Button("Send") {
                    if viewModel.sendMessage(text: draftText, attachments: pendingAttachments) {
                        draftText = ""
                        pendingAttachments = []
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TeamChatPalette.avatarRing, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("send_message_button")
            }
        }
        .padding()
    }

    private func bookmarksBar(bookmarks: [ChannelBookmark]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bookmarks) { bookmark in
                    HStack(spacing: 4) {
                        EmojiText(bookmark.emoji, pointSize: 12)
                        Text(bookmark.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TeamChatPalette.row, in: Capsule())
                    .overlay(Capsule().strokeBorder(TeamChatPalette.divider, lineWidth: 1))
                    .accessibilityIdentifier("channel_bookmark_\(bookmark.id)")
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("channel_bookmarks_bar")
    }

    private var formattingToolbar: some View {
        HStack(spacing: 12) {
            Button {
                draftText += "*bold*"
            } label: {
                Text("B")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(TeamChatPalette.row, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("format_bold_button")

            Button {
                draftText += "_italic_"
            } label: {
                Text("I")
                    .font(.subheadline.weight(.medium).italic())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(TeamChatPalette.row, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("format_italic_button")

            Button {
                draftText += "~strikethrough~"
            } label: {
                Text("S")
                    .font(.subheadline.weight(.medium))
                    .strikethrough()
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(TeamChatPalette.row, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("format_strikethrough_button")

            Button {
                draftText += "`code`"
            } label: {
                Text("</>")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(TeamChatPalette.row, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("format_code_button")

            Spacer()
        }
        .accessibilityIdentifier("formatting_toolbar")
    }

    private func emptyChannelState(channel: Channel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: channel.isPrivate ? "lock.bubble" : "number.square")
                .font(.largeTitle)
                .foregroundStyle(TeamChatPalette.subtleText)

            Text("Start the conversation in \(channel.displayName)")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Share a status update, post a handoff note, or ask a question.")
                .font(.subheadline)
                .foregroundStyle(TeamChatPalette.subtleText)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                starterChip("Post update")
                starterChip("Share blocker")
                starterChip("Ask question")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityIdentifier("empty_channel_state")
    }

    private func starterChip(_ title: String) -> some View {
        Button {
            draftText = title
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(TeamChatPalette.row, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("starter_chip_\(title.accessibilitySlug)")
    }
}
