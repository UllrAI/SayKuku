#!/usr/bin/env python3
"""Original sample-free SAYKUKU final score, deterministic Python synthesis.
15 seconds / 128 BPM / native 60 fps. Designed to the supplied cut and keypress frames.
Run: python scripts/make_score_final.py. Requires numpy, scipy, and FFmpeg.
Previous score versions are untouched. Output is 48kHz stereo 24-bit public/score-final.wav.
"""
from pathlib import Path
import json, subprocess, re
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile
ROOT=Path(__file__).resolve().parents[1]
SR=48000; DUR=15.; BPM=128; BEAT=60/BPM; FPS=60; N=int(DUR*SR)
# Shared visual/audio source of truth; the fallback keeps this file runnable alone.
BEATMAP=ROOT/'src'/'beatmap-real.ts'
DEFAULT_CUTS=[0,84,141,281,394,563,731]
DEFAULT_PRESSES=[113,309,323]

def read_array(source,names,default):
 for name in names:
  found=re.search(r'\b'+re.escape(name)+r'\s*(?::[^=]+)?=\s*\[([^\]]+)\]',source)
  if found:
   values=[int(v) for v in re.findall(r'\b\d+\b',found.group(1))]
   if values:return values
 return default
source=BEATMAP.read_text() if BEATMAP.exists() else ''
CUT_FRAMES=read_array(source,['cutFrames','CUT_FRAMES','cuts','CUTS'],DEFAULT_CUTS)
PRESS_FRAMES=read_array(source,['PRESS_FRAMES','keyPressFrames','KEY_PRESS_FRAMES','keypressFrames','fnPressFrames','FN_PRESS_FRAMES'],DEFAULT_PRESSES)
CUTS=[v/FPS for v in CUT_FRAMES]
# 128-BPM musical beats follow exact frame-quantized cut anchors; the <1-frame
# timing correction prevents double attacks against edit points.
ANCHOR_BEATS=[0,3,5,10,14,20,26,32]
ANCHOR_SECONDS=CUTS+[DUR]
def bt(beat):return float(np.interp(beat,ANCHOR_BEATS,ANCHOR_SECONDS))
rng=np.random.default_rng(410128)
buses={k:np.zeros((N,2),np.float64) for k in ['drums','bass','music','fx','room']}
kick_times=[]

def tvec(d): return np.arange(round(d*SR))/SR

def hz(n): return 440*2**((n-69)/12)

def hp(x,f=30): return sosfilt(butter(2,f,fs=SR,btype='high',output='sos'),x)

def lp(x,f=9000): return sosfilt(butter(2,f,fs=SR,btype='low',output='sos'),x)

def env_edge(x,a=.001,r=.012):
 x=x.copy(); na=min(len(x),max(2,int(a*SR))); nr=min(len(x),max(2,int(r*SR)))
 x[:na]*=np.linspace(0,1,na); x[-nr:]*=np.linspace(1,0,nr)**1.5
 return x

def mix(bus,x,start,g=1,p=0,room=0):
 i=round(start*SR)
 if i<0: x=x[-i:]; i=0
 n=min(len(x),N-i)
 if n<=0:return
 lr=np.array([np.cos((p+1)*np.pi/4),np.sin((p+1)*np.pi/4)])
 sig=x[:n,None]*lr*g
 buses[bus][i:i+n]+=sig
 if room:buses['room'][i:i+n]+=sig*room

def kick():
 t=tvec(.29); f=49+151*np.exp(-t/.014)+19*np.exp(-t/.075)
 ph=2*np.pi*np.cumsum(f)/SR
 body=(np.sin(ph)+.19*np.sin(2*ph)*np.exp(-t/.022))*np.exp(-t/.086)
 click=hp(lp(rng.standard_normal(len(t)),9500),1800)*np.exp(-t/.0035)*.31
 return env_edge(np.tanh((body+click)*1.9)/1.65,.00035,.016)

def kick_at(at,g=.83):
 kick_times.append(at);mix('drums',kick(),at,g)

def snare():
 t=tvec(.19); noise=hp(lp(rng.standard_normal(len(t)),10000),1350)
 ne=np.exp(-t/.037)
 for off,g in [(.008,.7),(.015,.45)]:ne+=g*(t>=off)*np.exp(-np.maximum(0,t-off)/.021)
 body=(np.sin(2*np.pi*185*t)+.25*np.sin(2*np.pi*330*t))*np.exp(-t/.026)
 return env_edge(np.tanh((noise*ne*.40+body*.35)*1.5)/1.5,.0005,.016)

