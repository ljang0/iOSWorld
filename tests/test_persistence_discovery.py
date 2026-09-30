"""Foundation-only regressions for app persistence and offline discovery.

Run with ``python3 -m unittest discover -s tests -p test_persistence_discovery.py``.
Swift source is read from this checkout; only UI dependencies and storage locations
are substituted. No simulator, network, seeded app data, or third-party modules are used.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPS = ROOT / "iphone/apps"


def method(source, signature):
    """Extract a balanced production method (these methods contain no brace literals)."""
    start = source.index("    " + signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private func", "func")


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler is required")
class PersistenceDiscoveryTests(unittest.TestCase):
    def run_swift(self, source):
        with tempfile.TemporaryDirectory(prefix="app-regression-") as directory:
            temp = Path(directory)
            main = temp / "main.swift"
            main.write_text(source)
            build = subprocess.run(
                ["swiftc", "-module-cache-path", str(temp / "cache"), str(main),
                 "-o", str(temp / "regression")],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(temp / "regression"), str(temp)],
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS", run.stdout)

    def test_clock_alarm_mutations_reload_and_malformed_storage(self):
        source = (APPS / "clock/xproj/Clock/ViewController.swift").read_text()
        model = source[source.index("struct AlarmItem:"):
                       source.index("final class AlarmListViewController:")]
        observer = source[source.index("    private var alarms:"):
                          source.index("    private let timeFormatter:", source.index("    private var alarms:"))]
        observer = (observer.replace("private var alarms", "var alarms")
                    .replace("AlarmStorage.load()", "AlarmStorage.load(from: testURL)")
                    .replace("AlarmStorage.save(alarms)",
                             "AlarmStorage.save(alarms, to: testURL)"))
        helpers = source[source.index("    private static func makeTime(hour:"):
                         source.index("\nfinal class AddAlarmViewController:")]
        self.run_swift('''import Foundation
let testURL = URL(fileURLWithPath: CommandLine.arguments[1])
    .appendingPathComponent("Clock/alarms.json")
''' + model + "final class AlarmListViewController {\n" + observer + helpers + '''
func reload() -> AlarmListViewController { AlarmListViewController() }
var host = reload()
// Missing storage retains the original four defaults and repeat labels.
precondition(host.alarms.count == 4)
precondition(host.alarms[0].label == "Morning run")
precondition(host.alarms[0].repeatSummary == "Weekdays")
let original = host.alarms
let sample = AlarmItem(time: Date(timeIntervalSince1970: 1800000000),
                       label: "Temporary 'alarm'", enabled: true, repeatDays: [1,3,7])
host.alarms.insert(sample, at: 0)
host = reload()
precondition(host.alarms.count == 5 && host.alarms[0].label == sample.label)
precondition(host.alarms[0].time == sample.time && host.alarms[0].repeatDays == [1,3,7])
host.alarms[0] = AlarmItem(time: sample.time.addingTimeInterval(60),
                           label: "Edited", enabled: true, repeatDays: [2])
host = reload()
precondition(host.alarms[0].label == "Edited" && host.alarms[0].repeatDays == [2])
precondition(host.alarms[0].time == sample.time.addingTimeInterval(60))
host.alarms[0].enabled = false
host = reload()
precondition(!host.alarms[0].enabled)
host.alarms.remove(at: 0)
host = reload()
precondition(host.alarms.count == original.count && host.alarms[0].label == original[0].label)
host.alarms.removeAll()
precondition(reload().alarms.isEmpty)
for malformed in ["invalid", "{}", "[{}]", "null"] {
    try Data(malformed.utf8).write(to: testURL)
    precondition(AlarmStorage.load(from: testURL) == nil)
    precondition(reload().alarms.count == 4)
}
for invalidDay in [0, 8, -1] {
    AlarmStorage.save([AlarmItem(time: sample.time, label: "Bad day", enabled: true,
                                repeatDays: [invalidDay])], to: testURL)
    precondition(AlarmStorage.load(from: testURL) == nil)
    precondition(reload().alarms.count == 4)
}
try FileManager.default.removeItem(at: testURL.deletingLastPathComponent())
precondition(reload().alarms.count == 4)
print("PASS")
''')

    def test_lockedin_reactions_roundtrip_legacy_likes_and_counts(self):
        root = APPS / "lockedin/xproj/LockedIn"
        source = (root / "ViewModels/AppState.swift").read_text()
        production = "\n".join((root / path).read_text() for path in
                               ["Models/AppEnums.swift", "Models/Post.swift",
                                "Persistence/AppPersistence.swift"])
        host = '''
struct Job { var id: String; var isSaved: Bool }
struct Invitation { var id: String }
final class State {
 var posts: [Post] = []
 var jobs: [Job] = []
 var invitations: [Invitation] = []
 let persistence: AppPersistence
 init(_ persistence: AppPersistence) { self.persistence = persistence }
'''
        for signature in ["func toggleLike(", "func reactToPost(",
                          "private func loadPersistedState(", "private func saveState("]:
            host += method(source, signature) + "\n"
        self.run_swift(production + host + "}\n" + r'''
let payload = #"{"id":"post","authorId":"author","authorName":"Test","authorHeadline":"","authorInitials":"T","authorAvatarTopHex":"","authorAvatarBottomHex":"","content":"","timestamp":0,"reactionCount":10,"commentCount":0,"repostCount":0,"topReactions":["like"],"hasImage":false,"isSponsored":false,"userHasLiked":false,"hasVideo":false,"attachments":[]}"#
let seed = try JSONDecoder().decode(Post.self, from: Data(payload.utf8))
precondition(seed.userReaction == nil && seed.selectedReaction == nil)
var legacy = seed
legacy.userHasLiked = true
precondition(legacy.selectedReaction == .like)
let suite = "reaction-test-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let persistence = AppPersistence(userDefaults: defaults)
func restore(_ post: Post = seed) -> State {
    let state = State(persistence)
    state.posts = [post]
    state.loadPersistedState()
    return state
}
let state = restore()
state.reactToPost(postId: seed.id, reaction: .celebrate)
precondition(state.posts[0].selectedReaction == .celebrate && state.posts[0].reactionCount == 11)
let decoded = try JSONDecoder().decode(Post.self, from: JSONEncoder().encode(state.posts[0]))
precondition(decoded.userReaction == .celebrate)
let restored = restore()
precondition(restored.posts[0].selectedReaction == .celebrate && restored.posts[0].reactionCount == 11)
restored.loadPersistedState()
precondition(restored.posts[0].reactionCount == 11)
restored.reactToPost(postId: seed.id, reaction: .love)
restored.reactToPost(postId: seed.id, reaction: .love)
precondition(restored.posts[0].selectedReaction == .love && restored.posts[0].reactionCount == 11)
precondition(restored.posts[0].topReactions.filter { $0 == .love }.count == 1)
precondition(restore().posts[0].selectedReaction == .love)
restored.toggleLike(postId: seed.id)
precondition(restored.posts[0].selectedReaction == nil && restored.posts[0].reactionCount == 10)
let removed = restore()
precondition(!removed.posts[0].userHasLiked && removed.posts[0].userReaction == nil)
removed.toggleLike(postId: seed.id)
precondition(removed.posts[0].selectedReaction == .like && removed.posts[0].reactionCount == 11)
persistence.clearAll()
precondition(persistence.loadUserReactions().isEmpty && persistence.loadLikedPostIds() == nil)
// Old installations persisted liked IDs without a reaction dictionary.
persistence.persistLikedPostIds([seed.id])
precondition(restore().posts[0].selectedReaction == .like)
precondition(restore(legacy).posts[0].reactionCount == 10)
persistence.persistLikedPostIds([])
precondition(restore(legacy).posts[0].reactionCount == 9)
var zero = legacy
zero.reactionCount = 0
precondition(restore(zero).posts[0].reactionCount == 0)
print("PASS")
''')

    def test_cinephile_cached_metadata_filters_and_bounded_cards(self):
        root = APPS / "cinephile/xproj/Cinephile/Shared/flux/models"
        model = (root / "Movie.swift").read_text().split("let sampleMovie =", 1)[0]
        model = model.replace("import SwiftUI", "").replace("import Backend", "")
        filters = (root / "DiscoverFilter.swift").read_text().replace("import SwiftUI", "")
        self.run_swift('''import Foundation
struct Genre: Codable { let id: Int; let name: String }
struct ImageData: Codable {}
struct Keyword: Codable {}
enum AppUserDefaults { static let alwaysOriginalTitle = false }
''' + model + filters + r'''
func movie(_ id: Int, _ genres: [Int]? = nil, _ date: String? = nil,
           _ popularity: Float = 1, _ rating: Float = 1) throws -> Movie {
    var json: [String: Any] = ["id": id, "title": "Test", "original_title": "Test",
        "overview": "", "popularity": popularity, "vote_average": rating,
        "vote_count": 1, "video": false]
    json["genre_ids"] = genres
    json["release_date"] = date
    return try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject: json))
}
let listMovie = try movie(2, [53], "2005-01-01", 7, 9)
let restored = try JSONDecoder().decode(Movie.self, from: JSONEncoder().encode(listMovie))
precondition(restored.genres == nil && restored.knownGenreIDs == [53])
var detailJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! [String: Any]
detailJSON["genres"] = [["id": 18, "name": "Drama"]]
let detail = try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject: detailJSON))
precondition(detail.knownGenreIDs == [18,53])
detailJSON.removeValue(forKey: "genre_ids")
let detailOnly = try JSONDecoder().decode(Movie.self, from: JSONSerialization.data(withJSONObject: detailJSON))
precondition(detailOnly.knownGenreIDs == [18])
let unknown = try movie(4)
precondition(unknown.knownGenreIDs.isEmpty)
let movies = [try movie(0, nil, nil, 99, 10), try movie(1, [18], "2001-01-01", 9, 7),
              restored, try movie(3, [53], "1995-01-01", 8, 8), unknown]
func filter(_ genre: Int? = nil, _ start: Int? = nil, _ end: Int? = nil,
            _ region: String? = nil, _ sort: String = "vote_average.desc") -> DiscoverFilter {
    DiscoverFilter(year: 2000, startYear: start, endYear: end, sort: sort, genre: genre, region: region)
}
precondition(offlineDiscoverMovies(movies, filter: nil).map { $0.id } == [1,3,2,4])
precondition(offlineDiscoverMovies(movies, filter: filter(53)).map { $0.id } == [2,3])
precondition(offlineDiscoverMovies(movies, filter: filter(53,2000,2010)).map { $0.id } == [2])
precondition(offlineDiscoverMovies(movies, filter: filter(53,2005,2005)).map { $0.id } == [2])
precondition(offlineDiscoverMovies(movies, filter: filter(99)).isEmpty)
precondition(offlineDiscoverMovies(movies, filter: filter(nil,nil,nil,"US")).isEmpty)
precondition(offlineDiscoverMovies(movies, filter: filter(53,nil,nil,nil,"vote_average.asc")).map { $0.id } == [3,2])
let tied = [try movie(8), try movie(7)]
precondition(offlineDiscoverMovies(tied, filter: nil).map { $0.id } == [7,8])
let invalidDate = try movie(5, [53], "unknown")
precondition(offlineDiscoverMovies([invalidDate], filter: filter(53,2000,2010)).isEmpty)
precondition(offlineDiscoverMovies(movies, filter: filter(-1)).count == 4)
let candidates = Array(1...500)
precondition(visibleDiscoverMovieIDs(candidates) == [497,498,499,500])
precondition(candidates.count == 500)
precondition(visibleDiscoverMovieIDs(Array(candidates.dropLast())) == [496,497,498,499])
precondition(visibleDiscoverMovieIDs([]).isEmpty)
precondition(visibleDiscoverMovieIDs([1,2]) == [1,2])
print("PASS")
''')


    def test_cinephile_refill_preserves_consumed_cards_and_reset_generation(self):
        root = APPS / "cinephile/xproj/Cinephile/Shared/flux"
        actions = (root / "actions/MoviesActions.swift").read_text()
        reducer = (root / "reducers/MoviesReducer.swift").read_text()
        state = (root / "state/MoviesState.swift").read_text()
        # Compile production action definitions, state fields, and relevant switch
        # branches. Stubs supply only unrelated Flux/model dependencies.
        fields = state[state.index("    var discover: [Int]"):
                       state.index("    // Seeded for benchmark:")]
        fields = fields.replace("discoverSeedMovies.map { $0.id }", "[]")
        cases = reducer[reducer.index("    case let action as MoviesActions.SetOfflineDiscover:"):
                        reducer.index("    case let action as MoviesActions.SetMovieReviews:")]
        cases += reducer[reducer.index("    case _ as  MoviesActions.PopRandromDiscover:"):
                         reducer.index("    case let action as MoviesActions.SetGenres:")]
        definitions = "\n".join(method(actions, "struct " + name + ":") for name in
                                ["SetOfflineDiscover", "SetRandomDiscover", "PopRandromDiscover",
                                 "PushRandomDiscover", "ResetRandomDiscover"])
        merge = reducer[reducer.index("private func mergeMovies("):]
        self.run_swift("""import Foundation
