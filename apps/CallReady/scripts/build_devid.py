#!/usr/bin/env python3
"""Build CallReady for direct download: Developer ID, Hardened Runtime, App Sandbox, notarized and stapled DMG.

It never uploads to App Store Connect. notarytool is the only network call.
Usage: python3 -I scripts/build_devid.py <out_dir> [--no-notarize]
Writes <out_dir>/CallReady.app, <out_dir>/CallReady-<version>.dmg, <out_dir>/logs/* and <out_dir>/devid-receipt.json.
"""
import hashlib, json, os, plistlib, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_release as mas  # reuse the universal bundle build (arm64 + x86_64, lipo)

TEAM = mas.TEAM; NAME = mas.NAME; BID = mas.BID
IDENTITY = 'Developer ID Application: Michael Lip (' + TEAM + ')'
# Same entitlements as the MAS build minus the profile-backed identifiers (no provisioning profile for Developer ID).
ENTITLEMENTS = {'com.apple.security.app-sandbox': True, 'com.apple.security.personal-information.calendars': True}
KIT = Path.home() / 'mas6/kit'


def safe_remove(path):
    path = Path(path)
    if not path.exists(): return
    args = ['lsof', '-t'] + (['+D', str(path)] if path.is_dir() else ['--', str(path)])
    check = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if check.returncode not in (0, 1) or check.stdout.strip():
        raise RuntimeError('Refusing removal of open or unchecked path ' + str(path))
    size = sum(p.stat().st_size for p in path.rglob('*') if p.is_file() and not p.is_symlink()) if path.is_dir() else path.stat().st_size
    with (mas.BUILD / 'deletions-manifest.txt').open('a') as manifest:
        manifest.write(f'{datetime.now().astimezone().isoformat()} {size} {path}\n')
    if path.is_dir(): shutil.rmtree(path)
    else: path.unlink()


def notary_args():
    sys.path.insert(0, str(KIT))
    import asc_meta
    asc_meta.load_credentials()
    return ['--key', os.environ['ASC_KEY_PATH'], '--key-id', os.environ['ASC_KEY_ID'], '--issuer', os.environ['ASC_ISSUER_ID']]


def notarize(path, log):
    out = mas.run(['xcrun', 'notarytool', 'submit', path, *notary_args(), '--wait', '--timeout', '40m', '--output-format', 'json'],
                  log, timeout=2700)
    result = json.loads(out[out.find('{'):])
    assert result.get('status') == 'Accepted', f'notarization not accepted: {result.get("status")} id {result.get("id")}'
    return result['id']


def sign(path, log, entitlements=None):
    args = ['codesign', '--force', '--sign', IDENTITY, '--options', 'runtime', '--timestamp']
    if entitlements: args += ['--entitlements', entitlements]
    mas.run(args + [path], log, timeout=300)


def make_dmg(app, out, version):
    stage = out / 'dmg-stage'
    if stage.exists(): safe_remove(stage)
    stage.mkdir()
    mas.run(['ditto', app, stage / app.name], 'ditto-stage.log')
    (stage / 'Applications').symlink_to('/Applications')
    dmg = out / f'{NAME}-{version}.dmg'
    if dmg.exists(): safe_remove(dmg)
    mas.run(['hdiutil', 'create', '-volname', NAME, '-srcfolder', stage, '-fs', 'HFS+', '-format', 'UDZO',
             '-imagekey', 'zlib-level=9', '-ov', dmg], 'hdiutil-create.log', timeout=600)
    safe_remove(stage)
    return dmg


def main():
    out = Path(sys.argv[1]).resolve()
    mas.BUILD = out; mas.LOGS = out / 'logs'; mas.LOGS.mkdir(parents=True, exist_ok=True)
    app, info = mas.build_bundle()
    version = info['CFBundleShortVersionString']
    entfile = out / 'devid-entitlements.plist'; entfile.write_bytes(plistlib.dumps(ENTITLEMENTS))
    mas.run(['chmod', '-R', 'u+rwX,go+rX,go-w', app], 'permissions.log')
    mas.run(['xattr', '-cr', app], 'xattr-clear.log')
    sign(app, 'codesign-app.log', entfile)
    mas.run(['codesign', '--verify', '--strict', '--deep', '--verbose=2', app], 'codesign-verify.log')
    dv = mas.run(['codesign', '-dv', '--verbose=4', app], 'codesign-dv.log')
    assert 'flags=0x10000(runtime)' in dv and 'TeamIdentifier=' + TEAM in dv, 'hardened runtime or team missing'
    signed = mas.run(['codesign', '-d', '--entitlements', ':-', app], 'codesign-entitlements.log')
    assert plistlib.loads(signed[signed.find('<?xml'):].encode()) == ENTITLEMENTS, 'signed entitlements differ'
    receipt = {'builtAt': datetime.now().astimezone().isoformat(), 'bundleID': BID, 'version': version,
               'build': info['CFBundleVersion'], 'minMacOS': info['LSMinimumSystemVersion'], 'identity': IDENTITY,
               'architectures': subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS' / NAME)], text=True).split(),
               'entitlements': ENTITLEMENTS}
    if '--no-notarize' not in sys.argv:
        zipped = out / f'{NAME}-app-notary.zip'
        mas.run(['ditto', '-c', '-k', '--keepParent', app, zipped], 'ditto-zip.log')
        receipt['appNotaryID'] = notarize(zipped, 'notarytool-app.log')
        safe_remove(zipped)
        mas.run(['xcrun', 'stapler', 'staple', app], 'stapler-app.log')
        mas.run(['xcrun', 'stapler', 'validate', app], 'stapler-validate-app.log')
    dmg = make_dmg(app, out, version)
    sign(dmg, 'codesign-dmg.log')
    if '--no-notarize' not in sys.argv:
        receipt['dmgNotaryID'] = notarize(dmg, 'notarytool-dmg.log')
        mas.run(['xcrun', 'stapler', 'staple', dmg], 'stapler-dmg.log')
        mas.run(['xcrun', 'stapler', 'validate', dmg], 'stapler-validate-dmg.log')
        mas.run(['spctl', '-a', '-vvv', '-t', 'exec', app], 'spctl-app.log')
        mas.run(['spctl', '-a', '-vvv', '-t', 'open', '--context', 'context:primary-signature', dmg], 'spctl-dmg.log')
    data = dmg.read_bytes()
    receipt.update(dmg=str(dmg), dmgBytes=len(data), dmgSHA256=hashlib.sha256(data).hexdigest())
    (out / 'devid-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=1))


if __name__ == '__main__':
    main()