def hat(open=False):
 t=tvec(.12 if open else .044)
 n=hp(rng.standard_normal(len(t)),7400)
 return env_edge(n*np.exp(-t/(.035 if open else .012)),.0004,.009)*.19

def snap():
 t=tvec(.09); n=hp(lp(rng.standard_normal(len(t)),13500),2400)
 click=n*np.exp(-t/.006)*.8
 tone=(np.sin(2*np.pi*1800*t)+.45*np.sin(2*np.pi*2950*t))*np.exp(-t/.012)*.21
 return env_edge(click+tone,.00025,.015)

def bass(note,d=.30,grit=1):
 t=tvec(d); f=hz(note); ph=2*np.pi*f*t
 # Solid centered sine/sub under band-limited, saturated upper harmonics.
 upper=np.zeros_like(t)
 for k in range(2,15):upper+=np.sin(ph*k+(.12 if k%2 else 0))/k**1.15
 sub=np.sin(ph)*.70; mid=np.tanh(upper*1.8)*.30*grit
 return env_edge((sub+mid)*(1-np.exp(-t/.003))*np.exp(-t/.7),.001,min(.032,d/4))*.59

def stab(notes,d=.24):
 t=tvec(d); out=np.zeros_like(t)
 for note in notes:
  f=hz(note)
  for det,g in [(.995,.24),(1,.52),(1.005,.24)]:
   for k in range(1,15):
    out+=g*np.sin(2*np.pi*f*det*k*t)/k**1.16*np.exp(-t/(.20/(1+.08*k)))
 return env_edge(np.tanh(out/len(notes)*1.7),.0025,.035)*.34

def arp(note,d=.18,accent=False):
 t=tvec(d); f=hz(note); out=np.zeros_like(t)
 # Bright band-limited saw sequence, rapid gate, with a small hard-sync-like octave.
 for k in range(1,19):
  out+=(np.sin(2*np.pi*f*k*t)+.23*np.sin(2*np.pi*f*1.004*k*t))/k**1.12*np.exp(-t/(.18/(1+.09*k)))
 out+=np.sin(2*np.pi*f*2*t)*np.exp(-t/.022)*.24
 return env_edge(np.tanh(out*1.30),.0017,.026)*(.24 if accent else .19)

def logo(note,d=.60):
 t=tvec(d); f=hz(note)
 tone=np.zeros_like(t)
 for k in range(1,10):tone+=np.sin(2*np.pi*f*k*t)/k**1.30*np.exp(-t/(.31/(1+.07*k)))
 return env_edge(np.tanh(tone*1.35),.0015,.065)*.31

def impact(at,g=.7):
 t=tvec(.35); f=40+95*np.exp(-t/.018); ph=2*np.pi*np.cumsum(f)/SR
 boom=np.sin(ph)*np.exp(-t/.095)*.55
 blast=hp(lp(rng.standard_normal(len(t)),8800),1550)*np.exp(-t/.026)*.29
 metal=(np.sin(2*np.pi*1060*t)+.35*np.sin(2*np.pi*1570*t))*np.exp(-t/.025)*.075
 mix('fx',env_edge(boom+blast+metal,.0004,.022),at,g,room=.08)
 mix('fx',snap(),at,g*.46,p=.06,room=.08)

def reverse_suck(cut):
 d=.16;t=tvec(d); f=350+2600*(t/d)**2
 ph=2*np.pi*np.cumsum(f)/SR
 no=hp(lp(rng.standard_normal(len(t)),6500),1800)
 x=(no*.19+np.sin(ph)*.15)*(t/d)**1.8
 mix('fx',env_edge(x,.003,.002),cut-.21,.83,p=-.25,room=.0)
 mix('fx',env_edge(x,.003,.002),cut-.21,.44,p=.55,room=.0)

def neon_swoosh(at,d=.64):
 t=tvec(d); u=t/d
 # Smooth Doppler/frequency sweep plus a bright filtered air layer.
 f=150+1850*(1-u)**2; ph=2*np.pi*np.cumsum(f)/SR
 fm=np.sin(ph+2.7*np.sin(2*np.pi*29*t)*(1-u))*.22
 air=hp(lp(rng.standard_normal(len(t)),11000),3200)*.16
 envelope=np.sin(np.pi*u)**.65*np.exp(-u*1.7)
 x=env_edge((fm+air)*envelope,.003,.025)
 mix('fx',x,at-.035,.70,p=-.63,room=.13)
 mix('fx',x,at+.042,.53,p=.63,room=.13)

