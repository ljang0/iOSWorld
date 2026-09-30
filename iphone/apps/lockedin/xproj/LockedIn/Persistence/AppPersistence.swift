import Foundation

final class AppPersistence {
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let savedJobIdsKey = "lockedin_sim_saved_job_ids"
    private let userReactionsKey = "lockedin_sim_user_reactions"
    private let likedPostIdsKey = "lockedin_sim_liked_post_ids"
    private let dismissedInvitationIdsKey = "lockedin_sim_dismissed_invitation_ids"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Saved Jobs

    func loadSavedJobIds() -> Set<String>? {
        guard let array = userDefaults.stringArray(forKey: savedJobIdsKey) else { return nil }
        return Set(array)
    }

    func persistSavedJobIds(_ ids: Set<String>) {
        userDefaults.set(Array(ids.sorted()), forKey: savedJobIdsKey)
    }

    // MARK: - Liked Posts

    func loadLikedPostIds() -> Set<String>? {
        guard let array = userDefaults.stringArray(forKey: likedPostIdsKey) else { return nil }
        return Set(array)
    }

    func persistLikedPostIds(_ ids: Set<String>) {
        userDefaults.set(Array(ids.sorted()), forKey: likedPostIdsKey)
    }

    func loadUserReactions() -> [String: PostReactionType] {
        let saved = userDefaults.dictionary(forKey: userReactionsKey) as? [String: String] ?? [:]
        return saved.compactMapValues(PostReactionType.init(rawValue:))
    }

    func persistUserReactions(_ reactions: [String: PostReactionType]) {
        userDefaults.set(reactions.mapValues { $0.rawValue }, forKey: userReactionsKey)
    }

    // MARK: - Dismissed Invitations

    func loadDismissedInvitationIds() -> Set<String>? {
        guard let array = userDefaults.stringArray(forKey: dismissedInvitationIdsKey) else { return nil }
        return Set(array)
    }

    func persistDismissedInvitationIds(_ ids: Set<String>) {
        userDefaults.set(Array(ids.sorted()), forKey: dismissedInvitationIdsKey)
    }

    // MARK: - Reset

    func clearAll() {
        userDefaults.removeObject(forKey: savedJobIdsKey)
        userDefaults.removeObject(forKey: likedPostIdsKey)
        userDefaults.removeObject(forKey: userReactionsKey)
        userDefaults.removeObject(forKey: dismissedInvitationIdsKey)
    }
}
