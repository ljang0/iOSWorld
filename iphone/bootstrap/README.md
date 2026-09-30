# iPhone Bootstrap

This folder contains the bootstrap script and app list used to build, install,
launch, and seed the 26 iOSWorld apps on one iPhone simulator. The script reads
`repos.txt`, resolves each app's Xcode project/workspace, then builds and
installs the apps onto the target simulator.

By default the simulator is erased before install so every benchmark task can
start from the canonical Jordan Avery state.

## Files
- `bootstrap_ios_apps.sh` - main bootstrap runner
- `repos.txt` - canonical list of the 26 apps to build/install
- `ContactImporter/` - helper sim app that seeds the simulator's Contacts

## Usage
Run from this folder:

```bash
./bootstrap_ios_apps.sh
```

Quick start (explicit device name, from repo root):

```bash
./iphone/bootstrap/bootstrap_ios_apps.sh --device "iPhone 17 Pro"
```

The app bootstrap itself does not require an LLM key. For later benchmark or
demo runs, keep provider keys in the repo-root `./.env` file created by
`scripts/setup_env.sh`.

The script auto-loads the first env file it finds in this order:

- `./.env`
- `iphone/bootstrap/.env`
- `./.env.example`
- `iphone/bootstrap/.env.example`

Quick start (from anywhere inside this repo, even inside app `xproj/` folders):

```bash
ROOT="$(pwd)"
while [[ "$ROOT" != "/" && ! -x "$ROOT/iphone/bootstrap/bootstrap_ios_apps.sh" ]]; do
  ROOT="$(dirname "$ROOT")"
done
"$ROOT/iphone/bootstrap/bootstrap_ios_apps.sh" --device "iPhone 17 Pro"
```

If you are inside an app `xproj/` folder, this relative path works:

```bash
../../../bootstrap/bootstrap_ios_apps.sh --device "iPhone 17 Pro"
```

If the script is not found, `cd` to the repo root first:

```bash
cd <repo-root>
./iphone/bootstrap/bootstrap_ios_apps.sh --device "iPhone 17 Pro"
```

Target a specific simulator device and OS:

```bash
./bootstrap_ios_apps.sh --device "iPhone 17 Pro" --os 26.2
```

Skip wiping simulator state:

```bash
./bootstrap_ios_apps.sh --no-clear-simulator
```

Use a custom repo list file:

```bash
./bootstrap_ios_apps.sh --repos ./repos.txt
```

## Environment Files

If you prefer a different env file name, pass it in:

```bash
./bootstrap_ios_apps.sh --env-file ./path/to/.env
```

Override the env file path or skip loading:

```bash
./bootstrap_ios_apps.sh --env-file /path/to/.env
./bootstrap_ios_apps.sh --no-env-file
```

## Environment Overrides
You can also override settings via environment variables:

```bash
APPS_DIR=../apps \\
DERIVED_DIR=./.derived_data \\
SIM_DEVICE_NAME="iPhone 17 Pro" \\
SIM_OS=26.2 \\
OPEN_SIMULATOR=true \\
CLEAR_SIMULATOR=true \\
ENV_FILE=./.env \\
LOAD_ENV_FILE=true \\
./bootstrap_ios_apps.sh
```

## Dedicated Simulator Automation

For automation that already controls its target simulator, set
`HEADLESS_DEDICATED_SIMULATOR=true` to skip the global Simulator-window
AppleScript used for dismissing alerts and returning Home. The controller must
handle those operations on its selected device. The default is `false`, retaining
the interactive behavior. This flag does not change simulator selection, app
installation, or reset behavior; use the existing options for those settings.

## Repo List Format
Each line in a repo list can be a local path or a repo URL. The public release
uses local paths under `iphone/apps/`. You can also provide a name and key/value
options:

```
name | repo_or_path | ios_dir=ios | scheme=AppScheme | type=react-native
```

Examples used here:

```
mail | ../apps/mail/xproj
cinephile | ../apps/cinephile/xproj/Cinephile
```
