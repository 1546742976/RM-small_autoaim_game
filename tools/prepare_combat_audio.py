"""Original MIT deterministic combat Foley, 48 kHz mono PCM."""
from pathlib import Path
import math, random, wave, struct, json
ROOT=Path(__file__).resolve().parents[1]/'射击游戏/assets/audio/combat'
ROOT.mkdir(parents=True,exist_ok=True)
report={}
for name,count,duration,frequency in [('deagle',3,.42,78),('ak47',3,.24,145),('m4a1',3,.16,270),('hard',4,.16,850),('wood',4,.22,180),('land',4,.24,110)]:
 for variant in range(count):
  rng=random.Random(1700+variant+sum(map(ord,name)))
  samples=[]; low=0.0
  for i in range(int(48000*duration)):
   t=i/48000; noise=rng.uniform(-1,1); low+=.18*(noise-low)
   decay=math.exp(-t/(duration/6))
   tone=math.sin(2*math.pi*frequency*(1+variant*.018)*t)*decay
   if name=='deagle': v=.55*tone+.35*low*decay+.4*noise*math.exp(-t/.009)
   elif name=='ak47': v=.25*tone+.6*noise*math.exp(-t/.025)+.2*low*decay
   elif name=='m4a1': v=.35*tone+.4*(noise-low)*math.exp(-t/.014)+.15*math.sin(2*math.pi*1900*t)*math.exp(-t/.035)
   else: v=.6*low*decay+.35*tone+noise*.15*math.exp(-t/.008)
   samples.append(v*min(1,t/.0008))
  peak=max(map(abs,samples)); samples=[v/peak*.65 for v in samples]
  filename=f'{name}_{variant}.wav'
  with wave.open(str(ROOT/filename),'wb') as f:
   f.setparams((1,2,48000,0,'NONE','not compressed'));f.writeframes(struct.pack('<'+'h'*len(samples),*[round(v*32767) for v in samples]))
  report[filename]={'peak':max(map(abs,samples)),'seconds':duration}
(ROOT/'manifest.json').write_text(json.dumps(report,indent=2))
print('Generated',len(report),'original PCM assets')
