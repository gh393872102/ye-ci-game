#!/usr/bin/env python3
"""Run P11 live-combat audio checks with temporary settings and capture the mixer."""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path


SHOWCASE = [
    ("SFX01", "01-start", 1.10), ("SFX02", "02-door-critical", 0.72),
    ("SFX03", "03-beam-climb", 0.91), ("SFX04", "04-water-entry", 0.95),
    ("SFX05", "05-guard-ledger", 0.85), ("SFX06", "06-footsteps", 2.25),
    ("SFX07", "07-register-brush", 0.62), ("SFX08", "08-tide-flood", 1.40),
    ("SFX09", "09-upper-pounce", 1.00), ("SFX10", "10-extinguish", 1.35),
    ("SFX11", "11-new-face", 1.46), ("SFX12", "12-iron-shoulder", 0.94),
]
QUIET_PAIR = [(ritual + " " + skill, ritual + "-" + skill, 1.70)
              for skill in ("gong", "bell", "cry") for ritual in ("R01", "R07")]


def mixed_excerpt(output, destination, plan):
    pcm = bytearray()
    chapters = []
    gap = None
    format_info = None
    for name, source, length in plan:
        with wave.open(str(output / (source + ".wav")), "rb") as audio:
            channels, width, rate = audio.getparams()[:3]
            current_format = channels, width, rate
            if format_info is None:
                format_info = current_format
            if current_format != format_info:
                raise ValueError("Mixer capture formats changed within one run")
            frame_bytes = channels * width
            gap = bytes(round(rate * 0.24) * frame_bytes)
            data = audio.readframes(round(rate * length))
            chapters.append({
                "label": name, "source_capture": source,
                "start_seconds": round(len(pcm) / (rate * frame_bytes), 3),
                "duration_seconds": round(len(data) / (rate * frame_bytes), 3),
            })
            pcm.extend(data)
            pcm.extend(gap)
    with wave.open(str(destination), "wb") as audio:
        audio.setparams((*format_info, 0, "NONE", "not compressed"))
        audio.writeframes(pcm[:-len(gap)])
    return chapters


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", choices=["Dummy", "CoreAudio"], default="Dummy")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = Path(tempfile.mkdtemp(prefix="ye-ci-p11-audio-", dir="/tmp")).resolve()
    project = out / "project"
    state = out / "state"
    project.mkdir()
    state.mkdir()
    for part in ("src", "data", "scenes", "resources", "assets", "tools"):
        shutil.copytree(repo / part, project / part, ignore=shutil.ignore_patterns("__pycache__"))
    for part in ("project.godot", "default_bus_layout.tres"):
        shutil.copy2(repo / part, project / part)
    for source in (project / "src").rglob("*.gd"):
        code = source.read_text(encoding="utf-8")
        if "user://" in code:
            source.write_text(code.replace("user://", str(state) + "/"), encoding="utf-8")

    print(out, flush=True)
    engine = [str(repo / "tools/godot.sh"), "--path", str(project)]
    with (out / "import.log").open("w") as log:
        subprocess.run(engine + ["--headless", "--import", "--log-file", str(out / "import-engine.log")],
                       cwd=project, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    with (out / "run.log").open("w") as log:
        completed = subprocess.run(
            engine + ["--display-driver", "headless", "--audio-driver", args.driver, "--text-driver", "Dummy",
                      "--disable-render-loop", "--log-file", str(out / "run-engine.log"),
                      "--script", "res://tools/p11_audio_acceptance.gd", "--", str(out)],
            cwd=project, stdout=log, stderr=subprocess.STDOUT, timeout=120,
        )
    path = out / "results.json"
    if not path.exists():
        raise SystemExit(f"No report written. Inspect {out / 'run.log'}.")
    report = json.loads(path.read_text())
    report["run_diagnostics"] = [
        line for filename in ("import.log", "run.log")
        for line in (out / filename).read_text().splitlines()
        if line.startswith(("ERROR:", "SCRIPT ERROR:", "WARNING:"))
    ]
    report["sample_assets"] = {
        sample.name: hashlib.sha256(sample.read_bytes()).hexdigest()
        for sample in sorted((project / "assets/audio/p11").glob("*.wav"))
    }
    state_prefix = (str(state) + "/").encode()
    report["implementation"] = {
        name: hashlib.sha256((project / name).read_bytes().replace(state_prefix, b"user://")).hexdigest()
        for name in ("src/audio/BattleAudio.gd", "src/combat/Combat.gd", "src/combat/CombatSimulation.gd",
                     "src/combat/BattleSession.gd", "default_bus_layout.tres", "src/autoload/Settings.gd")
    }
    report["listening_excerpts"] = {}
    for name, plan in [("p11-foley-showcase.wav", SHOWCASE), ("p11-r07-comparison.wav", QUIET_PAIR)]:
        if any(not (out / (source + ".wav")).is_file() for _, source, _ in plan):
            continue
        dest = out / name
        chapters = mixed_excerpt(out, dest, plan)
        report["listening_excerpts"][name] = {
            "sha256": hashlib.sha256(dest.read_bytes()).hexdigest(),
            "editing": "Native stereo PCM excerpts concatenated at measured gain, 0.24 seconds of silence between excerpts.",
            "chapters": chapters,
        }
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(out), "passed": report["passed"], "failed": report["failed"],
                      "driver": report["audio_driver"], "r07": report["r07_comparison"]}, ensure_ascii=False))
    script_error = any(line.startswith("SCRIPT ERROR:") for line in report["run_diagnostics"])
    return int(completed.returncode != 0 or report["failed"] or script_error or report["audio_driver"] != args.driver)


if __name__ == "__main__":
    raise SystemExit(main())
