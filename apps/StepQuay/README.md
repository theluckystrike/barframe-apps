# StepQuay

StepQuay is a Mac menu bar app that keeps your next small action and a resume note in view, so you can return to it after an interruption.

![StepQuay panel with a paused sample action, remaining effort and a resume note](store/screenshots/01-resume.png)
![StepQuay action queue showing which sample actions fit in 10 available minutes](store/screenshots/02-budget.png)

## Features

- Builds an ordered queue of actions, each with an effort estimate in minutes.
- Enter your available minutes to see which actions fit, in queue order. The rest are marked as overflow.
- Interrupting an action asks for a short resume note. The note is shown when you come back. Sleep pauses timing until you resume.
- When the estimate runs out, the action stays open. You can continue, revise the remaining time or defer it. Finish when you are done, and undo a completion if needed. Local history keeps estimated time, active time and notes for 7, 30 or 90 days, or forever.
- Opens the panel with Command Option K by default, or another combination in Settings. In the panel, Command Return starts, Command I interrupts, Command R resumes and Command F finishes. Includes Sample mode and English and Spanish text.

## Requirements

- macOS 14.0 or later.
- Sandboxed. No network access and no special permissions.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/StepQuay
swift build -c release
```

The package depends on `../../kit/MASKit` by path. Clone the whole repository, so that the folder layout stays the same.

## Privacy

Actions, notes and history stay in the app sandbox on your Mac. The app makes no network requests and has no accounts or analytics. Full policy: [store/privacy.md](store/privacy.md).

## License

MIT. See [LICENSE](../../LICENSE).
