# CheckHarbor

CheckHarbor is a Mac menu bar app that keeps failed GitHub Actions runs visible until a matching run succeeds.

<img src="store/screenshots/01-inbox.png" alt="CheckHarbor recovery inbox with two unresolved sample failures">

<img src="store/screenshots/02-recovery.png" alt="CheckHarbor Recovered list with a sample failure and its recovery run">

## Features

- Groups repeated failures into one episode for each repository, branch and workflow. An episode closes only when a newer run of the same workflow on the same branch succeeds.
- Acknowledge or snooze an episode. It stays unresolved until it recovers.
- Links to the first failure, the latest failure and the recovery run on github.com.
- Shows stale data, authentication errors and rate limit backoff. A global shortcut (Shift Command H by default) opens the unresolved list.
- Includes Sample mode with fictional workflows. Sample mode makes no network requests.

## Download

Download [CheckHarbor-1.0.0.dmg](https://github.com/theluckystrike/barframe-apps/releases/download/checkharbor-v1.0.0/CheckHarbor-1.0.0.dmg) for macOS 14 or later. It is signed with Developer ID and notarized by Apple. The [release page](https://github.com/theluckystrike/barframe-apps/releases/tag/checkharbor-v1.0.0) lists its SHA-256.

## Install with Homebrew

```sh
brew install --cask theluckystrike/barframe/checkharbor
```

The cask comes from the [barframe tap](https://github.com/theluckystrike/homebrew-barframe). It installs the same signed and notarized disk image as the download link.

## Requirements

- macOS 14.0 or later.
- Sandboxed. Network access to api.github.com, to read the workflow runs of repositories you add.
- Public repositories need no token. Private repositories need a fine grained token with Actions read access. The token is stored in the Keychain.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/CheckHarbor
swift build -c release
```

The package depends on `../../kit/MASKit` by path. Clone the whole repository, so that the folder layout stays the same.

## Privacy

Repository names, run data and episodes stay on your Mac, and the optional token stays in the Keychain. Requests go only to api.github.com, and the app never fetches source code or workflow logs. Full policy: [store/privacy.md](store/privacy.md).

## Support this work

This app is free and open source. If it saves you time, you can support more apps like it through [GitHub Sponsors](https://github.com/sponsors/theluckystrike), [PayPal](https://paypal.me/najzzz) or [Buy Me a Coffee](https://buymeacoffee.com/michaellip).

More free apps and tools by the author are at https://barframe.com/projects/.

## License

MIT. See [LICENSE](../../LICENSE).
