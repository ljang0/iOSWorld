//
//  DiscoverFilter.swift
//  Cinephile
//
//  Created by Thomas Ricouard on 23/06/2019.
//  Copyright © 2019 Thomas Ricouard. All rights reserved.
//

import Foundation
import SwiftUI

struct DiscoverFilter: Codable {
    let year: Int
    let startYear: Int?
    let endYear: Int?
    let sort: String
    let genre: Int?
    let region: String?
    
    static func randomFilter() -> DiscoverFilter {
        return DiscoverFilter(year: randomYear(),
                              startYear: nil,
                              endYear: nil,
                              sort: randomSort(),
                              genre: nil,
                              region: nil)
    }
    
    static func randomYear() -> Int {
        let calendar = Calendar.current
        return Int.random(in: 1950..<calendar.component(.year, from: Date()))
    }
    
    static func randomSort() -> String {
        let sortBy = ["popularity.desc",
                      "popularity.asc",
                      "vote_average.asc",
                      "vote_average.desc"]
        return sortBy[Int.random(in: 0..<sortBy.count)]
    }
    
    static func randomPage() -> Int {
        return Int.random(in: 1..<20)
    }
    
    func toParams() -> [String: String] {
        var params: [String: String] = [:]
        if let startYear = startYear, let endYear = endYear {
            params["primary_release_date.gte"] = "\(startYear)"
            params["primary_release_date.lte"] = "\(endYear)"
        } else {
            params["year"] = "\(year)"
        }
        if let genre = genre {
            params["with_genres"] = "\(genre)"
        }
        if let region = region {
            params["region"] = region
        }
        params["page"] = "\(DiscoverFilter.randomPage())"
        params["sort_by"] = sort
        params["language"] = "en-US"
        return params
    }
    
    func toText(genres: [Genre]) -> String {
        var text = String("")
        if let startYear = startYear, let endYear = endYear {
            text = text + "\(startYear)-\(endYear)"
        } else {
            text = text + " · Random"
        }
        if let genre = genre,
            let stateGenre = genres.first(where: { (realGenre) -> Bool in
                realGenre.id == genre
            }) {
            text = text + " · \(stateGenre.name)"
        }
        if let region = region {
            text = text + " · \(region)"
        }
        return text
    }
}

// The cached catalog has genre/year/rating data, but no regional release availability.
func offlineDiscoverMovies(_ movies: [Movie], filter: DiscoverFilter?) -> [Movie] {
    guard filter?.region == nil else { return [] }
    let matches = movies.filter { movie in
        guard movie.id != 0 else { return false }
        if let genre = filter?.genre, genre != -1,
           !movie.knownGenreIDs.contains(genre) { return false }
        if let start = filter?.startYear, let end = filter?.endYear {
            guard let date = movie.release_date, let year = Int(date.prefix(4)),
                  year >= start && year <= end else { return false }
        }
        return true
    }
    return matches.sorted { left, right in
        let sort = filter?.sort ?? "popularity.desc"
        let lhs = sort.hasPrefix("vote_average") ? left.vote_average : left.popularity
        let rhs = sort.hasPrefix("vote_average") ? right.vote_average : right.popularity
        if lhs == rhs { return left.id < right.id }
        return sort.hasSuffix(".asc") ? lhs < rhs : lhs > rhs
    }
}

// Keep the complete candidate stack in state, but only lay out its top four cards.
func visibleDiscoverMovieIDs(_ movies: [Int]) -> [Int] {
    Array(movies.suffix(4))
}
