"""Original 120 BPM score for the SayKuku film. Every sound is synthesized; no samples.

Cues come from src/timeline.json, so the music always lands on the same frames as the picture.
Output: public/score.wav (48 kHz stereo, about -14 LUFS, true peak under -1 dBTP).
"""
import json
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.ndimage import maximum_filter1d
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parent.parent
TL = json.loads((ROOT / 'src/timeline.json').read_text())
FPS, SR = TL['fps'], 48000
DUR = TL['durationInFrames'] / FPS
N = int(DUR * SR)
BEAT = 60 / TL['bpm']
rng = np.random.default_rng(20261002)

dry = np.zeros((2, N))
verb = np.zeros((2, N))  # reverb send
duckable = np.zeros((2, N))  # bus that pumps under the kick


def sec(frame):
    return frame / FPS


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_of(length):
    return np.arange(int(length * SR)) / SR


def noise(length):
    return rng.standard_normal(int(length * SR))


def filt(x, kind, cutoff, order=2):
    sos = butter(order, cutoff, btype=kind, fs=SR, output='sos')
    return sosfilt(sos, x)


def place(bus, at, sig, gain=1.0, pan=0.0, send=0.0):
    start = int(round(at * SR))
    if start >= N or start + len(sig) <= 0:
        return
    sig = sig[: N - start] * gain
    left, right = np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)
    bus[0, start:start + len(sig)] += sig * left
    bus[1, start:start + len(sig)] += sig * right
    if send:
        verb[0, start:start + len(sig)] += sig * left * send
        verb[1, start:start + len(sig)] += sig * right * send


# ---------- instruments ----------

def kick(length=0.5, top=125, bottom=46, punch=26):
    t = t_of(length)
    freq = bottom + top * np.exp(-t * punch)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 6.5)
    click = filt(noise(0.006), 'highpass', 2500) * np.exp(-t_of(0.006) * 600) * 0.6
    body[: len(click)] += click
    return np.tanh(body * 1.6)


def boom(length=2.2, top=90, bottom=27):
    t = t_of(length)
    freq = bottom + top * np.exp(-t * 9)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 2.2)


def clap(length=0.32):
    x = np.zeros(int(length * SR))
    for i, off in enumerate([0, 0.011, 0.022, 0.031]):
        burst = noise(length - off) * np.exp(-t_of(length - off) * (90 if i < 3 else 16))
        x[int(off * SR):] += burst
    return filt(filt(x, 'highpass', 900), 'lowpass', 7000) * 0.9


def snare(length=0.3):
    t = t_of(length)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30)
    rattle = filt(noise(length), 'bandpass', [1800, 9000]) * np.exp(-t * 18)
    return tone * 0.7 + rattle


def hat(open_=False):
    length = 0.24 if open_ else 0.05
    t = t_of(length)
    return filt(noise(length), 'highpass', 7500) * np.exp(-t * (14 if open_ else 80))


def crash(length=2.6):
    t = t_of(length)
    metal = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in [3170, 4410, 5260, 6980, 8120])
    body = filt(noise(length), 'highpass', 4500) + metal * 0.08
    return body * np.exp(-t * 1.9) * 0.8


def key_click(big=False):
    length = 0.09
    t = t_of(length)
    tick = filt(noise(length), 'bandpass', [2500, 9000]) * np.exp(-t * 260)
    thock = np.sin(2 * np.pi * (140 if big else 210) * t) * np.exp(-t * 55)
    ping = np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 120) * 0.25
    return tick * 0.9 + thock * (1.1 if big else 0.5) + ping


def fm(freq, length, ratio=2.0, index=2.2, decay=6.0, index_decay=9.0, attack=0.002):
    t = t_of(length)
    env = np.minimum(1, t / attack) * np.exp(-t * decay)
    mod = index * np.exp(-t * index_decay) * np.sin(2 * np.pi * freq * ratio * t)
    return np.sin(2 * np.pi * freq * t + mod) * env


