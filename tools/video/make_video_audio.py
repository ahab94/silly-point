#!/usr/bin/env python3
"""Extra sounds for the marketing videos only (the game's own comedy stingers,
like the duck, the sad trombone and the slide whistle, live in audio/sfx).
Writes build/video_audio/. Run: python3 tools/video/make_video_audio.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import synth as A  # noqa: E402
from make_audio import vibrato  # noqa: E402

OUT = os.path.join(A.HERE, "..", "build", "video_audio")
tone, noise, layer, at, hz = A.tone, A.noise, A.layer, A.at, A.hz


def main():
    s = {
        "pop": layer(tone(900, 0.08, "sine", 0.6, decay=0.015, glide_to=1800),
                     noise(0.03, 0.2, decay=0.006, highpass=2000, seed=23)),
        "whoosh": noise(0.45, 0.5, decay=None, lowpass=300, sweep_to=5000, highpass=150, seed=24, attack=0.2),
        "uh_oh": layer(vibrato(hz("A5"), 0.18, 0.4, 0.01, 6, shape="tri"),
                       at(0.2, vibrato(hz("E5"), 0.32, 0.4, 0.01, 6, shape="tri", glide_to=hz("D5")))),
        "bonk": layer(tone(620, 0.25, "sine", 0.6, decay=0.05, glide_to=380), tone(1240, 0.1, "sine", 0.2, decay=0.02)),
    }
    for name, samples in s.items():
        A.write_wav(os.path.join(OUT, name + ".wav"), samples)


if __name__ == "__main__":
    main()
