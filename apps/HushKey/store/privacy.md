# HushKey privacy summary

- No audio capture. The app never opens an input stream or records samples.
- CoreAudio device properties only: reads mute/volume state, writes mute (or volume 0) and default-device selection.
- Local storage only: preferences (UserDefaults) and per-device volume memory (JSON in the app container).
- No network connections, no analytics, no tracking.
- Privacy policy: https://theluckystrike.github.io/mac-apps/hushkey/privacy/

## Retention and deletion

Preferences and device memory remain on this Mac until you reset them. In Settings, choose “Reset Local Preferences and Device Memory” to clear saved shortcut, display and mode preferences and remembered device volumes. This does not change launch-at-login registration; turn that off separately in Settings.
