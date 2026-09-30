# iOSWorld

iOSWorld is a benchmark for LLM agents that use an iPhone Simulator. It
ships 26 SwiftUI apps, one shared fictional user profile, 133 tasks, rubrics,
agent runners, and tooling for local Mac or EC2 Mac execution.

![iOSWorld overview](docs/figures/overview.png)

## What You Get

- 26 runnable iOS apps under `iphone/apps/`
- 133 benchmark tasks and rubrics in [`tasks.json`](tasks.json)
- A seeded cross-app user state for Jordan Avery
- A local interactive demo
- Single-task, full-suite, and parallel benchmark runners
- Optional vision+XML observations
- Optional Qwen/vLLM MCP tool-use mode
- Optional AWS EC2 Mac bootstrap helpers

The first thing to try after setup is the demo. The first thing to use for a
repeatable benchmark run is `scripts/run_task_by_id.sh`.

## Requirements

- macOS
- Xcode 26+ with an iOS 26 simulator runtime
- Python 3.10+
- Node.js `^20.19`, `^22.12`, or `>=24`
- At least one model backend:
  - OpenAI: `OPENAI_API_KEY`
  - Anthropic: `ANTHROPIC_API_KEY`
  - Gemini: `GEMINI_API_KEY`
  - vLLM/Qwen: `VLLM_BASE_URL` and `VLLM_API_KEY`

For scoring, the default judge uses OpenAI, so `OPENAI_API_KEY` is needed even
when the agent itself uses another provider.

## Install Xcode First

iOSWorld builds and installs real iOS apps, so Xcode must be ready before the
Python/Appium setup can run end to end.

1. Install Xcode 26 or newer from the Mac App Store or Apple Developer
   Downloads.
2. Open Xcode once and accept the license.
3. Install an iOS 26 simulator runtime in Xcode:
   `Xcode` -> `Settings` -> `Platforms` -> `+` -> `iOS`.
4. Install Command Line Tools if needed:

```sh
xcode-select --install
```

Verify the install:

```sh
xcodebuild -version
xcrun simctl list runtimes | grep -i "iOS"
```

If `xcodebuild` asks for first-launch setup or license acceptance, run:

```sh
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## Quick Start

```sh
git clone https://github.com/ljang0/iOSWorld.git
cd iOSWorld

./scripts/setup_env.sh
source .venv/bin/activate
```

Edit `.env` and choose a runner:

```sh
LLM_PROVIDER=vllm
LLM_MODEL=qwen3.5-35B-a3
VLLM_BASE_URL=http://localhost:8000/v1
VLLM_API_KEY=EMPTY
```

Or use another supported provider/model:

| Provider | Example model | Required env |
|---|---|---|
| `openai` | `gpt-5.4-mini` | `OPENAI_API_KEY` |
| `anthropic` | `claude-sonnet-4-6` | `ANTHROPIC_API_KEY` |
| `gemini` | `gemini-3-flash-preview` | `GEMINI_API_KEY` |
| `vllm` | `qwen3.5-35B-a3` | `VLLM_BASE_URL`, `VLLM_API_KEY` |

## Prepare a Simulator

Check which iPhone simulators are available:

```sh
xcrun simctl list devices available | grep -i "iPhone"
```

The default device is `iPhone 17 Pro`. If you do not have one, either set
`DEVICE_NAME` in `.env` to an available iPhone, or create the default device
with the runtime installed on your machine:

```sh
xcrun simctl list devicetypes | grep -i "iPhone"
xcrun simctl list runtimes | grep -i "iOS"

xcrun simctl create "iPhone 17 Pro" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
```

Boot the simulator and install the benchmark apps:

```sh
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator

./iphone/bootstrap/bootstrap_ios_apps.sh
```

Expected bootstrap summary:

```text
Success: 26 | Failed: 0 | Skipped: 0
```

## Run The Demo

The demo lets you type a plain-language task and watch the agent operate the
seeded iPhone.

```sh
python3 scripts/demo.py
```

You can also double-click `iOSWorld Demo.command` in Finder.

Useful demo flags:

```sh
python3 scripts/demo.py --task "set a 6:45 AM alarm labeled Gym"
python3 scripts/demo.py --provider openai --model gpt-5.4-mini
python3 scripts/demo.py --verbose
```

Demo output is written under `results/demo-<timestamp>-<task>/`. Demo mode is for exploration; it
does not score tasks.

## Run One Benchmark Task

Start Appium in a separate terminal:

```sh
appium --port 4723
```

Then run a task:

```sh
./scripts/run_task_by_id.sh clock-001 \
  --provider vllm --model qwen3.5-35B-a3
```

Task IDs live in [`tasks.json`](tasks.json). Results are written under
`results/single-task-<timestamp>-<task-id>/` and include:

- `trajectory.json`
- `events.jsonl`
- per-step screenshots
- planned and executed actions
- rubric evaluation

`run_task_by_id.sh` evaluates the final trajectory by default. If scoring fails
because `OPENAI_API_KEY` is missing, the agent run artifacts are still the first
place to inspect.

## Run The Full Benchmark

Sequential run on one simulator:

```sh
LLM_PROVIDER=vllm LLM_MODEL=qwen3.5-35B-a3 \
  scripts/bootstrap_release.sh --target phone --tasks tasks.json
