import Foundation

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedDate: Date = Date()
    @Published var selectedTime: Date = SeedData.makeDate(daysFromNow: 0, hour: 19)
    @Published var partySize: Int = 2
    @Published var sortOption: RestaurantSortOption = .highestRated
    @Published var filterState: RestaurantFilterState = .default

    func effectiveDateTime(calendar: Calendar = .current) -> Date {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        return calendar.date(from: merged) ?? selectedDate
    }

    func availableCuisines(store: DiningStore) -> [String] {
        Array(Set(store.restaurants(in: store.selectedCityID).map { $0.cuisine })).sorted()
    }

    func availableNeighborhoods(store: DiningStore) -> [Neighborhood] {
        store.neighborhoods
            .filter { $0.cityID == store.selectedCityID }
            .sorted(by: { $0.name < $1.name })
    }

    func preferredSlots(for restaurantID: String, store: DiningStore, limit: Int = 3) -> [ReservationSlot] {
        let daySlots = store.availableSlots(for: restaurantID, date: selectedDate, partySize: partySize)
        let targetDateTime = effectiveDateTime()
        let nearTargetSlots = daySlots.filter { $0.date >= targetDateTime.addingTimeInterval(-60 * 30) }
        if !nearTargetSlots.isEmpty {
            return Array(nearTargetSlots.prefix(limit))
        }
        if !daySlots.isEmpty {
            return Array(daySlots.prefix(limit))
        }
        // Quick-slot chips show only a time, so they must stay on the selected day.
        return []
    }

    func filteredRestaurants(store: DiningStore) -> [Restaurant] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedDateStart = Calendar.current.startOfDay(for: selectedDate)
        let targetDateTime = effectiveDateTime()

        // Auto-switch city when query matches a city name
        if !normalizedQuery.isEmpty {
            for city in store.cities {
                if normalizedQuery.contains(city.name.lowercased()) && city.id != store.selectedCityID {
                    store.selectedCityID = city.id
                    break
                }
            }
        }

        let cityRestaurants = store.restaurants(in: store.selectedCityID)

        let needsAvailabilityCheck = filterState.requirePartySizeSupport
            || filterState.availableNowOnly
            || !filterState.selectedTimeOfDay.isEmpty

        var results = cityRestaurants.filter { restaurant in
            let neighborhoodName = store.neighborhood(for: restaurant.neighborhoodID)?.name ?? ""
            let cityName = store.city(for: restaurant.cityID)?.name ?? ""

            let matchesQuery: Bool = {
                guard !normalizedQuery.isEmpty else { return true }
                let haystack = [restaurant.name, restaurant.cuisine, neighborhoodName, cityName, restaurant.shortDescription, restaurant.address]
                    .joined(separator: " ")
                    .lowercased()
                let tokens = normalizedQuery.split(separator: " ").map { String($0) }
                return tokens.allSatisfy { token in haystack.contains(token) }
            }()

            guard matchesQuery else { return false }

            let matchesCuisine = filterState.selectedCuisines.isEmpty || filterState.selectedCuisines.contains(restaurant.cuisine)
            let matchesNeighborhood = filterState.selectedNeighborhoodIDs.isEmpty || filterState.selectedNeighborhoodIDs.contains(restaurant.neighborhoodID)
            let matchesPriceTier = filterState.selectedPriceTiers.isEmpty || filterState.selectedPriceTiers.contains(restaurant.priceTier)
            let matchesOutdoor = !filterState.outdoorSeatingOnly || restaurant.tags.contains(.outdoorSeating)
            let matchesBarSeating = !filterState.barSeatingOnly || restaurant.tags.contains(.barSeating)
            let matchesBookableOnline = !filterState.bookableOnlineOnly || restaurant.tags.contains(.bookableOnline)

            guard matchesCuisine && matchesNeighborhood && matchesPriceTier
                    && matchesOutdoor && matchesBarSeating && matchesBookableOnline else { return false }

            guard needsAvailabilityCheck else { return true }

            let daySlots = store.availableSlots(for: restaurant.id, date: selectedDateStart, partySize: partySize)
            let futureSlots = store.allFutureSlots(for: restaurant.id, partySize: partySize)

            let matchesPartySizeSupport = !filterState.requirePartySizeSupport || !daySlots.isEmpty
            let matchesAvailableNow: Bool = {
                guard filterState.availableNowOnly else { return true }
                let now = Date()
                let maxDate = now.addingTimeInterval(60 * 90)
                return futureSlots.contains(where: { $0.date >= now && $0.date <= maxDate })
            }()

            let matchesTimeOfDay: Bool = {
                guard !filterState.selectedTimeOfDay.isEmpty else { return true }
                return futureSlots.contains(where: { slot in
                    filterState.selectedTimeOfDay.contains(where: { $0.contains(slot.date) })
                })
            }()

            return matchesPartySizeSupport
                && matchesAvailableNow
                && matchesTimeOfDay
        }

        switch sortOption {
        case .earliestAvailability:
            results.sort { lhs, rhs in
                let lhsDate = preferredEarliestDate(for: lhs.id, store: store, targetDateTime: targetDateTime)
                let rhsDate = preferredEarliestDate(for: rhs.id, store: store, targetDateTime: targetDateTime)
                if lhsDate == rhsDate {
                    return lhs.rating > rhs.rating
                }
                return lhsDate < rhsDate
            }
        case .bestMatch:
            results.sort { lhs, rhs in
                matchScore(for: lhs, store: store, normalizedQuery: normalizedQuery, targetDateTime: targetDateTime) >
                    matchScore(for: rhs, store: store, normalizedQuery: normalizedQuery, targetDateTime: targetDateTime)
            }
        case .highestRated:
            results.sort { $0.rating > $1.rating }
        case .nearest:
            results.sort { $0.distanceMiles < $1.distanceMiles }
        case .lowestPriceTier:
            results.sort {
                if $0.priceTier == $1.priceTier {
                    return $0.rating > $1.rating
                }
                return $0.priceTier < $1.priceTier
            }
        }

        return results
    }

    private func matchScore(for restaurant: Restaurant, store: DiningStore, normalizedQuery: String, targetDateTime: Date) -> Double {
        var score = 0.0

        if restaurant.tags.contains(.popular) {
            score += 1.2
        }
        score += restaurant.rating
        score += max(0, 3.0 - restaurant.distanceMiles) * 0.2
        score += availabilityRelevance(for: restaurant.id, store: store, targetDateTime: targetDateTime)

        if !normalizedQuery.isEmpty {
            let neighborhoodName = store.neighborhood(for: restaurant.neighborhoodID)?.name.lowercased() ?? ""
            if restaurant.name.lowercased().contains(normalizedQuery) {
                score += 2.5
            }
            if restaurant.cuisine.lowercased().contains(normalizedQuery) {
                score += 1.5
            }
            if neighborhoodName.contains(normalizedQuery) {
                score += 1.0
            }
        }

        if store.isFavorite(restaurantID: restaurant.id) {
            score += 0.8
        }

        return score
    }

    private func preferredEarliestDate(for restaurantID: String, store: DiningStore, targetDateTime: Date) -> Date {
        let daySlots = store.availableSlots(for: restaurantID, date: selectedDate, partySize: partySize)
        if let firstNearTarget = daySlots.first(where: { $0.date >= targetDateTime.addingTimeInterval(-60 * 30) }) {
            return firstNearTarget.date
        }
        if let dayFirst = daySlots.first {
            return dayFirst.date
        }
        return store.earliestAvailabilityDate(for: restaurantID, partySize: partySize) ?? .distantFuture
    }

    private func availabilityRelevance(for restaurantID: String, store: DiningStore, targetDateTime: Date) -> Double {
        let daySlots = store.availableSlots(for: restaurantID, date: selectedDate, partySize: partySize)
        guard !daySlots.isEmpty else { return 0 }

        let nearestInterval = daySlots
            .map { abs($0.date.timeIntervalSince(targetDateTime)) }
            .min() ?? (60 * 60 * 24)

        if nearestInterval <= 60 * 30 { return 2.2 }
        if nearestInterval <= 60 * 90 { return 1.6 }
        if nearestInterval <= 60 * 180 { return 1.0 }
        return 0.5
    }
}
