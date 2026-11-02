"""Synthesize the Doorgunner music stems into assets/sfx/ (22050 Hz, 16-bit mono, peak -1 dBFS, 16 s loops). Stdlib only, deterministic.

All stems share tempo (120 BPM, 4/4: bar = 2 s, 8 bars = 16 s) and key (A minor; F major in the second half), exactly like the
existing music_calm / music_tense from gen_sfx.py, so any set of them can play together and crossfade on a bar line (sfx.gd).
Every stem is rendered over two loop lengths and the second one is kept, so filters and note tails wrap around seamlessly.
Existing music_calm / music_tense are NOT touched here.
"""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
SR = 22050
TAU = 2 * math.pi
L = 16.0  # loop length in s
N = round(L * SR)
BAR = 2.0
S = 0.125  # one 16th note
random.seed(4711)
os.makedirs(OUT, exist_ok=True)

mf = lambda m: 440.0 * 2 ** ((m - 69) / 12)  # midi note -> Hz
q = lambda f: round(f * L) / L  # whole cycles per loop, so continuous oscillators close the loop


def times(sec):
	return [i / SR for i in range(round(sec * SR))]


def osc(freq, sec, shape="sine", ph0=0.0):
	out, ph = [], ph0
	for t in times(sec):
		ph = (ph + (freq(t) if callable(freq) else freq) / SR) % 1.0
		out.append(2.0 * ph - 1.0 if shape == "saw" else 4.0 * abs(ph - 0.5) - 1.0 if shape == "tri" else math.sin(TAU * ph))
	return out


def noise(sec):
	return [random.uniform(-1.0, 1.0) for _ in range(round(sec * SR))]


def lp(x, fc):
	out, y = [], 0.0
	for i, s in enumerate(x):
		f = fc(i / SR) if callable(fc) else fc
		y += (1.0 - math.exp(-TAU * f / SR)) * (s - y)
		out.append(y)
	return out


def hp(x, fc):
	return [s - l for s, l in zip(x, lp(x, fc))]


def clip(x, drive=2.0):
	g = math.tanh(drive)
	return [math.tanh(drive * s) / g for s in x]


def gain(x, g):
	return [s * g for s in x]


def norm(x):
	return gain(x, 1.0 / max(1e-6, max(abs(s) for s in x)))


def env(x, e):
	return [a * (e(i / SR) if callable(e) else e[i]) for i, a in enumerate(x)]


def decay(x, rate):
	return [s * math.exp(-i / SR * rate) for i, s in enumerate(x)]


def sweep(f0, f1, rate):
	return lambda t: f1 + (f0 - f1) * math.exp(-t * rate)


