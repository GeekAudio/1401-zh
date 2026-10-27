#!/usr/bin/env python3
"""Package our app and mirror hash-verified upstream driver archives."""
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import urllib.request
from apply import ROOT, CONFIG

def sha(file):
    h = hashlib.sha256()
    with open(file, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def fetch(url, target):
    if not url.startswith('https://'): raise ValueError('HTTPS required')
    with urllib.request.urlopen(url, timeout=600) as source, open(target, 'wb') as destination:
        shutil.copyfileobj(source, destination)

def main():
    state = json.loads((ROOT / 'downstream/state.json').read_text())
    destination = ROOT / 'dist/release'; destination.mkdir(parents=True, exist_ok=True)
    version = state['app_version']; app = ROOT / 'dist/1401 中文版.app'
    if not app.is_dir(): raise RuntimeError('Build the native app before packaging')
    archive = destination / f'1401-Mac-{version}.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(app), str(archive)], check=True)
    subprocess.run(['swift', str(ROOT / 'downstream/sign.swift'), 'sign', str(archive)], check=True)
    tags = {'v' + state['driver_version'], state.get('driver_release_tag', 'v' + state['driver_version'])}
    mirrored = []
    for tag in sorted(tags):
        url = f'https://api.github.com/repos/{CONFIG["driver_repository"]}/releases/tags/{tag}'
        with urllib.request.urlopen(url, timeout=30) as response: release = json.load(response)
        assets = {a['name']: a for a in release['assets']}
        checksums = next((a for name, a in assets.items() if name in ('SHA256SUMS.txt', 'SHA256SUMS')), None)
        if checksums is None: raise RuntimeError('Upstream release has no checksums: ' + tag)
        with urllib.request.urlopen(checksums['browser_download_url'], timeout=30) as response: lines = response.read().decode().splitlines()
        sums = {}
        for line in lines:
            fields = line.split()
            if len(fields) == 2 and re.fullmatch('[0-9a-fA-F]{64}', fields[0]): sums[fields[1].lstrip('*')] = fields[0].lower()
        for name, asset in assets.items():
            if not re.fullmatch(r'nullmoth-nvidia-\d+\.\d+(?:\.\d+)?\.tar\.gz', name): continue
            if name not in sums: raise RuntimeError('Driver missing from upstream checksums: ' + name)
            target = destination / name
            fetch(asset['browser_download_url'], target)
            if sha(target) != sums[name]: raise RuntimeError('Upstream checksum mismatch: ' + name)
            if name == f'nullmoth-nvidia-{state["driver_version"]}.tar.gz':
                source = (ROOT / 'mac/Sources/main.swift').read_text()
                pin = re.search(r'struct Package \{.*?static let sha256 = "([a-f0-9]+)"', source, re.S).group(1)
                if sha(target) != pin: raise RuntimeError('Driver differs from source pin')
            mirrored.append({'name': name, 'upstream_url': asset['browser_download_url'], 'sha256': sha(target), 'tag': tag})
    if not mirrored: raise RuntimeError('No driver packages were mirrored')
    stage = ROOT / 'dist/dmg'; stage.mkdir(exist_ok=True)
    for item in stage.iterdir():
        if item.is_dir(): shutil.rmtree(item)
        else: item.unlink()
    shutil.copytree(app, stage / app.name)
    pinned = destination / f'nullmoth-nvidia-{state["driver_version"]}.tar.gz'
    shutil.copy2(pinned, stage / pinned.name)
    for name in ('LICENSE', 'NOTICE.md', 'README.md'): shutil.copy2(ROOT / name, stage / name)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = destination / f'1401-Mac-{version}.dmg'
    subprocess.run(['hdiutil', 'create', '-volname', '1401 中文版', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(dmg)], check=True)
    info = {**state, 'repository': CONFIG['repository'], 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'drivers': mirrored, 'code_signing': 'ad-hoc', 'notarized': False, 'runtime_hardware_verified': False}
    (destination / 'build-info.json').write_text(json.dumps(info, indent=2, ensure_ascii=False) + '\n')
    (destination / 'channels.json').write_text(json.dumps({'stable': {'tag': 'v' + version}, 'prerelease': None}) + '\n')
    sums = '\n'.join(sha(p) + '  ' + p.name for p in sorted(destination.iterdir()) if p.is_file() and p.name != 'SHA256SUMS.txt')
    (destination / 'SHA256SUMS.txt').write_text(sums + '\n')
    print('Packaged', version)

if __name__ == '__main__': main()
