"""Run first-person checks, captures, real-time measurement and explicit recordings.

Examples:
  python tools/run_viewmodel_validation.py --mode checks --headless
  python tools/run_viewmodel_validation.py --mode captures --engine builds/windows/RMPrecisionLab.exe
  python tools/run_viewmodel_validation.py --mode records --engine builds/windows/RMPrecisionLab.exe
  python tools/run_viewmodel_validation.py --mode benchmark --engine builds/windows/RMPrecisionLab.exe
"""
from pathlib import Path
import argparse
import json
import os
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path(r'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')


def normalize_performance(folder, expected_size):
    reports = json.loads((folder / 'performance.json').read_text(encoding='utf-8'))
    assert len(reports) == 2 and all(r['seconds'] >= 30 for r in reports)
    previous_serial = 0
    for report in reports:
        # With canvas scaling, ViewportTexture.get_width() differs from the
        # actual get_image() output. Use this run's rendered PNG dimensions,
        # preserve the original texture query, and never alter timing samples.
        with (folder / f"{report['map']}-benchmark.png").open('rb') as picture:
            header = picture.read(24)
        assert header[:8] == b'\x89PNG\r\n\x1a\n'
        actual_size = list(struct.unpack('>II', header[16:24]))
        assert actual_size == expected_size, (actual_size, expected_size)
        report.setdefault('texture_reported_resolution', report['resolution'])
        report['resolution'] = actual_size
        report['resolution_source'] = f"{report['map']}-benchmark.png (same-run viewport image)"
        report['reload_serial_end'] = report['reloads']
        report['reloads_in_map'] = report['reloads'] - previous_serial
        previous_serial = report['reloads']
    assert all(r['shots'] > 0 and r['reloads_in_map'] > 0 for r in reports)
    (folder / 'performance.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=DEFAULT_ENGINE)
    parser.add_argument('--mode', choices=['checks', 'captures', 'records', 'benchmark'], default='checks')
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--export', action='store_true', help='Run an exported EXE without an external project path')
    parser.add_argument('--out', type=Path, default=ROOT / 'artifacts' / 'first-person')
    parser.add_argument('--size', choices=['1280', '960', 'both'], default='both')
    args = parser.parse_args()
    engine = args.engine.resolve()
    exported = args.export or engine.is_relative_to(ROOT / 'builds')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for name in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP']:
        directory = ROOT / 'artifacts' / 'runtime' / name.lower()
        directory.mkdir(parents=True, exist_ok=True)
        env[name] = str(directory)
    resolutions = [('1280', '1280x720'), ('960', '960x540')]
    if args.size != 'both':
        resolutions = [item for item in resolutions if item[0] == args.size]
    ffmpeg = ROOT / 'tools/cache/python/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe'
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0

    def run(folder, size, options, movie=False):
        folder.mkdir(parents=True, exist_ok=True)
        log = folder / 'game.log'
        cmd = [str(engine)]
        if not exported:
            cmd += ['--path', str(ROOT / '射击游戏')]
        cmd += ['--resolution', size, '--log-file', str(log), '--position', '40,40']
        if args.headless:
            assert not movie and args.mode == 'checks', 'Rendered evidence requires a graphical renderer'
            cmd += ['--headless']
        if movie:
            cmd += ['--write-movie', str(folder / 'capture.avi'), '--fixed-fps', '60']
        cmd += ['--'] + options + [f'--capture-dir={folder}']
        with (folder / 'stdout.log').open('w', encoding='utf-8') as output:
            result = subprocess.run(cmd, cwd=ROOT, env=env, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=600, creationflags=flags)
        text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
        assert result.returncode == 0, f'Engine exited {result.returncode}: {folder}'
        assert not re.search(r'SCRIPT ERROR:|^ERROR:|VIEWMODEL FAIL:', text, re.M), folder
        print(f'Completed {folder.relative_to(out)}', flush=True)
        if movie:
            command = [str(ffmpeg), '-hide_banner', '-y', '-i', str(folder / 'capture.avi'),
                       '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p',
                       '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', str(folder / 'demo.mp4')]
            with (folder / 'encode.log').open('w', encoding='utf-8') as output:
                subprocess.run(command, check=True, stdout=output, stderr=subprocess.STDOUT,
                               timeout=240, creationflags=flags)
            assert (folder / 'demo.mp4').stat().st_size > 10000
            # Only the exact intermediate file created above is removed.
            (folder / 'capture.avi').unlink()

    if args.mode in ('checks', 'captures'):
        for tag, size in resolutions:
            options = ['--viewmodel-checks'] if args.mode == 'checks' else ['--reload-showcase', '--capture-only']
            folder = out / f'{args.mode}-{tag}'
            run(folder, size, options)
            if args.mode == 'checks':
                report = json.loads((folder / 'viewmodel-checks.json').read_text(encoding='utf-8'))
                assert report['failures'] == 0
    elif args.mode == 'benchmark':
        for tag, size in resolutions:
            folder = out / f'benchmark-{tag}'
            run(folder, size, ['--viewmodel-benchmark'])
            normalize_performance(folder, [int(v) for v in size.split('x')])
    else:
        for weapon in ['deagle', 'ak47', 'm4a1']:
            for kind in ['empty', 'tactical']:
                for slow in [1, 4]:
                    run(out / f'{weapon}-{kind}-{slow}x', '1280x720', ['--reload-showcase',
                        f'--demo-weapon={weapon}', f'--demo-kind={kind}', f'--demo-slow={slow}'], movie=True)
                    report = json.loads((out / f'{weapon}-{kind}-{slow}x/demo.json').read_text(encoding='utf-8'))
                    assert report['mag_after'] > 0 and report['reload_game_ms'] >= report['reload_ms'] - 0.01
                    expected_frames = report['reload_ms'] / 1000 * slow * 60
                    assert abs(report['reload_frames'] - expected_frames) <= 4, report
        run(out / 'hold-fire', '1280x720', ['--reload-showcase', '--hold-fire-demo'], movie=True)


if __name__ == '__main__':
    main()
