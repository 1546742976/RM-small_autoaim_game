"""Download CC0 ambientCG materials, retaining the exact receipts for distribution."""
from pathlib import Path
import hashlib, io, json, zipfile, requests

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '射击游戏/assets/town'
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = {'stone': 'PavingStones036', 'plaster': 'Plaster001', 'wood': 'WoodFloor051', 'roof': 'RoofingTiles012A'}
receipts = []
for name, asset in SOURCES.items():
    url = f'https://ambientcg.com/get?file={asset}_2K-JPG.zip'
    cache = ROOT / f'tools/cache/{asset}_2K-JPG.zip'
    if not cache.exists():
        response = requests.get(url, timeout=120)
        response.raise_for_status()
        cache.write_bytes(response.content)
    data = cache.read_bytes()
    files = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for suffix in ['Color', 'NormalGL', 'Roughness']:
            source = f'{asset}_2K-JPG_{suffix}.jpg'
            target = OUT / f'{name}_{suffix}.jpg'
            target.write_bytes(archive.read(source))
            files.append(target.name)
    receipts.append({'id': asset, 'author': 'ambientCG / Lennart Demes',
        'source': f'https://ambientcg.com/a/{asset}', 'download': url,
        'license': 'CC0-1.0', 'license_url': 'https://docs.ambientcg.com/license/',
        'sha256_zip': hashlib.sha256(data).hexdigest(), 'files': files,
        'modifications': 'Selected 2K color, OpenGL normal and roughness maps; in-engine tint and tiling.'})
    print(asset, 'ready', flush=True)
(ROOT / '射击游戏/assets/licenses/town-materials.json').write_text(json.dumps(receipts, ensure_ascii=False, indent=2), encoding='utf-8')
