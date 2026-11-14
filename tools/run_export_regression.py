"""Run gameplay, physical input and TCP regressions against the exported game."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import argparse

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "builds/windows/RMPrecisionLab.exe"
parser=argparse.ArgumentParser()
parser.add_argument('--out',type=Path,default=ROOT/'artifacts/first-person')
OUT=parser.parse_args().out.resolve()
env = os.environ.copy()
for key in ["APPDATA", "LOCALAPPDATA", "TEMP", "TMP"]:
    directory = ROOT / "artifacts/runtime" / key.lower()
    directory.mkdir(parents=True, exist_ok=True)
    env[key] = str(directory)

results = []
for size in ["1280x720", "960x540"]:
    for name, mode in [("gameplay", "--smoke-test"), ("input", "--input-checks"), ("network", "--control-smoke")]:
        folder = OUT / f"{name}-{size.split('x')[0]}"
        folder.mkdir(parents=True, exist_ok=True)
        log = folder / "game.log"
        command = [str(GAME), "--resolution", size, "--position", "40,40", "--log-file", str(log), "--", mode, f"--capture-dir={folder}"]
        with (folder / "stdout.log").open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=240, creationflags=subprocess.CREATE_NO_WINDOW)
        text = log.read_text(encoding="utf-8", errors="replace")
        assert result.returncode == 0, f"{name} {size}: exit {result.returncode}"
        assert not re.search(r"SCRIPT ERROR:|^ERROR:|SMOKE FAIL|INPUT FAIL|CONTROL FAIL|^FAIL", text, re.M), folder
        summaries = [line for line in text.splitlines() if re.search(r"PASS|failures|checks", line)]
        expected = {"gameplay": r"SMOKE PASS: \d+ integration checks \(0 failures\)", "input": r"PASS: \d+ input checks; failures: 0", "network": r"CONTROL PASS: \d+ checks \(0 failures\)"}[name]
        assert re.search(expected, text), f"{name} {size}: missing completion marker"
        results.append({"test": name, "resolution": size, "summary": summaries, "log": str(log.relative_to(ROOT))})
        print(name, size, summaries, flush=True)
(OUT / "export-regression.json").write_text(json.dumps({"exe_sha256": hashlib.sha256(GAME.read_bytes()).hexdigest(), "runs": results}, indent=2), encoding="utf-8")
