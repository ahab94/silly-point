"""Synthesizes every sound in audio/ from oscillators, noise and filters
(Python standard library only, so there's nothing to license). Run:
    /usr/bin/python3 tools/make_audio.py

Two families:
- Cricket: a woody "tock" off the middle, a "tick" off the edge, pad thuds,
  stumps clattering, and a crowd made of formant-filtered voices (real "oooh",
  "aaah" and "howzat" vowel shapes) plus clapping.
- Comedy: a duck quacking when you're out for nought, a sad trombone for
  wickets, a slide whistle for sixes, a boing off the helmet, a record
  scratch when a review is overturned, a pigeon cooing at Pigeon-Eye, and a
  brass band that has been at the bar since lunch.
"""
import math
import os
import random

from synth import SR, TAU, HERE, Track, at, hz, layer, noise, tone, write_wav, _wave

OUT = os.path.join(HERE, "..", "audio")


# --- building blocks ----------------------------------------------------------

def vibrato(freq, dur, vol, depth, rate, shape="sine", glide_to=None, decay=None, lowpass=None, attack=0.02):
    """A note with wobble: slide whistles, trombones, trumpets."""
    n = int(dur * SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    k = 1 - math.exp(-TAU * lowpass / SR) if lowpass else None
    for i in range(n):
        t = i / SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        f *= 1 + depth * math.sin(TAU * rate * t)
        p = (p + f / SR) % 1.0
        s = _wave(shape, p)
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0)
        env *= min(1.0, (dur - t) / 0.04)
        out[i] = s * env * vol
    return out


def bandpass(x, f, q):
    """Two-pole resonant bandpass (a vowel formant)."""
    w = TAU * f / SR
    alpha = math.sin(w) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
    b0, b2, a1, a2 = b0 / a0, b2 / a0, a1 / a0, a2 / a0
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, s in enumerate(x):
        o = b0 * s + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, s
        y2, y1 = y1, o
        y[i] = o
    return y


VOWELS = {"oo": (320, 870), "ah": (750, 1150), "aw": (580, 880), "ay": (640, 1750), "eh": (550, 1900)}


def voice(f0, dur, vowel, vol, glide=1.0, attack=0.1, decay=None, vowel_to=None, seed=0, jitter=0.02):
    """One person: a buzzy sawtooth through two vowel formants."""
    rng = random.Random(seed)
    n = int(dur * SR)
    src = [0.0] * n
    p = 0.0
    wob = rng.uniform(4, 7)
    for i in range(n):
        t = i / SR
        f = f0 * glide ** (t / dur) * (1 + jitter * math.sin(TAU * wob * t))
        p = (p + f / SR) % 1.0
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0) * min(1.0, (dur - t) / 0.08)
        src[i] = (2 * p - 1) * env
    f1, f2 = VOWELS[vowel]
    out = layer([s * 1.0 for s in bandpass(src, f1, 6)], [s * 0.6 for s in bandpass(src, f2, 8)])
    if vowel_to:
        # Crossfade into a second vowel (for "how-ZAT").
        g1, g2 = VOWELS[vowel_to]
        b = layer(bandpass(src, g1, 6), [s * 0.6 for s in bandpass(src, g2, 8)])
        out = [a * (1 - i / n) + c * (i / n) for i, (a, c) in enumerate(zip(out, b))]
    return [s * vol for s in out]


def crowd_vowel(vowel, dur, vol, people=14, glide=1.0, attack=0.12, decay=None, vowel_to=None, seed=1, spread=0.06):
    """A crowd saying a vowel together, everyone slightly out of time."""
    rng = random.Random(seed)
    parts = []
    for k in range(people):
        f0 = rng.uniform(110, 260) if k % 3 else rng.uniform(220, 380)
        parts.append(at(rng.uniform(0, spread), voice(f0, dur, vowel, vol / people ** 0.5, glide=glide * rng.uniform(0.97, 1.03),
                                                      attack=attack, decay=decay, vowel_to=vowel_to, seed=seed * 100 + k)))
    return layer(*parts, noise(dur, vol * 0.15, decay=decay, lowpass=1500, highpass=300, seed=seed, attack=attack))


