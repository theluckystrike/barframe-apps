# NativeLedger

A macOS 14+ windowed app that keeps a tamper evident ledger of app updates.

- Add App: choose one or more `.app` bundles with the file picker. Each gets a read-only app-scope bookmark.
- Inspect now: records bundle identifier, version, build, architecture, signing identifier, team, declared entitlements, code directory hash and main executable SHA-256. A new entry is appended only when something changed. Each entry stores the hash of the entry before it.
- Anomalies: silent rebuild, version regression, team change, new entitlement, architecture change.
- Verify chain names the earliest broken entry. Acknowledge records the reviewed baseline as a chain entry.
- Export Ledger writes a `.nativeledger` JSON file without bookmarks or paths. Compare with Ledger File reads one from another Mac.
- Sample (`Open Sample`, or launch with `--ledger-sample`) is synthetic and memory-only.

Targets: `LedgerCore` (library), `NativeLedger` (app), `LedgerCoreTests`, `NativeLedgerAppTests`. No package dependencies.

Command line modes of the built executable:
- `--selftest` prints the smoke report JSON. `--smoke` also writes `NSHomeDirectory()/smoke.json`.
- `--screenshots` renders the five store screenshots to `NSHomeDirectory()/screenshots`. `--render-screenshots <dir>` renders them to a folder.

Tests use Swift Testing with the Command Line Tools frameworks (see `kit/swift_test.sh`).
