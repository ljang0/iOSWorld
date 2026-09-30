#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BASE_DIR/../.." && pwd)"
APPS_DIR="${APPS_DIR:-$BASE_DIR/../apps}"
DERIVED_DIR="${DERIVED_DIR:-$BASE_DIR/.derived_data}"
DEFAULT_REPO_LIST="$BASE_DIR/repos.txt"
REPO_LIST="${REPO_LIST:-$DEFAULT_REPO_LIST}"
if [[ ! -f "$REPO_LIST" ]]; then
  REPO_LIST="$BASE_DIR/repos.txt"
fi

SIM_DEVICE_NAME="${SIM_DEVICE_NAME:-}"
SIM_OS="${SIM_OS:-latest}" # "latest" or an installed runtime like 17.0, 17.4

OPEN_IN_XCODE="${OPEN_IN_XCODE:-false}"
OPEN_SIMULATOR="${OPEN_SIMULATOR:-true}"
CLEAR_SIMULATOR="${CLEAR_SIMULATOR:-true}"
UPDATE_REPOS="${UPDATE_REPOS:-false}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-true}"
POD_BIN="${POD_BIN:-}"
NODE_INSTALL="${NODE_INSTALL:-auto}" # auto|always|never
ALLOW_NATIVESCRIPT="${ALLOW_NATIVESCRIPT:-true}"
ENV_FILE="${ENV_FILE:-}"
LOAD_ENV_FILE="${LOAD_ENV_FILE:-true}"

# Manifest of installed apps: written at end of bootstrap for per-task reinstall.
APP_MANIFEST_FILE="$BASE_DIR/.app_manifest.json"
LAST_BOOTSTRAP_STATE_FILE="$BASE_DIR/.last_bootstrap_state.env"
declare -a MANIFEST_ENTRIES=()

# Record an installed app in the manifest (called after each successful install).
record_manifest_entry() {
  local app_name="$1"
  local bundle_id="$2"
  local app_path="$3"
  local repo_dir="${4:-}"
  [[ -n "$bundle_id" && -n "$app_path" ]] || return 0
  local git_commit=""
  if [[ -n "$repo_dir" && -d "$repo_dir/.git" ]]; then
    git_commit="$(cd "$repo_dir" && git rev-parse --short HEAD 2>/dev/null || true)"
  fi
  MANIFEST_ENTRIES+=("$(printf '"%s": {"bundle_id": "%s", "app_path": "%s", "git_commit": "%s"}' "$app_name" "$bundle_id" "$app_path" "$git_commit")")
}

# Write the collected manifest entries to disk.
write_app_manifest() {
  local tmp
  tmp="$(mktemp)"
  printf '{\n' > "$tmp"
  local i=0
  for entry in "${MANIFEST_ENTRIES[@]}"; do
    if [[ $i -gt 0 ]]; then
      printf ',\n' >> "$tmp"
    fi
    printf '  %s' "$entry" >> "$tmp"
    i=$((i + 1))
  done
  printf '\n}\n' >> "$tmp"
  mv "$tmp" "$APP_MANIFEST_FILE"
  log "App manifest written to $APP_MANIFEST_FILE (${#MANIFEST_ENTRIES[@]} apps)"
}

write_last_bootstrap_state() {
  local udid="$1"
  local tmp
  tmp="$(mktemp)"
  printf 'BOOTSTRAP_SIMCTL_UDID=%q\n' "$udid" > "$tmp"
  printf 'BOOTSTRAP_REPO_LIST=%q\n' "$REPO_LIST" >> "$tmp"
  mv "$tmp" "$LAST_BOOTSTRAP_STATE_FILE"
  log "Bootstrap simulator state written to $LAST_BOOTSTRAP_STATE_FILE"
}

log() { printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./bootstrap_ios_apps.sh [options]

Options:
  --repos <file>           Path to a newline-delimited repo list (default: ./repos.txt)
  --device <name>          Simulator device name (example: "iPhone 15")
  --os <version|latest>    iOS runtime version (example: 17.4) or "latest"
  --open-xcode             Open each project in Xcode
  --no-open-simulator      Don't open the Simulator app UI
  --clear-simulator        Erase simulator before installing apps (default)
  --no-clear-simulator     Skip erasing simulator state
  --env-file <file>        Load environment variables from a file (default: auto-detect repo .env)
  --no-env-file            Skip loading an env file
  --update                 Pull latest changes when repo already exists
  --install-deps           Attempt to install missing dependencies (CocoaPods, Carthage, Node, brew deps)
  --node-install           Always run node package install when package.json exists
  --no-node-install        Skip node package install even if package.json exists
  --allow-nativescript     Allow NativeScript apps to run dependency setup (no build)
  --help                   Show this help

Env overrides:
  APPS_DIR, DERIVED_DIR, REPO_LIST, SIM_DEVICE_NAME, SIM_OS, OPEN_IN_XCODE,
  OPEN_SIMULATOR, CLEAR_SIMULATOR, UPDATE_REPOS, AUTO_INSTALL_DEPS, POD_BIN,
  NODE_INSTALL, ALLOW_NATIVESCRIPT, ENV_FILE, LOAD_ENV_FILE
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

ensure_brew_path() {
  if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi
  if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return 0
  fi
  return 0
}

brew_pkg_for_dep() {
  case "$1" in
    clang-format) echo "clang-format" ;;
    swiftlint) echo "swiftlint" ;;
    autoconf|automake|libtool|pkg-config|cmake|gettext|openssl|openssl@3) echo "$1" ;;
    *) echo "$1" ;;
  esac
}

ensure_brew_package() {
  local pkg="$1"
  if ! command -v brew >/dev/null 2>&1; then
    log "brew not found; cannot install $pkg."
    return 1
  fi
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  log "Installing $pkg via Homebrew..."
  brew install "$pkg" || true
  brew list --formula "$pkg" >/dev/null 2>&1
}

ensure_applesimutils() {
  if command -v applesimutils >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v brew >/dev/null 2>&1; then
    log "brew not found; cannot install applesimutils."
    return 1
  fi
  log "Installing applesimutils (Wix) for simulator permission management..."
  brew tap wix/brew 2>/dev/null || true
  brew install applesimutils || true
  command -v applesimutils >/dev/null 2>&1
}

