import Foundation

enum PostAttachmentType: String, Codable, CaseIterable, Hashable {
    case photo
    case document
    case link
    case event
}

struct PostAttachment: Identifiable, Codable, Hashable {
    var id: String
    var attachmentType: PostAttachmentType
    var title: String
    var subtitle: String
}

struct Post: Identifiable, Codable, Hashable {
    var id: String
    var authorId: String
    var authorName: String
    var authorHeadline: String
    var authorInitials: String
    var authorAvatarTopHex: String
    var authorAvatarBottomHex: String
    var content: String
    var timestamp: Date
    var reactionCount: Int
    var commentCount: Int
    var repostCount: Int
    var topReactions: [PostReactionType]
    var hasImage: Bool
    var imageDescription: String?
    var linkPreview: LinkPreview?
    var isSponsored: Bool
    var connectionContext: String?
    var connectionDegree: String?
    var userHasLiked: Bool
    var userReaction: PostReactionType? = nil
    // Legacy liked posts have no selected type and retain their existing Like appearance.
    var selectedReaction: PostReactionType? {
        userHasLiked ? (userReaction ?? .like) : nil
    }
    var hasVideo: Bool = false
    var videoDuration: String?
    var poll: PostPoll?
    var attachments: [PostAttachment] = []
    var scheduledDate: Date? = nil
}

struct PostPoll: Codable, Hashable {
    var question: String
    var options: [PollOption]
    var totalVotes: Int
    var endsIn: String
}

struct PollOption: Codable, Hashable, Identifiable {
    var id: String { text }
    var text: String
    var percentage: Int
}

struct LinkPreview: Codable, Hashable {
    var title: String
    var source: String
    var description: String?
}

struct PostComment: Identifiable, Codable, Hashable {
    var id: String
    var authorName: String
    var authorHeadline: String
    var authorInitials: String
    var authorAvatarTopHex: String
    var authorAvatarBottomHex: String
    var content: String
    var timestamp: Date
    var likeCount: Int
}