def bell(freq, length=2.4):
    return fm(freq, length, ratio=3.5, index=2.6, decay=2.2, index_decay=3.5) * 0.7 + fm(freq * 2, length, ratio=1.0, index=0.4, decay=4.0) * 0.2


def supersaw(notes, length, cutoff=3200, attack=0.02, release=0.4, voices=7, detune=0.16):
    t = t_of(length)
    out = np.zeros((2, len(t)))
    for note in notes:
        for v in range(voices):
            spread = (v - (voices - 1) / 2) / ((voices - 1) / 2)
            f = hz(note + spread * detune)
            phase = (f * t + rng.uniform()) % 1.0
            saw = 2 * phase - 1
            pan = spread * 0.85
            out[0] += saw * np.sqrt((1 - pan) / 2)
            out[1] += saw * np.sqrt((1 + pan) / 2)
    env = np.minimum(1, t / attack) * np.minimum(1, np.maximum(0, (length - t) / release))
    out = np.stack([filt(ch, 'lowpass', cutoff) for ch in out]) * env
    return out / (len(notes) * voices) * 2.2


def place_st(bus, at, sig, gain=1.0, send=0.0):
    start = int(round(at * SR))
    if start >= N:
        return
    sig = sig[:, : N - start] * gain
    bus[:, start:start + sig.shape[1]] += sig
    if send:
        verb[:, start:start + sig.shape[1]] += sig * send


def bass(note, length):
    t = t_of(length)
    f = hz(note)
    x = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 8)
    env = np.minimum(1, t / 0.004) * np.exp(-t * 3.2) * np.minimum(1, (length - t) / 0.02)
    return np.tanh(x * 1.4) * env


def sweep_noise(length, f0, f1, q=0.5, reverse=False):
    """Band-passed noise whose center moves from f0 to f1, processed in short blocks."""
    x = noise(length)
    out = np.zeros_like(x)
    block = 1024
    for i in range(0, len(x), block):
        p = i / len(x)
        center = f0 * (f1 / f0) ** p
        lo, hi = max(30, center * (1 - q)), min(SR / 2 - 100, center * (1 + q))
        out[i:i + block] = filt(x[i:i + block + 256], 'bandpass', [lo, hi])[: len(x[i:i + block])]
    env = np.linspace(0, 1, len(x)) ** 2
    return (out * (env[::-1] if reverse else env))


def whoosh(length=0.45):
    x = sweep_noise(length, 300, 5000, q=0.6)
    t = t_of(length)
    return x * np.sin(np.pi * t / length) ** 1.5 * 2


# ---------- harmony ----------
DM = [50, 53, 57, 64]          # Dm(add9)
BB = [46, 53, 57, 62]          # Bbmaj7
F = [53, 57, 60, 64]           # Fmaj7
C_ = [48, 55, 62, 64]          # Cadd9
A = [45, 52, 57, 61]           # A major (dominant)
D = [50, 54, 57, 61, 64]       # Dmaj9 for the brand
LOOP = [DM, BB, F, C_]
ROOTS = {id(DM): 38, id(BB): 34, id(F): 41, id(C_): 36, id(A): 33, id(D): 38}

drop = sec(TL['keyPresses'][0])
break_at, regroove = sec(TL['scenes']['double'][0]), sec(TL['keyPresses'][2]) + BEAT / 2
agent_land, verbs_at, finale = sec(TL['agentLand']), sec(TL['scenes']['verbs'][0]), sec(TL['finaleWipe'])


