# CostBar

Former working name: BurnRate.

CostBar is a sandboxed macOS 14+ menu bar meter for AI API costs. It shows USD daily/monthly spend, today's mean spend per hour, a linear month-end forecast, provider-specific budgets, optional threshold notifications, and OpenRouter account credits when permitted. Select the provider in the popover. Open Settings using the footer or Command-comma. Escape closes the popover or settings window; Command-Q quits.

## Connect

Save a provider key in Settings → General. The field is secure and clears after save. Credentials live in Keychain only. Save & connect immediately fetches costs; refreshes repeat every five minutes while the app runs. Remove key also clears that provider's cached totals. Launch at login and notifications default to off. The app uses `SMAppService.mainApp` and `UNUserNotificationCenter`; permission errors are shown in Settings.

- OpenRouter: GET `/api/v1/key` returns costs for the saved key (BYOK excluded). GET `/api/v1/credits` returns account credits, requiring a management key. A credits permission failure leaves key spend available.
- Anthropic: GET `/v1/organizations/cost_report` needs a Console organization Admin key. Decimal strings are cents, divided by 100. Priority Tier is excluded by the provider. Enterprise Analytics keys use another API and are unsupported.
- OpenAI: GET `/v1/organization/costs` needs an organization Admin key with cost access. Amounts are dollars.

Each provider has its own budget and reporting scope. No inference requests are made. Budgets send reminders, not spending caps. Reports can lag. Periods use UTC. The hourly average divides today's reported costs by hours since UTC midnight, clamped to one hour. Month-end projection waits for at least three days and ten percent of the month, then divides month-to-date costs by elapsed time and multiplies by the actual UTC month length. It is an estimate, not an invoice. Cached totals appear immediately and stale data is labelled; previous-day values are withheld until refresh. Wake clears the display and cancels old request generations. Forecasts are hidden while updating or after a failed or stale report. OpenRouter also shows weekly and lifetime saved-key usage, separately from account credits. Coverage names each failed provider and never sums different scopes.

## Sandbox and privacy

The only requested entitlement is `com.apple.security.network.client`, needed for direct HTTPS GET cost reports. The kit adds `com.apple.security.app-sandbox`. No user file access, helper processes, or paid generation APIs are used. Secrets use `kSecClassGenericPassword` in the macOS login Keychain, with access controlled by the system. Non-secret totals and settings use container UserDefaults (`CA92.1` in the privacy manifest). HTTP sessions are ephemeral, do not cache responses or cookies, and refuse redirects to avoid credential forwarding. Request failures never display provider response bodies. Read [the privacy policy](store/privacy.md).

## Build and verification

Run from this directory with Command Line Tools, without Xcode:

```sh
swift scripts/make_icon.swift
sh scripts/sync_fixtures.sh
swift build
../../kit/swift_test.sh
bash ../../kit/make_app.sh .
python3 -I ../../kit/gate.py .
```

The universal ad-hoc signed app is `build/CostBar.app`. Launch it using `open build/CostBar.app`. The gate launches through LaunchServices to enforce the sandbox. `--smoke` checks Keychain add/read/update/delete, a free public OpenRouter models GET, documented fixtures read from the real bundle, projections, and an explicit Desktop permission denial. It writes `smoke.json` inside the container. `--screenshots` renders three PNGs using the actual popover and labelled fixture data. Tests never access the network. Fixture sources are recorded in `Tests/CostBarCoreTests/Fixtures/SOURCES.md`.

## Support and distribution

For authentication errors, verify the key type and organization cost-report permission. For connection errors, restore internet access and click Refresh. For notification issues, allow CostBar in System Settings → Notifications. For login items pending approval, enable CostBar in System Settings → General → Login Items. For unexpected cost differences, compare the same UTC time range and provider reporting scope with the provider billing dashboard.

Privacy: https://theluckystrike.github.io/mac-apps/costbar/privacy/
Support: https://theluckystrike.github.io/mac-apps/costbar/support/
Distribution signing remains required before submission. Do not share credentials with support.

Provider references from the original fixture provenance (not fetched in this port):
- https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key
- https://openrouter.ai/docs/api/api-reference/credits/get-credits
- https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs

## Sample and alert behavior

Choose **Try with sample data** in the empty state or General settings. All three providers have neutral bundled documentation data rebased to the current UTC period. Sample budgets and simulated alerts stay in memory; exiting restores live settings and cached totals. No private credentials or network are needed. Fill sample key enables real add/read/update/delete checks in separate Keychain items; Refresh uses the bundled report. Send Sample notification requests actual macOS permission and sends a labeled test banner. Connected demo keys are removed on exit. Account credits can be expanded in the popover. Live alerts occur once per provider, UTC month and threshold; changing only the budget amount does not reset delivery. Keychain operations run on a worker so authorization cannot block the UI. Pending login approval keeps the toggle on and can be cancelled.

Pricing decision: retain the $4.99 one-time purchase. Free with IAP was evaluated; this small utility has no locked feature tiers or purchase infrastructure.

Brand decisions remain with the owner. The kit reads ../../brand.env, generates a local com.unfinalized bundle identifier, and keeps {DOMAIN} URLs until final values are selected. Current URLs cannot establish working public destinations. No submission occurred.

Screenshot rules: each headline has 4–7 words. The three screenshots use Sample-labelled neutral data and show spend metrics, an actual-spend budget alert preview, and account credits. The app has no activity lists; provider selectors reflect the three supported providers rather than invented sample accounts.

Privacy Policy and Support remain available in the popover and About through bundled native sheets while the public domain is pending. The final domain uses the kit-generated hosted links. Screenshots show the production popover at its real 360-point width, rendered at 2x for Retina.
