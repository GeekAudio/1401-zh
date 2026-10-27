#!/usr/bin/env python3
"""Package only the fork app. Driver delivery remains the original upstream service."""
import hashlib
import json
import pathlib
import re
import os
import shutil
import subprocess
import urllib.request
from apply import ROOT, CONFIG

def sha(file):
    h = hashlib.sha256()
    with open(file, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def main():
    state = json.loads((ROOT / 'downstream/state.json').read_text())
    destination = ROOT / 'dist/release'; destination.mkdir(parents=True, exist_ok=True)
    for old in destination.iterdir():
        if old.is_file(): old.unlink()
    version = state['app_version']; app = ROOT / 'dist/1401 中文版.app'
    if not app.is_dir(): raise RuntimeError('Build the native app before packaging')
    archive = destination / f'1401-Mac-{version}.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(app), str(archive)], check=True)
    subprocess.run(['swift', str(ROOT / 'downstream/sign.swift'), 'sign', str(archive)], check=True)
    # The first published fork (2.6.2.2) requires a driver asset before it can discover
    # an app update. Keep that exact upstream package as a migration asset. New apps
    # still use the unchanged upstream driver URLs and update channel.
    driver_name = f'nullmoth-nvidia-{state["driver_version"]}.tar.gz'
    headers = {'Accept': 'application/vnd.github+json'}
    if os.environ.get('GH_TOKEN'): headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    endpoint = f'https://api.github.com/repos/{CONFIG["driver_repository"]}/releases/tags/v{state["driver_version"]}'
    with urllib.request.urlopen(urllib.request.Request(endpoint, headers=headers), timeout=30) as response:
        release = json.load(response)
    asset = next(item for item in release['assets'] if item['name'] == driver_name)
    driver = destination / driver_name
    with urllib.request.urlopen(asset['browser_download_url'], timeout=600) as response, driver.open('wb') as output:
        shutil.copyfileobj(response, output)
    pinned = re.search(r'struct Package \{.*?static let sha256 = "([a-f0-9]{64})"', (ROOT / 'mac/Sources/main.swift').read_text(), re.S).group(1)
    if sha(driver) != pinned: raise RuntimeError('Legacy migration driver differs from upstream source pin')
    stage = ROOT / 'dist/dmg'
    if stage.exists(): shutil.rmtree(stage)
    stage.mkdir()
    shutil.copytree(app, stage / app.name)
    for name in ('LICENSE', 'NOTICE.md', 'README.md'): shutil.copy2(ROOT / name, stage / name)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = destination / f'1401-Mac-{version}.dmg'
    subprocess.run(['hdiutil', 'create', '-volname', '1401 中文版', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(dmg)], check=True)
    info = {**state, 'repository': CONFIG['repository'], 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'scope': ['Chinese native UI', 'fork app self-update'], 'legacy_app_update_compatibility': driver_name, 'upstream_operations_unchanged': True, 'code_signing': 'ad-hoc', 'notarized': False, 'runtime_hardware_verified': False}
    (destination / 'build-info.json').write_text(json.dumps(info, indent=2, ensure_ascii=False) + '\n')
    sums = '\n'.join(sha(p) + '  ' + p.name for p in sorted(destination.iterdir()) if p.is_file() and p.name != 'SHA256SUMS.txt')
    (destination / 'SHA256SUMS.txt').write_text(sums + '\n')
    print('Packaged app', version)
if __name__ == '__main__': main()
