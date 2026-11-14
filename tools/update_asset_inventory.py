"""Record actual delivered GLB geometry, clips, texture sizes and audio hashes."""
from pathlib import Path
import hashlib
import json
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "射击游戏/assets"


def inventory(path):
    raw = path.read_bytes()
    json_size = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_size])
    binary = raw[20 + json_size + 8:]
    triangles = 0
    for mesh in doc.get("meshes", []):
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) == 4:
                accessor = primitive.get("indices", primitive["attributes"]["POSITION"])
                triangles += doc["accessors"][accessor]["count"] // 3
    textures = []
    for item in doc.get("images", []):
        view = doc["bufferViews"][item["bufferView"]]
        start = view.get("byteOffset", 0)
        encoded = binary[start:start + view["byteLength"]]
        # Blender exports this project's embedded texture set as PNG.
        assert encoded[:8] == b"\x89PNG\r\n\x1a\n", item
        textures.append({"name": item.get("name", ""), "size": list(struct.unpack_from(">II", encoded, 16))})
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "triangles": triangles,
            "skins": len(doc.get("skins", [])),
            "animations": [a.get("name", "") for a in doc.get("animations", [])], "textures": textures}


if __name__ == "__main__":
    models = {path.name: inventory(path) for path in sorted((ASSETS / "models").glob("*.glb"))}
    (ASSETS / "licenses/model-inventory.json").write_text(json.dumps(models, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    audio = {}
    for path in sorted((ASSETS / "audio/reload").glob("*.wav")):
        with wave.open(str(path)) as stream:
            audio[path.name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                               "sample_rate": stream.getframerate(), "channels": stream.getnchannels(),
                               "seconds": stream.getnframes() / stream.getframerate(),
                               "author": "RMPrecisionLab project", "license": "MIT",
                               "source": "tools/prepare_reload_audio.py", "type": "original synthesized game foley"}
    (ASSETS / "licenses/reload-audio.json").write_text(json.dumps(audio, indent=2) + "\n", encoding="utf-8")
    print(f"Inventoried {len(models)} GLBs and {len(audio)} original audio clips")