def claps(dur, rate, vol, seed=3, fade=0.8):
    """Applause: lots of tiny noise bursts at random times."""
    rng = random.Random(seed)
    t = Track(dur + 0.1)
    count = int(dur * rate)
    for k in range(count):
        when = rng.uniform(0, dur) ** 1.0
        g = vol * (1 - (when / dur) ** 2 * fade)
        t.add(when, noise(0.03, g * rng.uniform(0.5, 1.0), decay=0.006, lowpass=rng.uniform(1800, 3500),
                          highpass=700, seed=seed * 1000 + k))
    return list(t.buf)


def trumpet(note, dur, vol=0.3, vib=0.006, glide_to=None):
    f = hz(note)
    return layer(vibrato(f, dur, vol, vib, 5.5, shape="saw", lowpass=2400, attack=0.03,
                         glide_to=hz(glide_to) if glide_to else None),
                 vibrato(f * 2, dur, vol * 0.25, vib, 5.5, shape="saw", lowpass=3500, attack=0.04))


def tune(notes, beat, inst, vol, start=0.0):
    """notes: [(note or None for a rest, beats), ...]"""
    t = start
    parts = []
    for n, b in notes:
        if n:
            parts.append(at(t, inst(n, b * beat * 0.95, vol)))
        t += b * beat
    return layer(*parts) if parts else []


# --- cricket ------------------------------------------------------------------

def tock(size=1.0, seed=3):
    """Middle of the bat: a sharp crack plus the willow ringing."""
    return layer(
        noise(0.03, 0.7 * size, decay=0.003, highpass=1500, seed=seed),
        tone(1180, 0.15, "sine", 0.5 * size, attack=0.0003, decay=0.022),
        tone(2350, 0.08, "sine", 0.22 * size, attack=0.0003, decay=0.01),
        tone(540, 0.2, "tri", 0.3 * size, attack=0.0005, decay=0.045),
        tone(260, 0.2, "sine", 0.25 * size, attack=0.001, decay=0.06),
    )


def edge():
    return layer(
        tone(3100, 0.06, "sine", 0.35, attack=0.0003, decay=0.01),
        noise(0.025, 0.4, decay=0.004, lowpass=9000, highpass=3000, seed=5),
    )


def pad():
    return layer(noise(0.15, 0.7, decay=0.03, lowpass=450, seed=7),
                 tone(130, 0.14, "sine", 0.5, attack=0.001, decay=0.04, glide_to=85),
                 noise(0.04, 0.2, decay=0.008, lowpass=2500, highpass=800, seed=8))


def stumps():
    rng = random.Random(9)
    t = Track(0.8)
    t.add(0.0, tone(760, 0.2, "sine", 0.55, attack=0.0005, decay=0.035))
    t.add(0.0, noise(0.08, 0.6, decay=0.01, lowpass=5000, highpass=600, seed=11))
    for k in range(7):
        t.add(0.05 + k * rng.uniform(0.04, 0.09), tone(rng.uniform(1300, 2600), 0.08, "sine", 0.25, attack=0.0005, decay=0.012))
    return list(t.buf)


def helmet():
    """Ball off the helmet: a clonk and a cartoon boing."""
    return layer(tone(950, 0.3, "sine", 0.45, decay=0.05), tone(1430, 0.25, "sine", 0.25, decay=0.04),
                 noise(0.03, 0.4, decay=0.005, highpass=2000, seed=12),
                 at(0.06, vibrato(170, 0.65, 0.5, 0.35, 11, shape="tri", glide_to=300, decay=0.28)))


def ooh():
    return crowd_vowel("oo", 1.5, 0.9, glide=0.82, attack=0.1, decay=0.9, seed=21)


def aah():
    return crowd_vowel("ah", 1.4, 0.8, glide=1.05, attack=0.08, decay=0.8, seed=22)


def groan():
    return crowd_vowel("aw", 1.6, 0.85, glide=0.7, attack=0.06, decay=0.9, seed=23)


def howzat():
    """The appeal: a crowd and fielders yelling "how-ZAT?" (rising)."""
    a = crowd_vowel("aw", 0.25, 0.7, people=10, glide=1.15, attack=0.03, seed=24, spread=0.04)
    b = crowd_vowel("ay", 0.6, 0.95, people=12, glide=1.25, attack=0.03, decay=0.5, seed=25, spread=0.05)
    return layer(a, at(0.22, b))


