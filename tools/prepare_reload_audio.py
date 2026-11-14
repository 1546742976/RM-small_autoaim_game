"""Generate original, deterministic reload foley; no downloaded recordings.

MIT, same license as this project. Layered filtered noise, short resonances and
contacts model magazine extraction, insertion and mechanical closure. These are
designed game sounds, not recordings of the named real weapons.
"""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "射击游戏/assets/audio/reload"
RATE = 48000


def render(weapon, event, seed):
    rng = random.Random(seed)
    length = {"remove": 0.24, "insert": 0.28, "mechanism": 0.23}[event]
    samples = [0.0] * int(RATE * length)
    tone = {"deagle": 1.18, "ak47": 0.78, "m4a1": 1.0}[weapon]
    strikes = {
        "remove": [(0.008, 0.65, 0.011), (0.057, 0.25, 0.025), (0.128, 0.19, 0.015)],
        "insert": [(0.007, 0.32, 0.018), (0.077, 1.0, 0.022), (0.116, 0.31, 0.014)],
        "mechanism": [(0.008, 0.65, 0.018), (0.083, 0.95, 0.019), (0.112, 0.3, 0.011)],
    }[event]
    for offset, gain, decay in strikes:
        start = int(offset * RATE)
        smooth_noise = 0.0
        for i in range(start, len(samples)):
            t = (i - start) / RATE
            envelope = (1.0 - math.exp(-t * 6500)) * math.exp(-t / decay)
            noise = rng.uniform(-1.0, 1.0)
            smooth_noise += 0.42 * (noise - smooth_noise)
            metallic = sum(math.sin(2 * math.pi * freq * tone * t) * weight
                           for freq, weight in [(730, 0.15), (1730, 0.10), (3190, 0.04)])
            low_knock = 0.35 * math.sin(2 * math.pi * 185 * tone * t) * math.exp(-t / 0.012)
            samples[i] += gain * envelope * (smooth_noise * 0.75 + metallic + low_knock)
    # A quieter scrape between contacts adds movement without a constant hiss.
    if event == "remove":
        last = 0.0
        for i in range(int(0.04 * RATE), int(0.16 * RATE)):
            t = i / RATE
            last += 0.15 * (rng.uniform(-1, 1) - last)
            samples[i] += last * 0.12 * math.sin(math.pi * (t - 0.04) / 0.12)
    peak = max(abs(v) for v in samples)
    # Leave ample headroom for the shot and hit-feedback buses.
    pcm = b"".join(struct.pack("<h", round(v / max(peak, 1e-9) * 17000)) for v in samples)
    with wave.open(str(OUT / f"{weapon}_{event}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for wi, weapon in enumerate(["deagle", "ak47", "m4a1"]):
        for ei, event in enumerate(["remove", "insert", "mechanism"]):
            render(weapon, event, 1400 + wi * 10 + ei)
    print("Generated 9 original 48 kHz / 16-bit mono reload sounds")
