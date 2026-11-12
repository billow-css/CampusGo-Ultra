#!/usr/bin/env python3
"""Package a privacy-clean universal app as an ad-hoc-signed, unnotarized DMG."""
import argparse
import hashlib
import html
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--app', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
args = p.parse_args()
app = args.app.resolve()
output = args.output.resolve()
assert app.is_dir(), 'Build the Release app first'
assert not output.exists(), 'Refusing to overwrite an existing DMG'
assert not list(app.rglob('WindowPet.png')), 'Private pet art must never enter the distribution'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
output.parent.mkdir(parents=True, exist_ok=True)
run = lambda command: subprocess.run(command, check=True)
with tempfile.TemporaryDirectory(prefix='campusgo-dmg-') as tmp:
    temp = Path(tmp)
    payload = temp / 'payload'
    payload.mkdir()
    bundled = payload / 'CampusGo Ultra.app'
    run(['ditto', str(app), str(bundled)])
    for binary in [bundled / 'Contents/MacOS/CampusGo Ultra', bundled / 'Contents/PlugIns/CampusGoUltraWidget.appex/Contents/MacOS/CampusGoUltraWidget']:
        archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        assert 'arm64' in archs and 'x86_64' in archs, f'Not universal: {binary}'
    group = info['CampusAppGroup']
    assert '$(' not in group
    for target, config in [(bundled / 'Contents/PlugIns/CampusGoUltraWidget.appex', 'Widget.entitlements'), (bundled, 'App.entitlements')]:
        entitlements = plistlib.loads((ROOT / 'Configuration' / config).read_bytes())
        entitlements['com.apple.security.application-groups'] = [group]
        entfile = temp / config
        entfile.write_bytes(plistlib.dumps(entitlements))
        run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--options', 'runtime', '--entitlements', str(entfile), str(target)])
    run(['codesign', '--verify', '--deep', '--strict', str(bundled)])
    (payload / 'Applications').symlink_to('/Applications', target_is_directory=True)
    guide = (ROOT / 'Docs/Installation.md').read_text()
    (payload / '安装说明（首次打开必读）.txt').write_text(guide)
    body = []
    for line in guide.splitlines():
        escaped = html.escape(line)
        if line.startswith('# '): body.append('<h1>' + escaped[2:] + '</h1>')
        elif line.startswith('## '): body.append('<h2>' + escaped[3:] + '</h2>')
        elif line.strip(): body.append('<p>' + escaped + '</p>')
    (payload / '安装说明.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>CampusGo Ultra 安装说明</title><style>body{font:16px/1.8 -apple-system,BlinkMacSystemFont,sans-serif;max-width:820px;margin:48px auto;padding:0 24px;color:#203042;background:#fff}h1{color:#00679c}h2{margin-top:36px}p{overflow-wrap:anywhere}</style>' + ''.join(body) + '</html>')
    for name in ['LICENSE', 'NOTICE']:
        shutil.copy2(ROOT / name, payload / name)
    run(['hdiutil', 'create', '-volname', 'CampusGo Ultra ' + version, '-srcfolder', str(payload), '-format', 'UDZO', '-ov', str(output)])
run(['hdiutil', 'verify', str(output)])
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
(output.parent / 'SHA256SUMS.txt').write_text(checksum + '  ' + output.name + '\n')
print('Created ' + output.name + ' (ad-hoc signed; NOT Apple notarized)')