# 0–2.35s: purposeful home/Fn opening, adding layers without delaying momentum.
for beat,g in [(0,.52),(1,.39),(2,.46),(3,.58),(4,.49)]:
 at=bt(beat);kick_at(at,g)
 mix('bass',bass(30,.25,.64),at+.035,.35 if beat<3 else .46)
 mix('drums',hat(),bt(beat+.5),.24,p=.24)
 if beat in (2,4):mix('drums',snare(),at,.26,p=.02,room=.045)
for beat,n,g in [(0,78,.34),(1,85,.29),(2,81,.31),(3,78,.39),(3.5,85,.26),(4,90,.37)]:
 mix('music',lp(arp(n,.23),5000),bt(beat),g,p=(-.20 if beat%2 else .22),room=.15)
mix('music',stab([66,69,73],.43),0,.47,p=-.18,room=.17)
mix('music',stab([66,69,73],.30),bt(3),.46,p=.18,room=.14)

# From the dictation cut: clear 128 BPM quarter-note pulse with spacious hats.
# Agent interpretation gets a half-time pocket before the completed-text lift.
for beat in range(5,26):
 at=bt(beat);half=14<=beat<20
 if not half or beat%2==0:kick_at(at,.83)
 if (half and beat%4==2) or (not half and beat%2==1):
  mix('drums',snare(),at,.56,p=.02,room=.055)
 mix('drums',hat(open=beat%2==0),bt(beat+.5),.43,p=.23,room=.018)
 if beat>=20 or beat in (9,13):
  mix('drums',hat(),bt(beat+.75),.18,p=-.25)
for beat,g in [(8.5,.34),(12.5,.36),(21.5,.36),(24.5,.34)]:kick_at(bt(beat),g)
for beat,g in [(13.5,.16),(19.5,.19),(19.75,.24),(25.5,.18)]:
 mix('drums',snare(),bt(beat),g,p=-.06,room=.025)

# One bass pattern and a restrained eighth-note saw motif, rather than busy runs.
phrases=[(5,10,30,[66,69,73],[78,81,85,90,85,81,78,85]),
         (10,14,26,[62,66,69],[74,78,81,86,81,78,74,81]),
         (14,20,33,[64,69,73],[76,81,85,88,85,81,76,85]),
         (20,26,30,[66,69,73],[78,81,85,90,85,81,78,85])]
for begin,end,root,chord,pattern in phrases:
 mix('music',stab(chord,.38),bt(begin),.70,p=-.25,room=.15)
 mix('music',stab([n+12 for n in chord],.23),bt(begin)+.018,.21,p=.40,room=.12)
 for beat in range(begin,end):
  mix('bass',bass(root,.30,.96),bt(beat+.13),.84 if beat%2==0 else .71)
  if beat%4==3:mix('bass',bass(root+12,.16,.84),bt(beat+.75),.42)
 for j,b in enumerate(np.arange(begin,end,.5)):
  if 14<=b<20 and j%2:continue
  note=pattern[j%8];g=.58 if 14<=b<20 else .66
  if j%4==0:g*=1.13
  mix('music',arp(note,.20,j%4==0),bt(b),g,p=(-.28 if j%2==0 else .30),room=.13)
  if j%4==0:mix('music',arp(note,.13),bt(b+.75),g*.13,p=.55,room=.05)

# Thump, click and brief swish on the actual-product transition frames.
for i,at in enumerate(CUTS):
 impact(at,.66 if i<2 else .90)
 if at>0:reverse_suck(at)
 if i in (2,4,5):neon_swoosh(at,.30)
# Frame 309 and frame 323 are two taps of the SAME key, with matching sounds.
# Synthesize once, reuse identically for the press pair, and include release ticks.
keyclick=snap()
for frame in PRESS_FRAMES:
 at=frame/FPS
 mix('fx',keyclick,at,1.01,p=0,room=.017)
 t=tvec(.06);x=np.sin(2*np.pi*(275-110*t/.06)*t)*np.exp(-t/.010)
 mix('fx',env_edge(x,.00025,.01),at,.25)
 mix('fx',keyclick,at+.086,.19,p=0,room=0)

# Brand at 12.183s: a memorable F#–C#–F# logo and a full graceful decay.
logo_start=CUTS[-1]
kick_at(logo_start,.87)
mix('bass',bass(30,1.17,.75),logo_start+.035,.97)
mix('music',stab([66,69,73,78],.50),logo_start,.99,p=-.10,room=.21)
for off,n,g in [(0,78,.84),(.234375,85,.76),(.46875,90,.91),(.9375,85,.43),(1.40625,90,.57)]:
 mix('music',logo(n,.77),logo_start+off,g,p=(-.15 if n==85 else .11),room=.24)