find_pod() {
  if [[ -n "${POD_BIN:-}" && -x "$POD_BIN" ]]; then
    echo "$POD_BIN"
    return 0
  fi
  if command -v pod >/dev/null 2>&1; then
    command -v pod
    return 0
  fi
  local candidates=(
    /opt/homebrew/bin/pod
    /usr/local/bin/pod
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_cocoapods() {
  local pod_bin
  if pod_bin="$(find_pod)"; then
    POD_BIN="$pod_bin"
    return 0
  fi

  if [[ "$AUTO_INSTALL_DEPS" == "true" ]]; then
    if command -v brew >/dev/null 2>&1; then
      log "Installing CocoaPods via Homebrew..."
      brew install cocoapods || true
    elif command -v gem >/dev/null 2>&1; then
      log "Installing CocoaPods via RubyGems..."
      gem install cocoapods || true
    fi
  fi

  if pod_bin="$(find_pod)"; then
    POD_BIN="$pod_bin"
    return 0
  fi
  return 1
}

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

trim_string() {
  printf '%s' "$1" | trim
}

load_root_env_file() {
  local file="$1"
  [[ -z "$file" || ! -f "$file" ]] && return 0
  log "Loading env file: $file"
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_string "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == export\ * ]]; then
      line="$(trim_string "${line#export}")"
    fi
    [[ "$line" != *=* ]] && continue
    key="$(trim_string "${line%%=*}")"
    value="$(trim_string "${line#*=}")"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value#\"}"
      value="${value%\"}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value#\'}"
      value="${value%\'}"
    fi
    export "$key=$value"
  done < "$file"
}

resolve_default_env_file() {
  local candidates=(
    "$REPO_ROOT/.env"
    "$BASE_DIR/.env"
    "$REPO_ROOT/.env.example"
    "$BASE_DIR/.env.example"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' "$REPO_ROOT/.env"
  return 1
}

ensure_app_dirs() {
  local app_root="$1"
  mkdir -p "$app_root/images" "$app_root/scripts"
}

ensure_app_deps() {
  local deps="$1"
  [[ -z "${deps:-}" ]] && return 0

  local dep_list=()
  IFS=',' read -r -a dep_list <<< "$deps"
  local dep
  for dep in "${dep_list[@]}"; do
    dep="$(trim_string "$dep")"
    [[ -z "$dep" ]] && continue
    if command -v "$dep" >/dev/null 2>&1; then
      continue
    fi
    if [[ "$AUTO_INSTALL_DEPS" != "true" ]]; then
      log "Dependency missing: $dep (use --install-deps to auto-install)."
      continue
    fi
    local pkg
    pkg="$(brew_pkg_for_dep "$dep")"
    if ! ensure_brew_package "$pkg"; then
      log "Failed to install dependency: $dep"
    fi
    if [[ "$dep" == "clang-format" && ! -x "$(command -v clang-format)" ]]; then
      if ensure_brew_package "llvm"; then
        if command -v brew >/dev/null 2>&1; then
          local llvm_bin
          llvm_bin="$(brew --prefix llvm 2>/dev/null)/bin"
          if [[ -d "$llvm_bin" ]]; then
            export PATH="$llvm_bin:$PATH"
          fi
        fi
      fi
    fi
  done
}

parse_app_line() {
  local line="$1"
  local name="" repo="" ios_dir="" scheme="" type="" prebuild="" pod_mode="" pod_args="" xcodebuild_args="" deps="" deploy_target=""
  local parts=()

  if [[ "$line" == *"|"* ]]; then
    IFS='|' read -r -a parts <<< "$line"
    if [[ ${#parts[@]} -ge 2 ]]; then
      name="$(trim_string "${parts[0]}")"
      repo="$(trim_string "${parts[1]}")"
      local field key val
      local i
      for ((i=2; i<${#parts[@]}; i++)); do
        field="$(trim_string "${parts[$i]}")"
        [[ -z "$field" ]] && continue
        if [[ "$field" == *=* ]]; then
          key="$(trim_string "${field%%=*}")"
          val="$(trim_string "${field#*=}")"
          key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
          case "$key" in
            ios_dir|iosdir|ios) ios_dir="$val" ;;
            scheme) scheme="$val" ;;
            type) type="$val" ;;
            prebuild) prebuild="$val" ;;
            pod|pod_mode|podmode) pod_mode="$val" ;;
            pod_args|podargs) pod_args="$val" ;;
            build_args|xcodebuild_args|xcodebuild) xcodebuild_args="$val" ;;
            deps|dependencies) deps="$val" ;;
            deploy|deployment_target|min_ios) deploy_target="$val" ;;
          esac
        fi
      done
    else
      repo="$(trim_string "$line")"
    fi
  elif [[ "$line" == *":"* && "$line" != *"://"* && "$line" != git@*:* ]]; then
    name="$(trim_string "${line%%:*}")"
    repo="$(trim_string "${line#*:}")"
  else
    repo="$(trim_string "$line")"
  fi

  if [[ -z "$repo" ]]; then
    log "Skipping invalid entry: $line"
    return 1
  fi

  if [[ -z "$name" ]]; then
    name="$(basename "$repo")"
    name="${name%.git}"
  fi

  APP_SPECS+=("$name|$repo|$ios_dir|$scheme|$type|$prebuild|$pod_mode|$pod_args|$xcodebuild_args|$deps|$deploy_target")
}

read_apps() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Repo list not found: $file"
    exit 1
  fi

  APP_SPECS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    local trimmed
    trimmed="$(trim_string "$line")"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    parse_app_line "$trimmed" || true
  done < "$file"
  if [[ ${#APP_SPECS[@]} -eq 0 ]]; then
    echo "Repo list is empty: $file"
    exit 1
  fi
}

select_simulator_udid() {
  local device_name="$1"
  local os_req="$2"

  local simctl_json
  simctl_json="$(xcrun simctl list devices available -j 2>/dev/null || true)"
  if [[ -z "${simctl_json:-}" ]]; then
    simctl_json="$(xcrun simctl list devices -j 2>/dev/null || true)"
  fi
  if [[ -z "${simctl_json:-}" ]]; then
    return 0
  fi
  local trimmed_json
  trimmed_json="$(printf '%s' "$simctl_json" | sed -e 's/^[[:space:]]*//')"
  if [[ "${trimmed_json:0:1}" != "{" ]]; then
    log "simctl returned an error instead of JSON; CoreSimulatorService may not be running."
    printf '%s\n' "$trimmed_json" >&2
    log "Try: open -a Simulator, or run 'xcrun simctl list devices available'."
    return 0
  fi

  local py
  py=$(cat <<'PY'
import json
import re
import sys

device_name = sys.argv[1].strip()
os_req = sys.argv[2].strip() or "latest"

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def runtime_version(runtime_id):
    m = re.search(r'iOS-([0-9-]+)$', runtime_id)
    if not m:
        return None
    parts = m.group(1).split('-')
    try:
        return tuple(int(p) for p in parts)
    except ValueError:
        return None

devices = data.get("devices", {})

candidates = []
for runtime_id, devs in devices.items():
    version = runtime_version(runtime_id)
    if not version:
        continue
    version_str = ".".join(str(p) for p in version)
    if os_req != "latest" and not version_str.startswith(os_req):
        continue
    for d in devs:
        if not d.get("isAvailable", True):
            continue
        name = d.get("name", "")
        udid = d.get("udid", "")
        if device_name and name != device_name:
            continue
        candidates.append((version, name, udid))

if not candidates:
    sys.exit(0)

def device_rank(name):
    return 0 if name.startswith("iPhone") else 1

def version_key(version):
    padded = version + (0, 0, 0)
    return tuple(-v for v in padded[:3])

best = sorted(
    candidates,
    key=lambda c: (version_key(c[0]), device_rank(c[1]), c[1])
)[0]

print(best[2])
PY
)
  printf '%s' "$simctl_json" | python3 -c "$py" "$device_name" "$os_req"
}

populate_contacts() {
  local udid="$1"
  local vcf_file="$BASE_DIR/../shared/contacts.vcf"
  local importer_dir="$BASE_DIR/ContactImporter"
  local app_bundle="$importer_dir/ContactImporter.app"
  local bundle_id="com.benchmark.ContactImporter"

  if [[ ! -f "$vcf_file" ]]; then
    log "No contacts.vcf found at $vcf_file; skipping contact population."
    return 0
  fi

  log "Populating simulator contacts from $vcf_file"

  # Build the ContactImporter app if needed
  if [[ ! -x "$app_bundle/ContactImporter" ]] || [[ "$importer_dir/main.swift" -nt "$app_bundle/ContactImporter" ]]; then
    log "Building ContactImporter..."
    mkdir -p "$app_bundle"
    xcrun -sdk iphonesimulator swiftc \
      -parse-as-library \
      -target arm64-apple-ios18.0-simulator \
      -o "$app_bundle/ContactImporter" \
      "$importer_dir/main.swift" 2>&1
    cp "$importer_dir/Info.plist" "$app_bundle/Info.plist"
  fi

  # Install the importer app
  xcrun simctl install "$udid" "$app_bundle" 2>&1

  # Grant contacts permission so the app can import without prompting
  xcrun simctl privacy "$udid" grant contacts "$bundle_id" 2>&1

  # Copy VCF into the app's Documents directory
  local app_container
  app_container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data 2>/dev/null || true)"
  if [[ -n "$app_container" ]]; then
    mkdir -p "$app_container/Documents"
    cp "$vcf_file" "$app_container/Documents/contacts.vcf"
  fi

  # Launch the importer and give it time to finish
  xcrun simctl launch "$udid" "$bundle_id" 2>&1
  sleep 3

  # Clean up: terminate and uninstall the helper app
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true

  log "Contacts populated successfully."
}

disable_cloud_services() {
  local udid="$1"
  log "Disabling iCloud / cloud sync..."

  # Mark device setup as complete to suppress first-run / iCloud sign-in dialogs
  xcrun simctl spawn "$udid" defaults write com.apple.purplebuddy SetupDone -bool true 2>/dev/null || true

  # Disable Siri & Assistant (avoids cloud-related prompts)
  xcrun simctl spawn "$udid" defaults write com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null || true

  # Refuse iCloud setup
  xcrun simctl spawn "$udid" defaults write com.apple.Preferences CloudSettingsRefused -bool true 2>/dev/null || true

  # Disable iCloud Drive
  xcrun simctl spawn "$udid" defaults write com.apple.CloudDocs CloudDocsServiceEnabled -bool false 2>/dev/null || true

  # Disable iCloud Keychain sync
  xcrun simctl spawn "$udid" defaults write com.apple.security.cloudkeychainproxy CloudKeychainProxyEnabled -bool false 2>/dev/null || true

  # Clear any MobileMe / iCloud accounts to prevent sync
  xcrun simctl spawn "$udid" defaults write MobileMeAccounts Accounts -array 2>/dev/null || true

  # Disable iCloud backup prompts
  xcrun simctl spawn "$udid" defaults write com.apple.cloud.quota CloudBackupEnabled -bool false 2>/dev/null || true
}

remove_home_screen_widgets() {
  local udid="$1"
  log "Removing default widgets from home screen..."

  local icon_state="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/SpringBoard/IconState.plist"
  if [[ ! -f "$icon_state" ]]; then
    log "IconState.plist not found; skipping widget removal."
    return 0
  fi

  python3 - "$icon_state" <<'PYEOF' || true
import plistlib, sys, os

path = sys.argv[1]
try:
    with open(path, "rb") as f:
        data = plistlib.load(f)
except Exception:
    sys.exit(0)

# Remove standalone widgets and smart stacks from home screen pages
new_icon_lists = []
for page in data.get("iconLists", []):
    new_page = []
    for item in page:
        if isinstance(item, dict):
            # Skip standalone widgets
            if item.get("elementType") == "widget":
                continue
            # Skip smart stacks (contain nested widget elements)
            if "elements" in item:
                continue
        new_page.append(item)
    new_icon_lists.append(new_page)
data["iconLists"] = new_icon_lists

# Clear today view / lock screen widgets
if "today" in data:
    data["today"] = []

with open(path, "wb") as f:
    plistlib.dump(data, f)
PYEOF
}

grant_all_permissions() {
  local udid="$1"
  log "Granting all privacy permissions..."

  # Native Apple apps and their widget extensions
  local apple_apps=(
    com.apple.Maps
    com.apple.Maps.GeneralMapsWidget
    com.apple.mobilecal
    com.apple.mobilecal.CalendarWidgetExtension
    com.apple.reminders
    com.apple.reminders.WidgetExtension
    com.apple.MobileAddressBook
    com.apple.mobilesafari
    com.apple.mobilesafari.SafariWidgetExtension
    com.apple.Preferences
    com.apple.DocumentsApp
    com.apple.mobilemail
    com.apple.mobilenotes
    com.apple.weather
    com.apple.camera
    com.apple.photos
    com.apple.mobileslideshow.PhotosReliveWidget
    com.apple.Health
    com.apple.Fitness.FitnessWidget
    com.apple.Passbook
    com.apple.findmy
    com.apple.Home
  )

  for bid in "${apple_apps[@]}"; do
    xcrun simctl privacy "$udid" grant all "$bid" 2>/dev/null || true
  done

  # Set a default simulated location
  xcrun simctl location "$udid" set -- 37.3349 -122.0090 2>/dev/null || true

  # Enable location services globally
  xcrun simctl spawn "$udid" defaults write com.apple.locationd LocationServicesEnabled -int 1 2>/dev/null || true

  # Disable iCloud / cloud sync to prevent sync popups and ensure benchmark reproducibility
  disable_cloud_services "$udid"

  # Remove default widgets (Maps, etc.) from the home screen — the widget location
  # popup is a SpringBoard-level prompt that cannot be pre-authorized via any
  # permission grant mechanism (TCC, applesimutils, locationd, etc.).
  remove_home_screen_widgets "$udid"

  # Pre-authorize notification permissions via applesimutils
  # (modifies BulletinBoard/VersionedSectionInfo.plist — the real notification authority)
  # NOTE: Only grant notifications here — DO NOT use location=always, it overwrites
  # locationd clients.plist and breaks simctl location.
  log "Using applesimutils to pre-authorize notifications..."
  local notify_bids=(
    com.apple.mobilecal com.apple.Health com.apple.reminders
    com.apple.mobilemail com.apple.mobilenotes com.apple.weather
    com.apple.Maps com.apple.Passbook com.apple.mobilesafari
    com.apple.findmy com.apple.Home com.apple.Fitness
    com.apple.camera com.apple.photos
  )
  for bid in "${notify_bids[@]}"; do
    applesimutils --byId "$udid" --bundle "$bid" --setPermissions "notifications=YES" 2>/dev/null || true
  done

  # Restart key daemons so they re-read updated databases:
  #   tccd      → TCC.db (privacy permissions)
  #   usernoted → BulletinBoard (notification authorization)
  #   SpringBoard → home screen layout, widget loading
  # NOTE: Do NOT kill locationd — it loses the simulated location set earlier.
  log "Restarting system daemons to apply permissions..."
  xcrun simctl spawn "$udid" killall -9 tccd 2>/dev/null || true
  xcrun simctl spawn "$udid" killall -9 usernoted 2>/dev/null || true
  sleep 1
  xcrun simctl spawn "$udid" killall -9 SpringBoard 2>/dev/null || true
  sleep 5

  # Re-set simulated location after daemon restarts
  xcrun simctl location "$udid" set -- 37.3349 -122.0090 2>/dev/null || true

  # Auto-dismiss any remaining system alerts (catch-all)
  dismiss_simulator_alerts

  log "All privacy permissions granted."
}

# Auto-dismiss permission alerts in the Simulator via AppleScript.
# Clicks "Allow" / "OK" on any system alert that appears.
dismiss_simulator_alerts() {
  if [[ "${HEADLESS_DEDICATED_SIMULATOR:-false}" == "true" ]]; then
    log "Skipping global Simulator-window AppleScript; use UDID-scoped device control."
    return 0
  fi
  log "Dismissing any remaining permission alerts..."
  osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "System Events"
    tell process "Simulator"
        repeat 10 times
            try
                set frontWin to front window
                -- Try clicking allow/OK buttons in various alert structures
                repeat with btn in (buttons of sheets of frontWin)
                    set btnName to name of btn
                    if btnName is "Allow" or btnName is "Allow While Using App" or btnName is "OK" then
                        click btn
                    end if
                end repeat
            end try
            try
                repeat with btn in (buttons of dialogs of frontWin)
                    set btnName to name of btn
                    if btnName is "Allow" or btnName is "Allow While Using App" or btnName is "OK" then
                        click btn
                    end if
                end repeat
            end try
            delay 0.5
        end repeat
    end tell
end tell
APPLESCRIPT
}

boot_simulator() {
  local udid
  # Fall back to DEVICE_NAME / PHONE_DEVICE_NAME from .env if SIM_DEVICE_NAME unset.
  # Lets a fresh `cp .env.example .env` user run bootstrap without further edits.
  : "${SIM_DEVICE_NAME:=${DEVICE_NAME:-${PHONE_DEVICE_NAME:-}}}"
  udid="$(select_simulator_udid "$SIM_DEVICE_NAME" "$SIM_OS" || true)"
  if [[ -z "${udid:-}" ]]; then
    log "Could not find a matching simulator."
    log "Device: ${SIM_DEVICE_NAME:-<auto>}"
    log "OS:     $SIM_OS"
    log "Tip: run 'xcrun simctl list devices available' to see installed runtimes."
    exit 1
  fi

  log "Booting simulator: $udid"
  if [[ "$CLEAR_SIMULATOR" == "true" ]]; then
    log "Erasing simulator state: $udid"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl erase "$udid" >/dev/null 2>&1 || true
  fi

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  if [[ "$OPEN_SIMULATOR" == "true" ]]; then
    open -a Simulator >/dev/null 2>&1 || true
  fi
  xcrun simctl bootstatus "$udid" -b >&2

  grant_all_permissions "$udid"

  echo "$udid"
}

find_xcode_container() {
  local ws
  # First try to find workspace in current directory
  ws="$(find . -maxdepth 1 -name "*.xcworkspace" | head -n 1 || true)"
  if [[ -n "$ws" ]]; then
    echo "workspace:$ws"
    return 0
  fi

  # Then search deeper, excluding common dependency folders
  ws="$(find . -maxdepth 4 -name "*.xcworkspace" \
    -not -path "*/Pods/*" -not -path "*/.git/*" \
    -not -path "*.xcodeproj/*" -not -path "*/Dependencies/*" \
    -not -path "*/.swiftpm/*" \
    -not -path "*/Carthage/*" | head -n 1 || true)"
  if [[ -n "$ws" ]]; then
    echo "workspace:$ws"
    return 0
  fi

  # Try to find project in current directory
  local proj
  proj="$(find . -maxdepth 1 -name "*.xcodeproj" | head -n 1 || true)"
  if [[ -n "$proj" ]]; then
    echo "project:$proj"
    return 0
  fi

  # Then search deeper
  proj="$(find . -maxdepth 4 -name "*.xcodeproj" \
    -not -path "*/Pods/*" -not -path "*/.git/*" \
    -not -path "*/Dependencies/*" -not -path "*/Carthage/*" \
    -not -path "*/.swiftpm/*" | head -n 1 || true)"
  if [[ -n "$proj" ]]; then
    echo "project:$proj"
    return 0
  fi

  return 1
}

pick_scheme() {
  local kind="$1"
  local container="$2"
  shift 2
  local preferred=("$@")
  local schemes

  schemes="$(xcodebuild -list "-$kind" "$container" 2>/dev/null | awk '
    $0 ~ /^[[:space:]]*Schemes:/ { in_schemes=1; next }
    in_schemes && NF==0 { exit }
    in_schemes { gsub(/^[[:space:]]+/, "", $0); if (length($0)) print $0 }
  ' || true)"

  if [[ -z "${schemes:-}" ]]; then
    return 1
  fi

  local scheme
  if [[ ${#preferred[@]} -gt 0 ]]; then
    local pref
    for pref in "${preferred[@]}"; do
      scheme="$(printf '%s\n' "$schemes" | grep -Fx "$pref" | head -n 1 || true)"
      if [[ -n "${scheme:-}" ]]; then
        echo "$scheme"
        return 0
      fi
    done
    for pref in "${preferred[@]}"; do
      scheme="$(printf '%s\n' "$schemes" | grep -Fxi "$pref" | head -n 1 || true)"
      if [[ -n "${scheme:-}" ]]; then
        echo "$scheme"
        return 0
      fi
    done
  fi

  scheme="$(printf '%s\n' "$schemes" | grep -vE '(Tests|UITests)$' | head -n 1 || true)"
  if [[ -z "${scheme:-}" ]]; then
    scheme="$(printf '%s\n' "$schemes" | head -n 1 || true)"
  fi
  echo "$scheme"
}

normalize_type() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_nativescript_repo() {
  local repo_dir="$1"
  [[ -f "$repo_dir/nativescript.config.js" || -f "$repo_dir/nativescript.config.ts" || -d "$repo_dir/App_Resources" ]]
}

is_react_native_repo() {
  local repo_dir="$1"
  [[ -f "$repo_dir/package.json" && -d "$repo_dir/ios" ]]
}

is_expo_repo() {
  local repo_dir="$1"
  [[ -f "$repo_dir/package.json" && ( -f "$repo_dir/app.config.js" || -f "$repo_dir/app.json" ) && ! -d "$repo_dir/ios" ]]
}

resolve_work_dir() {
  local repo_dir="$1"
  local ios_dir="$2"
  local app_type="$3"

  if [[ -n "$ios_dir" ]]; then
    echo "$repo_dir/$ios_dir"
    return 0
  fi

  if [[ ( "$app_type" == "react-native" || "$app_type" == "expo" ) && -d "$repo_dir/ios" ]]; then
    echo "$repo_dir/ios"
    return 0
  fi

  if [[ -d "$repo_dir/ios" ]]; then
    if [[ -n "$(find "$repo_dir/ios" -maxdepth 2 \( -name "*.xcworkspace" -o -name "*.xcodeproj" -o -name "Podfile" \) -print -quit)" ]]; then
      echo "$repo_dir/ios"
      return 0
    fi
  fi

  echo "$repo_dir"
}

ensure_node() {
  if command -v npm >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$AUTO_INSTALL_DEPS" == "true" ]] && command -v brew >/dev/null 2>&1; then
    log "Installing Node via Homebrew..."
    brew install node || true
  fi
  command -v npm >/dev/null 2>&1
}

ensure_corepack_yarn() {
  local version="$1"
  if ! command -v corepack >/dev/null 2>&1; then
    return 1
  fi
  corepack enable >/dev/null 2>&1 || true
  if [[ -n "$version" ]]; then
    corepack prepare "yarn@$version" --activate >/dev/null 2>&1 || true
  fi
  return 0
}

get_package_manager() {
  local repo_dir="$1"
  if [[ ! -f "$repo_dir/package.json" ]]; then
    return 0
  fi
  python3 - "$repo_dir/package.json" <<'PY'
import json
import sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    pm = data.get("packageManager", "")
    if isinstance(pm, str):
        print(pm)
except Exception:
    pass
PY
}

ensure_yarn() {
  if command -v yarn >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$AUTO_INSTALL_DEPS" == "true" ]] && command -v brew >/dev/null 2>&1; then
    log "Installing Yarn via Homebrew..."
    brew install yarn || true
  fi
  command -v yarn >/dev/null 2>&1
}

ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$AUTO_INSTALL_DEPS" == "true" ]] && command -v brew >/dev/null 2>&1; then
    log "Installing pnpm via Homebrew..."
    brew install pnpm || true
  fi
  command -v pnpm >/dev/null 2>&1
}

pick_node_manager() {
  local repo_dir="$1"
  local pkg_manager=""
  pkg_manager="$(get_package_manager "$repo_dir" || true)"
  if [[ "$pkg_manager" == yarn@* ]]; then
    local yarn_version="${pkg_manager#yarn@}"
    ensure_node || return 1
    ensure_corepack_yarn "$yarn_version" || true
    if command -v yarn >/dev/null 2>&1; then
      echo "yarn"
      return 0
    fi
  fi

  if [[ -f "$repo_dir/yarn.lock" ]]; then
    if ensure_yarn; then
      echo "yarn"
      return 0
    fi
  fi

  if [[ -f "$repo_dir/pnpm-lock.yaml" ]]; then
    if ensure_pnpm; then
      echo "pnpm"
      return 0
    fi
  fi

  if [[ -f "$repo_dir/package-lock.json" ]]; then
    if ensure_node; then
      echo "npm"
      return 0
    fi
  fi

  if ensure_node; then
    echo "npm"
    return 0
  fi
  return 1
}

run_node_install_if_needed() {
  local repo_dir="$1"
  if [[ "$NODE_INSTALL" == "never" ]]; then
    return 0
  fi
  if [[ ! -f "$repo_dir/package.json" ]]; then
    return 0
  fi
  if [[ "$NODE_INSTALL" == "auto" && -d "$repo_dir/node_modules" ]]; then
    log "node_modules present; skipping JS dependency install."
    return 0
  fi

  local manager
  manager="$(pick_node_manager "$repo_dir" || true)"
  if [[ -z "${manager:-}" ]]; then
    log "Node package manager not available; skipping JS dependencies."
    return 0
  fi

  log "Installing JS dependencies with $manager..."
  case "$manager" in
    yarn)
      if ! (cd "$repo_dir" && yarn install); then
        return 1
      fi
      ;;
    pnpm)
      if ! (cd "$repo_dir" && pnpm install); then
        return 1
      fi
      ;;
    npm)
      if ! (cd "$repo_dir" && npm install); then
        return 1
      fi
      ;;
  esac
  return 0
}

ensure_carthage() {
  if command -v carthage >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$AUTO_INSTALL_DEPS" == "true" ]] && command -v brew >/dev/null 2>&1; then
    log "Installing Carthage via Homebrew..."
    brew install carthage || true
  fi
  command -v carthage >/dev/null 2>&1
}

run_carthage_if_needed() {
  local repo_dir="$1"
  if [[ -f "$repo_dir/Cartfile" || -f "$repo_dir/Cartfile.resolved" ]]; then
    if [[ -d "$repo_dir/Carthage/Build" ]]; then
      log "Carthage build artifacts found; skipping carthage bootstrap."
      return 0
    fi
    if ensure_carthage; then
      log "Running carthage bootstrap..."
      (cd "$repo_dir" && carthage bootstrap --platform iOS --use-xcframeworks) || true
    else
      log "Carthage required but not installed; skipping carthage bootstrap."
    fi
  fi
}

run_git_submodules_if_needed() {
  local repo_dir="$1"
  if [[ -f "$repo_dir/.gitmodules" ]]; then
    log "Updating git submodules..."
    git -C "$repo_dir" submodule update --init --recursive || true
  fi
}

run_git_lfs_if_needed() {
  local repo_dir="$1"
  if [[ -f "$repo_dir/.gitattributes" ]] && grep -q "filter=lfs" "$repo_dir/.gitattributes"; then
    if git lfs version >/dev/null 2>&1; then
      log "Fetching Git LFS files..."
      git -C "$repo_dir" lfs pull || true
    else
      log "Git LFS pointers detected but git-lfs not installed."
    fi
  fi
}

patch_macos_sdk_prefix() {
  local script="$1"
  [[ ! -f "$script" ]] && return 0
  if ! grep -q "macosx10\\.15" "$script"; then
    return 0
  fi
  log "Patching macOS SDK prefix in $script"
  perl -0pi -e 's/macosx10\\.15/macosx/g' "$script"
}

patch_repo_build_scripts() {
  local repo_dir="$1"
  local script
  for script in "$repo_dir"/Submodules/*/scripts/build-libs.sh; do
    patch_macos_sdk_prefix "$script"
  done
}

update_deployment_target() {
  local work_dir="$1"
  local target="$2"
  [[ -z "${target:-}" ]] && return 0

  local pbxproj
  pbxproj="$(find "$work_dir" -maxdepth 3 -path "*.xcodeproj/*" -name "project.pbxproj" | head -n 1 || true)"
  if [[ -z "${pbxproj:-}" ]]; then
    log "Deployment target requested but no project.pbxproj found."
    return 0
  fi
  log "Setting IPHONEOS_DEPLOYMENT_TARGET to $target"
  perl -0pi -e "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = $target;/g" "$pbxproj"
}

run_prebuild_steps() {
  local repo_dir="$1"
  local steps="$2"
  [[ -z "${steps:-}" ]] && return 0

  local cmds=()
  IFS=';' read -r -a cmds <<< "$steps"
  local cmd
  for cmd in "${cmds[@]}"; do
    cmd="$(trim_string "$cmd")"
    [[ -z "$cmd" ]] && continue
    log "Prebuild: $cmd"
    if ! (cd "$repo_dir" && eval "$cmd"); then
      log "Prebuild failed: $cmd"
      return 1
    fi
  done
}

load_env_file() {
  local repo_dir="$1"
  local env_file="${2:-.env}"
  if [[ -f "$repo_dir/$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    . "$repo_dir/$env_file"
    set +a
    return 0
  fi
  return 1
}

run_pod_install_if_needed() {
  local work_dir="$1"
  local pod_mode="${2:-}"
  local pod_args="${3:-}"
  if [[ ! -f "$work_dir/Podfile" ]]; then
    return 0
  fi

  local needs_install="false"
  pod_mode="$(normalize_type "$pod_mode")"
  if [[ "$pod_mode" == "always" || "$pod_mode" == "force" ]]; then
    needs_install="true"
  elif [[ "$pod_mode" == "repo-update" ]]; then
    needs_install="true"
    pod_args="--repo-update ${pod_args:-}"
  fi

  if [[ ! -d "$work_dir/Pods" || ! -f "$work_dir/Podfile.lock" || ! -f "$work_dir/Pods/Manifest.lock" ]]; then
    needs_install="true"
  elif ! cmp -s "$work_dir/Podfile.lock" "$work_dir/Pods/Manifest.lock"; then
    needs_install="true"
  fi

  if [[ "$needs_install" != "true" ]]; then
    log "Pods up to date; skipping pod install."
    return 0
  fi

  if [[ -f "$work_dir/Gemfile" ]] && command -v bundle >/dev/null 2>&1; then
    if ! (cd "$work_dir" && bundle check >/dev/null 2>&1); then
      if [[ "$AUTO_INSTALL_DEPS" == "true" ]]; then
        log "Installing Ruby gems via bundler..."
        (cd "$work_dir" && bundle install) || true
      else
        log "Gemfile found but gems missing; run bundle install or use --install-deps."
      fi
    fi
    if (cd "$work_dir" && bundle check >/dev/null 2>&1); then
      log "Running bundle exec pod install..."
      (cd "$work_dir" && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bundle exec pod install ${pod_args:-}) || true
      return 0
    fi
  fi

  if ensure_cocoapods; then
    log "Running pod install..."
    (cd "$work_dir" && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$POD_BIN" install ${pod_args:-}) || true
  else
    log "Podfile found but CocoaPods not installed; skipping pod install."
    log "Install with: brew install cocoapods (or rerun with --install-deps)."
  fi
}

run_nativescript_build() {
  local app_name="$1"
  local repo_dir="$2"
  local udid="$3"
  local prebuild="$4"

  run_git_submodules_if_needed "$repo_dir"
  run_git_lfs_if_needed "$repo_dir"
  patch_repo_build_scripts "$repo_dir"
  if ! run_prebuild_steps "$repo_dir" "$prebuild"; then
    log "Prebuild failed for $app_name; skipping."
    return 1
  fi
  if ! run_node_install_if_needed "$repo_dir"; then
    log "Node dependency install failed for $app_name; skipping."
    return 1
  fi
  load_env_file "$repo_dir" ".env" || true

  log "Building NativeScript app: $app_name"
  if ! (cd "$repo_dir" && npx --yes @nativescript/cli@latest build ios --env.devlog); then
    log "NativeScript build failed for $app_name; skipping."
    return 1
  fi

  local app_path
  app_path="$(find "$repo_dir/platforms/ios/build" -maxdepth 4 -type d -name "*.app" \
    -path "*-iphonesimulator*" \
    -not -name "*Tests*.app" \
    -not -name "*UITests*.app" \
    | head -n 1 || true)"
  if [[ -z "${app_path:-}" ]]; then
    app_path="$(find "$repo_dir/platforms/ios/build" -maxdepth 4 -type d -name "*.app" \
      -not -name "*Tests*.app" \
      -not -name "*UITests*.app" \
      | head -n 1 || true)"
  fi

  if [[ -z "${app_path:-}" ]]; then
    log "Could not locate built .app for $app_name; skipping install."
    return 1
  fi

  local plist="$app_path/Info.plist"
  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c "Print:CFBundleIdentifier" "$plist" 2>/dev/null || true)"

  log "Installing: $app_path"
  xcrun simctl install "$udid" "$app_path"
  record_manifest_entry "$app_name" "${bundle_id:-}" "$app_path" "$repo_dir"

  if [[ -n "${bundle_id:-}" ]]; then
    log "Launching: $bundle_id"
    xcrun simctl launch "$udid" "$bundle_id" >/dev/null 2>&1 || true
  fi

  return 0
}

build_install_launch() {
  local app_name="$1"
  local repo_dir="$2"
  local udid="$3"
  local ios_dir="$4"
  local scheme_override="$5"
  local app_type="$6"
  local prebuild="$7"
  local pod_mode="$8"
  local pod_args="$9"
  local xcodebuild_args="${10:-}"
  local deploy_target="${11:-}"

  run_git_submodules_if_needed "$repo_dir"
  run_git_lfs_if_needed "$repo_dir"
  patch_repo_build_scripts "$repo_dir"

  if [[ "$app_type" == "react-native" || "$app_type" == "expo" ]]; then
    if ! run_node_install_if_needed "$repo_dir"; then
      log "Node dependency install failed for $app_name; skipping."
      return 1
    fi
  fi

  if ! run_prebuild_steps "$repo_dir" "$prebuild"; then
    log "Prebuild failed for $app_name; skipping."
    return 1
  fi

  local work_dir
  work_dir="$(resolve_work_dir "$repo_dir" "$ios_dir" "$app_type")"

  update_deployment_target "$work_dir" "$deploy_target"

  run_carthage_if_needed "$repo_dir"
  run_pod_install_if_needed "$work_dir" "$pod_mode" "$pod_args"

  if ! pushd "$work_dir" >/dev/null 2>&1; then
    log "Failed to access work directory: $work_dir; skipping."
    return 1
  fi

  local container
  container="$(find_xcode_container || true)"
  if [[ -z "${container:-}" ]]; then
    log "No .xcworkspace or .xcodeproj found in $work_dir; skipping."
    popd >/dev/null 2>&1 || true
    return 1
  fi

  local kind="${container%%:*}"
  local path="${container#*:}"
  local base_name
  if [[ "$kind" == "workspace" ]]; then
    base_name="$(basename "$path" .xcworkspace)"
  else
    base_name="$(basename "$path" .xcodeproj)"
  fi
  local repo_base
  repo_base="$(basename "$repo_dir")"
  local scheme
  if [[ -n "${scheme_override:-}" ]]; then
    scheme="$(pick_scheme "$kind" "$path" "$scheme_override" "$base_name" "$repo_base" || true)"
  else
    scheme="$(pick_scheme "$kind" "$path" "$base_name" "$repo_base" || true)"
  fi
  if [[ -z "${scheme:-}" && "$kind" == "workspace" ]]; then
    local proj_fallback
    proj_fallback="$(find . -maxdepth 4 -name "*.xcodeproj" \
      -not -path "*/Pods/*" -not -path "*/.git/*" \
      | head -n 1 || true)"
    if [[ -n "$proj_fallback" ]]; then
      kind="project"
      path="$proj_fallback"
      base_name="$(basename "$path" .xcodeproj)"
      if [[ -n "${scheme_override:-}" ]]; then
        scheme="$(pick_scheme "$kind" "$path" "$scheme_override" "$base_name" "$repo_base" || true)"
      else
        scheme="$(pick_scheme "$kind" "$path" "$base_name" "$repo_base" || true)"
      fi
    fi
  fi
  if [[ -z "${scheme:-}" ]]; then
    log "No scheme found for $path; skipping."
    popd >/dev/null 2>&1 || true
    return 1
  fi

  log "App:     $app_name"
  log "Project: $path"
  log "Scheme:  $scheme"

  if [[ "$OPEN_IN_XCODE" == "true" ]]; then
    open "$path" >/dev/null 2>&1 || true
  fi

  local safe_name
  if [[ -n "${app_name:-}" ]]; then
    safe_name="$(printf '%s' "$app_name" | tr ' /' '__')"
  else
    safe_name="$(basename "$repo_dir" | tr ' /' '__')"
  fi
  local dd="$DERIVED_DIR/$safe_name"
  mkdir -p "$dd"

  log "Building for simulator..."
  local build_args=()
  if [[ -n "${xcodebuild_args:-}" ]]; then
    read -r -a build_args <<< "$xcodebuild_args"
  fi
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    build_args+=(OPENAI_API_KEY="$OPENAI_API_KEY")
  fi
  if command -v xcpretty >/dev/null 2>&1; then
    if (( ${#build_args[@]} )); then
      if ! xcodebuild "-$kind" "$path" \
        -scheme "$scheme" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$dd" \
        -configuration Debug \
        "${build_args[@]}" \
        build | xcpretty; then
        log "Build failed for $app_name; skipping."
        popd >/dev/null 2>&1 || true
        return 1
      fi
    else
      if ! xcodebuild "-$kind" "$path" \
        -scheme "$scheme" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$dd" \
        -configuration Debug \
        build | xcpretty; then
        log "Build failed for $app_name; skipping."
        popd >/dev/null 2>&1 || true
        return 1
      fi
    fi
  else
    if (( ${#build_args[@]} )); then
      if ! xcodebuild "-$kind" "$path" \
        -scheme "$scheme" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$dd" \
        -configuration Debug \
        "${build_args[@]}" \
        build; then
        log "Build failed for $app_name; skipping."
        popd >/dev/null 2>&1 || true
        return 1
      fi
    else
      if ! xcodebuild "-$kind" "$path" \
        -scheme "$scheme" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$dd" \
        -configuration Debug \
        build; then
        log "Build failed for $app_name; skipping."
        popd >/dev/null 2>&1 || true
        return 1
      fi
    fi
  fi

  local app_path
  local products_dir="$dd/Build/Products/Debug-iphonesimulator"
  if [[ -d "$products_dir" ]]; then
    local candidate
    for candidate in "$scheme" "$base_name" "$app_name"; do
      if [[ -n "${candidate:-}" && -d "$products_dir/$candidate.app" ]]; then
        app_path="$products_dir/$candidate.app"
        break
      fi
    done
    if [[ -z "${app_path:-}" ]]; then
      app_path="$(find "$products_dir" -maxdepth 1 -type d -name "*.app" \
        -not -name "*Tests*.app" \
        -not -name "*UITests*.app" \
        | head -n 1 || true)"
    fi
  fi
  if [[ -z "${app_path:-}" ]]; then
    app_path="$(find "$dd/Build/Products" -maxdepth 4 -type d -name "*.app" \
      -path "*-iphonesimulator*" \
      -not -name "*Tests*.app" \
      -not -name "*UITests*.app" \
      | head -n 1 || true)"
  fi
  if [[ -z "${app_path:-}" ]]; then
    app_path="$(find "$dd/Build/Products" -maxdepth 4 -type d -name "*.app" \
      -not -name "*Tests*.app" \
      -not -name "*UITests*.app" \
      | head -n 1 || true)"
  fi

  if [[ -z "${app_path:-}" ]]; then
    log "Could not locate built .app in $dd/Build/Products; skipping install."
    popd >/dev/null 2>&1 || true
    return 1
  fi

  local plist="$app_path/Info.plist"
  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c "Print:CFBundleIdentifier" "$plist" 2>/dev/null || true)"

  log "Installing: $app_path"
  xcrun simctl install "$udid" "$app_path"
  record_manifest_entry "$app_name" "${bundle_id:-}" "$app_path" "$repo_dir"

  if [[ -n "${bundle_id:-}" ]]; then
    log "Launching: $bundle_id"
    xcrun simctl launch "$udid" "$bundle_id" >/dev/null 2>&1 || true
  fi

  log "Done: $app_name"
  popd >/dev/null 2>&1 || true
}

clone_or_update() {
  local spec="$1"
  local name_override="${2:-}"

  local local_spec="$spec"
  if [[ "$spec" == ./* || "$spec" == ../* ]]; then
    local_spec="$BASE_DIR/$spec"
  fi

  if [[ "$local_spec" == /* ]]; then
    if [[ -d "$local_spec" ]]; then
      local resolved
      resolved="$(cd "$local_spec" && pwd)"
      echo "$resolved"
      return 0
    fi
    log "Local path not found; skipping: $spec"
    return 1
  fi

  if [[ -d "$APPS_DIR/$spec/xproj" ]]; then
    local resolved
    resolved="$(cd "$APPS_DIR/$spec/xproj" && pwd)"
    ensure_app_dirs "$APPS_DIR/$spec"
    echo "$resolved"
    return 0
  fi

  if [[ -d "$APPS_DIR/$spec" ]]; then
    local resolved
    resolved="$(cd "$APPS_DIR/$spec" && pwd)"
    echo "$resolved"
    return 0
  fi

  if [[ "$spec" == */* && "$spec" != *"://"* && "$spec" != git@*:* ]]; then
    spec="https://github.com/$spec"
  fi

  local name
  if [[ -n "$name_override" ]]; then
    name="$name_override"
  else
    name="$(basename "$spec" .git)"
  fi
  local app_root="$APPS_DIR/$name"
  local dir="$app_root/xproj"

  ensure_app_dirs "$app_root"

  if [[ -d "$dir/.git" ]]; then
    if [[ "$UPDATE_REPOS" == "true" ]]; then
      if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
        log "Repo has local changes; skipping pull: $name"
      else
        log "Updating existing repo: $name"
        if ! git -C "$dir" pull --rebase; then
          log "Pull failed; using existing checkout: $name"
        fi
      fi
    else
      log "Repo already exists; skipping update: $name"
    fi
  else
    if [[ ! -d "$dir" ]]; then
      log "Cloning: $spec"
      if ! git -C "$app_root" clone "$spec" "xproj"; then
        log "Clone failed; skipping: $spec"
        return 1
      fi
    else
      log "Directory exists but no .git folder; using anyway: $name"
    fi
  fi

  echo "$dir"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repos) REPO_LIST="$2"; shift 2;;
      --device) SIM_DEVICE_NAME="$2"; shift 2;;
      --os) SIM_OS="$2"; shift 2;;
      --open-xcode) OPEN_IN_XCODE="true"; shift;;
      --no-open-simulator) OPEN_SIMULATOR="false"; shift;;
      --clear-simulator) CLEAR_SIMULATOR="true"; shift;;
      --no-clear-simulator) CLEAR_SIMULATOR="false"; shift;;
      --env-file) ENV_FILE="$2"; shift 2;;
      --no-env-file) LOAD_ENV_FILE="false"; shift;;
      --update) UPDATE_REPOS="true"; shift;;
      --install-deps) AUTO_INSTALL_DEPS="true"; shift;;
      --node-install) NODE_INSTALL="always"; shift;;
      --no-node-install) NODE_INSTALL="never"; shift;;
      --allow-nativescript) ALLOW_NATIVESCRIPT="true"; shift;;
      --help) usage; exit 0;;
      *) echo "Unknown option: $1"; usage; exit 1;;
    esac
  done

  if [[ "$LOAD_ENV_FILE" == "true" ]]; then
    local env_file="${ENV_FILE:-}"
    local using_default_env_file="false"
    if [[ -z "$env_file" ]]; then
      using_default_env_file="true"
      env_file="$(resolve_default_env_file || true)"
    fi
    if [[ -f "$env_file" ]]; then
      load_root_env_file "$env_file"
    else
      if [[ "$using_default_env_file" == "true" ]]; then
        log "Env file not found; skipping auto-detect."
        log "Tip: set OPENAI_API_KEY in $REPO_ROOT/.env or pass --env-file."
      else
        log "Env file not found; skipping: $env_file"
        log "Tip: create that file or pass a different --env-file path."
      fi
    fi
  fi

  ensure_brew_path

  require_cmd git
  require_cmd xcrun
  require_cmd xcodebuild
  require_cmd python3
  require_cmd /usr/libexec/PlistBuddy

  # applesimutils is required for reliable notification/location permission grants
  if ! ensure_applesimutils; then
    log "WARNING: applesimutils not installed. Notification permission popups may still appear."
    log "Install manually: brew tap wix/brew && brew install applesimutils"
  fi

  if ! command -v xcpretty >/dev/null 2>&1; then
    log "Note: xcpretty not found. Install with: gem install xcpretty (optional)"
  fi

  mkdir -p "$APPS_DIR" "$DERIVED_DIR"

  read_apps "$REPO_LIST"

  local udid
  udid="$(boot_simulator)"
  log "Using simulator UDID: $udid"

  populate_contacts "$udid"

  local total_apps=${#APP_SPECS[@]}
  local current=0
  local success=0
  local skipped=0
  local failed=0

  local spec
  for spec in "${APP_SPECS[@]}"; do
    current=$((current + 1))
    local app_name app_repo app_ios_dir app_scheme app_type app_prebuild app_pod_mode app_pod_args app_build_args app_deps app_deploy_target
    IFS='|' read -r app_name app_repo app_ios_dir app_scheme app_type app_prebuild app_pod_mode app_pod_args app_build_args app_deps app_deploy_target <<< "$spec"
    app_type="$(normalize_type "${app_type:-}")"

    log "========================================="
    log "Processing app $current/$total_apps: $app_name"
    log "========================================="

    local repo_dir
    if ! repo_dir="$(clone_or_update "$app_repo" "$app_name")"; then
      log "Failed to clone/update $app_name; continuing with next app."
      failed=$((failed + 1))
      continue
    fi

    if [[ -z "$app_type" ]]; then
      if is_nativescript_repo "$repo_dir"; then
        app_type="nativescript"
      elif is_expo_repo "$repo_dir"; then
        app_type="expo"
      elif is_react_native_repo "$repo_dir"; then
        app_type="react-native"
      fi
    fi

    if [[ "$app_type" == "meta" || "$app_type" == "docs" ]]; then
      log "No build step for $app_name (type=$app_type)."
      success=$((success + 1))
      continue
    elif [[ "$app_type" == "skip" ]]; then
      log "Skipping $app_name (type=$app_type)."
      skipped=$((skipped + 1))
      continue
    fi

    ensure_app_deps "$app_deps"

    if [[ "$app_type" == "nativescript" ]]; then
      if [[ "$ALLOW_NATIVESCRIPT" == "true" ]]; then
        if run_nativescript_build "$app_name" "$repo_dir" "$udid" "$app_prebuild"; then
          success=$((success + 1))
        else
          failed=$((failed + 1))
        fi
      else
        log "NativeScript app detected for $app_name; skipping build."
        skipped=$((skipped + 1))
      fi
      continue
    fi

    if build_install_launch "$app_name" "$repo_dir" "$udid" "$app_ios_dir" "$app_scheme" "$app_type" "$app_prebuild" "$app_pod_mode" "$app_pod_args" "$app_build_args" "$app_deploy_target"; then
      success=$((success + 1))
    else
      log "Failed to build/install $app_name; continuing with next app."
      failed=$((failed + 1))
    fi
  done

  # Write manifest for per-task reinstall (clean slate without full erase).
  if [[ ${#MANIFEST_ENTRIES[@]} -gt 0 ]]; then
    write_app_manifest
  fi

  # Grant all privacy + notification permissions for custom apps post-install.
  # This is the authoritative grant for custom apps — at boot time the manifest
  # may not have existed yet (first run).
  if [[ -f "$APP_MANIFEST_FILE" ]]; then
    log "Granting permissions for custom apps (post-install)..."
    local post_bids
    post_bids="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
for app in m.values():
    print(app.get('bundle_id', ''))
" "$APP_MANIFEST_FILE" 2>/dev/null || true)"
    while IFS= read -r bid; do
      [[ -z "$bid" ]] && continue
      xcrun simctl privacy "$udid" grant all "$bid" 2>/dev/null || true
      if command -v applesimutils >/dev/null 2>&1; then
        applesimutils --byId "$udid" --bundle "$bid" --setPermissions "notifications=YES" 2>/dev/null || true
      fi
    done <<< "$post_bids"
  fi

  # Restart daemons so post-install permission grants take effect
  log "Restarting daemons to apply post-install permissions..."
  xcrun simctl spawn "$udid" killall -9 tccd 2>/dev/null || true
  xcrun simctl spawn "$udid" killall -9 usernoted 2>/dev/null || true
  sleep 2

  # Re-set simulated location (daemon restart may have cleared it)
  xcrun simctl location "$udid" set -- 37.3349 -122.0090 2>/dev/null || true

  # Wait for simulator to settle after all installs and daemon restarts
  log "Waiting for simulator to settle..."
  sleep 5

  write_last_bootstrap_state "$udid"

  # Return to home screen with double home-button press (Cmd+Shift+H in Simulator)
  if [[ "${HEADLESS_DEDICATED_SIMULATOR:-false}" != "true" ]]; then
    log "Returning to home screen..."
    open -a Simulator 2>/dev/null || true
    sleep 1
    osascript -e 'tell application "Simulator" to activate' \
              -e 'delay 0.5' \
              -e 'tell application "System Events" to keystroke "h" using {command down, shift down}' \
              2>/dev/null || true
    sleep 1
    osascript -e 'tell application "Simulator" to activate' \
              -e 'delay 0.5' \
              -e 'tell application "System Events" to keystroke "h" using {command down, shift down}' \
              2>/dev/null || true
    sleep 1
  fi
  # Dismiss any lingering permission alerts
  dismiss_simulator_alerts

  log "========================================="
  log "All repos processed!"
  log "Success: $success | Failed: $failed | Skipped: $skipped | Total: $total_apps"
  log "Apps should now be installed on the simulator."
  log "========================================="
}

main "$@"
