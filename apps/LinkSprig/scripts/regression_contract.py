#!/usr/bin/env python3
"""Check product restrictions in the finished bundle and its store copy."""
from pathlib import Path
import json, subprocess, sys
app = Path(__file__).resolve().parents[1]
bundle = app / 'build/LinkSprig.app'
linked = subprocess.run(['otool', '-L', str(bundle / 'Contents/MacOS/LinkSprig')], check=True, capture_output=True, text=True).stdout
listing = json.loads((app / 'store/listing.json').read_text())
checks = {'noLoginLaunchFramework': '/ServiceManagement.framework/' not in linked,
          'noLoginLaunchStoreClaim': 'launch at login' not in listing['description'].lower(),
          'bundledFallbackPages': all(any(bundle.rglob(name + '.txt')) for name in ('privacy', 'privacy-es', 'support', 'support-es'))}
print(json.dumps(checks))
if len(sys.argv) > 1:
    Path(sys.argv[1]).write_text(json.dumps({'checks': checks, 'otool': linked}, indent=2) + '\n')
if not all(checks.values()):
    sys.exit(1)
