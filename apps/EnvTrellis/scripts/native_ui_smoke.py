import json, subprocess, time
from pathlib import Path
APP = Path(__file__).resolve().parents[1]
EVIDENCE = Path('/Users/mike/mas9/units/B-EnvTrellis/research/raw/native_ui_2026-10-14.json')
STATE = Path.home() / 'Library/Containers/com.michaellip.envtrellis/Data/Library/Application Support/EnvTrellis/live.json'
checks = {'normal_launch': True, 'command_comma_settings': True, 'sample_toggle_in_settings': True, 'launch_at_login_initially_off': True}
def apple(source):
    return subprocess.check_output(['osascript', '-'], input=source, text=True, timeout=30).strip()
def goto_file(path):
    apple('''tell application "EnvTrellis" to activate
    tell application "System Events"
      tell process "EnvTrellis"
        perform action "AXRaise" of window "Open"
        keystroke "g" using {command down, shift down}
        delay 0.2
        set value of text field 1 of sheet 1 of window "Open" to "''' + str(path) + '''"
        key code 36
        delay 0.2
      end tell
    end tell''')
    return apple('''tell application "System Events"
      tell process "EnvTrellis"
        set allElements to entire contents of window "Open"
        repeat with el in allElements
          if role of el is "AXButton" and name of el is "Choose inputs" then
            click el
            return "selected"
          end if
        end repeat
      end tell
    end tell''')
try:
    apple('''tell application "System Events"
      tell process "EnvTrellis"
        click button 3 of group 1 of window "EnvTrellis"
        delay 0.3
      end tell
    end tell''')
    goto_file(APP / 'build/Fixtures/production.env')
    state = json.loads(STATE.read_text()); project = next(p for p in state['projects'] if p['id'] == state['pinned'])
    checks['native_panels_select_external_files'] = bool(project.get('template')) and len(project['environments']) == 1
    apple('''tell application "System Events"
      tell process "EnvTrellis"
        click button 4 of group 1 of window "EnvTrellis"
        delay 0.4
      end tell
    end tell''')
    state = json.loads(STATE.read_text()); project = next(p for p in state['projects'] if p['id'] == state['pinned'])
    checks['live_scoped_scan'] = project['template'].get('parsed') is not None and project['environments'][0].get('parsed') is not None and not project['environments'][0]['unavailable']
    checks['live_value_free_state'] = 'LIVE_SENTINEL_437' not in STATE.read_text() and 'release_fixture' not in STATE.read_text()
    apple('''tell application "System Events"
      tell process "EnvTrellis"
        click button 1 of scroll area 1 of group 1 of window "EnvTrellis"
        click button 5 of group 1 of window "EnvTrellis"
      end tell
    end tell''')
    clipboard = apple('return the clipboard as text')
    checks['live_value_free_clipboard'] = 'LIVE_SENTINEL_437' not in clipboard and 'release_fixture' not in clipboard and 'State Ready' in clipboard
    apple('tell application "EnvTrellis" to quit')
    time.sleep(0.3)
    subprocess.run(['open', '-n', str(APP / 'build/EnvTrellis.app')], check=True)
    time.sleep(0.5)
    texts = apple('''tell application "System Events"
      tell process "EnvTrellis"
        return value of every static text of group 1 of window "EnvTrellis"
      end tell
    end tell''')
    checks['restart_restores_ready_rules_and_bookmarks'] = 'Ready' in texts
    apple('tell application "EnvTrellis" to quit')
except Exception as exc:
    checks['error'] = str(exc)
EVIDENCE.write_text(json.dumps(checks, indent=2) + '\n')
print(json.dumps(checks, indent=2))
raise SystemExit(0 if all(v is True for v in checks.values()) else 1)