protocol Action {}
struct Movie { let id: Int }
struct DiscoverFilter { let genre: Int }
struct PaginatedResponse<T> { let results: [T] }
struct MoviesState {
    var movies: [Int: Movie] = [:]
""" + fields + "}\nenum MoviesActions {\n" + definitions + "}\n" + """
func reduce(_ state: MoviesState, _ action: Action) -> MoviesState {
    var state = state
    switch action {
""" + cases + "default: break\n}\nreturn state\n}\n" + merge + """
let catalog = [Movie(id: 1), Movie(id: 2), Movie(id: 3)]
let filter = DiscoverFilter(genre: 53)
var state = MoviesState()
func refill(_ generation: UUID? = nil) -> MoviesActions.SetOfflineDiscover {
    MoviesActions.SetOfflineDiscover(filter: filter, movies: catalog,
                                     notice: "Offline", generation: generation)
}
state = reduce(state, refill())
precondition(state.discover == [3,2,1])
state = reduce(state, MoviesActions.PopRandromDiscover())
precondition(state.consumedDiscoverIDs == [1])
state = reduce(state, refill())
precondition(state.discover == [3,2])
state = reduce(state, MoviesActions.SetRandomDiscover(filter: filter,
    response: PaginatedResponse(results: catalog + [Movie(id: 4), Movie(id: 4)])))
precondition(state.discover == [4,3,2])
// Restore offline mode before testing undo; consumed ID 1 stays absent.
state = reduce(state, refill())
precondition(state.discover == [3,2])
state = reduce(state, MoviesActions.PushRandomDiscover(movie: 1))
state = reduce(state, MoviesActions.PushRandomDiscover(movie: 1))
precondition(state.discover == [3,2,1] && state.consumedDiscoverIDs!.isEmpty)
state = reduce(state, refill())
precondition(state.discover == [3,2,1])
for _ in catalog { state = reduce(state, MoviesActions.PopRandromDiscover()) }
state = reduce(state, refill())
precondition(state.discover.isEmpty)
state = reduce(state, MoviesActions.ResetRandomDiscover())
let generation = state.discoverGeneration
precondition(generation != nil && state.consumedDiscoverIDs!.isEmpty)
precondition(state.discoverFilter == nil && state.discoverNotice == nil)
state = reduce(state, refill()) // stale request from before reset
precondition(state.discover.isEmpty && state.discoverNotice == nil)
state = reduce(state, MoviesActions.SetRandomDiscover(filter: filter,
    response: PaginatedResponse(results: catalog)))
precondition(state.discover.isEmpty)
state = reduce(state, refill(generation))
precondition(state.discover == [3,2,1] && state.discoverFilter?.genre == 53)
state = reduce(state, MoviesActions.ResetRandomDiscover())
precondition(state.discoverGeneration != generation)
state = reduce(state, refill(generation))
precondition(state.discover.isEmpty)
let newGeneration = state.discoverGeneration
let newFilter = DiscoverFilter(genre: 18)
state = reduce(state, MoviesActions.SetOfflineDiscover(filter: newFilter,
    movies: [Movie(id: 7)], notice: "Offline", generation: newGeneration))
precondition(state.discover == [7] && state.discoverFilter?.genre == 18)
print("PASS")
""")

if __name__ == "__main__":
    unittest.main()
