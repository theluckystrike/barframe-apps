# MeetNext

MeetNext is a Mac menu bar app that shows your next meeting with a live countdown and a Join button.

<img src="store/screenshots/readme-01-next-meeting.png" alt="MeetNext popover with sample events, showing today's timeline, the next meeting with a Join Google Meet button and the next five events">

## Features

- Shows the next meeting title and a countdown in the menu bar. Click it to see today's busy periods on a timeline with a marker for the current time, and the start times of your next five events.
- Finds Zoom, Google Meet, Microsoft Teams and Webex links in the event URL, location and notes. Join opens the next meeting's link in your browser or meeting app.
- Reads events for today and tomorrow from the calendars you choose in Settings. It leaves out all-day events and events with no duration.
- Sends optional local reminders 5, 10 or 15 minutes before a meeting.
- Includes sample mode with example events, so you can try the app without calendar access.

## Download

Download [MeetNext-1.0.0.dmg](https://github.com/theluckystrike/barframe-apps/releases/download/meetnext-v1.0.0/MeetNext-1.0.0.dmg) for macOS 14 or later. It is signed with Developer ID and notarized by Apple. The [release page](https://github.com/theluckystrike/barframe-apps/releases/tag/meetnext-v1.0.0) lists its SHA-256.

## Install with Homebrew

```sh
brew install --cask theluckystrike/barframe/meetnext
```

The cask comes from the [barframe tap](https://github.com/theluckystrike/homebrew-barframe). It installs the same signed and notarized disk image as the download link.

## Requirements

- macOS 14.0 or later.
- Sandboxed. Full access to your calendars, which macOS asks you to allow.
- Notification permission, only if you turn on reminders.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/MeetNext
swift build -c release
```

The package depends on `../../kit/MASKit` by path. Clone the whole repository, so that the folder layout stays the same.

## Privacy

MeetNext processes calendar events on your Mac and keeps their contents in memory. It has no account, analytics or developer data collection. Full policy: [store/privacy.md](store/privacy.md).

## Support this work

This app is free and open source. If it saves you time, you can support more apps like it through [GitHub Sponsors](https://github.com/sponsors/theluckystrike), [PayPal](https://paypal.me/najzzz) or [Buy Me a Coffee](https://buymeacoffee.com/michaellip).

More free apps and tools by the author are at https://barframe.com/projects/.

## License

MIT. See [LICENSE](../../LICENSE).
