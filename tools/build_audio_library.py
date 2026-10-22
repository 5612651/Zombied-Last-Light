"""Original procedural industrial audio and loopable music; runtime Ogg assets."""
import math, random, wave, struct, subprocess, shutil, json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
audio=root/'assets/audio'
sr=22050
rng=random.Random(23017)
def save(name,duration,render):
    frames=bytearray(); smooth=0
    for i in range(int(sr*duration)):
        t=i/sr; noise=rng.uniform(-1,1); smooth=.92*smooth+.08*noise
        sample=render(t,noise,smooth)*min(1,t/.015,(duration-t)/.025)
        frames.extend(struct.pack('<h',int(max(-1,min(1,sample))*27000)))
    with wave.open(str(audio/(name+'.wav')),'wb') as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(sr);output.writeframes(frames)
for index,freq in enumerate([82,103,126]):
    save('infected_'+str(index+1),1.15,lambda t,n,s,f=freq:(math.sin(2*math.pi*(f*t+8*t*t))*.12+math.sin(2*math.pi*f*2.7*t)*.055+s*.4)*math.sin(math.pi*t/1.15)**2)
save('runner_yelp',.5,lambda t,n,s:(math.sin(2*math.pi*(190*t-80*t*t))*.2+s*.5)*math.exp(-t*5))
save('heavy_growl',1.4,lambda t,n,s:(math.sin(2*math.pi*(53*t-5*t*t))*.2+s*.5)*math.sin(math.pi*t/1.4))
save('elite_warning',1.1,lambda t,n,s:sum(math.sin(2*math.pi*f*t)*.12 for f in [330,440])*(.2+.8*(math.sin(t*math.pi*9)>0))*math.exp(-t*2))
save('boss_warning',1.5,lambda t,n,s:(math.sin(2*math.pi*55*t)*.2+math.sin(2*math.pi*110*t)*.1+s*.25)*math.exp(-t*1.8))
save('slow_motion',.6,lambda t,n,s:(math.sin(2*math.pi*(240*t-160*t*t))*.12+s*.55)*math.exp(-t*4))
save('kill_stinger',.65,lambda t,n,s:sum(math.sin(2*math.pi*f*t)*.08 for f in [82.4,123.47,164.81])*math.exp(-t*7)+s*.2*math.exp(-t*16))
save('indoor_room',16,lambda t,n,s:math.sin(2*math.pi*55*t)*.025+math.sin(2*math.pi*110*t)*.012+s*.055)
def music(kind,duration=32):
    bpm={'safe':75,'combat':105,'boss':120}[kind]; beat=60/bpm; roots=[55,43.65,36.71,41.2]
    def render(t,n,s):
        bar=int(t/(beat*4)); note=roots[(bar//2)%4]; section=(t%(beat*8))/(beat*8)
        pad=sum(math.sin(2*math.pi*note*r*t)*.018 for r in [2,3,4,6])*math.sin(math.pi*section)**.6
        if kind=='safe': return pad+math.sin(2*math.pi*note*4*t)*math.exp(-(t%(beat*2))*3)*.025+s*.003
        phase=t%beat
        kick=math.sin(2*math.pi*(55*phase+25*(1-math.exp(-phase*25))))*.13*math.exp(-phase*18)
        bass=math.sin(2*math.pi*note*t)*.07*(.4+.6*math.exp(-phase*6))
        hat=n*.018*math.exp(-(t%(beat*.5))*80)
        snare=s*.28*math.exp(-phase*22) if int(t/beat)%4 in [1,3] else 0
        tension=math.sin(2*math.pi*note*8*t)*.018*math.exp(-(t%(beat*.25))*20) if kind=='boss' else 0
        return pad+bass+kick+hat+snare+tension
    save('music_'+kind,duration,render)
for kind in ['safe','combat','boss']: music(kind)
ffmpeg=shutil.which('ffmpeg')
if not ffmpeg: raise RuntimeError('ffmpeg is required to encode runtime audio')
manifest=[]
for source in sorted(audio.glob('*.wav')):
    destination=source.with_suffix('.ogg')
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(source),'-c:a','libvorbis','-q:a','5',str(destination)],check=True)
    with wave.open(str(source),'rb') as wav:
        manifest.append({'id':source.stem,'path':'res://assets/audio/'+destination.name,'seconds':wav.getnframes()/wav.getframerate(),'bytes':destination.stat().st_size})
(root/'assets/audio_manifest.json').write_text(json.dumps({'schema_version':1,'provenance':'Original procedural synthesis','runtime_format':'Ogg Vorbis','items':manifest},indent=2))
print('AUDIO_LIBRARY_COMPLETE',len(manifest),'clips /',sum(item['bytes'] for item in manifest),'runtime bytes')
