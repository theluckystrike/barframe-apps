# RevPulse Revenue at a Glance

RevPulse is a Mac menu bar app that shows your Stripe net payments for the current UTC day.

<img src="store/screenshots/readme-screenshot-01.png" alt="RevPulse popover with sample data for today, yesterday, the last 7 days and the monthly goal">

## Features

- Shows today's net payments in the menu bar. The panel compares today with yesterday and draws a 7-day trend line.
- Lists month-to-date net payments, new customers, new subscriptions, failed payments and refunds, with progress toward a monthly goal that you set.
- Totals use payment and refund balance movements in your default settlement currency, with fees included. If it finds more than one settlement currency, it shows "Net unavailable" instead of adding them together.
- Refreshes every 1, 5, 15 or 30 minutes. Optional notifications for the first sale of the UTC day and for failed payments. Both start off.
- Includes Sample mode, so you can try the app without a Stripe key.

## Download

Download [RevPulse-1.0.0.dmg](https://github.com/theluckystrike/barframe-apps/releases/download/revpulse-v1.0.0/RevPulse-1.0.0.dmg) for macOS 14 or later. It is signed with Developer ID and notarized by Apple. The [release page](https://github.com/theluckystrike/barframe-apps/releases/tag/revpulse-v1.0.0) lists its SHA-256.

## Requirements

- macOS 14.0 or later.
- A Stripe restricted key (starts with `rk_`) with read access to charges, customers, subscriptions, refunds, balance transactions and account details.
- Sandboxed. Network access to api.stripe.com only. The key is stored in your macOS Keychain.

## Build

You need Xcode 16 or later (Swift 5.9 or later).

```sh
cd apps/RevPulse
swift build -c release
```

The package depends on `../../kit/MASKit` by path. Clone the whole repository, so that the folder layout stays the same.

## Privacy

The app sends read-only requests to api.stripe.com only. Revenue data stays in memory and is not written to disk. Settings stay in local preferences, and the key stays in your Keychain. Full policy: [store/privacy.md](store/privacy.md).

## Support this work

This app is free and open source. If it saves you time, you can support more apps like it through [GitHub Sponsors](https://github.com/sponsors/theluckystrike), [PayPal](https://paypal.me/najzzz) or [Buy Me a Coffee](https://buymeacoffee.com/michaellip).

More free apps and tools by the author are at https://barframe.com/projects/.

## License

MIT. See [LICENSE](../../LICENSE).
