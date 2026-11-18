#!/usr/bin/env python3
"""Run the actual Boot/Night UI smoke against a temporary copy with isolated IO.

No game rules change: only three user:// storage destinations are substituted.
The GDScript fails closed before clicking a button if its Codex path is not isolated.
Results and native screenshots stay below the printed /tmp directory.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', help='New or empty absolute directory below /tmp')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = Path(args.output) if args.output else Path(tempfile.mkdtemp(prefix='ye-ci-p8-host-ui-', dir='/tmp'))
    if not str(output).startswith('/tmp/') or (output.exists() and any(output.iterdir())):
        parser.error('--output must be a new or empty absolute directory below /tmp')
    output.mkdir(parents=True, exist_ok=True)
    project = output / 'project'
    state = output / 'state'
    project.mkdir()
    state.mkdir()
    shutil.copy2(repo / 'project.godot', project / 'project.godot')
    shutil.copytree(repo / 'src', project / 'src')
    for name in ('assets', 'data', 'scenes', '.godot'):
        (project / name).symlink_to(repo / name, target_is_directory=True)
    substitutions = {
        'user://night_save.json': str(state / 'night.json'),
        'user://codex.json': str(state / 'codex.json'),
        'user://battle_replays': str(state / 'replays'),
    }
    for source in (project / 'src').rglob('*.gd'):
        original = source.read_text()
        isolated = original
        for old, new in substitutions.items():
            isolated = isolated.replace(old, new)
        if isolated != original:
            source.write_text(isolated)
    (output / 'isolation.json').write_text(json.dumps({'source': str(repo), 'substitutions': substitutions,
        'scope': 'Actual Boot/Night buttons, first battle only; not a complete night. No rules changed.'}, indent=2) + '\n')
    command = [str(repo / 'tools/godot.sh'), '--path', str(project), '--script', str(repo / 'tools/p8_host_ui_smoke.gd'),
        '--log-file', str(output / 'native.log'), '--', str(state)]
    answer = subprocess.run(command, cwd=repo, timeout=120)
    print('P8 host UI evidence:', output, flush=True)
    return answer.returncode


if __name__ == '__main__':
    raise SystemExit(main())
