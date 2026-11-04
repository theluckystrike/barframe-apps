# Hook source templates

Copy installation-specific snippets from RelayNook Settings. Require the installation token. Keep the copied snippets private.

Use files in this directory as source templates. Supply AGENTPING_TOKEN in the shell environment before using the templates. Do not print the token. The app inserts its token into the snippets copied from Settings. The templates contain no installation credential.

Map Claude Code Notification permission/input matchers to waiting. Map Stop to done. Do not install SubagentStop because it does not finish the parent session. Map Codex agent-turn-complete to done. Do not claim Codex waiting detection.

Optional hooks use /usr/bin/perl with system JSON::PP and Encode modules to parse data and encode UTF-8 URLs. The app does not execute scripts.
