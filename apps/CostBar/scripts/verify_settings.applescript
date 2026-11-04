-- Run after: open -n build/CostBar.app
tell application "System Events"
    repeat 30 times
        if exists (first application process whose bundle identifier is "com.unfinalized.costbar") then exit repeat
        delay 0.1
    end repeat
    set costProcess to first application process whose bundle identifier is "com.unfinalized.costbar"
    set frontmost of costProcess to true
    keystroke "," using {command down}
    repeat 30 times
        if exists window "CostBar Settings" of costProcess then exit repeat
        delay 0.1
    end repeat
    if not (exists window "CostBar Settings" of costProcess) then error "Command-comma did not open Settings"
    return "PASS normal launch; Command-comma opened CostBar Settings"
end tell
