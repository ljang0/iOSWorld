import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedHeadline: HeadlineArticle?
    @State private var showSearchSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                // This bounded feed must be measured as one layout. Lazy section
                // discovery can cycle with nested horizontal scroll views on iOS 26.
                VStack(alignment: .leading, spacing: 18) {
                    Text("Home")
                        .font(.caption)
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("navigation_title_home")

                    // Score ticker
                    if !viewModel.tickerGames.isEmpty {
                        scoreTicker
                    }

                    statusHeader

                    if !viewModel.alerts.isEmpty {
                        sectionHeader(title: "Alerts")
                            .accessibilityIdentifier("home_alerts_header")
                        alertSection
                    }

                    // Hero headline card
                    sectionHeader(title: "Top Stories")
                        .accessibilityIdentifier("home_top_stories_header")
                    heroHeadlineCard
                    topStoriesSection

                    sectionHeader(title: "Favorite Teams")
                        .accessibilityIdentifier("home_favorite_teams_header")
                    favoriteTeamsSection

                    sectionHeader(title: "Featured Games")
                        .accessibilityIdentifier("home_featured_games_header")
                    featuredGamesSection

                    sectionHeader(title: "Upcoming")
                        .accessibilityIdentifier("home_upcoming_games_header")
                    upcomingGamesSection

                    sectionHeader(title: "Leagues")
                        .accessibilityIdentifier("home_league_shortcuts_header")
                    leagueShortcutsSection

                    if let league = appState.league(for: "nba") {
                        HStack {
                            sectionHeader(title: "Standings Preview")
                                .accessibilityIdentifier("home_standings_preview_header")
                            Spacer()
                            NavigationLink(destination: StandingsView(league: league)) {
                                Text("View All")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ScoreZoneColors.accentRed)
                            }
                            .accessibilityIdentifier("home_open_standings_button")
                        }
                        standingsPreviewSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen_home")
        .safeAreaInset(edge: .top) {
            homeTopBar
        }
        .task {
            await viewModel.refresh(appState: appState)
        }
        .onChange(of: appState.dataAccessMode) { _, _ in
            Task {
                await viewModel.refresh(appState: appState)
            }
        }
        .onChange(of: appState.benchmarkDayOffset) { _, _ in
            Task {
                await viewModel.refresh(appState: appState)
            }
        }
        .refreshable {
            await viewModel.refresh(appState: appState)
        }
        .sheet(item: $selectedHeadline) { article in
            HomeHeadlineDetailSheet(article: article)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSearchSheet) {
            NavigationStack {
                SearchView()
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Top Bar

    private var homeTopBar: some View {
        HStack(spacing: 18) {
            Button {
                showSearchSheet = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .regular))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_header_search_button")

            Spacer()

            Text("ScoreZone")
                .font(.system(size: 34, weight: .black))
                .italic()

            Spacer()

            Button {
                Task {
                    await viewModel.refresh(appState: appState)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .regular))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_refresh_button")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Color.black
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.8)
                }
        )
    }

    // MARK: - Score Ticker

    private var scoreTicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tickerGames) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                TeamLogoView(team: game.awayTeam, size: 14, cornerRadius: 3)
                                Text(game.awayTeam.abbreviation)
                                    .font(.system(size: 11, weight: .bold))
                                Spacer()
                                Text(game.awayScore.map(String.init) ?? "-")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                            }
                            HStack(spacing: 4) {
                                TeamLogoView(team: game.homeTeam, size: 14, cornerRadius: 3)
                                Text(game.homeTeam.abbreviation)
                                    .font(.system(size: 11, weight: .bold))
                                Spacer()
                                Text(game.homeScore.map(String.init) ?? "-")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                            }
                            Text(game.status.shortText)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(game.status.isLive ? ScoreZoneColors.liveRed : .gray)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 95)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ScoreZoneColors.cardBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("For You")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .accessibilityIdentifier("home_editorial_header")

            Text(homeSubtitle)
                .font(.caption)
                .foregroundStyle(.gray)
                .accessibilityIdentifier("home_editorial_subtitle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Alerts

    private var alertSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(viewModel.alerts.enumerated()), id: \.element.id) { index, alert in
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(alertColor(alert.severity).opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(alertColor(alert.severity).opacity(0.45), lineWidth: 1)
                )
                .accessibilityIdentifier("home_alert_row_\(String(format: "%03d", index + 1))")
            }
        }
    }

    // MARK: - Hero Headline

    private var heroHeadlineCard: some View {
        Group {
            if let article = viewModel.headlines.first {
                Button {
                    selectedHeadline = article
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        HeadlineThumbnailView(article: article, height: 260)

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.sectionTag.uppercased())
                                .font(.caption.weight(.black))
                                .foregroundStyle(ScoreZoneColors.accentRed)
                            Text(article.headline)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_open_headline_001")
            }
        }
    }

    // MARK: - Top Stories (horizontal scroll, starting from index 1)

    private var topStoriesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.headlines.dropFirst().prefix(11).enumerated()), id: \.element.id) { index, article in
                    let displayIndex = index + 2  // offset by 2 since hero is #1
                    Button {
                        selectedHeadline = article
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HeadlineThumbnailView(article: article, height: 132)
                                .accessibilityIdentifier("home_headline_image_\(String(format: "%03d", displayIndex))")

                            Text(article.sectionTag.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.gray)
                            Text(article.headline)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(3)
                            Text(article.summary)
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .lineLimit(3)

                            HStack {
                                Text("Read")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(ScoreZoneColors.accentRed, lineWidth: 1)
                                    )
                                    .foregroundStyle(ScoreZoneColors.accentRed)
                                    .accessibilityIdentifier("home_open_headline_\(String(format: "%03d", displayIndex))")

                                Spacer()

                                Button {
                                    appState.toggleSavedHeadline(article.id)
                                } label: {
                                    Image(systemName: appState.isHeadlineSaved(article.id) ? "bookmark.fill" : "bookmark")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(appState.isHeadlineSaved(article.id) ? .yellow : .gray)
                                .accessibilityIdentifier("home_save_headline_\(String(format: "%03d", displayIndex))")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 280, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(ScoreZoneColors.cardBackgroundLighter)
                    )
                    .accessibilityIdentifier("home_top_headline_\(String(format: "%03d", displayIndex))")
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Favorite Teams

    private var favoriteTeamsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if viewModel.favoriteTeams.isEmpty {
                    Button("Find Teams to Follow") {
                        appState.selectedTab = .menu
                    }
                    .buttonStyle(.bordered)
                    .tint(ScoreZoneColors.accentRed)
                    .accessibilityIdentifier("home_find_teams_button")
                } else {
                    ForEach(viewModel.favoriteTeams) { team in
                        NavigationLink(destination: TeamDetailView(team: team)) {
                            HStack(spacing: 8) {
                                TeamLogoView(team: team, size: 24, cornerRadius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.abbreviation)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text(team.shortName)
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(ScoreZoneColors.cardBackgroundLighter))
                        }
                        .accessibilityIdentifier("team_row_\(AccessibilityID.slug(team.displayName))")
                    }
                }
            }
        }
    }

    // MARK: - Featured Games

    private var featuredGamesSection: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.featuredGames) { game in
                NavigationLink(destination: GameDetailView(game: game)) {
                    GameCardView(game: game, isFavorite: appState.favoriteTeamIDs.contains(game.homeTeam.id) || appState.favoriteTeamIDs.contains(game.awayTeam.id))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(game.accessibilityRowID)
            }
        }
    }

    // MARK: - Upcoming Games

    private var upcomingGamesSection: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.upcomingGames) { game in
                HStack {
                    NavigationLink(destination: GameDetailView(game: game)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.matchupTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(DateFormatting.shortDate.string(from: game.startDate)) \u{2022} \(DateFormatting.gameTime.string(from: game.startDate))")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(game.accessibilityRowID)

                    Spacer()

                    if let league = appState.league(for: game.leagueID) {
                        Text(league.shortName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - League Shortcuts

    private var leagueShortcutsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.leagues) { league in
                    Button {
                        appState.preferredLeagueID = league.id
                        appState.selectedTab = .scores
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: league.iconSystemName)
                            Text(league.shortName)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(ScoreZoneColors.cardBackgroundElevated))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home_league_shortcut_\(league.accessibilitySlug)")
                }
            }
        }
    }

    // MARK: - Standings Preview

    private var standingsPreviewSection: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.standingsPreview) { entry in
                HStack {
                    Text("\(entry.rank)")
                        .frame(width: 24, alignment: .leading)
                        .foregroundStyle(.white)
                    Text(entry.team.abbreviation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(entry.recordText)
                        .foregroundStyle(.gray)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("standings_row_\(AccessibilityID.slug(entry.leagueID))_\(AccessibilityID.slug(entry.conference))_\(entry.rank)")
            }
        }
    }

    // MARK: - Helpers

    private func alertColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high": return .red
        case "warning": return .orange
        default: return ScoreZoneColors.accentRed
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.title3.weight(.black))
            .tracking(0.5)
            .foregroundStyle(.white)
    }

    private var homeSubtitle: String {
        let liveCount = viewModel.featuredGames.filter { $0.status.isLive }.count
        if liveCount > 0 {
            return "\(liveCount) live games now \u{2022} \(DateFormatting.shortDate.string(from: appState.benchmarkDate))"
        }
        return "Top stories and scores for \(DateFormatting.shortDate.string(from: appState.benchmarkDate))"
    }
}