def cheer():
    return layer(crowd_vowel("ay", 2.4, 0.7, people=16, glide=1.08, attack=0.12, decay=1.2, seed=26, spread=0.2),
                 claps(2.6, 160, 0.35, seed=27))


def roar():
    return layer(crowd_vowel("ah", 3.2, 0.9, people=20, glide=1.12, attack=0.1, decay=1.6, seed=28, spread=0.25),
                 claps(3.4, 220, 0.4, seed=29))


def applause():
    return claps(3.0, 140, 0.45, seed=30)


def murmur(seconds=8.0):
    """Background crowd: distant chatter, the odd clap and call, looped."""
    t = Track(seconds, loop=True)
    t.add(0.0, noise(seconds, 0.22, decay=None, lowpass=650, highpass=140, seed=31))
    rng = random.Random(32)
    for k in range(10):
        t.add(rng.uniform(0, seconds), voice(rng.uniform(130, 300), rng.uniform(0.25, 0.6),
                                             rng.choice(["ah", "eh", "oo"]), 0.05, attack=0.05, decay=0.3, seed=200 + k))
    for k in range(18):
        t.add(rng.uniform(0, seconds), noise(0.03, 0.08, decay=0.006, lowpass=2800, highpass=700, seed=60 + k))
    return list(t.buf)


def click():
    return tone(1200, 0.04, "sine", 0.3, attack=0.0005, decay=0.008)


# --- comedy -------------------------------------------------------------------

def quack(f0, seed):
    """One quack: a nasal, falling buzz."""
    n = int(0.19 * SR)
    src = [0.0] * n
    p = 0.0
    for i in range(n):
        t = i / SR
        f = f0 * (1.25 - 0.45 * min(1.0, t / 0.19))
        p = (p + f / SR) % 1.0
        env = min(1.0, t / 0.008) * math.exp(-t / 0.09)
        src[i] = (2 * p - 1) * env
    return layer(bandpass(src, 1100, 4), [s * 0.8 for s in bandpass(src, 2300, 5)],
                 noise(0.02, 0.1, decay=0.005, highpass=2500, seed=seed))


def duck():
    """Out for nought: the walk of shame gets a duck."""
    return layer(quack(310, 1), at(0.24, quack(300, 2)), at(0.5, [s * 1.1 for s in quack(330, 3)]))


def sad_trombone():
    notes = [("D4", 0.3), ("C#4", 0.3), ("C4", 0.3), ("B3", 1.1)]
    t = 0.0
    parts = []
    for i, (n, d) in enumerate(notes):
        last = i == len(notes) - 1
        parts.append(at(t, vibrato(hz(n), d, 0.35, 0.035 if last else 0.012, 5.5, shape="saw",
                                   glide_to=hz(n) * (0.96 if last else 0.995), lowpass=1400)))
        t += d * 0.95
    return layer(*parts)


def slide_up():
    return vibrato(480, 0.6, 0.45, 0.012, 7, glide_to=2000, lowpass=5000)


def slide_down():
    return vibrato(1900, 0.6, 0.45, 0.012, 7, glide_to=400, lowpass=5000)


def record_scratch():
    return layer(noise(0.12, 0.6, decay=0.08, lowpass=900, sweep_to=4500, seed=41),
                 at(0.1, noise(0.16, 0.6, decay=0.1, lowpass=4500, sweep_to=600, seed=42)),
                 tone(300, 0.26, "saw", 0.12, glide_to=900, lowpass=2500, decay=0.12))


def coo():
    """A pigeon: coo-ROO-coo. Also Pigeon-Eye's signature tune."""
    def c(f, d, g):
        return vibrato(f, d, 0.4, 0.04, 22, glide_to=f * g, lowpass=900, attack=0.03)
    return layer(c(330, 0.22, 0.9), at(0.26, c(400, 0.42, 0.75)), at(0.74, c(320, 0.3, 0.85)))


def fanfare_four():
    """A short brass-band toot: the boundary riff."""
    beat = 0.14
    return layer(tune([("G4", 1), ("B4", 1), ("D5", 1), ("G5", 3)], beat, trumpet, 0.35),
                 tune([("D4", 1), ("G4", 1), ("B4", 1), ("D5", 3)], beat, trumpet, 0.2))


