# CostBar privacy policy

Effective October 15, 2026.

CostBar reads the API credentials you enter and requests cost reports directly from OpenRouter, Anthropic, or OpenAI. Reports include the saved key's daily, weekly, monthly, and lifetime usage for OpenRouter, organization cost buckets for Anthropic and OpenAI, and account credit balances when an OpenRouter management key can read them. CostBar normalizes these reports to USD totals. It makes no inference requests. It does not request prompts, completions, or conversations from a provider.

Keys are stored only in the macOS Keychain. They are held in memory while an authenticated request runs and sent over HTTPS only to the selected provider. Credential fields are not written to preferences, screenshots, logs, exports, or analytics. Redirects are refused. Keys are not synced by CostBar.

Accounts & Credits gives each added account a separate identity, Keychain item, report, and connection state. These account credentials are separate from keys saved in the original Settings screen. Adding a manual-only account stores no key and makes no provider request for that account. Adding a reporting key enables its cost reports. Other connected accounts can continue their own requests.

In Accounts & Credits, display names, manual credit grants, expiry dates, workload eligibility, debt, subscription allowance observations, source notes, and token budgets stay in the app's sandbox container on this Mac. Manual balances and allowance percentages are your dated entries. They are not verified by the provider. Dollar credit, debt, reported spend, and subscription percentages remain separate facts.

Import log file reads only the local file you select. CostBar reads the selected file into local memory, with a 5 MB import limit, and parses JSON Lines to extract token usage. A selected log can contain prompts, conversation text, identifiers, or other content. The parser can read that content as part of the file, but keeps only token totals, counting-method information, record counts, and the import time. It does not retain or transmit the raw log, conversation content, message IDs, or file path. It does not scan your folders automatically. Token estimates are not billed spend or official provider quotas.

Export redacted report saves a JSON file at the location you choose. The typed export includes provider, reporting scope, pseudonymous account IDs, amounts, dates, connection status, manual observations, and token estimates. Account IDs use salted hashes; the export is pseudonymous, not anonymous. It excludes API keys, authentication tokens, original account IDs, display names, email addresses, source notes, source URLs, error text, raw logs, and file paths. Financial figures can still be sensitive. Check a report before you share it. CostBar does not upload it.

Non-secret preferences, budgets, notification identities, cached cost totals, and Accounts & Credits records remain in the app's sandbox container. In Accounts & Credits, Disconnect deletes that account's saved key and stops its reporting requests. It retains the last observation and manual records, with the report labelled unavailable. Remove account deletes its saved key, account record, reports, failures, grants, allowance observation, and token estimate. The original Remove key control in Settings deletes that provider's original Keychain entry and cached totals. It does not remove a separate Accounts & Credits account. Removing the app does not automatically remove Keychain entries. Use the relevant key or account removal controls first.

Diagnostic --smoke mode writes a local report of checks and uses a temporary credential that it deletes. --screenshots writes local images containing labelled documentation samples, not your keys.

CostBar sends nothing to the developer. There are no ads, analytics, tracking, developer servers, or third-party SDKs that collect data. Your connected provider receives your authenticated read-only requests and the network metadata needed to serve them under its own privacy policy.

Notifications are local and optional. Launch at login is optional and off by default. You can turn either off in Settings. For support, open Support in the app. It opens the hosted support page; you can also email support@barframe.com. Do not send API keys, raw logs, or unredacted account records in support requests. Developer: Michael Lip.

The original Sample mode uses bundled neutral documentation examples and makes no network requests. It never reads your live provider credentials. Fill sample key supplies an optional demo credential. Saving it uses separate Keychain items; connected demo items are removed when you exit Sample mode. Sample budgets, reports and simulated alert identities stay in memory and are discarded on exit. Send Sample notification explicitly requests macOS permission and sends a labeled local test notification; macOS controls banner visibility.

The separate Accounts & Credits synthetic sample makes no provider requests and uses no Keychain credentials. Its edits stay in memory. Exit Sample mode restores the saved live account workspace and discards the synthetic workspace.
