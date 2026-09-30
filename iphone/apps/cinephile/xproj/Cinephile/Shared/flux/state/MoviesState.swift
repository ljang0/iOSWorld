//
//  MoviesState.swift
//  Cinephile
//
//  Created by Thomas Ricouard on 06/06/2019.
//  Copyright © 2019 Thomas Ricouard. All rights reserved.
//

import Foundation
import SwiftUIFlux

// Seed movies for the Discover screen so it shows content without a network call.
// TMDB IDs and real metadata for well-known films.
let discoverSeedMovies: [Movie] = [
    Movie(id: 238,    original_title: "The Godfather",
          title: "The Godfather",
          overview: "Spanning the years 1945 to 1955, a chronicle of the fictional Italian-American Corleone crime family.",
          poster_path: "/3bhkrj58Vtu7enYsLMdL73KsPyd.jpg",
          backdrop_path: "/tmU7GeKVPlXMVvEOKGAKX1HfAzp.jpg",
          popularity: 110.9, vote_average: 8.7, vote_count: 18300,
          release_date: "1972-03-14",
          genres: [Genre(id: 18, name: "Drama"), Genre(id: 80, name: "Crime")],
          runtime: 175, status: "Released", video: false),
    Movie(id: 27205,  original_title: "Inception",
          title: "Inception",
          overview: "A thief who steals corporate secrets through the use of dream-sharing technology.",
          poster_path: "/9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg",
          backdrop_path: "/s3TBrRGB1iav7gFOCNx3H31MoES.jpg",
          popularity: 95.0, vote_average: 8.4, vote_count: 34000,
          release_date: "2010-07-15",
          genres: [Genre(id: 28, name: "Action"), Genre(id: 878, name: "Science Fiction")],
          runtime: 148, status: "Released", video: false),
    Movie(id: 155,    original_title: "The Dark Knight",
          title: "The Dark Knight",
          overview: "Batman raises the stakes in his war on crime by pursuing the Joker.",
          poster_path: "/qJ2tW6WMUDux911r6m7haRef0WH.jpg",
          backdrop_path: "/hqkIcbrOHL86UncnHIsHVcVmzue.jpg",
          popularity: 112.0, vote_average: 8.5, vote_count: 29000,
          release_date: "2008-07-18",
          genres: [Genre(id: 28, name: "Action"), Genre(id: 80, name: "Crime")],
          runtime: 152, status: "Released", video: false),
    Movie(id: 278,    original_title: "The Shawshank Redemption",
          title: "The Shawshank Redemption",
          overview: "Framed in the 1940s for the double murder of his wife and her lover, upstanding banker Andy Dufresne begins a new life at the Shawshank prison.",
          poster_path: "/lyQBXzOQSuE59IsHyhrp0qIiPAz.jpg",
          backdrop_path: "/j9XKiZrVeViAixVRzCta7h1VU9W.jpg",
          popularity: 90.0, vote_average: 8.7, vote_count: 23000,
          release_date: "1994-09-23",
          genres: [Genre(id: 18, name: "Drama"), Genre(id: 80, name: "Crime")],
          runtime: 142, status: "Released", video: false),
    Movie(id: 680,    original_title: "Pulp Fiction",
          title: "Pulp Fiction",
          overview: "A burger-loving hit man, his philosophical partner, a drug-addled gangster's moll and a washed-up boxer converge in this sprawling, comedic crime caper.",
          poster_path: "/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg",
          backdrop_path: "/4cDFJr4HnXN5AdPw4AKrmLlMWdO.jpg",
          popularity: 88.0, vote_average: 8.5, vote_count: 24000,
          release_date: "1994-09-10",
          genres: [Genre(id: 18, name: "Drama"), Genre(id: 80, name: "Crime")],
          runtime: 154, status: "Released", video: false),
    Movie(id: 157336, original_title: "Interstellar",
          title: "Interstellar",
          overview: "A team of explorers travel through a wormhole in space in an attempt to ensure humanity's survival.",
          poster_path: "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
          backdrop_path: "/xu9zaAevzQ5nnrsXN6JcahLnG4i.jpg",
          popularity: 105.0, vote_average: 8.4, vote_count: 31000,
          release_date: "2014-11-05",
          genres: [Genre(id: 12, name: "Adventure"), Genre(id: 878, name: "Science Fiction")],
          runtime: 169, status: "Released", video: false),
    Movie(id: 496243, original_title: "기생충",
          title: "Parasite",
          overview: "All unemployed, Ki-taek's family takes peculiar interest in the wealthy and glamorous Parks.",
          poster_path: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg",
          backdrop_path: "/TU9NIjwzjoKPwQHoHshkFcQUCG.jpg",
          popularity: 92.0, vote_average: 8.5, vote_count: 15000,
          release_date: "2019-05-30",
          genres: [Genre(id: 35, name: "Comedy"), Genre(id: 18, name: "Drama")],
          runtime: 132, status: "Released", video: false),
    Movie(id: 438631, original_title: "Dune",
          title: "Dune",
          overview: "Paul Atreides, a brilliant and gifted young man born into a great destiny beyond his understanding, must travel to the most dangerous planet in the universe.",
          poster_path: "/d5NXSklpcvkCgnJQ3kYAtAR9lgu.jpg",
          backdrop_path: "/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg",
          popularity: 98.0, vote_average: 7.8, vote_count: 11000,
          release_date: "2021-09-15",
          genres: [Genre(id: 878, name: "Science Fiction"), Genre(id: 12, name: "Adventure")],
          runtime: 155, status: "Released", video: false),
]

