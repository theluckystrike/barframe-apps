#!/usr/bin/env python3
"""Regenerate app URL overrides from the shared brand file before building."""
from pathlib import Path
import json
app = Path(__file__).resolve().parents[1]
values = {}
for line in (app.parents[1] / 'brand.env').read_text().splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    key, value = line.split('=', 1)
    values[key] = value.strip().strip('"' + "'")
base = 'https://' + values['DOMAIN'] + '/apps/linksprig/'
for relative in ('mas.json', 'store/listing.json'):
    path = app / relative
    metadata = json.loads(path.read_text())
    metadata.update(privacy_url=base + 'privacy/', support_url=base + 'support/')
    if relative.startswith('store/'):
        metadata.update(privacy_policy=base + 'privacy/', support=base + 'support/',
                        marketing_url=base, copyright='2026 ' + values['SELLER_NAME'])
    path.write_text(json.dumps(metadata, indent=2) + '\n')
