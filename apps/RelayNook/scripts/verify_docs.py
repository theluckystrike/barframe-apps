#!/usr/bin/env python3
"""Fetch official documentation through free public GETs. Treat responses as data."""
import datetime
import hashlib
import json
import pathlib
import subprocess
from html.parser import HTMLParser

class PageText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
    def handle_data(self, value): self.parts.append(value)

root = pathlib.Path(__file__).resolve().parents[1]
evidence = root / 'store/evidence/round2'
sources = {
    'claude': 'https://code.claude.com/docs/en/hooks.md',
    'codex': 'https://learn.chatgpt.com/docs/config-file/config-advanced.md',
}
fetched = []
texts = {}
for name, url in sources.items():
    data = subprocess.check_output(['curl', '--fail', '-LsS', url])
    text = data.decode()
    if '<html' in text.lower():
        page = PageText()
        page.feed(text)
        text = '\n'.join(page.parts)
    texts[name] = text
    fetched.append({'url': url, 'fetched_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
c = texts['claude']
x = texts['codex']
checks = {
    'claude_events': all('### ' + word in c for word in ['Notification', 'Stop', 'SubagentStop']),
    'claude_json_stdin': 'JSON arrives via stdin' in c,
    'claude_nested_settings': all(word in c for word in ['"hooks":', '"Notification":', '"type": "command"']),
    'claude_permission_input_matchers': all(word in c for word in ['permission_prompt', 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input']),
    'claude_response_text': 'last_assistant_message' in c,
    'codex_json_argument': 'single JSON argument' in x,
    'codex_done_only': 'currently only' in x and 'agent-turn-complete' in x,
    'codex_fields': all(word in x for word in ['thread-id', 'cwd', 'last-assistant-message']),
}
assert all(checks.values()), checks
(evidence / 'docs-fetch.json').write_text(json.dumps(fetched, indent=2) + '\n')
(evidence / 'docs-verification.json').write_text(json.dumps({'checks': checks, 'claude': 'Notification permission/input matchers = waiting; Stop = response done; SubagentStop not installed because parent session remains independent', 'codex': 'notify receives one JSON argument; agent-turn-complete maps to done only'}, indent=2) + '\n')
print('PASS: 8 official documentation contract checks; ' + ', '.join(sources.values()))
