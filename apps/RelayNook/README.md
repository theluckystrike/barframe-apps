# RelayNook

Requires macOS 14. Source port from AgentPing; preserve the agentping URL scheme and AgentPing Swift module for hook compatibility. The installed bundle is RelayNook.app.

From this directory run `bash scripts/build.sh`, `bash scripts/test.sh`, or `python3 -I ../../kit/gate.py .`. The shared brand.env supplies the bundle prefix and URLs. Final brand and domain remain owner decisions.

Open `build/RelayNook.app`. Send test event works without any external agent. Settings offers notification kinds, sound, optional launch at login, privacy and support links, and setup snippets. Copy Terminal test command to exercise authenticated ingress. Keep copied tokens private. Regenerate token invalidates old hooks.

The app records up to 200 local events, counts waiting sessions by agent and session, rejects invalid tokens and malformed URLs, limits accepted events to 30 per minute, and coalesces identical notification content for ten seconds. Clear removes events and waiting identities; rejected count remains. Quit flushes pending history writes. No transcript inspection, remote event service, analytics, or process control.

Users install optional hooks themselves. Claude hooks report waiting or response completion. Codex notify reports turn completion only. Generic shell events support waiting, done, error and info. `python3 scripts/verify_snippets.py` runs generated snippets against fictional payloads without modifying agent configuration.

See store/review_notes.md for manual review steps and ../../units/A3-relay/audit.md for this port's self-audit. The screenshots show isolated Sample data across history, setup and security. No real history or installation token appears.
