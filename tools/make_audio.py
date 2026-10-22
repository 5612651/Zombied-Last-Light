"""Original synthesized layers; no third-party audio or dependencies."""
import math, random, wave, struct
from pathlib import Path
random.seed(17)
out=Path('D:/Zombied/assets/audio');out.mkdir(parents=True,exist_ok=True)
sr=22050

def save(name,duration,func):
    data=bytearray();smooth=0
    for i in range(int(sr*duration)):
        t=i/sr;n=random.uniform(-1,1);smooth=.91*smooth+.09*n
        value=max(-1,min(1,func(t,n,smooth)))
        data.extend(struct.pack('<h',int(value*30000)))
    with wave.open(str(out/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(data)

save('ar_crack',.24,lambda t,n,s:(n*.8*math.exp(-t*70)+math.sin(2*math.pi*(130*t-60*t*t))*.48*math.exp(-t*23)))
save('shotgun_blast',.62,lambda t,n,s:(n*.8*math.exp(-t*18)+math.sin(2*math.pi*(85*t-30*t*t))*.65*math.exp(-t*10)))
save('weapon_mechanism',.12,lambda t,n,s:n*.6*math.exp(-t*90)+math.sin(2*math.pi*1800*t)*.1*math.exp(-t*65))
save('casing',.24,lambda t,n,s:sum(math.sin(2*math.pi*f*t)*math.exp(-t*d)*a for f,d,a in [(3100,22,.15),(4700,35,.1),(6200,16,.06)]))
save('impact',.22,lambda t,n,s:(s*2+math.sin(2*math.pi*75*t)*.35)*math.exp(-t*20))
save('kill',.48,lambda t,n,s:(s*1.8+math.sin(2*math.pi*(60*t+80*t*t))*.25)*math.exp(-t*10))
save('dash',.33,lambda t,n,s:s*4*math.sin(min(1,t/.33)*math.pi)*.5)
save('reload',.5,lambda t,n,s:n*.4*(math.exp(-t*70)+math.exp(-abs(t-.19)*90)+math.exp(-abs(t-.4)*85)))
save('hurt',.5,lambda t,n,s:(math.sin(2*math.pi*(70*t-20*t*t))*.45+s)*math.exp(-t*8))
save('upgrade',.9,lambda t,n,s:sum(math.sin(2*math.pi*f*t)*.09*math.exp(-max(0,t-j*.12)*4)*(t>=j*.12) for j,f in enumerate([440,554.37,659.25,880])))
save('rain',12,lambda t,n,s:(n*.045+s*.12)*(0.92+.08*math.sin(2*math.pi*t/12)))
save('ambience',24,lambda t,n,s:sum(math.sin(2*math.pi*f*t)*a for f,a in [(48,.045),(60,.018),(72,.028),(96,.016),(144,.008)])*(.8+.2*math.sin(2*math.pi*t/24))+s*.012)
print('Generated 12 original audio layers')