// MARK: - Headline Detail Sheet

private struct HomeHeadlineDetailSheet: View {
    let article: HeadlineArticle

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeadlineThumbnailView(article: article, height: 210)
                        .accessibilityIdentifier("headline_detail_image")

                    Text(article.sectionTag.uppercased())
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("headline_detail_section")

                    Text(article.headline)
                        .font(.title2.weight(.bold))
                        .accessibilityIdentifier("headline_detail_title")

                    Text(article.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("headline_detail_summary")

                    Text("Published \(DateFormatting.shortDate.string(from: article.publishedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("headline_detail_published_at")

                    HStack(spacing: 10) {
                        Button {
                            appState.toggleSavedHeadline(article.id)
                        } label: {
                            Label(
                                appState.isHeadlineSaved(article.id) ? "Saved" : "Save Story",
                                systemImage: appState.isHeadlineSaved(article.id) ? "bookmark.fill" : "bookmark"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("headline_detail_save_button")

                        if let leagueID = article.leagueID,
                           let league = appState.league(for: leagueID) {
                            Button {
                                appState.preferredLeagueID = league.id
                                appState.selectedTab = .scores
                                dismiss()
                            } label: {
                                Label("Open \(league.shortName)", systemImage: league.iconSystemName)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("headline_detail_open_league_button")
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Story")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen_headline_detail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("headline_detail_done_button")
                }
            }
        }
    }
}

// MARK: - Game Card

private struct GameCardView: View {
    let game: Game
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.leagueID.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.gray)
                Spacer()
                Text(game.status.shortText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(game.status.isLive ? ScoreZoneColors.liveRed : .gray)
                    .accessibilityIdentifier("game_status_label_\(AccessibilityID.slug(game.status.state.rawValue))")
            }

            scoreRow(team: game.awayTeam, score: game.awayScore)
            scoreRow(team: game.homeTeam, score: game.homeScore)

            HStack {
                Text(game.venue ?? "Venue TBD")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ScoreZoneColors.cardBackgroundLighter)
        )
    }

    private func scoreRow(team: Team, score: Int?) -> some View {
        HStack {
            TeamLogoView(team: team, size: 18, cornerRadius: 4)
            Text(team.abbreviation)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(score.map(String.init) ?? "-")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
