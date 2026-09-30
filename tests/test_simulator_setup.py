"""Exercise bootstrap UI guards without launching or operating a simulator."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "iphone/bootstrap/bootstrap_ios_apps.sh"


class SimulatorSetupTests(unittest.TestCase):
    def run_fragment(self, fragment, headless):
        with tempfile.TemporaryDirectory() as directory:
            calls = Path(directory) / "calls"
            env = os.environ.copy()
            env.pop("HEADLESS_DEDICATED_SIMULATOR", None)
            if headless is not None:
                env["HEADLESS_DEDICATED_SIMULATOR"] = headless
            env["IOSWORLD_TEST_CALLS"] = str(calls)
            stubs = '''
log() { :; }
sleep() { :; }
open() { printf 'open\n' >> "$IOSWORLD_TEST_CALLS"; }
osascript() { printf 'osascript\n' >> "$IOSWORLD_TEST_CALLS"; }
'''
            subprocess.run(["bash", "-c", stubs + fragment], env=env,
                           check=True, capture_output=True, text=True)
            return calls.read_text().splitlines() if calls.exists() else []

    def test_bootstrap_syntax(self):
        subprocess.run(["bash", "-n", str(BOOTSTRAP)], check=True)

    def test_alert_dismissal_is_opt_out(self):
        text = BOOTSTRAP.read_text()
        fragment = text.split("dismiss_simulator_alerts() {", 1)[1].split(
            "\nboot_simulator() {", 1)[0]
        fragment = "dismiss_simulator_alerts() {" + fragment + "\ndismiss_simulator_alerts\n"
        for headless, expected in [("true", []), (None, ["osascript"]),
                                   ("false", ["osascript"])]:
            with self.subTest(headless=headless):
                self.assertEqual(self.run_fragment(fragment, headless), expected)

    def test_home_shortcut_is_opt_out(self):
        text = BOOTSTRAP.read_text()
        fragment = text.split("  # Return to home screen with double home-button press", 1)[1]
        fragment = fragment.split("\n", 1)[1].split("  # Dismiss any lingering permission alerts", 1)[0]
        for headless, expected in [("true", []),
                                   (None, ["open", "osascript", "osascript"]),
                                   ("false", ["open", "osascript", "osascript"])]:
            with self.subTest(headless=headless):
                self.assertEqual(self.run_fragment(fragment, headless), expected)


if __name__ == "__main__":
    unittest.main()