def chord_at(t):
    return LOOP[int((t - drop) // (4 * BEAT)) % 4]


# ---------- intro (0 - drop) ----------
place_st(duckable, 0, supersaw([n + 12 for n in DM[:3]], drop + 0.1, cutoff=900, attack=1.6, release=0.2), 0.32, send=0.4)
for at in TL['hookWords']:
    place(dry, sec(at), boom(1.2, 70, 34), 0.55)
    place_st(dry, sec(at), supersaw([38, 50, 57], 0.6, cutoff=2400, attack=0.004, release=0.5), 0.35, send=0.5)
for at in TL['typeTicks']:
    place(dry, sec(at), key_click(), 0.55, pan=rng.uniform(-0.3, 0.3), send=0.15)
riser = sweep_noise(drop - 1.6, 400, 9000, q=0.4)
place(dry, 1.6, riser, 0.5, send=0.3)
t = t_of(drop - 1.8)
place(dry, 1.8, np.sin(2 * np.pi * np.cumsum(220 * 2 ** (2 * t / t[-1])) / SR) * (t / t[-1]) ** 2 * 0.25, 0.6, send=0.4)
for i, at in enumerate(np.arange(drop - 0.75, drop - 0.06, BEAT / 4)):  # snare roll into the drop
    place(dry, at, snare(0.12), 0.18 + 0.35 * i / 6, send=0.2)
place(dry, drop - 1.2, crash(1.2)[::-1], 0.5)

# ---------- groove helpers ----------
kicks = []


def groove(start, stop, clap_beats=(1, 3), hats16=True, kick_gain=1.0):
    for k in range(int(round((stop - start) / BEAT))):
        at = start + k * BEAT
        kicks.append(at)
        place(dry, at, kick(), 0.78 * kick_gain)
        if k % 4 in clap_beats:
            place(dry, at, clap(), 0.5, send=0.35)
        for s in range(4 if hats16 else 2):
            off = s * BEAT / (4 if hats16 else 2)
            open_ = s == (2 if hats16 else 1)
            place(dry, at + off, hat(open_), (0.26 if open_ else 0.15) * (1.0 if s % 2 == 0 or not hats16 else 0.7), pan=0.25 if s % 2 else -0.2)
        chord = chord_at(at)
        # Bass pumps on the off-beat eighths.
        place(duckable, at + BEAT / 2, bass(ROOTS[id(chord)], BEAT / 2 - 0.01), 0.42)
        # 16th FM arp through the chord, an octave up.
        for s in range(4):
            note = chord[(k * 4 + s) % len(chord)] + 12 + (12 if s == 3 else 0)
            place(duckable, at + s * BEAT / 4, fm(hz(note), 0.22, ratio=1.0, index=1.6, decay=14, index_decay=20), 0.11, pan=0.4 * np.sin(k + s), send=0.3)


def pads(start, stop, gain=0.5, cutoff=4200):
    at = start
    while at < stop - 1e-6:
        bar_end = min(stop, drop + (np.floor((at - drop) / (4 * BEAT) + 1e-9) + 1) * 4 * BEAT)
        place_st(duckable, at, supersaw([n + 12 for n in chord_at(at)], bar_end - at + 0.15, cutoff=cutoff, attack=0.01, release=0.15), gain, send=0.25)
        at = bar_end


def impact(at, size=1.0, with_crash=True):
    place(dry, at, boom(2.4), 0.7 * size)
    place(dry, at, kick(0.6, 160, 40, 20), 0.8 * size)
    if with_crash:
        place(dry, at, crash(), 0.55 * size, send=0.4)
    kicks.append(at)


# ---------- A: drop to the break ----------
impact(drop, 1.15)
place(dry, drop, key_click(big=True), 0.9, send=0.2)
groove(drop, break_at)
pads(drop, break_at)
for i, at in enumerate(TL['speakWords']):  # each spoken word sings a note
    note = [81, 77, 74, 77, 79, 81][i % 6]
    place(dry, sec(at), bell(hz(note), 1.6), 0.16, pan=0.3 * np.sin(i * 2), send=0.5)
place(dry, sec(TL['dictationCommit']) - 0.5, sweep_noise(0.5, 600, 6000, q=0.3), 0.35, send=0.2)
land = sec(TL['dictationLand'])
impact(land, 0.55)
place_st(dry, land, supersaw([69, 74, 77, 81], 1.2, cutoff=5000, attack=0.003, release=1.0), 0.3, send=0.6)
for at in TL['montageLands']:
    place(dry, sec(at), fm(hz(86), 0.8, ratio=2.0, index=1.2, decay=5), 0.16, send=0.5)
    place(dry, sec(at), snare(), 0.28, send=0.3)
for start in [sec(TL['scenes']['montage'][0]), sec(600), sec(660)]:
    place(dry, start - 0.2, whoosh(), 0.5, pan=-0.3)
place(dry, sec(296), whoosh(0.6), 0.6, pan=0.3)
place(dry, sec(222), fm(hz(88), 0.12, ratio=1.0, index=0.5, decay=30), 0.12)  # pill appears

# ---------- break: Fn Fn ----------
place_st(duckable, break_at, supersaw([n + 12 for n in BB], regroove - break_at + 0.2, cutoff=700, attack=0.05, release=0.2), 0.4, send=0.5)
place(dry, break_at, sweep_noise(sec(TL['keyPresses'][1]) - break_at, 500, 7000, q=0.3), 0.3)
for at, chord in zip(TL['keyPresses'][1:], [BB, C_]):
    a = sec(at)
    place(dry, a, key_click(big=True), 0.9, send=0.25)
    place(dry, a, boom(1.4, 110, 32), 0.75)
    place_st(dry, a, supersaw([n + 12 for n in chord], 0.5, cutoff=4200, attack=0.003, release=0.45), 0.45, send=0.5)
    kicks.append(a)
place(dry, sec(792), fm(hz(88), 0.12, ratio=1.0, index=0.5, decay=30), 0.12)

# ---------- B: agent, lighter under the UI, then a build into the rewrite ----------
build = agent_land - 2 * BEAT
groove(regroove, build, clap_beats=(2,), hats16=False, kick_gain=0.85)
pads(regroove, verbs_at, gain=0.42, cutoff=3000)
place(dry, sec(840), whoosh(0.5)[::-1], 0.5)
place(dry, sec(840), boom(1.0, 90, 40), 0.4)
for i, at in enumerate(TL['commandWords']):
    place(dry, sec(at), bell(hz([74, 77, 81][i]), 1.6), 0.18, send=0.5)
for at in [TL['agentUnderstand'], TL['agentRun']]:
    place(dry, sec(at), fm(hz(93), 0.5, ratio=3.0, index=1.0, decay=7), 0.08, send=0.6)
for i, at in enumerate(np.arange(build, agent_land - 0.01, BEAT / 4)):
    place(dry, at, snare(0.14), 0.3 + 0.4 * i / 8, send=0.25)
    if i % 2 == 0:  # the kick keeps time through the build
        place(dry, at, kick(), 0.6 + 0.2 * i / 8)
        kicks.append(at)
place(dry, build, sweep_noise(agent_land - build, 600, 10000, q=0.35), 0.7)
impact(agent_land, 0.8)
groove(agent_land, verbs_at)

# ---------- verbs: four stop-time hits, ending on the dominant ----------
for at, chord in zip(TL['verbHits'], [BB, C_, DM, A]):
    a = sec(at)
    impact(a, 0.85, with_crash=at == TL['verbHits'][0])
    place(dry, a, snare(), 0.5, send=0.4)
    place_st(dry, a, supersaw([n + 12 for n in chord] + [chord[0] + 24], 0.48, cutoff=6000, attack=0.002, release=0.3), 0.55, send=0.5)
    place(dry, a, bass(ROOTS[id(chord)], 0.45), 0.7)
last = sec(TL['verbHits'][-1])
place(dry, last, sweep_noise(finale - last, 800, 12000, q=0.3), 0.45)
for i, at in enumerate(np.arange(last + BEAT / 4, finale - 0.02, BEAT / 8)):
    place(dry, at, snare(0.1), 0.12 + 0.2 * i / 4, send=0.2)

# ---------- finale in D major ----------
impact(finale, 1.2)
place_st(dry, finale, supersaw([n + 12 for n in D], DUR - finale, cutoff=4200, attack=0.004, release=3.5), 0.55, send=0.6)
place(dry, finale, bass(38, 3.0), 0.6)
for i, note in enumerate([74, 78, 81, 85, 88]):  # the bird draws itself
    place(dry, finale + 0.125 + i * BEAT / 4, bell(hz(note), 2.0), 0.16, pan=-0.4 + 0.2 * i, send=0.6)
dot = sec(TL['dotPop'])
place(dry, dot, fm(hz(93), 1.6, ratio=2.0, index=1.5, decay=3.5), 0.26, send=0.7)
place(dry, dot, fm(hz(98), 1.6, ratio=2.0, index=1.2, decay=3.8), 0.16, send=0.7)
place(dry, dot, kick(0.4, 90, 50, 30), 0.35)
place(dry, sec(1248), boom(1.6, 60, 36), 0.35)
for k, at in enumerate(np.arange(dot + BEAT, DUR, BEAT / 2)):  # soft shimmer that fades out
    place(dry, at, fm(hz(D[k % 5] + 24), 0.5, ratio=1.0, index=0.8, decay=6), 0.05 * max(0, 1 - (at - dot) / 3.2), pan=0.5 * np.sin(k), send=0.6)

# ---------- mix ----------
env = np.ones(N)
tt = np.arange(N) / SR
for at in kicks:
    i = int(at * SR)
    seg = tt[i:i + int(0.35 * SR)] - at
    env[i:i + len(seg)] = np.minimum(env[i:i + len(seg)], 1 - 0.62 * np.exp(-seg / 0.11))
mix = dry + duckable * env

ir_len = int(2.2 * SR)
ir_t = np.arange(ir_len) / SR
ir = np.stack([filt(rng.standard_normal(ir_len), 'lowpass', 6500) * np.exp(-ir_t * 3.0) for _ in range(2)])
ir[:, : int(0.012 * SR)] = 0  # pre-delay
wet = np.stack([fftconvolve(verb[c], ir[c])[:N] for c in range(2)])
mix = mix + filt(wet, 'highpass', 250) * 0.06

mix = np.stack([filt(ch, 'highpass', 28) for ch in mix])
fade = np.minimum(1, np.minimum(tt / 0.01, (DUR - tt) / 1.2))
mix *= fade


def measure(x):
    with tempfile.NamedTemporaryFile(suffix='.wav') as tmp:
        wavfile.write(tmp.name, SR, x.T.astype(np.float32))
        log = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', tmp.name, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
    lufs = float(re.findall(r'I:\s+(-?[\d.]+) LUFS', log)[-1])
    peak = float(re.findall(r'Peak:\s+(-?[\d.]+|-inf) dBFS', log)[-1])
    return lufs, peak


def limit(x, ceiling):
    """Look-ahead peak limiter on 4x-oversampled peaks, so true peak stays under the ceiling."""
    over = np.abs(resample_poly(x, 4, 1, axis=1)).max(axis=0).reshape(-1, 4).max(axis=1)[:x.shape[1]]
    look = int(0.004 * SR)
    peak = maximum_filter1d(over, size=2 * look + 1)
    gain = np.minimum(1, ceiling / np.maximum(peak, 1e-9))
    a = 1 - np.exp(-1 / (0.05 * SR))  # 50 ms release
    smoothed = lfilter([a], [1, a - 1], gain - 1) + 1
    applied = np.minimum(gain, smoothed)
    print(f'  limiter: max reduction {20 * np.log10(applied.min()):.1f} dB, >3 dB for {(applied < 0.708).mean() * DUR:.2f}s')
    return x * applied


target, ceiling = -14.0, 10 ** (-1.3 / 20)
for _ in range(4):
    lufs, _ = measure(mix)
    mix = limit(mix * 10 ** ((target - lufs) / 20), ceiling)
lufs, peak = measure(mix)
out = ROOT / 'public/score.wav'
out.parent.mkdir(exist_ok=True)
wavfile.write(out, SR, (np.clip(mix, -1, 1).T * 32767).astype(np.int16))
print(f'{out}: {DUR:.1f}s, {lufs:.1f} LUFS, true peak {peak:.1f} dBTP')
