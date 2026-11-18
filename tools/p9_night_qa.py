#!/usr/bin/env python3
"""Exercise the night pages in a disposable source mirror with native Godot rendering."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="an empty directory under /tmp")
    args = parser.parse_args()
    scratch = Path(tempfile.gettempdir()).resolve()
    task_tmp = Path("/tmp").resolve()
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="ye-ci-p9-night-", dir=task_tmp))
    if not (output.is_relative_to(task_tmp) or output.is_relative_to(scratch)):
        parser.error("output must be beneath /tmp or the system temporary directory")
    if output.exists() and any(output.iterdir()):
        parser.error("output must be empty")
    output.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[1]
    project = output / "project"
    project.mkdir()
    state = output / "state"
    state.mkdir()
    for part in ("src", "assets", "data", "scenes", "resources"):
        shutil.copytree(repo / part, project / part)
    for name in ("project.godot", "default_bus_layout.tres"):
        shutil.copy2(repo / name, project / name)
    config = project / "project.godot"
    original = config.read_text()
    key = 'config/custom_user_dir_name="ye-ci"'
    if key not in original:
        raise RuntimeError("cannot isolate the engine's player directory")
    config.write_text(original.replace(key, f'config/custom_user_dir_name="ye-ci-p9-{uuid.uuid4().hex}"'))
    state_prefix = json.dumps(str(state) + "/", ensure_ascii=False)[1:-1]
    for source in (project / "src").rglob("*.gd"):
        code = source.read_text()
        if "user://" in code:
            source.write_text(code.replace("user://", state_prefix))

    command = [str(repo / "tools/godot.sh"), "--path", str(project)]
    for log, options in (
        ("import", ["--headless", "--import"]),
        ("native", ["--resolution", "1280x720", "--script", str(repo / "tools/p9_night_qa.gd"), "--", str(output)]),
    ):
        split = options.index("--") if "--" in options else len(options)
        with (output / f"{log}.stdout").open("w") as stdout:
            result = subprocess.run(
                [*command, *options[:split], "--log-file", str(output / f"{log}.log"), *options[split:]],
                cwd=project,
                timeout=180,
                stdout=stdout,
                stderr=subprocess.STDOUT,
            )
        runtime_log = output / f"{log}.stdout"
        if result.returncode != 0 or "SCRIPT ERROR" in runtime_log.read_text():
            raise SystemExit(f"{log} failed ({result.returncode}): {runtime_log}")
    print(output)


if __name__ == "__main__":
    main()
