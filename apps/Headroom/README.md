# Headroom Agent Memory

Headroom Agent Memory is a Mac menu bar app that estimates how many more coding agents fit in your Mac's memory.

![Headroom dashboard with sample data showing room for 5 more agents at normal memory pressure](store/screenshots/headroom-1.png)

![Headroom dashboard with sample data showing 0 more agents because swap is in use](store/screenshots/headroom-2.png)

## Features

- Estimates capacity as available memory minus a 4 GiB reserve, divided by the memory budget per agent that you set (0.5 to 16 GiB). Shows 0 when swap is in use or memory pressure is above normal. Shows no estimate when memory data is unavailable.
- Shows available memory, the memory pressure level and swap use. The reading refreshes every 5 seconds.
- Detects coding agents that run as your user by their executable name, such as claude, codex, gemini, aider and opencode. Script-hosted or unknown agents can be missed.
- Adds up the resident memory of the detected process trees. The value is marked partial when some processes cannot be read.
- Includes Sample mode with three scenarios: Balanced, Under pressure and Room to grow.

## Requirements

- macOS 14.0 or later.
- Sandboxed, with no other entitlements. The app has no network access and no file access. It reads system memory statistics and the process list of your own user.

## Build

You need Xcode 16 or later (Swift 6.0 or later).

```sh
cd apps/Headroom
swift build -c release
```

## Privacy

Memory statistics and process details are read on your Mac. Process names, paths and arguments are not saved or sent, and the app has no network access. Full policy: [store/privacy.md](store/privacy.md).

## License

MIT. See [LICENSE](../../LICENSE).

The app is a port of upstream Headroom code by Michael Lip, which is also under the MIT License, as stated in [UPSTREAM-LICENSE.txt](UPSTREAM-LICENSE.txt).
