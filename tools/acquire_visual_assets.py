"""Fetch attributed model inputs and a portable Blender into the build cache."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib, json, requests, re, zipfile, argparse

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'tools/cache/visuals'
CACHE.mkdir(parents=True, exist_ok=True)
BASE = 'https://raw.githubusercontent.com/cktang88/3d-fps/main/'

def fetch(item):
    name, url = item
    dest = CACHE / name
    if not dest.exists():
        r = requests.get(url, timeout=90)
        r.raise_for_status()
        dest.write_bytes(r.content)
    return {'file': name, 'url': url, 'bytes': dest.stat().st_size,
            'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}

items = []
STEEL = 'https://raw.githubusercontent.com/AetherRadar/operation-steel-tide/main/'
for folder, names in {
    'elizion_desert_eagle': ['desert_eagle.glb', 'LICENSE.md'],
    'djmaesen_smg45': ['animated_reload_arms.glb','smg45_pistol_large_arms.glb','smg45_rifle_arms.glb','LICENSE.md'],
    'steel_tide_m4a1': ['steel_tide_m4a1.glb','LICENSE.md'],
    'steel_tide_ak74': ['ak47_reloadable_fp.glb','LICENSE.md'],
}.items():
    for name in names:
        items.append((folder+'_'+name,STEEL+'assets/models/'+folder+'/'+name))
items.append(('baldman.zip','https://opengameart.org/sites/default/files/baldman_painted_rigged.zip'))
receipt=[]
with ThreadPoolExecutor(max_workers=4) as pool:
    for item, result in zip(items, pool.map(lambda x: fetch(x), items)):
        receipt.append(result)
        print(result,flush=True)
with zipfile.ZipFile(CACHE/'baldman.zip') as archive:
    for info in archive.infolist():
        if not (CACHE/'baldman'/info.filename).resolve().is_relative_to((CACHE/'baldman').resolve()):raise ValueError('Unsafe archive path')
    archive.extractall(CACHE/'baldman')

(CACHE/'download-receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')

if '--blender' in __import__('sys').argv:
    name='blender-4.5.3-windows-x64.zip'
    base='https://download.blender.org/release/Blender4.5/'
    dest=CACHE/name
    if not dest.exists():
        with requests.get(base+name,stream=True,timeout=90) as r:
            r.raise_for_status()
            with dest.open('wb') as out:
                for chunk in r.iter_content(1024*1024): out.write(chunk)
    hashes=requests.get(base+'blender-4.5.3.sha256',timeout=30)
    hashes.raise_for_status()
    expected=next(line.split()[0] for line in hashes.text.splitlines() if name in line)
    actual=hashlib.sha256(dest.read_bytes()).hexdigest()
    if actual!=expected: raise ValueError('Blender checksum mismatch')
    print('Blender official SHA256 verified',actual,flush=True)
    with zipfile.ZipFile(dest) as archive:
        for info in archive.infolist():
            target=(CACHE/info.filename).resolve()
            if not target.is_relative_to(CACHE.resolve()): raise ValueError('Unsafe zip path')
        archive.extractall(CACHE)
    print('Blender extracted',flush=True)
