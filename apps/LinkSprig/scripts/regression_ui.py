#!/usr/bin/env python3
"""Exercise the normal menu bar lifecycle through macOS Accessibility."""
import json, subprocess, sys
from pathlib import Path
app = Path(__file__).resolve().parents[1]
subprocess.run(['open', '-n', str(app / 'build/LinkSprig.app')], check=True)
script = r'''tell application "System Events"
    repeat 40 times
        if exists process "LinkSprig" then exit repeat
        delay 0.1
    end repeat
    tell process "LinkSprig"
        set frontmost to true
        delay 0.5
        keystroke "s" using {command down, shift down}
        delay 0.5
        set launched to exists window "LinkSprig"
        click button 1 of window "LinkSprig"
        delay 0.4
        set closed to not (exists window "LinkSprig")
        click menu bar item 1 of menu bar 2
        delay 0.4
        click button 1 of group 1 of pop over 1 of menu bar item 1 of menu bar 2
        delay 0.5
        set reopened to exists window "LinkSprig"
        set frontmost to true
        keystroke "," using command down
        delay 0.5
        set settingsOpened to exists window "LinkSprig Settings"
        return {launched, closed, reopened, settingsOpened}
    end tell
end tell'''
try:
    result = subprocess.run(['osascript', '-e', script], check=True, capture_output=True, text=True, timeout=30)
    flags = [part.strip() == 'true' for part in result.stdout.strip().split(',')]
    evidence = {'normalLaunch': flags[0], 'detailClosed': flags[1], 'reviewMoveReopenedDetail': flags[2], 'commandCommaOpenedSettings': flags[3], 'stdout': result.stdout.strip()}
    print(json.dumps(evidence))
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(json.dumps(evidence, indent=2) + '\n')
    if not all(flags):
        sys.exit(1)
finally:
    subprocess.run(['osascript', '-e', 'tell application id "com.michaellip.linksprig" to quit'], check=False)