```

Skip rubric scoring:

```sh
LLM_PROVIDER=vllm LLM_MODEL=qwen3.5-35B-a3 \
  scripts/bootstrap_release.sh --target phone --tasks tasks.json --no-evaluate
```

Parallel run across cloned simulators:

```sh
SOURCE_UDID=$(python3 scripts/find_latest_udid.py --bare)

LLM_PROVIDER=vllm LLM_MODEL=qwen3.5-35B-a3 \
  scripts/run_parallel.sh \
    --workers 4 \
    --source-udid "$SOURCE_UDID" \
    --tasks tasks.json
```

## Runner Modes

| Mode | How to run |
|---|---|
| Screenshot-only UI actions | default |
| Vision + accessibility XML | add `--xml-agent` |
| Qwen MCP tools | add `--mcp --mcp-model qwen3.5-35B-a3` |
| Qwen MCP + `mobile_use` fallback | add `--mcp --mcp-cua --mcp-model qwen3.5-35B-a3` |

MCP mode is Qwen/vLLM-only. List the active MCP tools with:

```sh
python3 scripts/mcp_agent_runner.py --list-tools
```

## Scoring

Each task has rubric criteria in `tasks.json`. A task score is
`n_satisfied / n_criteria`; pass rate counts tasks where every criterion is
satisfied.

Full-suite and single-task wrappers score automatically. Re-score an existing
run without rerunning the agent:

```sh
python3 scripts/judge_trajectories.py --run-dir results/run-<name>
```

Judge controls:

| Env var | Default | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | required | Key for the default judge |
| `EVAL_PROVIDER` | `openai` | Judge provider |
| `EVAL_MODEL` | `gpt-5.4-mini` | Judge model |
| `EVAL_MAX_WORKERS` | `4` | Parallel judge calls |

## Tasks

`tasks.json` is the canonical benchmark task file. It contains 133 tasks,
goals, app scopes, categories, difficulty labels, and grading rubrics.

Minimal task shape:

```json
{
  "name": "clock-001",
  "goal": "Set a 6:45 AM alarm labeled 'Gym' in the Clock app and confirm it's set.",
  "apps": ["clock"],
  "category": "single_app",
  "difficulty": "easy",
  "rubric": [
    { "criterion": "Open Clock and navigate to the Alarm tab" },
    { "criterion": "Set the alarm time to 6:45 AM" },
    { "criterion": "Set the alarm label to 'Gym'" },
    { "criterion": "Confirm the alarm is enabled" }
  ]
}
```

Every app named in `apps` must have:

- an app directory under `iphone/apps/<app>/`
- an MCP server under `mcps/<app>.py`

## Repository Layout

```text
.env.example              provider/model and simulator config template
tasks.json                canonical benchmark tasks and rubrics
iOSWorld Demo.command     Finder launcher for demo mode

scripts/setup_env.sh      Python/Appium setup
scripts/demo.py           interactive demo
scripts/run_task_by_id.sh single-task runner
scripts/bootstrap_release.sh
scripts/run_parallel.sh   full-suite runners
scripts/judge_trajectories.py
scripts/mcp_agent_runner.py

scripts/aws/              EC2 Mac helpers
mcps/                     MCP tool servers
iphone/apps/              SwiftUI benchmark apps
iphone/bootstrap/         app build/install bootstrap
iphone/shared/            shared seed data
```

## EC2 Mac

Users without a local Mac can run iOSWorld on AWS EC2 Mac. The supported paths
are:

- already-installed Xcode
- a user-provided licensed Xcode `.xip`
- a private S3 object containing that `.xip`
- a private AMI you create after setup

Start with:

```sh
CHECK_ONLY=1 scripts/setup_mac_host.sh
scripts/setup_mac_host.sh
```

See [`docs/aws_ec2_mac.md`](docs/aws_ec2_mac.md) for the full guarded flow,
including Dedicated Host cleanup notes.

## More Docs

- [`docs/app_fixes.md`](docs/app_fixes.md) - app behavior corrections and
  standalone regression checks.
- [`mcps/README.md`](mcps/README.md) - how MCP mode works, how tools are
  exposed to Qwen, confirmation-tool options, simulator fallback tools, and MCP
  troubleshooting.
- [`docs/qwen_vllm_cluster.md`](docs/qwen_vllm_cluster.md) - how to serve
  Qwen3.5 with vLLM, configure `VLLM_BASE_URL`, test tool calling, and run a
  Qwen smoke task.
- [`docs/aws_ec2_mac.md`](docs/aws_ec2_mac.md) - how to run iOSWorld on AWS EC2
  Mac, including Dedicated Host setup, Xcode `.xip` handling, S3 upload, smoke
  tests, and cleanup.
- [`iphone/bootstrap/README.md`](iphone/bootstrap/README.md) - details for
  `bootstrap_ios_apps.sh`, including simulator selection, env files, repo-list
  format, and bootstrap flags.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Could not find a matching simulator` | Set `DEVICE_NAME` in `.env` to a simulator listed by `xcrun simctl list devices available`. |
| Appium cannot find `XCUITest` | Run `appium driver install xcuitest`. |
| Bootstrap fails on one app | Re-run `./iphone/bootstrap/bootstrap_ios_apps.sh`; builds are incremental. |
| A run is very slow | Shut down extra simulators with `xcrun simctl shutdown all`, then boot only the target simulator. |
| Scoring fails but the task ran | Set `OPENAI_API_KEY`, or rerun the suite with `--no-evaluate`. |

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
