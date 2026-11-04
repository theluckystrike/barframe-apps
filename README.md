# Barframe apps

This repository holds the source code for 20 small Mac apps by Michael Lip. 19 of them run in the menu bar. NativeLedger is a regular window app. Each app is a Swift package built with SwiftUI and AppKit. Most apps share one small helper package, `kit/MASKit`.

All code is under the MIT License. See [LICENSE](LICENSE).

## Apps

| App | What it does | Requires | Screenshot |
|---|---|---|---|
| [CacheSlope](apps/CacheSlope/) | Find folders that keep growing | macOS 14.0 | <a href="apps/CacheSlope/"><img src="apps/CacheSlope/store/screenshots/01-growth.png" width="200" alt="CacheSlope screenshot"></a> |
| [CallReady](apps/CallReady/) | Next call, mic guard and mute key | macOS 14.0 | <a href="apps/CallReady/"><img src="apps/CallReady/assets/AppIcon-1024.png" width="64" alt="CallReady app icon"></a> |
| [CheckHarbor](apps/CheckHarbor/) | Track builds until recovery | macOS 14.0 | <a href="apps/CheckHarbor/"><img src="apps/CheckHarbor/store/screenshots/01-inbox.png" width="200" alt="CheckHarbor screenshot"></a> |
| [CostBar](apps/CostBar/) | AI API cost & budget monitor | macOS 14.0 | <a href="apps/CostBar/"><img src="apps/CostBar/store/screenshots/readme-build-3-04-provider-costs.png" width="200" alt="CostBar screenshot"></a> |
| [Headroom Agent Memory](apps/Headroom/) | Memory pressure & swap budget | macOS 14.0 | <a href="apps/Headroom/"><img src="apps/Headroom/store/screenshots/headroom-1.png" width="200" alt="Headroom screenshot"></a> |
| [HushKey Mic Mute Hotkey](apps/HushKey/) | Mic mute hotkey and push-to-talk | macOS 14.0 | <a href="apps/HushKey/"><img src="apps/HushKey/store/screenshots/01-menu-mic-state.png" width="200" alt="HushKey screenshot"></a> |
| [KeyOverlap](apps/KeyOverlap/) | Check shortcut plan conflicts | macOS 14.0 | <a href="apps/KeyOverlap/"><img src="apps/KeyOverlap/store/screenshots/01-scope-plan.png" width="200" alt="KeyOverlap screenshot"></a> |
| [MarkShot Screenshot Markup](apps/MarkShot/) | Arrows, annotations and steps | macOS 14.0 | <a href="apps/MarkShot/"><img src="apps/MarkShot/store/screenshots/01-markshot.png" width="200" alt="MarkShot screenshot"></a> |
| [MeetNext](apps/MeetNext/) | Meeting countdown & timeline | macOS 14.0 | <a href="apps/MeetNext/"><img src="apps/MeetNext/store/screenshots/readme-01-next-meeting.png" width="200" alt="MeetNext screenshot"></a> |
| [NativeLedger](apps/NativeLedger/) | Automatic app update ledger | macOS 14.0 | <a href="apps/NativeLedger/"><img src="apps/NativeLedger/store/screenshots/01-recent-changes.png" width="200" alt="NativeLedger screenshot"></a> |
| [PermitPeek](apps/PermitPeek/) | See app permission changes | macOS 14.0 | <a href="apps/PermitPeek/"><img src="apps/PermitPeek/store/screenshots/01-review.png" width="200" alt="PermitPeek screenshot"></a> |
| [PortSense](apps/PortSense/) | Charger wattage & USB devices | macOS 14.0 | <a href="apps/PortSense/"><img src="apps/PortSense/store/screenshots/readme-screenshot-01.png" width="200" alt="PortSense screenshot"></a> |
| [QuotaPace](apps/QuotaPace/) | Token pace & usage limits | macOS 14.0 | <a href="apps/QuotaPace/"><img src="apps/QuotaPace/store/screenshots/readme-screenshot-01.png" width="200" alt="QuotaPace screenshot"></a> |
| [RelayNook](apps/RelayNook/) | Coding agent alerts & hooks | macOS 14.0 | <a href="apps/RelayNook/"><img src="apps/RelayNook/store/screenshots/history.png" width="200" alt="RelayNook screenshot"></a> |
| [ReminderVault](apps/ReminderVault/) | Markdown tasks and reminders | macOS 14.0 | <a href="apps/ReminderVault/"><img src="apps/ReminderVault/store/screenshots/readme-02-preview.png" width="200" alt="ReminderVault screenshot"></a> |
| [RevPulse Revenue at a Glance](apps/RevPulse/) | Net payments in your menu bar | macOS 14.0 | <a href="apps/RevPulse/"><img src="apps/RevPulse/store/screenshots/readme-screenshot-01.png" width="200" alt="RevPulse screenshot"></a> |
| [RouteLoom Connection Report](apps/RouteLoom/) | Compare connection failures | macOS 14.0 | <a href="apps/RouteLoom/"><img src="apps/RouteLoom/store/screenshots/01-paired-observations.png" width="200" alt="RouteLoom screenshot"></a> |
| [ShelfDock](apps/ShelfDrop/) | Drag & drop file staging | macOS 14.0 | <a href="apps/ShelfDrop/"><img src="apps/ShelfDrop/store/screenshots/readme-screenshot-01.png" width="200" alt="ShelfDock screenshot"></a> |
| [Starglass Night Sky Planner](apps/Starglass/) | Cloud and moon night planner | macOS 14.0 | <a href="apps/Starglass/"><img src="apps/Starglass/store/screenshots/readme-01-tonight-score.png" width="200" alt="Starglass screenshot"></a> |
| [StepQuay](apps/StepQuay/) | Resume your next small task | macOS 14.0 | <a href="apps/StepQuay/"><img src="apps/StepQuay/store/screenshots/01-resume.png" width="200" alt="StepQuay screenshot"></a> |

Each app folder has a README with features, requirements, build steps and privacy notes.

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

- Website: https://barframe.com/open-source/

## Contact

Open an issue in this repository. Email: support@barframe.com.
