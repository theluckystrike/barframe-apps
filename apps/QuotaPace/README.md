# QuotaPace

QuotaPace is a macOS 14+ menu bar pace forecaster for local Claude Code and Codex token usage. It costs $5.99 in the proposed store listing. This directory contains source, synthetic test fixtures, an icon generator, a store listing and sandbox verification artifacts.

## Use

1. Open QuotaPace and choose a log format. Click Try Sample mode to inspect synthetic usage without an account or files. Sample limits start at 45 million tokens per five hours and 200 million per seven days; Sample budget edits stay in memory. Exit Sample mode restores saved live settings.
2. Connect its session log folder. The picker shows hidden folders: `~/.claude/projects` for Claude Code or `~/.codex/sessions` for Codex. Select a projects/sessions root, or a smaller subfolder. Logs are never modified.
3. In Settings > General, enter your five-hour and seven-day token budgets and click Save. An empty field or zero leaves that budget unset. No provider quota is assumed. Use Pace details to see the observed span and full-window projection.
4. Inspect totals, percentage used, average pace and the five-hour time-to-limit estimate. Logs refresh every 30 seconds; use Refresh for an immediate update.
5. Use Disconnect in Settings to remove a folder grant and its cached counts. Launch at Login is optional and off by default.

Escape closes the popover. Command-comma opens Settings. Command-Q quits.

## Interpretation

This is a local estimate against user-entered token budgets, not an official provider quota monitor. The app cannot see usage on other devices, plan weights, account entitlements or official reset schedules. Claude input, output, cache creation and cache reads are summed. Repeated assistant message IDs use the largest complete usage record. Codex `event_msg` / `token_count` cumulative totals are converted to deltas; cached input is already included. Counter decreases use the last-turn usage when present. A first cumulative record represents the history included in that record and is attributed to its timestamp; a truncated log can therefore distort the time allocation.

The rolling windows are `(now - duration, now]`. Pace uses elapsed time since the oldest event in a window, after one minute of observation. A projected full window is `used / elapsedFraction`. Forecasts assume that average pace continues and remove past events when they expire. Predictions cover the next five hours; “Within pace” means no crossing within that horizon at that assumed pace. Provider rules can differ. Seven-day usage and percent are displayed; the primary pace and forecast use the five-hour window.

Logs stream in 64 KB chunks. The scanner tracks file identity, modification timestamp and byte offset, buffers incomplete trailing lines, rescans modified files (including same-size edits), skips symlinks, and deduplicates Claude messages across files. It reports malformed lines, oversized lines (4 MB maximum) and unreadable files. A folder scan is limited to 20,000 JSONL files; exceeding it produces a visible warning. Select a narrower folder to resolve it. Cached values remain visible if access fails; reconnect to restore the grant. All scanning occurs off the main actor.

## Sandbox and privacy

- `com.apple.security.app-sandbox`: added by the build kit; isolates app data.
- `com.apple.security.files.user-selected.read-only`: reads only session folders selected through NSOpenPanel.
- `com.apple.security.files.bookmarks.app-scope`: restores read-only folder access after relaunch; stale bookmarks are renewed while access is active.

There is no network entitlement. No account credentials are read. Only bookmarks, preferences, recent timestamp/token records, opaque record identifiers, file counts and refresh times are retained in UserDefaults in the sandbox. UserDefaults is declared in `PrivacyInfo.xcprivacy` with reason CA92.1. File modification timestamps detect edited logs, declared with reason C617.1. Full source paths are not stored in cached usage IDs; old path-containing caches are discarded on upgrade. Login item management uses SMAppService.mainApp. The full policy is in `store/privacy.md`.

## Build and verify

From this directory on a Mac with Command Line Tools:

```sh
swift scripts/make_icon.swift
swift build
../../kit/swift_test.sh
bash ../../kit/make_app.sh .
python3 -I ../../kit/gate.py .
```

The universal arm64/x86_64, ad-hoc signed sandbox app is `build/QuotaPace.app`. Distribution signing and store submission belong to the publisher. The readiness gate uses the free iTunes Search API for a name snapshot. No paid API calls are used.

`--smoke` runs seven real checks inside the sandbox, including bookmark creation/resolution, container JSONL reads, window and forecast math over those reads, and an EPERM/EACCES positive control for ungranted Desktop access. `--screenshots` renders three opaque 2880×1800 store images on the main actor: the usage popover, General Settings and Pace details. All use bundled neutral sample usage labeled Sample data, regardless of live folder access. UI Sample mode uses these same resource fixtures with current timestamps and scaled token values. Repeating timers are invalidated and scan tasks cancelled when the model stops.

All three screenshots use in-memory captures of the production views and native controls at their real point sizes before QuotaPaceScreenshotComposer composes the PNG, without enlargement. This avoids ImageRenderer placeholders for tabs, toggles and editable text fields. A local Vision text-recognition regression test checks that the Sample budgets and Save control are present. Native policy buttons expose distinct accessible titles and open bundled pages in app windows until the HTTPS domain is final.

## Support

For missing usage, verify the selected provider and folder, then Refresh. For expired access, Reconnect logs. If a folder contains no valid recent records, choose the correct session root. For an incorrect forecast, check the limits and the interpretation above. Unset budgets are intentional; the app does not infer official plan allowances. Support: About > Support opens bundled local help until the configured domain is final.

Privacy: About or the popover footer opens the bundled policy until the configured domain is final.

## Listing decision and claim checks

Free download with IAP was evaluated against design rules R7/R8. Keep the proposed $5.99 paid utility: it has no account, purchases or recurring service; adding IAP would expand this polish scope.

Store claims were checked against source: “refreshes every 30 seconds” → AppModel.start / RefreshTimer.start; “previous five hours and seven days” → UsageWindow.duration / WindowSummary.calculate; “separate token budgets” → SettingsView / Limits; “time to your five-hour limit” → PopoverView / WindowSummary; “Pace details” → PaceDetailsView; “deduplicated” and “deltas” → JSONLParser.ingest; “opaque record identifiers” → JSONLParser.opaqueID and Preferences cache.v2; “Sample budgets are temporary” → AppModel.saveLimits / setSampleMode; “Launch at Login is optional” → AppModel.setLogin. Format names identify supported input data.

The provisional domain uses bundled offline HTML privacy and support pages for in-app links. When a final domain is configured, the links use kit-written HTTPS URLs. Public hosting is deferred to the owner; local pages open inside QuotaPace without a network connection. A verified contact channel remains an owner prerequisite before submission.