def mix(*parts):
	n = max(len(p) for p in parts)
	return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def fade(x, ms=4):
	n = min(len(x) // 2, int(SR * ms / 1000))
	for i in range(n):
		x[i] *= i / n
		x[-1 - i] *= i / n
	return x


def adsr(sec, a, d, s, r):
	e = []
	for t in times(sec):
		v = t / a if t < a else 1.0 + (s - 1.0) * (t - a) / d if t < a + d else s
		e.append(v * min(1.0, max(0.0, (sec - t) / r)))
	return e


def pluck(f, sec, rate):
	return decay(mix(osc(f, sec), gain(osc(2 * f, sec), 0.3), gain(osc(3 * f, sec), 0.1)), rate)


def buf():
	return [0.0] * (2 * N + 8)


def put(dst, src, sec):
	"""Place src at sec in both loop copies (the first copy's tails spill into the second one)."""
	for k in (0, 1):
		o = int((sec + k * L) * SR)
		for i, s in enumerate(src):
			if o + i < len(dst):
				dst[o + i] += s


def write(name, x):
	assert abs(x[2 * N - 1] - x[N - 1]) <= 0.02 * max(abs(s) for s in x[N:2 * N]), "%s does not close its loop" % name
	x = x[N:2 * N]
	peak = max(1e-6, max(abs(s) for s in x))
	pcm = [int(max(-1.0, min(1.0, s / peak * 0.891)) * 32767) for s in x]
	with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(struct.pack("<%dh" % len(pcm), *pcm))
	rms = math.sqrt(sum((p / 32767) ** 2 for p in pcm) / len(pcm))
	print("%-15s %d frames  rms %.1f dBFS" % (name, len(pcm), 20 * math.log10(rms)))


# ---- shared voices -----------------------------------------------------------------------------------------------
def sm(u):
	return 0.5 - 0.5 * math.cos(math.pi * min(1.0, max(0.0, u)))


def pad(freqs):
	"""Detuned saw + triangle voices (+-5/16 Hz), whole 2-loop length."""
	voice = lambda f: mix(osc(q(f - 0.3125), 2 * L, "saw", 0.4), gain(osc(q(f + 0.3125), 2 * L, "tri", 0.15), 0.5))
	return gain(mix(*(voice(f) for f in freqs)), 1.0 / (1.5 * len(freqs)))


def pad_seq(chords, bars_each, xf=1.0):
	"""One chord per bars_each bars, cosine-crossfaded over xf s; the window is periodic in the loop."""
	seg, out = bars_each * BAR, []
	for i, fs in enumerate(chords):
		a, b = i * seg, (i + 1) * seg
		win = lambda u: sm((u - (a - xf / 2)) / xf) * sm(((b + xf / 2) - u) / xf)
		w = [win(t) + win(t + L) + win(t - L) for t in times(L)]
		out.append(env(pad(fs), lambda t, w=w: w[int(t * SR) % N]))
	return mix(*out)


kick = lambda: decay(osc(sweep(130, 48, 35), 0.3), 12)
snare = lambda: mix(decay(norm(lp(hp(noise(0.2), 500), 7000)), 18), gain(decay(osc(sweep(260, 170, 30), 0.2), 25), 0.6))
tom = lambda f: decay(osc(sweep(f * 1.4, f, 18), 0.35), 9)
hat = lambda: decay(norm(hp(noise(0.06), 5000)), 90)
AM, F = (110.0, 130.81, 164.81, 220.0), (87.31, 110.0, 130.81, 174.61)  # A minor / F major chord tones, 2nd octave


# ---- stems -------------------------------------------------------------------------------------------------------
def combat():
	x = buf()
	k, sn, h = kick(), snare(), hat()
	for b in range(8):
		t0 = b * BAR
		root = 55.0 if b < 4 else 43.65
		for st, g in ((0, 1.0), (3, 0.8), (8, 1.0), (10, 0.7)):
			put(x, gain(k, g), t0 + st * S)
		for st in (4, 12):
			put(x, sn, t0 + st * S)
		if b == 7:
			for st in (13, 14, 15):
				put(x, gain(sn, 0.5), t0 + st * S)
		for st in range(16):
			put(x, gain(h, 1.0 if st % 2 else 0.5), t0 + st * S)
		for i, m in enumerate((1, 1, 2, 1, 1, 2, 1, 1.5)):
			put(x, fade(decay(osc(root * m, 0.24, "saw"), 9)), t0 + i * 0.25)
	return hp(clip(lp(x, 6500), 1.6), 35)


def assault():
	x = buf()
	crash = decay(norm(hp(noise(1.6), 4000)), 3)
	stabs = {id(ch): env(lp(pad([f * 2 for f in ch]), 1300)[:int(0.8 * SR)], adsr(0.8, 0.01, 0.2, 0.6, 0.5)) for ch in (AM, F)}
	for b in range(8):
		t0, ch = b * BAR, AM if b < 4 else F
		for st in range(16):
			put(x, gain(fade(decay(osc(ch[(0, 1, 2, 1, 0, 1, 2, 3)[st % 8]], 0.15, "saw"), 16)), 0.55), t0 + st * S)
		if b % 2 == 0:
			stab = stabs[id(ch)]
			put(x, stab, t0)
			put(x, stab, t0 + 10 * S)
		if b in (0, 4):
			put(x, gain(crash, 0.5), t0)
		if b in (3, 7):
			for i, f in enumerate((200, 170, 140, 110)):
				put(x, tom(f), t0 + (12 + i) * S)
	return hp(clip(lp(x, 5000), 1.8), 35)


def bloodmoon():
	x = buf()
	drone = gain(clip(lp(osc(q(55.0), 2 * L, "saw"), 160), 1.5), 0.8)
	trit = pad([q(110.0), q(155.56), q(233.08)])  # A, Eb (tritone), Bb: dark and unresolved
	trem = env(lp(trit, 600), lambda t: 0.55 + 0.45 * math.sin(TAU * 2 * t / L))
	beat = decay(osc(sweep(70, 38, 25), 0.4), 9)
	for k in range(16):  # lub-dub every 2 beats
		put(x, beat, k * 1.0)
		put(x, gain(beat, 0.7), k * 1.0 + 0.25)
	wail = env(osc(lambda t: 600 + 300 * t / 4.0, 4.0), lambda t: math.sin(math.pi * t / 4.0) ** 2)
	put(x, gain(lp(wail, 1800), 0.25), 12.0)
	return hp(mix(gain(drone, 0.9), gain(trem, 0.8), x), 30)


def victory():
	x = buf()
	pads = pad_seq([(130.81, 164.81, 196.0), (98.0, 123.47, 146.83), (110.0, 130.81, 164.81), (87.31, 110.0, 130.81)], 2)  # C G Am F
	chords = [(mf(60), mf(64), mf(67), mf(72)), (mf(55), mf(59), mf(62), mf(67)), (mf(57), mf(60), mf(64), mf(69)), (mf(53), mf(57), mf(60), mf(65))]
	for c, ch in enumerate(chords):
		for i in range(16):  # 8th arpeggio over each 2-bar chord
			put(x, gain(pluck(ch[(0, 1, 2, 3, 2, 1, 2, 1)[i % 8]], 0.5, 6), 0.45), c * 4.0 + i * 0.25)
	for beat, m, d in ((0, 76, 2), (2, 79, 2), (4, 84, 4), (8, 83, 2), (10, 86, 2), (12, 83, 4), (16, 81, 2), (18, 84, 2), (20, 88, 4), (24, 81, 2), (26, 79, 2), (28, 76, 4)):
		put(x, gain(fade(pluck(mf(m), d * 0.5 + 1.0, 2.5)), 0.7), beat * 0.5)
	timp = decay(osc(sweep(110, 70, 18), 0.5), 6)
	for b in range(8):
		put(x, timp, b * BAR)
		put(x, gain(timp, 0.6), b * BAR + 1.0)
	return hp(mix(gain(pads, 0.6), x), 35)


def title():
	x = buf()
	pads = lp(pad_seq([(110.0, 164.81, 220.0, 261.63), (87.31, 130.81, 174.61, 220.0), (130.81, 196.0, 261.63, 329.63), (98.0, 146.83, 196.0, 246.94)], 2, 1.5), 900)
	lead = ((0, 76, 2), (2, 81, 1), (3, 79, 1), (4, 76, 4), (8, 77, 2), (10, 81, 1), (11, 79, 1), (12, 77, 2), (14, 76, 2),
		(16, 79, 2), (18, 76, 1), (19, 74, 1), (20, 72, 4), (24, 71, 2), (26, 74, 2), (28, 79, 2), (30, 76, 2))
	for beat, m, d in lead:
		put(x, gain(fade(pluck(mf(m), d * 0.5 + 1.4, 1.8)), 0.8), beat * 0.5)
	t = tom(80)
	for b in range(8):
		put(x, gain(t, 0.8), b * BAR)
		put(x, gain(t, 0.4), b * BAR + 1.5)
	return hp(mix(gain(pads, 1.2), x), 35)


for name, fn in (("music_combat", combat), ("music_assault", assault), ("music_bloodmoon", bloodmoon), ("music_victory", victory), ("music_title", title)):
	write(name, fn())
