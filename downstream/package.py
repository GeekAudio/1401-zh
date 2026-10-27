#!/usr/bin/env python3
"""Package only the fork app. Driver delivery remains the original upstream service."""
import hashlib
import json
import pathlib
import shutil
import subprocess
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
    stage = ROOT / 'dist/dmg'
    if stage.exists(): shutil.rmtree(stage)
    stage.mkdir()
    shutil.copytree(app, stage / app.name)
    for name in ('LICENSE', 'NOTICE.md', 'README.md'): shutil.copy2(ROOT / name, stage / name)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = destination / f'1401-Mac-{version}.dmg'
    subprocess.run(['hdiutil', 'create', '-volname', '1401 中文版', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(dmg)], check=True)
    info = {**state, 'repository': CONFIG['repository'], 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'scope': ['Chinese native UI', 'fork app self-update'], 'upstream_operations_unchanged': True, 'code_signing': 'ad-hoc', 'notarized': False, 'runtime_hardware_verified': False}
    (ROOT / 'dist/build-info.json').write_text(json.dumps(info, indent=2, ensure_ascii=False) + '\n')
    sums = '\n'.join(sha(p) + '  ' + p.name for p in sorted(destination.iterdir()) if p.is_file() and p.name != 'SHA256SUMS.txt')
    (destination / 'SHA256SUMS.txt').write_text(sums + '\n')
    expected = {archive.name, archive.name + '.sig', dmg.name, 'SHA256SUMS.txt'}
    if {p.name for p in destination.iterdir()} != expected:
        raise RuntimeError('Release may contain only the app archives and update verification files')
    print('Packaged app', version)
if __name__ == '__main__': main()
