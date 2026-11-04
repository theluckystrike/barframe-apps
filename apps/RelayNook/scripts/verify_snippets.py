#!/usr/bin/env python3
"""Run exact generated shell commands with fixture JSON. Replace open with echo."""
import json
import os
import pathlib
import shlex
import subprocess
import tempfile
import urllib.parse

root = pathlib.Path(__file__).resolve().parents[1]
setup = root / 'store/setup'
# Fixture credential. Never read or print a real installation token in this harness.
fixture_token = '0123456789abcdef0123456789abcdef'
env = dict(os.environ, AGENTPING_TOKEN=fixture_token)
for name in ['agentping-hook.sh', 'install-hook.sh', 'generic-function.sh']:
    subprocess.run(['/bin/sh', '-n', str(setup / name)], check=True)
claude = json.loads((setup / 'claude-settings.json').read_text())
assert set(claude['hooks']) == {'Notification', 'Stop'}
assert claude['hooks']['Notification'][0]['matcher'] == 'permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input'
notify = json.loads((setup / 'codex-config.toml').read_text().split('=', 1)[1])
title = "Fixture: ' \" & + # ? $(text) `text` ✓"

def validate(output, kind, agent, expected_title=title):
    assert output.startswith('-g agentping://event?')
    url = output.removeprefix('-g ').strip()
    fields = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query, keep_blank_values=True)
    assert fields['kind'] == [kind] and fields['agent'] == [agent]
    assert fields['title'] == [expected_title] and fields['token'] == [fixture_token]
    assert set(fields) == {'agent', 'kind', 'title', 'project', 'session', 'token'}

with tempfile.TemporaryDirectory(dir=root / 'build', prefix='snippet-fixtures-') as directory:
    directory = pathlib.Path(directory)
    exporter = root / 'build/export-snippets'
    subprocess.run(['/usr/bin/swiftc', '-parse-as-library', str(root / 'Sources/AgentPingCore/Snippets.swift'), str(root / 'scripts/export_snippets.swift'), '-o', str(exporter)], check=True)
    subprocess.run([str(exporter), str(directory), '--fixtures'], check=True)
    hook = directory / 'agentping-hook'
    install = (setup / 'install-hook.sh').read_text().replace('"$HOME/.local/bin"', shlex.quote(str(directory))).replace('"$HOME/.local/bin/agentping-hook"', shlex.quote(str(hook))).replace('/usr/bin/open -g', '/bin/echo -g')
    subprocess.run(['/bin/sh', '-c', install], env=env, check=True)
    assert hook.read_text().startswith('#!/bin/sh\n')
    assert hook.stat().st_mode & 0o777 == 0o700
    for name, kind in [('Notification', 'waiting'), ('Stop', 'done')]:
        command = claude['hooks'][name][0]['hooks'][0]['command'].replace('"$HOME/.local/bin/agentping-hook"', shlex.quote(str(hook)))
        payload = {'hook_event_name': name, 'session_id': 'fixture-claude', 'cwd': '/fixture & project', 'message': title, 'last_assistant_message': title, 'notification_type': 'permission_prompt'}
        output = subprocess.check_output(['/bin/sh', '-c', command], input=json.dumps(payload), text=True, env=env)
        validate(output, kind, 'Claude Code')
        print(f'PASS: exact Claude {name} settings command; JSON stdin; open -g URL; token; encoded metacharacters')
    codex = [x.replace('"$HOME/.local/bin/agentping-hook"', shlex.quote(str(hook))) for x in notify]
    payload = {'type': 'agent-turn-complete', 'thread-id': 'fixture-codex', 'cwd': '/fixture & project', 'last-assistant-message': title}
    output = subprocess.check_output(codex + [json.dumps(payload)], text=True, env=env)
    validate(output, 'done', 'Codex CLI')
    print('PASS: exact Codex notify argv; single JSON argument; done only; open -g URL; token')
    assert subprocess.check_output(codex + ['{"type":"approval-requested"}'], text=True, env=env) == ''
    payload = {'session_id': 'fixture-long', 'last_assistant_message': '🙂' * 300}
    output = subprocess.check_output(['/bin/sh', str(hook), 'done'], input=json.dumps(payload), text=True, env=env)
    validate(output, 'done', 'Claude Code', '🙂' * 240)
    for bad_payload in ['{invalid json', '{}', '[]', '{"session_id":"sample","message":{}}']:
        rejected = subprocess.run(['/bin/sh', str(hook), 'done'], input=bad_payload, text=True, env=env, capture_output=True)
        assert rejected.returncode != 0 and rejected.stdout == '', rejected
    print('PASS: malformed JSON, missing session and invalid field types fail without a URL')
    generic = (setup / 'generic-function.sh').read_text().replace('/usr/bin/open -g', '/bin/echo -g')
    command = generic + '\nagentping ' + ' '.join(shlex.quote(x) for x in ['fixture', 'error', title, '/fixture & project', 'fixture-generic'])
    output = subprocess.check_output(['/bin/sh', '-c', command], text=True, env=env)
    validate(output, 'error', 'fixture')
    print('PASS: exact generic function; five shell arguments; token; Unicode limit; unsupported Codex event ignored')
    # Test the bound snippets copied by Settings through the same Swift generator.
    bound = (directory / 'install-bound-hook.sh').read_text().replace('"$HOME/.local/bin"', shlex.quote(str(directory))).replace('"$HOME/.local/bin/agentping-hook"', shlex.quote(str(hook))).replace('/usr/bin/open -g', '/bin/echo -g')
    subprocess.run(['/bin/sh', '-c', bound], check=True)
    bound_env = dict(os.environ)
    bound_env.pop('AGENTPING_TOKEN', None)
    output = subprocess.check_output(codex + [json.dumps({'type': 'agent-turn-complete', 'thread-id': 'fixture-bound', 'last-assistant-message': title})], text=True, env=bound_env)
    validate(output, 'done', 'Codex CLI')
    generic = (directory / 'generic-bound-function.sh').read_text().replace('/usr/bin/open -g', '/bin/echo -g')
    command = generic + '\nagentping ' + ' '.join(shlex.quote(x) for x in ['fixture', 'error', title, '', 'fixture-bound'])
    validate(subprocess.check_output(['/bin/sh', '-c', command], text=True, env=bound_env), 'error', 'fixture')
    print('PASS: Settings-generated bound installer and generic function; embedded fixture token; no environment credential required')
print('PASS: shell syntax; installer permission 700; fixture-only harness; no agent configuration changed')
