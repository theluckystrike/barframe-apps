# Starglass Privacy

Starglass has no accounts, analytics, advertising or tracking SDKs. The developer does not operate a server receiving your app data.

City search sends the text you submit to Open-Meteo's geocoding service. Forecast requests send your chosen city's coordinates to Open-Meteo. Network requests also expose your IP address and standard connection metadata to that provider. Open-Meteo processes requests and may retain server logs under its own policy: https://open-meteo.com/en/terms . The provider currently states that server logs are deleted after 90 days. Provider retention is governed by that policy, not by Starglass.

Your selected city, settings and latest forecast remain in the app's local sandbox until replaced or cleared. Use Settings → Clear saved city and forecast to delete the saved city and cached forecast and cancel pending notifications. This does not delete logs held by Open-Meteo. Removing the app alone does not reliably remove its sandbox data. Other preferences can remain in the sandbox after clearing the city.

Astronomical calculations run locally. Notifications are optional, off by default, and scheduled through macOS only after you enable them and grant permission. Sample mode uses bundled synthetic weather without forecast or search requests.

Contact: support@barframe.com
Last updated: 2026-10-14
