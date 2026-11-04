# CallReady

CallReady is a Mac menu bar app that shows your next call, puts your preferred microphone back when a Bluetooth headset takes over, and mutes the microphone with one shortcut.

![CallReady app icon](assets/AppIcon-1024.png)

## Features

- Shows the next event from the calendars you select, with a countdown in the menu bar. Join opens the Zoom, Google Meet, Microsoft Teams or Webex link that it finds in the event URL, location or notes.
- When the default input is a Bluetooth microphone, or the default input is no longer available, sets the default input to your preferred microphone or the next backup in your list. It skips virtual and loopback devices. You can allow a Bluetooth microphone for 1 hour from the menu.
- Mutes and unmutes the default microphone with a global shortcut in any app. The default is Shift-Option-M. Push-to-talk and a floating mute badge are optional. For a microphone without a mute control, it sets the input volume to zero.
- Checks the microphone one minute before a call and again when you click Join. It can remind you one minute before a call if you are still muted.
- Optional call reminders 5, 10 or 15 minutes before a call, as local notifications.

## Download

A notarized build is on the [CallReady 1.0.1 release page](https://github.com/theluckystrike/barframe-apps/releases/tag/callready-v1.0.1).

## Requirements

- macOS 14.0 or later.
- Sandboxed. Calendar access to read events for the next call. CallReady never creates, changes or deletes events. The microphone and mute parts work without calendar access.
- No microphone permission. CallReady does not open an audio stream. It changes only the default input, its mute state and its input volume.
- Notification permission only if you turn on a call reminder or the mute reminder.
- Your calling app must use the system default input, for example "Same as System" in its audio settings.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/CallReady
swift build -c release
```

## Privacy

Calendar events and settings stay on your Mac. CallReady collects no data, has no analytics and makes no network connections of its own. It never records or listens to audio.

## License

MIT. See [LICENSE](../../LICENSE).
