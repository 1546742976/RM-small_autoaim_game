"""Run the actual C++ client against a rendered game; never exposes test RPCs."""
from pathlib import Path
import argparse
import json
import os
import re
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--game', required=True, type=Path)
parser.add_argument('--export', action='store_true')
parser.add_argument('--case', choices=['probe', 'vision', 'benchmark'], default='probe')
parser.add_argument('--map', default='training_hall')
parser.add_argument('--mode', choices=['camera', 'ping'], default='camera')
parser.add_argument('--resolution', default='1280x720')
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
with socket.socket() as allocator:
    allocator.bind(('127.0.0.1', 0))
    port = allocator.getsockname()[1]
duration = 40 if args.case == 'benchmark' else 10
token = 'local-validation-token'
command = [str(args.game.resolve())]
if not args.export:
    command += ['--path', str(ROOT / '射击游戏')]
command += ['--resolution', args.resolution, '--log-file', str(out / 'game.log'), '--',
            '--control', '--control-bind=127.0.0.1', f'--control-port={port}',
            f'--control-token={token}', '--control-fixture', f'--fixture-map={args.map}',
            f'--fixture-exit-after={duration+4}']
if args.case == 'benchmark':
    command += ['--fixture-motion', f'--control-measure={out / "performance.json"}']
environment = os.environ.copy()
for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP']:
    directory = ROOT / 'artifacts/runtime' / key.lower()
    directory.mkdir(exist_ok=True, parents=True)
    environment[key] = str(directory)
process = None
with (out / 'process.log').open('w', encoding='utf-8') as log:
    try:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        deadline = time.monotonic() + 12
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                    break
            except OSError:
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Game listener did not start; inspect process.log')
                time.sleep(0.1)
        binary = ROOT / 'artifacts/cpp-build'
        if args.case == 'vision':
            client = [str(binary / 'rm_vision_template.exe'), '127.0.0.1', token,
                      str(port), '--no-window', '--frames=120']
        else:
            client = [str(binary / 'rm_control_probe.exe'), '--host', '127.0.0.1', '--port', str(port),
                      '--token', token, '--seconds', str(duration), '--output', '.']
            if args.mode == 'ping':
                client += ['--ping-only']
            else:
                client += ['--actions']
        result = subprocess.run(client, cwd=out, capture_output=True, timeout=duration+8)
        (out / 'client.log').write_bytes(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'C++ client failed: {result.returncode}; inspect client.log')
        process.wait(timeout=duration+8)
        if process.returncode:
            raise RuntimeError(f'Game exit code: {process.returncode}')
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
text = (out / 'game.log').read_text(encoding='utf-8')
assert not re.search(r'SCRIPT ERROR:|^ERROR:', text, re.M), text
if args.case == 'benchmark':
    performance = json.loads((out / 'performance.json').read_text(encoding='utf-8'))
    assert performance['seconds'] >= 30
if args.case == 'vision':
    assert '120 decoded BGR frames' in (out / 'client.log').read_text()
if args.export:
    import hashlib
    (out / 'build.json').write_text(json.dumps({'exe_sha256': hashlib.sha256(args.game.resolve().read_bytes()).hexdigest()}), encoding='utf-8')
print(f'CONTROL CLIENT PASS: {args.case}, {args.map}, {args.mode}, {args.resolution}')
