# RouteLoom privacy policy

Michael Lip provides RouteLoom. Endpoint settings and diagnostic history stay locally in the app sandbox on your Mac. RouteLoom has no telemetry, analytics, account system or developer backend.

Only active live sessions send HTTPS HEAD requests to the two endpoints you configure. DNS resolution and TLS negotiation follow normally. Endpoint servers see requests and your source IP. Redirects are not followed. Requests use ephemeral sessions without stored cookies, credentials or response caches. Response bodies are not stored. Certificate validation uses system defaults.

Sample mode uses fictional bundled observations and sends no requests. Sample sessions stay in memory separately from live history. Saved history includes hostnames and observations. Configuration stores complete endpoint URLs locally. Reports omit URL paths and query strings. Reports are copied only on your command. Other software with clipboard access may read copied reports.

Retention and deletion

Settings offers retention of 5, 20 or 50 recent live sessions. The default is 20. Older sessions are removed when the limit is reached or lowered. Each session stops at 1000 checks. Retained history and endpoint settings remain on this Mac until you clear them. Sample data is not saved to disk.

Choose Clear local data in Settings to stop requests and remove endpoint configuration and saved live history. Stop session also stops active requests. Quitting stops requests. No checks run while the Mac sleeps or the app is closed. Copied reports must be deleted separately from any destination where you pasted them. You can clear the clipboard by copying other text. Endpoint servers control their own request logs and retention.

Launch at login is optional and off by default. No location, Accessibility or packet capture permissions are requested. Opening website links uses your browser and the website privacy policy applies to that visit.

Privacy Policy https://barframe.com/apps/routeloom/privacy/
Support https://barframe.com/apps/routeloom/support/
