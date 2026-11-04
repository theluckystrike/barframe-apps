# Barframe apps

This repository holds the source code for 20 small Mac menu bar apps by Michael Lip. Each app is a Swift package built with SwiftUI and AppKit. Most apps share one small helper package, `kit/MASKit`.

All code is under the MIT License. See [LICENSE](LICENSE).

## Apps

| App | What it does | Requires |
|---|---|---|
| [CacheSlope](apps/CacheSlope/) | Find folders that keep growing | macOS 14.0 |
| [CallReady](apps/CallReady/) | Next call, mic guard and mute key | macOS 14.0 |
| [CheckHarbor](apps/CheckHarbor/) | Track builds until recovery | macOS 14.0 |
| [CostBar](apps/CostBar/) | AI API cost & budget monitor | macOS 14.0 |
| [Headroom Agent Memory](apps/Headroom/) | Memory pressure & swap budget | macOS 14.0 |
| [HushKey Mic Mute Hotkey](apps/HushKey/) | Hold to talk, release to mute | macOS 14.0 |
| [KeyOverlap](apps/KeyOverlap/) | Check shortcut plan conflicts | macOS 14.0 |
| [MarkShot Screenshot Markup](apps/MarkShot/) | Arrows, annotations and steps | macOS 14.0 |
| [MeetNext](apps/MeetNext/) | Meeting countdown & timeline | macOS 14.0 |
| [NativeLedger](apps/NativeLedger/) | Automatic app update ledger | macOS 14.0 |
| [PermitPeek](apps/PermitPeek/) | See app permission changes | macOS 14.0 |
| [PortSense](apps/PortSense/) | Charger wattage & USB devices | macOS 14.0 |
| [QuotaPace](apps/QuotaPace/) | Token pace & usage limits | macOS 14.0 |
| [RelayNook](apps/RelayNook/) | Coding agent alerts & hooks | macOS 14.0 |
| [ReminderVault](apps/ReminderVault/) | Markdown tasks and reminders | macOS 14.0 |
| [RevPulse Revenue at a Glance](apps/RevPulse/) | Net payments in your menu bar | macOS 14.0 |
| [RouteLoom Connection Report](apps/RouteLoom/) | Compare connection failures | macOS 14.0 |
| [ShelfDock](apps/ShelfDrop/) | Drag & drop file staging | macOS 14.0 |
| [Starglass Night Sky Planner](apps/Starglass/) | Cloud and moon night planner | macOS 14.0 |
| [StepQuay](apps/StepQuay/) | Resume your next small task | macOS 14.0 |

## Build an app

You need Xcode 16 or later (Swift 5.9 or later) on macOS 14 or later.

```sh
cd apps/CostBar
swift build -c release
swift test
```

Most packages refer to `../../kit/MASKit`. Keep the folder layout when you copy an app.

Some scripts in `apps/*/scripts` are release helpers for the author's own signing setup. You do not need them to build or run an app.

## Status

These apps were made for the Mac App Store. They are not on sale there now. The code is published so that anyone can build, use, study or change it. CallReady also has a notarized direct download at https://barframe.com/apps/callready/download/.

## Related

- Frit, a glaze recipe book for potters: https://github.com/theluckystrike/frit
- Website: https://barframe.com/open-source/

## Contact

Open an issue in this repository. Email: support@barframe.com.
