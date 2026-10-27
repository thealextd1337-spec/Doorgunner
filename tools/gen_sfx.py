"""Synthesize the Doorgunner sound effects into assets/sfx/ (44100 Hz, 16-bit mono, peak -1 dBFS). Stdlib only, deterministic."""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
SR = 44100
TAU = 2 * math.pi
XF = 2048  # loop seam crossfade in samples
random.seed(1337)
os.makedirs(OUT, exist_ok=True)


def write(name, samples, is_loop=False):
	peak = max(1e-6, max(abs(s) for s in samples))
	pcm = [int(max(-1.0, min(1.0, s / peak * 0.891)) * 32767) for s in samples]  # 0.891 = -1 dBFS
	with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(struct.pack("<%dh" % len(pcm), *pcm))
	if is_loop:
		print("loop %-12s first=%6d last=%6d  seam ok=%s" % (name, pcm[0], pcm[-1], abs(pcm[0] - pcm[-1]) <= 200))
		assert abs(pcm[0] - pcm[-1]) <= 200, name


# ---- building blocks ---------------------------------------------------------------------------
def times(sec):
	return [i / SR for i in range(round(sec * SR))]


def osc(freq, sec, shape="sine", ph0=0.0):
	"""Phase-accumulating oscillator; freq may be a function of t; ph0 = start phase 0..1."""
	out, ph = [], ph0
	for t in times(sec):
		ph = (ph + (freq(t) if callable(freq) else freq) / SR) % 1.0
		if shape == "saw":
			v = 2.0 * ph - 1.0
		elif shape == "tri":
			v = 4.0 * abs(ph - 0.5) - 1.0
		else:
			v = math.sin(TAU * ph)
		out.append(v)
	return out


def fm(freq, ratio, index, sec):
	"""Sine carrier phase-modulated by a sine at ratio*freq; index may be a function of t."""
	out, ph = [], 0.0
	for t in times(sec):
		f = freq(t) if callable(freq) else freq
		ph = (ph + f / SR) % 1.0
		out.append(math.sin(TAU * ph + (index(t) if callable(index) else index) * math.sin(TAU * ratio * ph)))
	return out


def noise(sec):
	return [random.uniform(-1.0, 1.0) for _ in range(round(sec * SR))]


def lp(x, fc):
	"""One-pole low-pass; fc in Hz or a function of t."""
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


def adsr(sec, a, d, s, r):
	e = []
	for t in times(sec):
		if t < a:
			v = t / a
		elif t < a + d:
			v = 1.0 + (s - 1.0) * (t - a) / d
		else:
			v = s
		e.append(v * min(1.0, max(0.0, (sec - t) / r)))
	return e


def sweep(f0, f1, rate):
	"""Exponential pitch glide f0 -> f1."""
	return lambda t: f1 + (f0 - f1) * math.exp(-t * rate)


def mix(*parts):
	n = max(len(p) for p in parts)
	return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def at(sec, x):
	"""Delay x by sec (for mix offsets)."""
	return [0.0] * int(sec * SR) + x


def place(dst, src, sec):
	o = int(sec * SR)
	for i, s in enumerate(src):
		if o + i < len(dst):
			dst[o + i] += s
	return dst


