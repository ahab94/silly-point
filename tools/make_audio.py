"""Synthesizes every sound in audio/ from oscillators and noise (Python
standard library only, so there's nothing to license). Run:
    python3 tools/make_audio.py
"""
import os
import random

from synth import SR, HERE, Track, at, layer, noise, tone, write_wav

OUT = os.path.join(HERE, "..", "audio")


def tock():
    """Middle of the bat: a woody knock with a bright crack on top."""
    return layer(
        tone(820, 0.16, "sine", 0.55, attack=0.0005, decay=0.03),
        tone(1650, 0.1, "sine", 0.25, attack=0.0005, decay=0.015),
        tone(410, 0.18, "tri", 0.2, attack=0.0005, decay=0.05),
        noise(0.05, 0.5, decay=0.006, lowpass=6000, highpass=900, seed=3),
    )


def edge():
    """A thin, high tick off the edge."""
    return layer(
        tone(2600, 0.07, "sine", 0.35, attack=0.0003, decay=0.012),
        noise(0.03, 0.35, decay=0.004, lowpass=9000, highpass=2500, seed=5),
    )


def pad():
    """Ball into pad: a dull, padded thud."""
    return layer(
        noise(0.15, 0.6, decay=0.035, lowpass=500, seed=7),
        tone(140, 0.12, "sine", 0.4, attack=0.001, decay=0.04, glide_to=90),
    )


def stumps():
    """Timber! A ball through the stumps and the bails clattering."""
    rng = random.Random(9)
    t = Track(0.7)
    t.add(0.0, tone(700, 0.2, "sine", 0.5, attack=0.0005, decay=0.04))
    t.add(0.0, noise(0.08, 0.5, decay=0.012, lowpass=5000, highpass=600, seed=11))
    for k in range(6):
        f = rng.uniform(1100, 2200)
        t.add(0.05 + k * rng.uniform(0.04, 0.09), tone(f, 0.08, "sine", 0.25, attack=0.0005, decay=0.015))
    return list(t.buf)


def crowd(dur, vol, swell, lowpass, seed, tail):
    """A crowd: band-limited noise that swells up and dies away."""
    return noise(dur, vol, decay=tail, lowpass=lowpass, highpass=250, seed=seed, attack=swell)


def cheer():
    return layer(crowd(2.6, 0.6, 0.25, 1800, 21, 0.9), crowd(2.6, 0.3, 0.4, 3200, 22, 0.7))


def roar():
    return layer(crowd(3.4, 0.7, 0.2, 2200, 23, 1.3), crowd(3.4, 0.4, 0.3, 3800, 24, 1.0))


def ooh():
    """The crowd's 'oooh' at a play-and-miss: a vowel-ish hum plus noise."""
    voices = [tone(f, 1.3, "saw", 0.06, attack=0.15, decay=0.6, lowpass=700, glide_to=f * 0.8)
              for f in (190, 230, 270, 310, 150)]
    return layer(*voices, crowd(1.3, 0.25, 0.15, 900, 25, 0.5))


def groan():
    voices = [tone(f, 1.5, "saw", 0.05, attack=0.08, decay=0.7, lowpass=600, glide_to=f * 0.65)
              for f in (220, 260, 180, 300)]
    return layer(*voices, crowd(1.5, 0.3, 0.05, 800, 26, 0.6))


def click():
    return tone(1200, 0.04, "sine", 0.3, attack=0.0005, decay=0.008)


def murmur(seconds=8.0):
    """Background crowd murmur, looped."""
    t = Track(seconds, loop=True)
    t.add(0.0, noise(seconds, 0.25, decay=None, lowpass=700, highpass=150, seed=31))
    rng = random.Random(32)
    for k in range(14):   # the odd distant shout or clap
        t.add(rng.uniform(0, seconds), noise(0.08, 0.15, decay=0.02, lowpass=2500, highpass=600, seed=40 + k))
    return list(t.buf)


def main():
    sfx = {"tock": tock(), "edge": edge(), "pad": pad(), "stumps": stumps(), "cheer": cheer(),
           "roar": roar(), "ooh": ooh(), "groan": groan(), "click": click()}
    for name, s in sfx.items():
        write_wav(os.path.join(OUT, "sfx", name + ".wav"), s)
    write_wav(os.path.join(OUT, "loops", "murmur.wav"), murmur(), peak=0.5)


if __name__ == "__main__":
    main()
