#!/usr/bin/env python3
"""Export in a disposable project copy; never alter developer template settings."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--template', type=Path,
                        help='Optional official windows_release_x86_64.exe for this exact Godot version')
    args = parser.parse_args()
    engine = args.godot.resolve()
    root = Path(__file__).resolve().parents[1]
    output = root / 'exports/windows'
    output.mkdir(parents=True, exist_ok=True)
    log = []
    with tempfile.TemporaryDirectory(prefix='ye-ci-export-') as temp:
        project = Path(temp) / 'project'
        shutil.copytree(root, project, ignore=shutil.ignore_patterns(
            '.git', '.godot', 'exports', 'builds', 'docs', '__pycache__'))
        if args.template:
            template = Path(temp) / 'windows_release_x86_64.exe'
            shutil.copy2(args.template.resolve(), template)
            preset = project / 'export_presets.cfg'
            content = preset.read_text()
            # JSON quoted strings are also valid Godot ConfigFile string values.
            content = content.replace('custom_template/release=""',
                                      'custom_template/release=' + json.dumps(str(template)))
            preset.write_text(content)
        for command in [
            [str(engine), '--headless', '--path', str(project), '--editor', '--import', '--quit'],
            [str(engine), '--headless', '--path', str(project), '--export-release',
             'Windows Desktop', str(output / 'ye-ci.exe')],
        ]:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            log.append(result.stdout)
            if result.returncode or 'SCRIPT ERROR:' in result.stdout or '\nERROR:' in result.stdout:
                (output / 'export.log').write_text('\n'.join(log))
                raise SystemExit(result.stdout)
    (output / 'export.log').write_text('\n'.join(log))
    files = {}
    for name in ['ye-ci.exe', 'ye-ci.pck']:
        p = output / name
        if not p.is_file():
            raise SystemExit('Missing exported artifact: ' + name)
        files[name] = {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    manifest = {'engine': version, 'files': files, 'windows_launch_verified': False}
    (root / 'docs/phase-reports/p0-export-results.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
