#!/usr/bin/env python3
"""Run P9 Godot acceptance against a fresh isolated copy, including editor imports."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--script', default='tests/P9InputNight.gd')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--realtime', action='store_true', help='Use wall time for native frame and input measurements')
    parser.add_argument('--scene', help='Run a historical test scene in the same isolated copy')
    parser.add_argument('--input', choices=['pad', 'mouse'], default='pad')
    parser.add_argument('--state', help='Existing isolated state directory under /tmp/ye-ci-p9-* for restart verification')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    script = (repo / args.script).resolve()
    if not script.is_relative_to(repo) or not script.is_file():
        parser.error('Script must be an existing file in this repository')
    out = Path(tempfile.mkdtemp(prefix='ye-ci-p9-', dir='/tmp')).resolve()
    project = out / 'project'
    state = Path(args.state).resolve() if args.state else out / 'state'
    if state.parent.parent != out.parent or not state.parent.name.startswith('ye-ci-p9-') or state.name != 'state':
        parser.error('State must be an isolated P9 temp directory')
    state.mkdir(exist_ok=True)
    project.mkdir()
    for name in ('src', 'data', 'scenes', 'resources', 'assets', 'tests', 'tools'):
        shutil.copytree(repo / name, project / name, ignore=shutil.ignore_patterns('__pycache__'))
    for name in ['project.godot', 'default_bus_layout.tres']:
        shutil.copy2(repo / name, project / name)
    (project / 'docs/phase-reports').mkdir(parents=True)
    config = project / 'project.godot'
    config.write_text(config.read_text().replace('config/custom_user_dir_name="ye-ci"', 'config/custom_user_dir_name="'+out.name+'"'))
    for source in (project / 'src').rglob('*.gd'):
        src = source.read_text()
        if 'user://' in src:
            source.write_text(src.replace('user://', str(state) + '/'))
    print(out, flush=True)
    engine = [str(repo / 'tools/godot.sh'), '--path', str(project)]
    subprocess.run(engine + ['--headless', '--import', '--log-file', str(out / 'import.log')],
                   cwd=project, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, timeout=240)
    log = out / 'run.log'
    launch = ['--script', 'res://' + str(script.relative_to(repo))]
    tail = [str(out), args.input]
    if args.scene:
        scene = (repo / args.scene).resolve()
        if not scene.is_relative_to(repo/'tests') or not scene.is_file():
            parser.error('Expected repository test scene')
        launch = ['res://' + str(scene.relative_to(repo))]
        tail = ['--report-prefix=p9-' + scene.stem.lower()]
    command = engine + ([] if args.native else ['--headless']) + [
        *([] if args.realtime else ['--fixed-fps', '60']), *launch, '--log-file', str(log), '--', *tail]
    env = dict(os.environ, P9_EVIDENCE=str(out))
    with (out / 'console.log').open('w') as console:
        result = subprocess.run(command, cwd=project, env=env, timeout=900, stdout=console, stderr=console)
    errors = [line for file in [log, out/'import.log'] for line in file.read_text().splitlines()
              if 'SCRIPT ERROR' in line or line.startswith(('ERROR:', 'FAIL '))]
    print(json.dumps({'output': str(out), 'exit_code': result.returncode, 'errors': errors[:12]}, ensure_ascii=False))
    return int(result.returncode != 0 or bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
