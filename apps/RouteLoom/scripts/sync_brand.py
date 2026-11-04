#!/usr/bin/env python3
"""Refresh this app's URL overrides and seller from the shared brand data before building."""
from pathlib import Path
import json
import re

APP = Path(__file__).resolve().parent.parent
BRAND_FILE = APP.parent.parent / 'brand.env'
values = {}
for line in BRAND_FILE.read_text().splitlines():
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    key, value = line.split('=', 1)
    values[key] = value.strip().strip("\"'")
domain = values['DOMAIN']
base = 'https://' + domain + '/apps/routeloom/'
manifest_path = APP / 'mas.json'
manifest = json.loads(manifest_path.read_text())
manifest.update(privacy_url=base + 'privacy/', support_url=base + 'support/')
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
listing_path = APP / 'store/listing.json'
listing = json.loads(listing_path.read_text())
for field in ('privacy_url', 'privacy_policy'):
    listing[field] = base + 'privacy/'
for field in ('support_url', 'support'):
    listing[field] = base + 'support/'
listing['marketing_url'] = base
seller = values.get('SELLER_NAME', 'Michael Lip')
if '{' in seller or '}' in seller:
    seller = 'Michael Lip'
listing['copyright'] = '2026 ' + seller
# Keep tokenized provisional URLs in configuration fields, out of visible prose.
listing['description'] = re.sub(r'\nPrivacy Policy https://[^\s]+\nSupport https://[^\s]+\n', '\n', listing['description'])
listing_path.write_text(json.dumps(listing, indent=2) + '\n')
print('Refreshed RouteLoom URLs and seller from brand.env')