def fanfare_six():
    beat = 0.13
    mel = [("C5", 1), ("C5", 1), ("C5", 1), ("E5", 2), ("C5", 1), ("G5", 4)]
    low = [("E4", 1), ("E4", 1), ("E4", 1), ("G4", 2), ("E4", 1), ("C5", 4)]
    return layer(slide_up(), at(0.5, tune(mel, beat, trumpet, 0.38)), at(0.5, tune(low, beat, trumpet, 0.22)))


def win():
    beat = 0.16
    mel = [("C5", 1), ("E5", 1), ("G5", 1), ("C6", 2), ("G5", 1), ("C6", 4)]
    return layer(tune(mel, beat, trumpet, 0.38), tune([(n.replace("5", "4").replace("6", "5"), b) for n, b in mel], beat, trumpet, 0.2),
                 at(0.2, claps(2.4, 150, 0.35, seed=50)))


def ding():
    return layer(tone(hz("E6"), 0.9, "sine", 0.4, decay=0.3), tone(hz("E6") * 2.76, 0.4, "sine", 0.1, decay=0.1))


def brass_band(seconds_per_beat=0.5):
    """The menu theme: an oompah brass band, slightly tipsy. Loops."""
    beat = seconds_per_beat
    bars = 8
    total = bars * 4 * beat
    t = Track(total, loop=True)
    roots = ["D", "A", "D", "G", "D", "A", "G", "D"]
    triads = {"D": ("F#4", "A4"), "A": ("E4", "C#5"), "G": ("G4", "B4")}
    bass_oct = {"D": "D2", "A": "A1", "G": "G1"}
    for b, r in enumerate(roots):
        start = b * 4 * beat
        for k in range(4):
            if k % 2 == 0:   # oom
                t.add(start + k * beat, vibrato(hz(bass_oct[r] if k == 0 else bass_oct[r].replace("2", "1") if "2" in bass_oct[r] else bass_oct[r]), beat * 0.8,
                                                0.45, 0.004, 4, shape="tri", lowpass=600, decay=0.5, attack=0.02))
            else:            # pah
                for nn in triads[r]:
                    t.add(start + k * beat, vibrato(hz(nn), beat * 0.4, 0.09, 0.006, 5, shape="saw", lowpass=1500, attack=0.01))
        # A light snare on the offbeats.
        for k in (1, 3):
            t.add(start + k * beat, noise(0.12, 0.12, decay=0.04, highpass=1500, seed=b * 10 + k))
    melody = [("A4", 1), ("D5", 1), ("F#5", 1.5), ("E5", 0.5), ("D5", 1), ("E5", 1), ("C#5", 2),
              ("A4", 1), ("C#5", 1), ("E5", 1.5), ("D5", 0.5), ("C#5", 1), ("B4", 1), ("A4", 2),
              ("B4", 1), ("D5", 1), ("G5", 1.5), ("F#5", 0.5), ("E5", 1), ("D5", 1), ("F#5", 2),
              ("E5", 1), ("C#5", 1), ("A4", 1), ("C#5", 1), ("D5", 4)]
    t.add(0.0, tune(melody, beat, lambda n, d, v: trumpet(n, d, v, vib=0.012), 0.22))
    return list(t.buf)


def main():
    sfx = {
        "tock": tock(1.0), "tock_soft": tock(0.45, seed=4), "edge": edge(), "pad": pad(), "stumps": stumps(),
        "helmet": helmet(), "click": click(),
        "ooh": ooh(), "aah": aah(), "groan": groan(), "howzat": howzat(), "cheer": cheer(), "roar": roar(),
        "applause": applause(),
        "duck": duck(), "sad_trombone": sad_trombone(), "slide_up": slide_up(), "slide_down": slide_down(),
        "record_scratch": record_scratch(), "coo": coo(), "four": fanfare_four(), "six": fanfare_six(),
        "win": win(), "ding": ding(),
    }
    for name, s in sfx.items():
        write_wav(os.path.join(OUT, "sfx", name + ".wav"), s)
    write_wav(os.path.join(OUT, "loops", "murmur.wav"), murmur(), peak=0.5)
    write_wav(os.path.join(OUT, "music", "brass_band.wav"), brass_band(), peak=0.7)


if __name__ == "__main__":
    main()
