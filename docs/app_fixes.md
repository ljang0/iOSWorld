# App behavior and simulator setup fixes

These corrections keep tasks, rubrics, judge code, and seed records unchanged.

| App | Behavior |
|---|---|
| CalTrack | Daily history displays the log's protein, carbohydrate, and fat totals. |
| Cinephile | Discovery falls back to existing cached movies, retains list-response genre metadata, and respects genre/year/rating filters. Unsupported country availability is identified explicitly. Only four cards are laid out at once; dismissed cards stay dismissed until reset, undo restores them, and stale responses cannot overwrite a new filter session. |
| CityRide | The initial driver ETA is derived from the trip before the countdown starts. |
| Clock | Creating, editing, toggling, and deleting alarms writes an atomic app-container file. Relaunch restores the saved list, including an empty list. Missing or malformed storage falls back to the existing defaults. |
| CloudSheets | The editor shows the current workbook's filename above its controls. |
| DineSpot | Quick-booking slots stay on the selected date rather than silently falling back to another day. |
| FreshCart | Historical orders display their final status timestamp, or their creation date when no matching status event exists. Active orders keep their delivery-slot labels. |
| LockedIn | Reaction type, icon, label, and color survive relaunch. Legacy likes remain readable, and switching reactions does not inflate reaction counts. |
| ScoreZone | Date and league selections survive refresh. Responses for older selections are ignored, and games from a different date are not shown as the selected day's results. |
| TeamChat | A bounded, scrolling multiline editor avoids repeated height negotiation while retaining the composer accessibility identifier. |

The bootstrap's optional `HEADLESS_DEDICATED_SIMULATOR=true` setting skips
global Simulator-window alert dismissal and Home shortcuts. See the
[bootstrap documentation](../iphone/bootstrap/README.md) for its behavior.

## Regression checks

Run from the repository root with Python 3 and the Xcode Swift compiler available:

```sh
python3 -m unittest discover -s tests -v
bash -n iphone/bootstrap/bootstrap_ios_apps.sh
```

The tests compile production Swift declarations with minimal substitutes for UI,
network, and storage boundaries. They cover alarm and reaction persistence,
malformed and legacy state, offline discovery and refill behavior, stale-response
rejection, historical dates, selected-day booking, and ETA initialization.
Bootstrap tests intercept UI commands to check both the headless and default
paths without operating a simulator. Swift tests are skipped if `swiftc` is not
available; a complete validation run must have no skipped tests.

These logic checks do not exercise simulator rendering or real network services.
Build each affected app for the simulator to validate UIKit/SwiftUI integration.
For example:

```sh
xcodebuild \
  -project iphone/apps/clock/xproj/Clock.xcodeproj \
  -scheme Clock -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The other schemes are `CalTrack`, `Cinephile`, `CityRide`, `CloudSheets`,
`DineSpot`, `FreshCart`, `LockedIn`, `ScoreZone`, and `TeamChat`.
Cinephile's project is nested at
`iphone/apps/cinephile/xproj/Cinephile/Cinephile.xcodeproj`.
