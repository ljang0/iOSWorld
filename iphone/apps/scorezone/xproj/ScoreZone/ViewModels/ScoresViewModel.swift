import Foundation

@MainActor
final class ScoresViewModel: ObservableObject {
    @Published var selectedLeagueID: String
    @Published var selectedDate: Date
    @Published var selectedFilter: ScoresFilter
    @Published var selectedSort: ScoresSort

    @Published var games: [Game]
    @Published var dataOrigin: DataOrigin
    @Published var loadState: LoadState
    @Published var warningMessage: String?
    private var lastSyncedBenchmarkDayOffset: Int?

    init() {
        self.selectedLeagueID = "nba"
        self.selectedDate = Date()
        self.selectedFilter = .all
        self.selectedSort = .liveFirst
        self.games = []
        self.dataOrigin = .fallback
        self.loadState = .idle
    }

    func syncFromAppState(_ appState: AppState) {
        if SeedData.league(by: appState.preferredLeagueID) != nil {
            selectedLeagueID = appState.preferredLeagueID
        }
        if lastSyncedBenchmarkDayOffset != appState.benchmarkDayOffset {
            selectedDate = appState.benchmarkDate
            lastSyncedBenchmarkDayOffset = appState.benchmarkDayOffset
        }
    }

    /// Change the league while preserving the selected date.
    func selectLeague(_ leagueID: String) {
        selectedLeagueID = leagueID
    }

    /// Call when the user taps the date back/forward arrows.
    func navigateDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }

    func refresh(appState: AppState) async {
        loadState = .loading
        guard let league = appState.league(for: selectedLeagueID) else {
            loadState = .failed("League is unavailable.")
            return
        }

        let requestedDate = selectedDate
        let requestedLeagueID = selectedLeagueID
        let result = await appState.repository.loadScoreboard(
            league: league,
            date: requestedDate,
            mode: appState.dataAccessMode
        )
        // A slower previous request must not replace the user's current selection.
        guard selectedLeagueID == requestedLeagueID,
              Calendar.current.isDate(selectedDate, inSameDayAs: requestedDate) else { return }
        // The repository can return recent off-season results. A date-specific
        // scoreboard must not relabel those games or navigate away from its date.
        games = result.value.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: requestedDate)
        }
        dataOrigin = result.origin
        warningMessage = result.warningMessage

        loadState = .loaded

        appState.refreshCacheMetadata()
    }

    func displayedGames(favoriteIDs: Set<String>) -> [Game] {
        let filtered = games.filter { game in
            switch selectedFilter {
            case .all:
                return true
            case .live:
                return game.status.isLive
            case .final:
                return game.status.isFinal
            case .upcoming:
                return game.status.isUpcoming
            }
        }

        switch selectedSort {
        case .date:
            return filtered.sorted { $0.startDate < $1.startDate }
        case .alphabetical:
            return filtered.sorted { lhs, rhs in
                lhs.awayTeam.displayName < rhs.awayTeam.displayName
            }
        case .liveFirst:
            return filtered.sorted { lhs, rhs in
                statusRank(lhs.status.state) < statusRank(rhs.status.state)
            }
        case .favoritesFirst:
            return filtered.sorted { lhs, rhs in
                let lhsFavorite = favoriteScore(game: lhs, favoriteIDs: favoriteIDs)
                let rhsFavorite = favoriteScore(game: rhs, favoriteIDs: favoriteIDs)
                if lhsFavorite != rhsFavorite {
                    return lhsFavorite > rhsFavorite
                }
                return lhs.startDate < rhs.startDate
            }
        }
    }

    private func statusRank(_ state: GameState) -> Int {
        switch state {
        case .live: return 0
        case .upcoming: return 1
        case .final: return 2
        case .postponed: return 3
        }
    }

    private func favoriteScore(game: Game, favoriteIDs: Set<String>) -> Int {
        let homeFavorite = favoriteIDs.contains(game.homeTeam.id)
        let awayFavorite = favoriteIDs.contains(game.awayTeam.id)
        switch (homeFavorite, awayFavorite) {
        case (true, true): return 2
        case (true, false), (false, true): return 1
        case (false, false): return 0
        }
    }
}
