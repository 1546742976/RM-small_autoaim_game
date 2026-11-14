"""Original MIT deterministic combat Foley, 48 kHz mono PCM."""
from pathlib import Path
import math, random, wave, struct, json
ROOT=Path(__file__).resolve().parents[1]/'射击游戏/assets/audio/combat'
ROOT.mkdir(parents=True,exist_ok=True)
report={}
for name,count,duration,frequency in [('deagle',3,.24,95),('ak47',3,.15,180),('m4a1',3,.11,300),('hard',4,.18,115),('wood',4,.22,155),('land',4,.24,85),('head',3,.15,220),('body',3,.13,120)]:
 for variant in range(count):
  rng=random.Random(1700+variant+sum(map(ord,name)))
  samples=[]; low=0.0; muffled=0.0; air=0.0
  for i in range(int(48000*duration)):
   t=i/48000; noise=rng.uniform(-1,1); low+=.18*(noise-low)
   decay=math.exp(-t/(duration/6))
   tone=math.sin(2*math.pi*frequency*(1+variant*.018)*t)*decay
   # Band-limited transient, low blast, early reflections and mechanical closure.
   air+=.52*(noise-air)
   crack=air-low
   if name in ['deagle','ak47','m4a1']:
    weight={'deagle':.52,'ak47':.30,'m4a1':.19}[name]
    blast=math.sin(2*math.pi*(frequency*t+35*.012*(1-math.exp(-t/.012))))
    v=1.1*crack*math.exp(-t/.009)+weight*blast*math.exp(-t/.025)
    v+=.24*low*math.exp(-t/.04)
    for offset,gain in [(.018,.13),(.037,.065)]:
     if t>offset:v+=gain*crack*math.exp(-(t-offset)/.009)
    if t>.025:v+=.10*math.sin(2*math.pi*(2100 if name=='m4a1' else 1400)*t)*math.exp(-(t-.025)/.006)
   elif name in ['head','body']:
    v=.70*low*math.exp(-t/.017)+.30*tone
    if name=='head':v+=.7*crack*math.exp(-t/.006)
   else:
    # Heel impact followed by a restrained sole contact; avoid a pure bass beep.
    muffled+=.075*(low-muffled)
    v=1.25*muffled*decay+.22*tone
    v+=.16*low*math.exp(-t/.012)
    if t>.045:v+=.18*low*math.exp(-(t-.045)/.023)
   samples.append(v*min(1,t/(.00025 if name in ['deagle','ak47','m4a1'] else .004)))
  peak=max(map(abs,samples)); samples=[v/peak*.65 for v in samples]
  filename=f'{name}_{variant}.wav'
  with wave.open(str(ROOT/filename),'wb') as f:
   f.setparams((1,2,48000,0,'NONE','not compressed'));f.writeframes(struct.pack('<'+'h'*len(samples),*[round(v*32767) for v in samples]))
  report[filename]={'peak':max(map(abs,samples)),'seconds':duration}
(ROOT/'manifest.json').write_text(json.dumps(report,indent=2))
print('Generated',len(report),'original PCM assets')
