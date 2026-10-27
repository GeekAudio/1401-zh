#!/usr/bin/env python3
"""CI-only snapshot synchronization; preserve downstream overlays, fail on incompatible upstream."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import urllib.request
import urllib.error
from apply import apply, ROOT, CONFIG

def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Snapshot sync runs only in an ephemeral GitHub Actions checkout. Use apply.py locally.')
    run('git', 'fetch', '--no-tags', 'https://github.com/' + CONFIG['upstream_repository'] + '.git', 'main')
    ref = run('git', 'rev-parse', 'FETCH_HEAD')
    with urllib.request.urlopen('https://api.github.com/repos/' + CONFIG['driver_repository'] + '/releases/latest', timeout=30) as response:
        driver = json.load(response)
    state = json.loads((ROOT / 'downstream/state.json').read_text())
    force = os.environ.get('FORCE_BUILD') == 'true'
    changed = force or state['upstream_sha'] != ref or state.get('driver_release_tag') != driver['tag_name']
    # Retry incomplete releases even if a previous run saved the synchronized source commit.
    try:
        with urllib.request.urlopen('https://api.github.com/repos/' + CONFIG['repository'] + '/releases/latest', timeout=30) as response:
            current = json.load(response)
        changed = changed or current['tag_name'] != 'v' + state['app_version']
    except urllib.error.HTTPError as error:
        if error.code != 404: raise
        changed = True
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('changed=' + str(changed).lower() + '\n')
    if not changed:
        print('Upstream source and driver release are unchanged.'); return
    with tempfile.TemporaryDirectory() as temporary:
        saved = pathlib.Path(temporary)
        shutil.copytree(ROOT / 'downstream', saved / 'downstream')
        shutil.copytree(ROOT / '.github/workflows', saved / 'workflows')
        run('git', 'read-tree', '--reset', '-u', ref)
        shutil.copytree(saved / 'downstream', ROOT / 'downstream', dirs_exist_ok=True)
        shutil.rmtree(ROOT / '.github/workflows', ignore_errors=True)
        shutil.copytree(saved / 'workflows', ROOT / '.github/workflows')
    apply(ref, int(os.environ['GITHUB_RUN_NUMBER']))
    state = json.loads((ROOT / 'downstream/state.json').read_text())
    state['driver_release_tag'] = driver['tag_name']
    (ROOT / 'downstream/state.json').write_text(json.dumps(state, indent=2) + '\n')
    print('Prepared upstream', ref, 'and driver', driver['tag_name'])

if __name__ == '__main__': main()
