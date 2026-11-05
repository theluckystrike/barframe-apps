#!/usr/bin/env python3
"""Signed UI regressions. Run after the build with fixture folder and evidence directory."""
import json
from pathlib import Path
import subprocess
import sys
import time
app = Path(__file__).resolve().parents[1] / "build/HashDock.app"
fixture = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
assert fixture.is_dir() and any(fixture.iterdir())
out.mkdir(parents=True, exist_ok=True)
container = Path.home() / "Library/Containers/com.michaellip.hashdock/Data"
def script(body):
    return 'tell application "System Events" to tell process "HashDock"\n' + body + '\nend tell'
def osa(body):
    return subprocess.check_output(["osascript", "-e", script(body)], text=True, timeout=10).strip()
def until(body, expected, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = osa(body)
            if expected in value: return value
        except subprocess.SubprocessError: pass
        time.sleep(0.15)
    raise AssertionError(expected + " not reached")
def select(index):
    for attempt in range(2):
        osa(f'set frontmost to true\ndelay 0.2\nclick button {index} of group 1 of window "HashDock"')
        try:
            until('get name of windows', 'Open', timeout=75)
            break
        except AssertionError:
            if attempt: raise
            print("RETRY first-use AppKit panel bridge timeout", flush=True)
    quoted = json.dumps(str(fixture))
    osa('set frontmost to true\nkeystroke "g" using {command down, shift down}\ndelay 0.3\nkeystroke ' + quoted + '\nkey code 36\ndelay 0.5\nclick button "Open" of splitter group 1 of window "Open"')
subprocess.run(["open", "-n", str(app), "--args", "--external-select"], check=True)
until('get name of windows', 'HashDock')
time.sleep(0.5)
select(1)
osa('click button 3 of group 1 of window "HashDock"')
until('get value of static texts of group 1 of window "HashDock"', 'files frozen')
select(2)
osa('click button 4 of group 1 of window "HashDock"')
until('get value of static texts of group 1 of window "HashDock"', 'Verified')
deadline = time.monotonic() + 10
while True:
    state = json.loads((container / "Library/Application Support/HashDock/ExternalTest/state.json").read_text())
    job = state["jobs"][state["pinned"]]
    if job["manifest"]["entries"] and all(r.get("result", {}).get("verified", 0) > 0 for r in job["recipients"]): break
    assert time.monotonic() < deadline
    time.sleep(0.1)
settings = osa('set frontmost to true\nkeystroke "," using command down\ndelay 0.4\nget name of windows')
assert "HashDock Settings" in settings
subprocess.run(["osascript", "-e", 'tell application "HashDock" to quit'], check=True)
subprocess.run(["open", "-W", "-n", str(app), "--args", "--external-reopen"], check=True)
report = json.loads((container / "smoke.json").read_text())
assert report["pass"] and report["sandboxed"] and report["checks"][0]["name"] == "External bookmark after process restart"
(out / "external-restart_2026-10-14.json").write_text(json.dumps(report, indent=2))
subprocess.run(["open", "-n", str(app)], check=True)
until('get name of windows', 'HashDock')
normal_settings = osa('set frontmost to true\nkeystroke "," using command down\ndelay 0.4\nget name of windows')
assert "HashDock Settings" in normal_settings
osa('click button 1 of window "HashDock Settings"')
osa('click button 1 of window "HashDock"\ndelay 0.2\nclick menu bar item 1 of menu bar 2\ndelay 0.3\nclick button 1 of group 1 of window 1')
reopened = until('get name of windows', 'HashDock')
subprocess.run(["osascript", "-e", 'tell application "HashDock" to quit'], check=True)
(out / "ui-regressions_2026-10-14.json").write_text(json.dumps({"external_selection": True, "bookmark_process_restart": True, "command_comma": normal_settings, "menu_reopens_closed_matrix": reopened}, indent=2))
print("PASS external selection, process restart, Command comma, menu reopening")
