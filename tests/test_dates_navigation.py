"""Portable logic regressions: stdlib Python and a Swift compiler only.

Production declarations are extracted verbatim; stubs replace UI, storage and
network boundaries. These checks do not replace simulator lifecycle/UI tests.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(app, path):
    return (ROOT / 'iphone/apps' / app.lower() / 'xproj' / app / path).read_text()


def declaration(text, marker):
    """Extract these balanced Swift declarations, including nested closures."""
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end] + '\n'


@unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is required')
class DateNavigationTests(unittest.TestCase):
    def swift(self, program):
        with tempfile.TemporaryDirectory(prefix='iosworld-dates-') as tmp:
            path = Path(tmp)
            (path / 'Check.swift').write_text(program)
            result = subprocess.run(
                ['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'cache'),
                 str(path / 'Check.swift'), '-o', str(path / 'check')],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(path / 'check')], capture_output=True,
                                    text=True, timeout=30, env={**os.environ, 'TZ': 'UTC'})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_scorezone_selection_and_stale_responses(self):
        text = source('ScoreZone', 'ViewModels/ScoresViewModel.swift')
        methods = '\n'.join(declaration(text, marker) for marker in (
            'func syncFromAppState(', 'func selectLeague(', 'func navigateDate(', 'func refresh('))
        self.swift('''import Foundation
struct Game { let id: String; let startDate: Date }
struct League { let id: String }
enum Mode { case automatic }
enum Origin { case live }
enum LoadState { case loading, loaded, failed(String) }
struct Result { let value: [Game]; let origin = Origin.live; let warningMessage: String? = nil; let adjustedDate: Date? }
enum SeedData { static func league(by id: String) -> League? { ["nba", "nfl"].contains(id) ? League(id:id) : nil } }
@MainActor final class Repository {
 var result = Result(value: [], adjustedDate: nil)
 var continuation: CheckedContinuation<Result, Never>?
 var suspend = false
 func loadScoreboard(league: League, date: Date, mode: Mode) async -> Result {
  if suspend { return await withCheckedContinuation { continuation = $0 } }
  return result
 }
}
@MainActor final class AppState {
 let repository = Repository()
 var dataAccessMode = Mode.automatic
 var preferredLeagueID = "nba"
 var benchmarkDayOffset = 0
 var benchmarkDate = Date(timeIntervalSince1970: 1900000000)
 func league(for id: String) -> League? { SeedData.league(by:id) }
 func refreshCacheMetadata() {}
}
@MainActor final class ScoresViewModel {
 var selectedDate = Date(); var selectedLeagueID = "nba"
 var games: [Game] = []; var dataOrigin = Origin.live
 var warningMessage: String?; var loadState = LoadState.loaded
 var lastSyncedBenchmarkDayOffset: Int?
''' + methods + '''
}
@main struct Check {
 @MainActor static func main() async {
  let app = AppState(); let model = ScoresViewModel()
  model.syncFromAppState(app)
  let initial = model.selectedDate
  model.navigateDate(by: 1)
  let next = model.selectedDate
  precondition(Calendar.current.dateComponents([.day], from: initial, to: next).day == 1)
  model.selectLeague("nfl")
  precondition(model.selectedDate == next && model.selectedLeagueID == "nfl")
  app.preferredLeagueID = "nfl"
  model.syncFromAppState(app)
  precondition(model.selectedDate == next)
  app.benchmarkDayOffset = 2; app.benchmarkDate = initial.addingTimeInterval(172800)
  model.syncFromAppState(app)
  precondition(model.selectedDate == app.benchmarkDate)
  let day = model.selectedDate; let old = day.addingTimeInterval(-86400 * 90)
  app.repository.result = Result(value: [Game(id:"old", startDate:old)], adjustedDate:old)
  await model.refresh(appState:app)
  precondition(model.selectedDate == day && model.games.isEmpty)
  app.repository.result = Result(value: [Game(id:"today", startDate:day), Game(id:"old", startDate:old)], adjustedDate:nil)
  await model.refresh(appState:app)
  precondition(model.games.map(\\.id) == ["today"])
  for changeLeague in [false, true] {
   model.selectedDate = day; model.selectedLeagueID = "nba"
   app.repository.suspend = true
   let pending = Task { await model.refresh(appState:app) }
   while app.repository.continuation == nil { await Task.yield() }
   if changeLeague { model.selectLeague("nfl") } else { model.navigateDate(by:1) }
   model.games = [Game(id:"newer", startDate:model.selectedDate)]
   app.repository.continuation!.resume(returning:app.repository.result)
   app.repository.continuation = nil
   await pending.value
   precondition(model.games.map(\\.id) == ["newer"])
  }
 }
}
''')

    def test_freshcart_historical_timestamp_labels(self):
        text = source('FreshCart', 'Models/AppModels.swift')
        self.swift('import Foundation\n' + declaration(text, 'enum OrderStatus:') +
                   source('FreshCart', 'Utilities/AppFormatters.swift') + '''
struct Event { let status: OrderStatus; let timestamp: Date }
struct Slot { let displayLabel = "Today • 5 PM" }
struct Order {
 var orderStatus: OrderStatus
 var statusEvents: [Event]
 let createdAt: Date
 let deliverySlot = Slot()
''' + declaration(text, 'var scheduleDisplayLabel:') + '''
}
@main struct Check {
 static func main() {
  AppFormatters.historicalOrderDate.locale = Locale(identifier:"en_US_POSIX")
  AppFormatters.historicalOrderDate.timeZone = TimeZone(secondsFromGMT:0)
  let created = Date(timeIntervalSince1970:0)
  for status in [OrderStatus.delivered, .pickedUp, .canceled] {
   var order = Order(orderStatus:status, statusEvents:[], createdAt:created)
   precondition(order.scheduleDisplayLabel == "Placed • Jan 1, 1970 • 12:00 AM")
   order.statusEvents = [Event(status:status, timestamp:created.addingTimeInterval(86400)), Event(status:.shopping, timestamp:created.addingTimeInterval(259200)), Event(status:status, timestamp:created.addingTimeInterval(172800))]
   precondition(order.scheduleDisplayLabel == status.label + " • Jan 3, 1970 • 12:00 AM")
  }
  for status in [OrderStatus.placed, .scheduled, .shopping] {
   let order = Order(orderStatus:status, statusEvents:[], createdAt:created)
   precondition(order.scheduleDisplayLabel == "Today • 5 PM")
  }
 }
}
''')

    def test_dinespot_quick_slots_stay_on_selected_day(self):
        text = source('DineSpot', 'ViewModels/DiscoverViewModel.swift')
        self.swift('''import Foundation
struct ReservationSlot { let date: Date }
final class DiningStore {
 var slots: [ReservationSlot] = []
 var nextDayCalls = 0
 func availableSlots(for id: String, date: Date, partySize: Int) -> [ReservationSlot] {
  precondition(id == "restaurant" && partySize == 4)
  return slots.filter { Calendar.current.isDate($0.date, inSameDayAs:date) }
 }
 func nextAvailableSlots(for id: String, from date: Date, partySize: Int, limit: Int) -> [ReservationSlot] {
  nextDayCalls += 1; return Array(slots.prefix(limit))
 }
}
struct DiscoverViewModel {
 var selectedDate: Date; var selectedTime: Date; var partySize = 4
''' + declaration(text, 'func effectiveDateTime(') + declaration(text, 'func preferredSlots(') + '''
}
@main struct Check {
 static func main() {
  let day = Calendar.current.startOfDay(for:Date(timeIntervalSince1970:1900000000))
  let model = DiscoverViewModel(selectedDate:day, selectedTime:day.addingTimeInterval(19*3600))
  let store = DiningStore()
  store.slots = [ReservationSlot(date:day.addingTimeInterval(86400+19*3600))]
  precondition(model.preferredSlots(for:"restaurant", store:store).isEmpty)
  precondition(store.nextDayCalls == 0)
  store.slots = [17, 19, 20, 21].map { ReservationSlot(date:day.addingTimeInterval(Double($0)*3600)) }
  let near = model.preferredSlots(for:"restaurant", store:store, limit:2)
  precondition(near.map(\\.date) == [19,20].map { day.addingTimeInterval(Double($0)*3600) })
  store.slots = [ReservationSlot(date:day.addingTimeInterval(17*3600))]
  precondition(model.preferredSlots(for:"restaurant", store:store).count == 1)
 }
}
''')

    def test_cityride_initial_eta_and_countdown(self):
        text = source('CityRide', 'Views/Request/TripStatusView.swift')
        # Verify the SwiftUI entry hook as well as executing its actual callback.
        hook = declaration(text, '.onChange(of: trip?.id, initial: true)')
        callback = hook.rstrip()[hook.index('in\n') + 3:-1]
        timer = declaration(text, 'private func startETATimer(').replace('private func', 'func')
        display = declaration(text, 'private func etaDisplayText(').replace('private func', 'func')
        state = re.search(r'@State private var etaCountdown[^\n]*', text).group().replace('@State private ', '@State ')
        self.swift('''import Foundation
enum Status { case requesting, tripInProgress, tripCompleted, canceled }
struct Trip { let etaMinutes: Int; let tripStatus: Status }
final class Timer {
 static var callback: ((Timer) -> Void)?
 var invalidated = false
 func invalidate() { invalidated = true }
 static func scheduledTimer(withTimeInterval: Double, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
  precondition(withTimeInterval == 15 && repeats); callback = block; return Timer()
 }
}
@propertyWrapper final class State<Value> {
 var wrappedValue: Value
 init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
struct Screen {
 var trip: Trip?
 @State var etaTimer: Timer?
''' + state + '\n' + timer + '\n' + display + '\nfunc onTripChange() {\n' + callback + '''
}
}
@main struct Check {
 static func main() {
  var screen = Screen()
  let trip = Trip(etaMinutes:7, tripStatus:.requesting)
  precondition(screen.etaDisplayText(for:trip) == "ETA 7 min")
  screen.onTripChange(); precondition(screen.etaTimer == nil)
  screen.trip = trip; screen.onTripChange()
  precondition(screen.etaDisplayText(for:trip) == "ETA 7 min")
  Timer.callback!(screen.etaTimer!)
  precondition(screen.etaDisplayText(for:trip) == "ETA 6 min")
  for _ in 0..<10 { Timer.callback!(Timer()) }
  precondition(screen.etaDisplayText(for:trip) == "ETA 1 min")
  precondition(screen.etaTimer == nil)
  precondition(screen.etaDisplayText(for:Trip(etaMinutes:7, tripStatus:.tripCompleted)) == "Arrived")
  precondition(screen.etaDisplayText(for:Trip(etaMinutes:7, tripStatus:.canceled)) == "Canceled")
 }
}
''')


if __name__ == '__main__':
    unittest.main()
