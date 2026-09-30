//
//  MoviesStateReducer.swift
//  Cinephile
//
//  Created by Thomas Ricouard on 06/06/2019.
//  Copyright © 2019 Thomas Ricouard. All rights reserved.
//

import Foundation
import SwiftUIFlux

func moviesStateReducer(state: MoviesState, action: Action) -> MoviesState {
    var state = state
    switch action {
    case let action as MoviesActions.SetMovieMenuList:
        if action.page == 1 {
            state.moviesList[action.list] = action.response.results.map{ $0.id }
        } else {
            if var list = state.moviesList[action.list] {
                list.append(contentsOf: action.response.results.map{ $0.id })
                state.moviesList[action.list] = list
            } else {
                state.moviesList[action.list] = action.response.results.map{ $0.id }
            }
        }
        state.movies += action.response.results

    case let action as MoviesActions.SetDetail:
        state.movies[action.movie] = action.response
        
    case let action as MoviesActions.SetRecommended:
        state.recommended[action.movie] = action.response.results.map{ $0.id }
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.SetSimilar:
        state.similar[action.movie] = action.response.results.map{ $0.id }
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.SetVideos:
        state.videos[action.movie] = action.response.results
        
    case let action as MoviesActions.SetSearch:
        if action.page == 1 {
            state.search[action.query] = action.response.results.map{ $0.id }
        } else {
            state.search[action.query]?.append(contentsOf: action.response.results.map{ $0.id })
        }
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.SetSearchKeyword:
        state.searchKeywords[action.query] = action.response.results
        
    case let action as MoviesActions.AddToWishlist:
        state.wishlist.insert(action.movie)
        state.seenlist.remove(action.movie)
        
        var meta = state.moviesUserMeta[action.movie] ?? MovieUserMeta()
        meta.addedToList = Date()
        state.moviesUserMeta[action.movie] = meta
        
    case let action as MoviesActions.RemoveFromWishlist:
        state.wishlist.remove(action.movie)
        
    case let action as MoviesActions.AddToSeenList:
        state.seenlist.insert(action.movie)
        state.wishlist.remove(action.movie)
        
        var meta = state.moviesUserMeta[action.movie] ?? MovieUserMeta()
        meta.addedToList = Date()
        state.moviesUserMeta[action.movie] = meta
        
    case let action as MoviesActions.RemoveFromSeenList:
        state.seenlist.remove(action.movie)
        
    case let action as MoviesActions.AddMovieToCustomList:
        state.customLists[action.list]?.movies.insert(action.movie)
        
    case let action as MoviesActions.AddMoviesToCustomList:
        if var list = state.customLists[action.list] {
            for movie in action.movies {
                list.movies.insert(movie)
            }
            state.customLists[action.list] = list
        }
        
    case let action as MoviesActions.RemoveMovieFromCustomList:
        state.customLists[action.list]?.movies.remove(action.movie)
        
    case let action as MoviesActions.SetMovieForGenre:
        if action.page == 1 {
            state.withGenre[action.genre.id] = action.response.results.map{ $0.id }
        } else {
            state.withGenre[action.genre.id]?.append(contentsOf: action.response.results.map{ $0.id })
        }
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.SetOfflineDiscover:
        guard action.generation == state.discoverGeneration else { break }
        // Refill must not resurrect cards consumed while the request was in flight.
        // The top card is the last ID in the Discover stack.
        let consumed = state.consumedDiscoverIDs ?? []
        let candidates = action.movies.reversed().map { $0.id }.filter { !consumed.contains($0) }
        if state.discoverNotice == nil {
            state.discover = candidates
        } else {
            let existing = Set(state.discover)
            state.discover.insert(contentsOf: candidates.filter { !existing.contains($0) }, at: 0)
        }
        for movie in action.movies { state.movies[movie.id] = movie }
        state.discoverFilter = action.filter
        state.discoverNotice = action.notice

    case let action as MoviesActions.SetRandomDiscover:
        guard action.generation == state.discoverGeneration else { break }
        state.discoverNotice = nil
        var excluded = (state.consumedDiscoverIDs ?? []).union(state.discover)
        let candidates = action.response.results.map { $0.id }.filter { excluded.insert($0).inserted }
        if state.discover.isEmpty {
            state.discover = candidates
        } else if state.discover.count < 10 {
            state.discover.insert(contentsOf: candidates, at: 0)
        }
        state = mergeMovies(movies: action.response.results, state: state)
        state.discoverFilter = action.filter
        
    case let action as MoviesActions.SetMovieReviews:
        state.reviews[action.movie] = action.response.results
        
    case let action as MoviesActions.SetMovieWithCrew:
        state.withCrew[action.crew] = action.response.results.map{ $0.id }
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.SetMovieWithKeyword:
        if action.page == 1 {
            state.withKeywords[action.keyword] = action.response.results.map{ $0.id }
        } else {
            state.withKeywords[action.keyword]?.append(contentsOf: action.response.results.map{ $0.id })
        }
        
        state = mergeMovies(movies: action.response.results, state: state)
        
    case let action as MoviesActions.AddCustomList:
        state.customLists[action.list.id] = action.list
        
    case let action as MoviesActions.EditCustomList:
        if var list = state.customLists[action.list] {
            if let cover = action.cover {
                list.cover = cover
            }
            if let title = action.title {
                list.name = title
            }
            state.customLists[action.list] = list
        }
        
    case let action as MoviesActions.RemoveCustomList:
        state.customLists[action.list] = nil
        
    case _ as  MoviesActions.PopRandromDiscover:
        if let movie = state.discover.popLast() {
            var consumed = state.consumedDiscoverIDs ?? []
            consumed.insert(movie)
            state.consumedDiscoverIDs = consumed
        }
    case let action as  MoviesActions.PushRandomDiscover:
        state.consumedDiscoverIDs?.remove(action.movie)
        state.discover.removeAll { $0 == action.movie }
        state.discover.append(action.movie)
        
    case _ as  MoviesActions.ResetRandomDiscover:
        state.discoverGeneration = UUID()
        state.consumedDiscoverIDs = []
        state.discoverFilter = nil
        state.discoverNotice = nil
        state.discover = []
        
    case let action as MoviesActions.SetGenres:
        state.genres = action.genres
        state.genres.insert(Genre(id: -1, name: "Random"), at: 0)
        
    case let action as PeopleActions.SetPeopleCredits:
        if let crews = action.response.crew {
            state = mergeMovies(movies: crews, state: state)
        }
        
        if let casts = action.response.cast {
            state = mergeMovies(movies: casts, state: state)
        }
        
    case let action as MoviesActions.SaveDiscoverFilter:
        state.savedDiscoverFilters.append(action.filter)
        
    case _ as MoviesActions.ClearSavedDiscoverFilters:
        state.savedDiscoverFilters = []
        
    default:
        break
    }
    
    
    return state
}

func +=(lhs: inout [Int: Movie], rhs: [Movie]) {
    for movie in rhs {
        lhs[movie.id] = movie
    }
}

private func mergeMovies(movies: [Movie], state: MoviesState) -> MoviesState {
    var state = state
    for movie in movies {
        if state.movies[movie.id] == nil {
            state.movies[movie.id] = movie
        }
    }
    return state
}
