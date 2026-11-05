#!/usr/bin/env python3
"""Build, sign and package CallReady for the Mac App Store. It never uploads and never calls App Store Connect.

Usage: python3 -I scripts/build_release.py [--unsigned]
Writes build/CallReady.app, build/CallReady.pkg and build/logs/*.
"""
import hashlib, json, plistlib, shutil, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
BUILD = APP / 'build'; LOGS = BUILD / 'logs'
NAME = 'CallReady'; TEAM = '55R57JNHZX'; BID = 'com.michaellip.callready'  # 1.0.2: own bundle ID (1.0.1 and older shared com.michaellip.micanchor with MicAnchor)
PROFILE = Path.home() / 'mas6/profiles/callready.provisionprofile'  # Mac App Store builds only; Developer ID builds need no profile
KEYCHAIN = Path.home() / 'Library/Keychains/mas6.keychain-db'; UNLOCK = Path.home() / 'mas6/signing/keychain.pw'
APPSIGN = '3rd Party Mac Developer Application: Michael Lip (' + TEAM + ')'
PKGSIGN = '3rd Party Mac Developer Installer: Michael Lip (' + TEAM + ')'
ENV = dict(__import__('os').environ, DEVELOPER_DIR='/Library/Developer/CommandLineTools')

def run(args, log, timeout=900):
    with (LOGS / log).open('wb') as f:
        r = subprocess.run([str(a) for a in args], stdout=f, stderr=subprocess.STDOUT, timeout=timeout, cwd=APP, env=ENV)
    if r.returncode: raise SystemExit(f'{log} failed: exit {r.returncode}')
    return (LOGS / log).read_text(errors='replace')

def build_bundle():
    info = plistlib.loads((APP / 'Resources/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == BID and info['CFBundleExecutable'] == NAME
    assert not any(k.startswith('MAS') for k in info), 'template keys in Info.plist'
    bundle = BUILD / (NAME + '.app')
    if bundle.exists(): shutil.rmtree(bundle)
    (bundle / 'Contents/MacOS').mkdir(parents=True); (bundle / 'Contents/Resources').mkdir(parents=True)
    binaries = []
    for arch in ('arm64', 'x86_64'):
        # Check each slice separately. Free space can fall while the first slice builds.
        disk = subprocess.check_output(['df', '-g', '/System/Volumes/Data'], text=True, timeout=15)
        available_gb = int(disk.splitlines()[-1].split()[3])
        if available_gb < 20:
            raise SystemExit(f'Refusing {arch} build with {available_gb} GB free. Run the coldstore rules before retrying.')
        args = ['swift', 'build', '-c', 'release', '--product', NAME, '--triple', arch + '-apple-macosx14.0']
        text = run(args, f'swift-build-release-{arch}.log', timeout=1800)
        if 'warning:' in text: print(f'WARN warnings in {arch} build, see logs', flush=True)
        folder = Path(subprocess.check_output(args + ['--show-bin-path'], cwd=APP, text=True, env=ENV).strip())
        binaries.append(folder / NAME)
        if list(folder.glob('*.bundle')): raise SystemExit('unexpected resource bundle in release output')
    run(['lipo', '-create', *binaries, '-output', bundle / 'Contents/MacOS' / NAME], 'lipo.log')
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    (bundle / 'Contents/PkgInfo').write_text('APPL????')
    shutil.copy2(APP / 'Resources/PrivacyInfo.xcprivacy', bundle / 'Contents/Resources/PrivacyInfo.xcprivacy')
    shutil.copy2(APP / 'Resources/AppIcon.icns', bundle / 'Contents/Resources/AppIcon.icns')
    return bundle, info

def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    bundle, info = build_bundle()
    ent = plistlib.loads((APP / 'Resources/CallReady.entitlements').read_bytes())
    assert ent == {'com.apple.security.app-sandbox': True, 'com.apple.security.personal-information.calendars': True}, ent
    if '--unsigned' in sys.argv:
        run(['codesign', '--force', '--sign', '-', '--entitlements', APP / 'Resources/CallReady.entitlements', bundle], 'adhoc-sign.log')
        print('PASS unsigned (ad hoc) ' + str(bundle)); return
    p = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(PROFILE)]))
    assert p['ExpirationDate'] > datetime.now(timezone.utc).replace(tzinfo=None) and TEAM in p['TeamIdentifier']
    assert p['Entitlements']['com.apple.application-identifier'] == TEAM + '.' + BID
    assert not p.get('ProvisionedDevices') and not p.get('ProvisionsAllDevices') and not p['Entitlements'].get('get-task-allow')
    subprocess.run(['security', 'unlock-keychain', str(KEYCHAIN)], input=UNLOCK.read_bytes().strip() + b'\n', capture_output=True, check=True, timeout=15)
    identities = subprocess.check_output(['security', 'find-identity', '-v', str(KEYCHAIN)], text=True)
    assert APPSIGN in identities and PKGSIGN in identities, 'signing identities missing'
    requested = dict(ent, **{'com.apple.application-identifier': TEAM + '.' + BID, 'com.apple.developer.team-identifier': TEAM})
    entfile = BUILD / 'distribution-entitlements.plist'; entfile.write_bytes(plistlib.dumps(requested))
    shutil.copy2(PROFILE, bundle / 'Contents/embedded.provisionprofile')
    run(['chmod', '-R', 'u+rwX,go+rX,go-w', bundle], 'permissions.log')
    run(['xattr', '-cr', bundle], 'xattr-clear.log')
    run(['codesign', '--force', '--keychain', KEYCHAIN, '--sign', APPSIGN, '--entitlements', entfile, bundle], 'codesign-sign.log', timeout=300)
    run(['codesign', '--verify', '--strict', '--deep', '--verbose=2', bundle], 'codesign-verify.log')
    run(['codesign', '-dv', '--verbose=2', bundle], 'codesign-dv.log')
    signed = run(['codesign', '-d', '--entitlements', ':-', bundle], 'codesign-entitlements.log')
    start = signed.find('<?xml')
    assert start >= 0 and plistlib.loads(signed[start:].encode()) == requested, 'signed entitlements differ'
    pkg = BUILD / (NAME + '.pkg')
    if pkg.exists(): pkg.unlink()
    run(['productbuild', '--component', bundle, '/Applications', '--keychain', KEYCHAIN, '--sign', PKGSIGN, pkg], 'productbuild.log', timeout=300)
    sig = run(['pkgutil', '--check-signature', pkg], 'pkgutil-check-signature.log')
    assert 'Status: signed' in sig and PKGSIGN in sig, 'package signature not trusted'
    binary = bundle / 'Contents/MacOS' / NAME
    archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    receipt = {'builtAt': datetime.now().astimezone().isoformat(), 'bundleID': BID, 'version': info['CFBundleShortVersionString'],
               'build': info['CFBundleVersion'], 'architectures': archs, 'entitlements': requested,
               'executableSHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
               'package': str(pkg), 'packageSHA256': hashlib.sha256(pkg.read_bytes()).hexdigest(), 'packageBytes': pkg.stat().st_size,
               'uploaded': False}
    (BUILD / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=1))

if __name__ == '__main__':
    main()
