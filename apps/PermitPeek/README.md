# PermitPeek

PermitPeek is a Mac menu bar app that shows how an app's code signing entitlements changed since the baseline you acknowledged.

![PermitPeek inbox with a sample app that changed its signing team, version and network entitlement](store/screenshots/01-review.png)

## Features

- Reads the code signature of an app that you choose, without running it. Only the main executable is covered.
- Rescan compares entitlement keys and values, the app version and the signing team with your baseline. It lists added, removed and changed items.
- Acknowledge changes to make the current reading your new baseline. A failed read keeps the previous baseline. You can copy a text report, or remove a watched app without changing its bundle.
- Opens the inbox with a global shortcut, Shift Command P by default. You can choose another shortcut or turn it off in Settings.
- Includes Sample mode with two fictional apps, kept apart from your live watches.

## Requirements

- macOS 14.0 or later.
- Sandboxed. Read-only access to apps that you choose in the system file picker. No network access.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/PermitPeek
swift build -c release
```

The package depends on `../../kit/MASKit` by path. Clone the whole repository, so that the folder layout stays the same.

## Privacy

Signing details and baselines stay on your Mac. PermitPeek does not read documents, inspect traffic, collect analytics or contact a server. Full policy: [store/privacy.md](store/privacy.md).

## License

MIT. See [LICENSE](../../LICENSE).
