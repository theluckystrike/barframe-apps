# Website deployment handoff

These artifacts are prepared locally. They have not been published.

Deploy site-product.html to https://barframe.com/apps/routeloom/ to address audit D1.
Deploy site-privacy.html to https://barframe.com/apps/routeloom/privacy/ to address audit D2.
The privacy page includes session limits, default retention, local deletion, stopping requests, clipboard copies and endpoint server log responsibility.
Keep https://barframe.com/apps/routeloom/support/ available. site-support.html contains the matching support guide.

After deployment, confirm all three URLs return HTTP 200 without redirects. Confirm the public privacy document contains Retention and deletion and Clear local data. Recheck metadata and the bundled plist against the current brand.env with scripts/sync_brand.py before rebuilding.

The A6 brief's later URL rule uses privacy and support subpages. The older base page only rule is superseded. No external account or credentials are needed to test the app's bundled Sample scenarios.
