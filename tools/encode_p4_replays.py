#!/usr/bin/env python3
"""Encode the actual P4 renderer samples; never synthesizes game state or frames."""
import hashlib
import json
from datetime import datetime
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
report_path = root / 'docs/phase-reports/p4-render-results.json'
report = json.loads(report_path.read_text())
if report['failures'] or not report['capture']:
    raise SystemExit('Need a passing P4 --capture run before encoding')
ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
if not ffmpeg or not ffprobe:
    raise SystemExit('Install ffmpeg/ffprobe or add the existing executables to PATH')
movies = []
for battle in report['full_battles']:
    mode = battle['mode']
    if mode not in ('shouxiang', 'duoming'):
        raise SystemExit('Unexpected battle mode')
    folder = root / 'exports/p4-replays' / mode
    frames = sorted(folder.glob('frame-*.png'))
    expected = [folder / f'frame-{index:04d}.png' for index in range(battle['replay_frames'])]
    if frames != expected or not frames:
        raise SystemExit(f'{mode}: missing, extra or nonsequential source frames')
    output = folder.parent / f'{mode}-12x.mp4'
    # Six actual samples/second, each sampled every two simulation seconds.
    # Duplicate display frames to 30 fps; no motion interpolation. Hold final result two seconds.
    subprocess.run([
        ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '6',
        '-start_number', '0', '-i', str(folder / 'frame-%04d.png'),
        '-vf', 'tpad=stop_mode=clone:stop_duration=2,fps=30',
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', str(output),
    ], check=True)
    probe = json.loads(subprocess.check_output([
        ffprobe, '-v', 'error', '-show_entries', 'stream=width,height,codec_name,nb_frames,r_frame_rate',
        '-show_entries', 'format=duration,size', '-of', 'json', str(output),
    ], text=True))
    stream = probe['streams'][0]
    duration = float(probe['format']['duration'])
    if stream['width'] != 1920 or stream['height'] != 1080 or abs(duration - (len(frames) / 6 + 2)) > 0.1:
        raise SystemExit(f'{mode}: unexpected encoded resolution or duration')
    digest = hashlib.sha256()
    for frame in frames:
        digest.update(frame.name.encode())
        digest.update(hashlib.sha256(frame.read_bytes()).digest())
    movies.append({
        'mode': mode, 'path': str(output.relative_to(root)),
        'source_frames': len(frames), 'source_frame_digest_sha256': digest.hexdigest(),
        'sample_sim_seconds': 2, 'source_samples_per_video_second': 6,
        'approximate_speed': '12x; final result held two extra seconds',
        'simulation_seconds': battle['seconds'], 'result': battle['result'],
        'width': stream['width'], 'height': stream['height'], 'codec': stream['codec_name'],
        'duration_seconds': duration, 'display_frame_rate': stream['r_frame_rate'],
        'bytes': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
    })
    print(f'{mode}: {len(frames)} real samples -> {duration:.3f}s, {output.name}')
manifest = {
    'phase': 'P4', 'generated_at': datetime.now().astimezone().isoformat(),
    'source_report': str(report_path.relative_to(root)),
    'source_report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
    'method': 'Native Godot viewport samples from fixed-step public-command acceptance. Timelapse, not manual realtime play. No motion interpolation or generated imagery.',
    'movies': movies,
}
(root / 'docs/phase-reports/p4-replay-results.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
