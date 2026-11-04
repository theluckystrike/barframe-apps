on run
    tell application "System Events"
        tell process "QuotaPace"
            set frontmost to true
            click menu bar item 1 of menu bar 2
            delay 0.3
            keystroke "," using command down
            delay 0.7
            if not (exists window "QuotaPace Settings") then error "Command-comma did not open Settings"
            set output to "Command-comma: QuotaPace Settings opened" & linefeed
            set elementsList to entire contents of window "QuotaPace Settings"
            repeat with uiElement in elementsList
                if role of uiElement is "AXRadioButton" and description of uiElement is "General" then
                    click uiElement
                    exit repeat
                end if
            end repeat
            delay 0.3
            set elementsList to entire contents of window "QuotaPace Settings"
            set toggleList to {}
            repeat with uiElement in elementsList
                if role of uiElement is "AXCheckBox" then set end of toggleList to contents of uiElement
            end repeat
            if (count of toggleList) is not 2 then error "Expected login and Sample toggles"
            set sampleToggle to item 2 of toggleList
            if value of sampleToggle is 0 then click sampleToggle
            delay 0.5
            set elementsList to entire contents of window "QuotaPace Settings"
            set budgetsFound to 0
            repeat with uiElement in elementsList
                if role of uiElement is "AXTextField" then
                    if value of uiElement is "45000000" then set budgetsFound to budgetsFound + 1
                end if
            end repeat
            if budgetsFound is not 2 then error "Sample budgets did not appear for both formats"
            set output to output & "UI Sample mode: both five-hour budgets are 45000000" & linefeed
            repeat with uiElement in elementsList
                if role of uiElement is "AXRadioButton" and description of uiElement is "About" then
                    click uiElement
                    exit repeat
                end if
            end repeat
            delay 0.3
            set elementsList to entire contents of window "QuotaPace Settings"
            set privacyFound to false
            set supportFound to false
            repeat with uiElement in elementsList
                try
                    if role of uiElement is "AXButton" and description of uiElement is "Privacy Policy" then
                        if not enabled of uiElement then error "Privacy Policy button disabled"
                        set privacyFound to true
                        set privacyButton to contents of uiElement
                    end if
                    if role of uiElement is "AXButton" and description of uiElement is "Support" then
                        if not enabled of uiElement then error "Support button disabled"
                        set supportFound to true
                        set supportButton to contents of uiElement
                    end if
                end try
            end repeat
            if not privacyFound or not supportFound then error "About links not found"
            set output to output & "Settings About: distinct enabled Privacy Policy and Support buttons" & linefeed
            repeat with uiElement in elementsList
                if role of uiElement is "AXStaticText" then
                    set visibleText to value of uiElement as text
                    if visibleText contains "{BRAND}" or visibleText contains "{DOMAIN}" then error "Provisional text visible in About"
                end if
            end repeat
            perform action "AXPress" of privacyButton
            delay 0.4
            if not (exists window "QuotaPace Privacy Policy") then error "Bundled privacy window did not open"
            set output to output & "Privacy Policy: bundled native window opened" & linefeed
            click button 1 of window "QuotaPace Privacy Policy"
            perform action "AXPress" of supportButton
            delay 0.4
            if not (exists window "QuotaPace Support") then error "Bundled support window did not open"
            set output to output & "Support: bundled native window opened" & linefeed
            click button 1 of window "QuotaPace Support"
            return output
        end tell
    end tell
end run