for off,g in [(.46875,.23),(.9375,.16),(1.40625,.10)]:
 mix('drums',hat(),logo_start+off,g,p=.19)

# Short diffused stereo room. All generated in-process, no impulse-response files.
room=np.zeros_like(buses['room'])
for sec,g,cross in [(.045,.26,True),(.081,.21,False),(.123,.15,True),(.177,.11,False),(.241,.075,True),(.329,.04,False)]:
 sh=round(sec*SR);src=buses['room'][:,::-1] if cross else buses['room']
 room[sh:]+=src[:-sh]*g
for c in range(2):room[:,c]=hp(lp(room[:,c],6800),500)
# Kick-triggered ducking keeps the bass powerful without swallowing the drum attack.
duck=np.ones(N)
for at in kick_times:
 i=round(at*SR);m=min(round(.19*SR),N-i)
 if m<=0:continue
 t=np.arange(m)/SR
 shape=1-.69*np.exp(-t/.052)
 duck[i:i+m]=np.minimum(duck[i:i+m],shape)
buses['bass']*=duck[:,None]
buses['music']*=(.60+.40*duck)[:,None]
master=buses['drums']+buses['bass']+buses['music']+buses['fx']+room
for c in range(2):master[:,c]=hp(master[:,c],28)
# Punchy soft saturation, used before final true-peak controlled loudness mastering.
master=np.tanh(master*1.10)/1.10
# Purposeful 50ms of silence before every supplied hard cut; a 3ms fade avoids pops.
for at in CUTS[1:]:
 stop=round((at-.05)*SR);fade=round(.003*SR);cut=round(at*SR)
 master[stop-fade:stop]*=np.linspace(1,0,fade)[:,None]
 master[stop:cut]=0
# End naturally and exactly at 15 seconds, preserving the final sonic-logo impact.
i=round(14.45*SR);master[i:]*=np.linspace(1,0,N-i)[:,None]**1.6
master[-1]=0
master*=.94/max(1e-12,np.max(np.abs(master)))
pre=ROOT/'public'/'score-final-premaster.wav';out=ROOT/'public'/'score-final.wav'
wavfile.write(pre,SR,master.astype(np.float32))
base=['ffmpeg','-hide_banner','-nostats','-i',str(pre)]
scan=subprocess.run(base+['-af','loudnorm=I=-12.5:TP=-1.95:LRA=6:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
stats=json.JSONDecoder().raw_decode(scan.stderr[scan.stderr.rfind('{'):])[0]
filt=('loudnorm=I=-12.5:TP=-1.95:LRA=6:linear=true:'
 f"measured_I={stats['input_i']}:measured_TP={stats['input_tp']}:measured_LRA={stats['input_lra']}:measured_thresh={stats['input_thresh']}:offset={stats['target_offset']}")
subprocess.run(base+['-af',filt,'-ar',str(SR),'-ac','2','-c:a','pcm_s24le','-y',str(out)],capture_output=True,text=True,check=True)
pre.unlink()
check=subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(out),'-af','loudnorm=I=-12.5:TP=-1.95:LRA=6:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
s=json.JSONDecoder().raw_decode(check.stderr[check.stderr.rfind('{'):])[0]
sr,a=wavfile.read(out);a=a.astype(np.float64)/2147483648
report={'file':str(out.relative_to(ROOT)),'duration_seconds':len(a)/sr,'sample_rate':sr,'channels':2,'bit_depth':24,'bpm':BPM,
 'integrated_lufs':float(s['input_i']),'true_peak_dbtp':float(s['input_tp']),'loudness_range_lu':float(s['input_lra']),
 'sample_peak_dbfs':float(20*np.log10(np.max(np.abs(a)))),'sample_free':True,'seed':410128,'cut_frames':CUT_FRAMES,
 'cut_seconds':CUTS,'keypress_frames':PRESS_FRAMES,'keypress_seconds':[v/FPS for v in PRESS_FRAMES],
 'precut_silence_seconds':.05,'logo_start_seconds':CUTS[-1],'timing_source':str(BEATMAP.relative_to(ROOT)),'native_fps':FPS,'final_sample':a[-1].tolist(),
 'description':'Original 128 BPM lively cinematic electronic score aligned to actual-product cuts: clear drums, rich sub-bass, restrained saw arpeggio, half-time Agent pocket, identical same-key double-press snaps, and brand sonic logo.'}
(ROOT/'public'/'score-final-analysis.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