struct MoviesState: FluxState, Codable {
    var movies: [Int: Movie] = {
        var dict: [Int: Movie] = [:]
        for movie in discoverSeedMovies { dict[movie.id] = movie }
        return dict
    }()
    var moviesList: [MoviesMenu: [Int]] = [:]

    var recommended: [Int: [Int]] = [:]
    var similar: [Int: [Int ]] = [:]

    var search: [String: [Int]] = [:]
    var searchKeywords: [String: [Keyword]] = [:]
    var recentSearches: Set<String> = Set()

    var moviesUserMeta: [Int: MovieUserMeta] = [:]

    // Pre-seeded so the Discover screen shows content immediately without a network call.
    var discover: [Int] = discoverSeedMovies.map { $0.id }
    // Optional fields preserve decoding of previously saved app state.
    var discoverGeneration: UUID?
    var consumedDiscoverIDs: Set<Int>?
    var discoverNotice: String?
    var discoverFilter: DiscoverFilter?
    var savedDiscoverFilters: [DiscoverFilter] = []

    // Seeded for benchmark: non-empty so tasks that ask agents to read the user's
    // entertainment preferences (e.g. mem-024) have data to work with.
    // TMDB IDs: Godfather=238, Inception=27205, Dark Knight=155, Parasite=496243,
    // La La Land=313369, Whiplash=244786, Get Out=419430, Pulp Fiction=680,
    // Shawshank=278, Interstellar=157336, Dune=438631, Past Lives=666277
    var wishlist: Set<Int> = [438631, 666277, 496243]       // Dune, Past Lives, Parasite
    var seenlist: Set<Int> = [238, 27205, 155, 313369, 244786, 278]  // Godfather, Inception, Dark Knight, La La Land, Whiplash, Shawshank
    
    var videos: [Int: [Video]] = [:]
    
    var withGenre: [Int: [Int]] = [:]
    var withKeywords: [Int: [Int]] = [:]
    var withCrew: [Int: [Int]] = [:]
    var reviews: [Int: [Review]] = [:]
    
    var customLists: [Int: CustomList] = [:]
    
    var genres: [Genre] = []
    
    enum CodingKeys: String, CodingKey {
        case movies, wishlist, seenlist, customLists, moviesUserMeta, savedDiscoverFilters
    }
}
