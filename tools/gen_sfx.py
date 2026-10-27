"""Synthesize the Doorgunner sound effects into assets/sfx/ (22050 Hz, 16-bit mono). Stdlib only."""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
SR = 22050
random.seed(1337)
os.makedirs(OUT, exist_ok=True)


def write(name, samples):
	peak = max(1e-6, max(abs(s) for s in samples))
	with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.9)) * 32767)) for s in samples))


def times(seconds):
	return [i / SR for i in range(int(seconds * SR))]


def decay(t, rate):
	return math.exp(-t * rate)


def tone(freq, seconds, shape="sine", rate=0.0):
	"""Fixed-pitch oscillator; freq may be a function of t for sweeps."""
	out, phase = [], 0.0
	for t in times(seconds):
		f = freq(t) if callable(freq) else freq
		phase += f / SR
		x = phase % 1.0
		if shape == "square":
			v = 1.0 if x < 0.5 else -1.0
		elif shape == "saw":
			v = 2.0 * x - 1.0
		else:
			v = math.sin(TAU * x)
		out.append(v * decay(t, rate))
	return out


def noise(seconds, rate=0.0, cutoff=1.0):
	"""White noise through a one-pole lowpass (cutoff 0..1 or a function of t)."""
	out, y = [], 0.0
	for t in times(seconds):
		a = cutoff(t) if callable(cutoff) else cutoff
		y += a * (random.uniform(-1, 1) - y)
		out.append(y * decay(t, rate))
	return out


def mix(*parts):
	n = max(len(p) for p in parts)
	return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def fade(samples, ms=5):
	n = min(len(samples) // 2, int(SR * ms / 1000))
	for i in range(n):
		k = i / n
		samples[i] *= k
		samples[-1 - i] *= k
	return samples


def sweep(f0, f1, seconds):
	return lambda t: f0 + (f1 - f0) * min(1.0, t / seconds)


TAU = 2 * math.pi

write("gun", fade(mix(noise(0.06, rate=60, cutoff=0.6), tone(110, 0.06, rate=50))))
write("hit", fade(mix(tone(sweep(180, 60, 0.08), 0.08, rate=35), noise(0.04, rate=90, cutoff=0.3))))
write("enemy_die", fade(tone(lambda t: 600 * math.exp(-t * 7) + 80 + 25 * math.sin(TAU * 30 * t), 0.3, "square", rate=9)))
write("boss_roar", fade(tone(lambda t: 70 - 25 * t + 4 * math.sin(TAU * 6 * t), 0.8, "saw", rate=2.5), 30))
write("explosion", fade(noise(0.5, rate=7, cutoff=lambda t: max(0.03, 0.4 * decay(t, 6)))))
write("pickup", fade(tone(440, 0.07, "square", rate=20) + tone(660, 0.09, "square", rate=18)))
write("board", fade(tone(520, 0.08, rate=30), 10))
write("levelup", fade(sum((tone(f, 0.1, "square", rate=12) for f in (523, 659, 784, 1047)), [])))
write("radio", fade(mix(tone(900, 0.06, rate=10) + tone(1200, 0.06, rate=10), [n * 0.08 for n in noise(0.12, cutoff=0.5)])))
write("alarm", fade(tone(lambda t: 600 if int(t / 0.2) % 2 == 0 else 450, 0.8, "square"), 20))
write("land", fade(mix(tone(sweep(90, 40, 0.15), 0.15, rate=18), noise(0.1, rate=40, cutoff=0.15))))
write("takeoff", fade([s * min(1.0, t * 4) for s, t in zip(noise(0.5, rate=3, cutoff=lambda t: 0.05 + 0.5 * t), times(0.5))], 60))
write("ui", fade(mix(noise(0.02, rate=200, cutoff=0.8), tone(1500, 0.02, rate=150))))
write("base_hit", fade(mix(tone(50, 0.2, rate=14), noise(0.2, rate=25, cutoff=0.1))))

# rotor: 12 chops and 48 hum cycles per second, both periodic over the 1 s loop; the pulse is 0 at both ends
rotor = []
for t, n in zip(times(1.0), noise(1.0, cutoff=0.25)):
	pulse = (0.5 - 0.5 * math.cos(TAU * 12 * t)) ** 2
	rotor.append(n * pulse + 0.25 * math.sin(TAU * 48 * t) * (0.6 + 0.4 * pulse))
write("rotor", rotor)
print("wrote %d wavs to %s" % (len(os.listdir(OUT)), os.path.normpath(OUT)))
