#!/usr/bin/env python3
"""Build a universal macOS test installer from the public Release app."""
import argparse
import hashlib
import html
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_NAME = 'CampusGo Ultra.app'
WIDGET_PATH = Path('Contents/PlugIns/CampusGoUltraWidget.appex')
PACKAGE_ID = 'com.campusschedule.mac.installer'


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output.resolve()
    if not app.is_dir() or output.suffix != '.pkg' or output.exists():
        parser.error('Provide an existing Release app and a new .pkg output path.')
    if any(app.rglob('WindowPet.*')) or any(app.rglob('embedded.provisionprofile')):
        parser.error('Build the public source without private resources or provisioning profiles.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CampusAppGroup'] != 'group.com.campusschedule.shared':
        parser.error('The app must use the public App Group configuration.')
    widget_info = plistlib.loads((app / WIDGET_PATH / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if widget_info['CFBundleShortVersionString'] != version or widget_info['CampusAppGroup'] != info['CampusAppGroup']:
        parser.error('App and widget versions and App Groups must match.')

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='campusgo-pkg-') as temporary:
        work = Path(temporary)
        payload = work / 'payload'
        resources = work / 'resources'
        payload.mkdir()
        resources.mkdir()
        bundled = payload / APP_NAME
        run('ditto', str(app), str(bundled))
        for bundle, manifest, entitlement_name in [
            (bundled / WIDGET_PATH, widget_info, 'Widget.entitlements'),
            (bundled, info, 'App.entitlements'),
        ]:
            executable = bundle / 'Contents/MacOS' / manifest['CFBundleExecutable']
            archs = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
            if not {'arm64', 'x86_64'}.issubset(archs):
                parser.error(f'Expected a universal Mach-O: {executable}')
            entitlements = plistlib.loads((ROOT / 'Configuration' / entitlement_name).read_bytes())
            entitlements['com.apple.security.application-groups'] = [info['CampusAppGroup']]
            entitlement_file = work / entitlement_name
            entitlement_file.write_bytes(plistlib.dumps(entitlements))
            run('codesign', '--force', '--sign', '-', '--timestamp=none', '--options', 'runtime',
                '--entitlements', str(entitlement_file), str(bundle))
        run('codesign', '--verify', '--deep', '--strict', str(bundled))

        components = work / 'components.plist'
        components.write_bytes(plistlib.dumps([{
            'RootRelativeBundlePath': APP_NAME,
            'BundleIsRelocatable': False,
            'BundleIsVersionChecked': True,
            'BundleHasStrictIdentifier': True,
            'BundleOverwriteAction': 'upgrade',
        }]))
        component = work / 'CampusGoUltra-component.pkg'
        run('pkgbuild', '--root', str(payload), '--component-plist', str(components),
            '--identifier', PACKAGE_ID, '--version', version, '--install-location', '/Applications', str(component))

        (resources / 'Welcome.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<title>CampusGo Ultra 安装说明</title><body style="font: 14px -apple-system, sans-serif">
<h1>CampusGo Ultra macOS 测试版</h1>
<p>安装前请退出旧版本。安装器会将应用放入「应用程序」文件夹。</p>
<p>此安装器没有 Developer ID 签名，应用使用临时签名，未经 Apple 公证。</p>
<p>若 macOS 阻止打开，确认文件来自官方 Release 且校验值一致后，请在「系统设置 → 隐私与安全性」中为该安装器或应用选择「仍要打开」。小组件的共享数据权限可能因设备而异。</p>
</body></html>''', encoding='utf-8')
        shutil.copyfile(ROOT / 'LICENSE', resources / 'License.txt')
        distribution = work / 'Distribution.xml'
        distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>CampusGo Ultra {html.escape(version)}</title>
    <welcome file="Welcome.html" mime-type="text/html"/>
    <license file="License.txt" mime-type="text/plain"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
    <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    <choices-outline><line choice="app"/></choices-outline>
    <choice id="app" visible="false"><pkg-ref id="{PACKAGE_ID}"/></choice>
    <pkg-ref id="{PACKAGE_ID}" version="{html.escape(version, quote=True)}">{component.name}</pkg-ref>
</installer-gui-script>
''', encoding='utf-8')
        run('productbuild', '--distribution', str(distribution), '--package-path', str(work),
            '--resources', str(resources), str(output))

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (output.parent / 'SHA256SUMS.txt').write_text(f'{digest}  {output.name}\n', encoding='utf-8')
    print(f'Created {output.name} (unsigned installer; ad-hoc signed app)')


if __name__ == '__main__':
    main()