def fade(x, ms=5):
	n = min(len(x) // 2, int(SR * ms / 1000))
	for i in range(n):
		x[i] *= i / n
		x[-1 - i] *= i / n
	return x


def loop(x, sec):
	"""Seamless loop: render sec + XF samples, crossfade the overhang into the head."""
	n = round(sec * SR)
	out = x[:n]
	for i in range(XF):
		out[i] = out[i] * (i / XF) + x[n + i] * (1 - i / XF)
	return out


def pluck(f, sec, rate):
	return decay(mix(osc(f, sec), gain(osc(2 * f, sec), 0.3), gain(osc(3 * f, sec), 0.1)), rate)


# ---- one-shots ---------------------------------------------------------------------------------
# gun: sub thump + band-limited noise crack + short metallic ring, soft clipped
sub = decay(osc(sweep(90, 55, 30), 0.12), 35)
crack = decay(norm(lp(hp(noise(0.12), 700), 6000)), 90)
ring = gain(decay(mix(osc(2300, 0.12), gain(osc(3400, 0.12), 0.5)), 70), 0.15)
write("gun", fade(clip(mix(gain(sub, 1.2), crack, ring), 2.5)))

# hit: short pitched thump + dull noise
write("hit", fade(clip(mix(decay(osc(sweep(200, 70, 40), 0.1), 40), gain(decay(norm(lp(noise(0.1), 2500)), 80), 0.8)), 2)))

# enemy_die: FM squelch gliding down + sweeping noise burst + bubbly wobble
sq = decay(fm(sweep(420, 90, 8), 2.3, lambda t: 6 * math.exp(-t * 5), 0.4), 7)
burst = gain(decay(norm(lp(noise(0.4), sweep(3500, 300, 10))), 12), 0.7)
bubble = gain(decay(osc(lambda t: 160 + 90 * math.sin(TAU * 23 * t), 0.4), 9), 0.5)
write("enemy_die", fade(clip(mix(sq, burst, bubble), 2)))

# boss_roar: four detuned saws with slow vibrato + AM noise growl, low-passed, driven, ADSR
sec = 1.1
vib = lambda t: 1 + 0.02 * math.sin(TAU * 5 * t)
saws = mix(*(osc(lambda t, k=k: 52 * k * vib(t), sec, "saw") for k in (1.0, 1.012, 0.988, 2.005)))
growl = gain(env(norm(lp(noise(sec), 350)), lambda t: 0.5 + 0.5 * math.sin(TAU * 28 * t)), 1.5)
write("boss_roar", env(clip(lp(mix(saws, growl), 900), 3.0), adsr(sec, 0.08, 0.2, 0.7, 0.4)))

# explosion: pitch-dropping boom + sweeping low-passed noise + sparse crackle tail, tanh distortion
sec = 1.3
boom = decay(osc(sweep(95, 32, 6), sec), 4)
body = decay(norm(lp(noise(sec), sweep(3500, 120, 5))), 3.5)
crackle = decay(at(0.08, norm(lp([random.uniform(-1, 1) if random.random() < 0.004 else 0.0 for _ in times(sec)], 2500))), 2.5)
write("explosion", fade(clip(mix(gain(boom, 1.3), body, gain(crackle, 0.8)), 3), 20))

# pickup: two warm plucks (sine + harmonics) a fifth apart
write("pickup", fade(mix(pluck(660, 0.25, 14), at(0.07, pluck(990, 0.25, 12)))))

# board: soft door thunk + low pluck
write("board", fade(mix(pluck(392, 0.25, 16), decay(norm(lp(noise(0.05), 800)), 120))))

# levelup: rising C-major arpeggio of overlapping plucks, last note rings
lv = []
for i, f in enumerate((523, 659, 784, 1047)):
	lv = mix(lv, at(0.11 * i, pluck(f, 0.7, 4 if i == 3 else 7)))
write("levelup", fade(lv))

# radio: PTT click + static burst + two-tone chirp + release click, all band-limited to 400-3500 Hz
click = decay(norm(lp(noise(0.01), 3000)), 400)
static = decay(norm(lp(hp(noise(0.08), 900), 3500)), 25)
chirp = gain(mix(decay(osc(1050, 0.05), 20), at(0.05, decay(osc(1400, 0.05), 20))), 0.6)
write("radio", fade(clip(lp(hp(mix(click, at(0.01, static), at(0.07, chirp), at(0.18, click)), 400), 3500), 2)))

# alarm: two-tone siren (sine + soft harmonics) with 12 ms gated edges
sec = 1.0
sf = lambda t: 540 if int(t / 0.25) % 2 == 0 else 400
gate = lambda t: min(1.0, min(t % 0.25, 0.25 - t % 0.25) / 0.012)
siren = mix(osc(sf, sec), gain(osc(lambda t: 2 * sf(t), sec), 0.3), gain(osc(lambda t: 3 * sf(t), sec, "tri"), 0.15))
write("alarm", fade(lp(env(siren, gate), 2500), 15))

# land: skid thump + sweeping noise + faint clank
thump = decay(osc(sweep(85, 32, 25), 0.35), 12)
skid = decay(norm(lp(noise(0.35), sweep(900, 200, 15))), 14)
clank = gain(decay(mix(osc(1700, 0.35), gain(osc(2900, 0.35), 0.4)), 40), 0.12)
write("land", fade(clip(mix(gain(thump, 1.3), gain(skid, 0.7), clank), 2)))

# takeoff: rising filtered noise + rising low hum, swelling in and fading out
sec = 0.9
rise = norm(lp(noise(sec), lambda t: 150 + 2400 * t / sec))
hum = gain(norm(lp(osc(lambda t: 38 + 32 * t / sec, sec, "saw"), 200)), 0.6)
write("takeoff", fade(clip(env(mix(rise, hum), adsr(sec, 0.4, 0.0, 1.0, 0.3)), 2), 20))

# ui: soft short tick
write("ui", fade(mix(decay(osc(1300, 0.03), 120), gain(decay(osc(2600, 0.03), 200), 0.3), gain(decay(norm(lp(noise(0.03), 4000)), 300), 0.4))))

# base_hit: deep sub + mid thud + low rumble, driven
sec = 0.45
write("base_hit", fade(clip(mix(decay(osc(sweep(60, 38, 10), sec), 8), gain(decay(osc(sweep(140, 70, 20), sec), 18), 0.6), gain(decay(norm(lp(noise(sec), 350)), 9), 0.8)), 3), 20))

# weapon_swap: two mechanical clacks with a slide of noise between
clack = lambda f: mix(decay(norm(lp(hp(noise(0.06), 400), 5000)), 150), gain(decay(osc(f, 0.06), 90), 0.5))
slide = gain(decay(norm(lp(hp(noise(0.06), 1000), 3000)), 40), 0.3)
write("weapon_swap", fade(clip(mix(clack(1500), at(0.03, slide), at(0.09, clack(1100))), 2)))

# survivor_lost: descending sad two-note (E4 -> C4), sine + triangle with vibrato, dark
sad = lambda f, sec: decay(mix(osc(lambda t: f * (1 + 0.006 * math.sin(TAU * 5 * t)), sec), gain(osc(f, sec, "tri"), 0.4)), 4)
write("survivor_lost", fade(lp(mix(sad(330, 0.6), at(0.35, sad(262, 0.8))), 1800), 10))

# town_alarm: distant church bell, inharmonic FM with decaying index, two strikes, low-passed
bell = lambda sec: decay(mix(fm(440, 1.41, lambda t: 2.5 * math.exp(-t * 1.5), sec), gain(fm(1214, 1.41, lambda t: math.exp(-t * 3), sec), 0.3)), 2.2)
write("town_alarm", fade(lp(mix(bell(2.0), at(0.7, bell(1.8))), 2200), 10))


# ---- loops (periodic parts use integer cycles over the loop length; noise is seam-crossfaded) ----
def rotor_loop(chop_hz, cut, whine_hz, drive):
	sec = 1.0 + XF / SR
	chop = lambda t: (0.5 - 0.5 * math.cos(TAU * chop_hz * t)) ** 3
	air = env(norm(lp(noise(sec), lambda t: cut + 500 * chop(t))), chop)
	thud = [0.5 * math.sin(TAU * 4 * chop_hz * t) * (0.4 + 0.6 * chop(t)) for t in times(sec)]
	whine = [0.04 * (math.cos(TAU * whine_hz * t) + 0.5 * math.cos(TAU * 2 * whine_hz * t)) * (0.85 + 0.15 * chop(t)) for t in times(sec)]
	return clip(mix(air, thud, whine), drive)


# rotor: 11 Hz blade chop over low-passed noise + 44 Hz blade thud + 1210 Hz turbine whine
write("rotor", loop(rotor_loop(11, 300, 1210, 1.8), 1.0), True)
# hover: slower 8 Hz chop, lower whine, plus dust hiss puffing with each blade pass (extra layer while landed)
dust = env(gain(norm(lp(hp(noise(1.0 + XF / SR), 300), 1500)), 0.3), lambda t: math.sin(TAU * 4 * t) ** 2)  # pulses with the 8 Hz chop
write("hover", loop(mix(rotor_loop(8, 250, 900, 1.6), dust), 1.0), True)

# wind: brown noise (low-passed white) with gust-modulated cutoff and slow amplitude LFOs (2 and 5 cycles / 8 s)
sec = 8.0 + XF / SR
lfo = lambda t: 0.55 + 0.25 * math.sin(TAU * 0.25 * t) + 0.2 * math.sin(TAU * 0.625 * t + 1.0)
write("wind", loop(env(norm(lp(hp(lp(noise(sec), 60), 30), lambda t: 250 + 500 * lfo(t))), lfo), 8.0), True)

# night: darker bed + 55 Hz drone with slow swell + 7 distant alien chitters (3-6 FM blips each)
bed = env(norm(lp(hp(lp(noise(sec), 40), 25), 160)), lambda t: 0.6 + 0.3 * math.sin(TAU * 0.375 * t))
drone = [0.15 * math.sin(TAU * 55 * t) * (0.7 + 0.3 * math.sin(TAU * 0.375 * t + 2.0)) for t in times(sec)]
chit = [0.0] * len(bed)
for _ in range(7):
	start, f = random.uniform(0.2, 7.3), random.uniform(1700, 2600)
	for p in range(random.randint(3, 6)):
		place(chit, decay(fm(f * random.uniform(0.95, 1.05), 1.5, 2.0, 0.02), 150), start + p * 0.03)
write("night", loop(mix(bed, drone, gain(lp(chit, 3000), 0.35)), 8.0), True)

# music: pad voices are a saw + triangle detuned by +-5/16 Hz (integer cycles over 16 s) so the loop closes
L = 16.0
sec = L + XF / SR
q = lambda f: round(f * L) / L
# saw starts mid-ramp (no edge at the seam); the half-gain triangle starts on its falling slope so the stack has no net ramp there
voice = lambda f: mix(osc(q(f - 0.3125), sec, "saw", 0.4), gain(osc(q(f + 0.3125), sec, "tri", 0.15), 0.5))
pad = lambda freqs: gain(mix(*(voice(f) for f in freqs)), 1.0 / (1.5 * len(freqs)))

# music_calm: A minor <-> F major pads crossfading over one 16 s cosine, slow filter LFO
ga = lambda t: 0.5 + 0.5 * math.cos(TAU * (t - 4.0) / L)
calm = mix(env(pad((55.0, 110.0, 164.81, 261.63)), ga), env(pad((65.41, 130.81, 174.61, 220.0)), lambda t: 1.0 - ga(t)))
write("music_calm", loop(clip(hp(lp(calm, lambda t: 350 + 150 * math.sin(TAU * 0.125 * t)), 35), 1.2), L), True)

# music_tense: D minor pad with faster filter LFO + 8-step low saw ostinato (0.25 s steps) + tom pulse every 0.5 s
tense_pad = lp(pad((73.42, 110.0, 174.61)), lambda t: 300 + 200 * math.sin(TAU * 0.5 * t))
ost = [0.0] * len(tense_pad)
pulse = [0.0] * len(tense_pad)
for i in range(int(sec / 0.25) + 1):
	f = (36.71, 36.71, 73.42, 36.71, 43.65, 36.71, 73.42, 34.65)[i % 8]
	place(ost, fade(decay(osc(f, 0.25, "saw"), 10)), i * 0.25)
	if i % 2 == 0:
		place(pulse, decay(osc(sweep(90, 45, 30), 0.3), 12 if i % 8 else 8), i * 0.25)
tense = mix(gain(tense_pad, 0.5), gain(clip(lp(ost, 450), 2), 0.6), gain(pulse, 0.5))
write("music_tense", loop(hp(tense, 35), L), True)

print("wrote %d wavs to %s" % (len([f for f in os.listdir(OUT) if f.endswith(".wav")]), os.path.normpath(OUT)))
