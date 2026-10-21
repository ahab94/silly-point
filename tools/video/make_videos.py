#!/usr/bin/env python3
"""Builds the marketing videos from recorded footage.

    bash tools/video/record_footage.sh            # raw gameplay -> build/footage/
    python3 tools/video/make_video_audio.py       # extra stingers -> build/video_audio/
    /usr/bin/python3 tools/video/make_videos.py [video-id ...]

Needs Pillow (captions) and ffmpeg. Writes build/videos/<id>.mp4 plus
docs/marketing/youtube.md (titles, descriptions, tags for uploading).

Each video is a list of segments cut from the footage (optionally sped up),
with captions burned on top. Audio = the footage's game sound (bat, crowd and
the game's own comedy stingers: the duck, the sad trombone, the slide
whistle) + the stadium anthem + extra stingers. Adapted from Air
Superiority Complex's video tools.
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOOTAGE = os.path.join(ROOT, "build", "footage")
OUT = os.path.join(ROOT, "build", "videos")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
VIDEO_AUDIO = os.path.join(ROOT, "build", "video_audio")


def sfx_path(name):
    """Video-only effects (build/video_audio) first, then the game's own (audio/sfx)."""
    for folder in (VIDEO_AUDIO, os.path.join(ROOT, "audio", "sfx")):
        path = os.path.join(folder, name + ".wav")
        if os.path.exists(path):
            return path
    raise FileNotFoundError(name)


def music_path(name):
    return os.path.join(ROOT, "audio", "music", name + ".wav")


PLAY = "https://ahab94.github.io/silly-point/"
PLAY_SHORT = "ahab94.github.io/silly-point"   # shown on screen
REPO = "https://github.com/ahab94/silly-point"
RELEASES = REPO + "/releases/latest"

CYAN = (200, 230, 255)
YELLOW = (255, 216, 74)
GREEN = (159, 225, 160)
RED = (220, 40, 40)
NAVY = (14, 52, 30)          # cricket green for the cards
INK = (4, 12, 6)

LINKS = f"""⭐ Open source on GitHub, a star helps a lot: {REPO}
⬇ Windows / Mac / Linux downloads: {RELEASES}"""


def description(blurb, tags):
    return f"""▶ PLAY FREE in your browser: {PLAY}

{blurb}

{LINKS}

Silly Point is a free 3D cricket batting game about all the strange things a cricket ball does: the new ball swings, the old ball reverses, Day 5 pitches crack, spinners bowl googlies, and every LBW can be reviewed by Pigeon-Eye. Get out for nought and a duck quacks. Ten match situations, phone controls, made with the Godot engine; every player, pitch and sound is made in code.

{" ".join("#" + t for t in tags)}"""


BASE_TAGS = ["silly point", "cricket game", "cricket", "indie game", "free game", "browser game",
             "godot", "gamedev", "batting", "funny cricket"]
HASHTAGS = ["SillyPoint", "cricket", "indiegame", "gamedev", "godot"]


def frame_size(orient):
    return (1080, 1920) if orient == "portrait" else (1920, 1080)


def font(size):
    return ImageFont.truetype(FONT, size)


def draw_centered(draw, lines, y_center, size, fill, width, stroke=10, line_gap=1.12):
    f = font(size)
    heights = [size * line_gap] * len(lines)
    y = y_center - sum(heights) / 2
    for line, h in zip(lines, heights):
        w = draw.textlength(line, font=f)
        draw.text(((width - w) / 2, y), line, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
        y += h


def caption_png(path, text, style, orient):
    """Full-frame transparent PNG with the caption placed for the format."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n") if text else []
    portrait = orient == "portrait"
    if not lines:
        img.save(path)
        return
    if style == "big":
        # Punchlines go mid-screen: between the enemy formation and our jet.
        size = 150 if portrait else 140
        while size > 60 and max(d.textlength(l, font=font(size)) for l in lines) > W - 90:
            size -= 6                      # shrink to fit the frame
        draw_centered(d, lines, H * (0.36 if portrait else 0.42), size, YELLOW, W, stroke=14)
    elif style == "note":
        draw_centered(d, lines, H * (0.44 if portrait else 0.55), 52, (235, 240, 245), W, stroke=6)
    elif style == "counter":
        draw_centered(d, lines, H * 0.84, 110, GREEN, W, stroke=12)
    elif style == "cta":   # call to action with the play link, above the Shorts UI
        cy = H * (0.66 if portrait else 0.78)
        f1, f2 = font(52 if portrait else 60), font(36 if portrait else 38)
        l1, l2 = "PLAY FREE IN YOUR BROWSER", PLAY_SHORT
        w = max(d.textlength(l1, font=f1), d.textlength(l2, font=f2)) + 140
        w = min(w, W - 60)
        h = 190 if portrait else 175
        d.rounded_rectangle([(W - w) / 2, cy - h / 2, (W + w) / 2, cy + h / 2], 30, fill=(255, 216, 74, 245))
        # a drawn "play" triangle, since the font has no symbol for it
        tx = (W - d.textlength(l1, font=f1)) / 2 - 10
        d.polygon([(tx - 46, cy - 62), (tx - 46, cy - 18), (tx - 8, cy - 40)], fill=INK)
        d.text(((W - d.textlength(l1, font=f1)) / 2 + 12, cy - 75), l1, font=f1, fill=INK)
        d.text(((W - d.textlength(l2, font=f2)) / 2, cy + 18), l2, font=f2, fill=(20, 40, 60))
    elif style == "low":   # landscape lower-third
        size = 76
        f = font(size)
        widths = [d.textlength(l, font=f) for l in lines]
        box_w, box_h = max(widths) + 80, len(lines) * size * 1.15 + 40
        y0 = H - box_h - 120
        d.rounded_rectangle([(W - box_w) / 2, y0, (W + box_w) / 2, y0 + box_h], 28, fill=(3, 10, 18, 190))
        draw_centered(d, lines, y0 + box_h / 2, size, (255, 255, 255), W, stroke=0)
    else:  # hook: the top band of a Short, where the platform UI doesn't cover it
        size = 76 if max(len(l) for l in lines) <= 18 else 62
        f = font(size)
        widths = [d.textlength(l, font=f) for l in lines]
        box_w, box_h = min(W - 40, max(widths) + 70), len(lines) * size * 1.15 + 44
        # Over the HUD strip at the very top: in this game the enemies fly
        # just below it, so captions must not sit on the formation.
        cy = H * 0.2   # the sky above the batter, below the scoreboard
        d.rounded_rectangle([(W - box_w) / 2, cy - box_h / 2, (W + box_w) / 2, cy + box_h / 2], 34,
                            fill=(255, 255, 255, 235))
        draw_centered(d, lines, cy, size, INK, W, stroke=0)
    img.save(path)


def draw_jet(d, cx, cy, s, col=None):
    """The card emblem: a red cricket ball with its seam (the name is kept
    from the other games' tools)."""
    r = 22 * s
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(178, 22, 28), outline=INK, width=max(3, int(s // 2)))
    d.ellipse([cx - r * 0.55, cy - r * 0.75, cx - r * 0.2, cy - r * 0.4], fill=(235, 120, 120))
    for k in (-1, 1):
        x = cx + k * r * 0.12
        d.line([x, cy - r * 0.97, x, cy + r * 0.97], fill=(245, 240, 225), width=max(2, int(s // 2)))
        for j in range(-6, 7):
            y = cy + j * r * 0.13
            d.line([x - k * r * 0.07, y - r * 0.04, x + k * r * 0.07, y + r * 0.04], fill=(245, 240, 225),
                   width=max(2, int(s // 3)))


def grid(d, W, H, step):
    """Mowing stripes."""
    for i, x in enumerate(range(0, W, step)):
        if i % 2:
            d.rectangle([x, 0, x + step, H], fill=(20, 64, 38))


def card_png(path, orient, title_lines, kind):
    W, H = frame_size(orient)
    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)
    grid(d, W, H, 90)
    portrait = orient == "portrait"
    if kind == "intro":
        draw_jet(d, W // 2, int(H * (0.34 if portrait else 0.3)), 9 if portrait else 7)
        draw_centered(d, title_lines, H * (0.6 if portrait else 0.7), 116 if portrait else 106, YELLOW, W, stroke=12)
    else:  # outro: title + call to action
        draw_jet(d, W // 2, int(H * (0.22 if portrait else 0.2)), 7 if portrait else 5)
        draw_centered(d, ["SILLY POINT"],
                      H * (0.42 if portrait else 0.44), 100 if portrait else 92, (255, 255, 255), W, stroke=10)
        draw_centered(d, ["PLAY FREE", "IN YOUR BROWSER"] if portrait else ["PLAY FREE IN YOUR BROWSER"],
                      H * (0.58 if portrait else 0.62), 84 if portrait else 78, YELLOW, W, stroke=10)
        draw_centered(d, [PLAY_SHORT], H * (0.69 if portrait else 0.75), 44 if portrait else 44, (255, 255, 255), W, stroke=6)
        draw_centered(d, ["free & open source on GitHub"],
                      H * (0.76 if portrait else 0.85), 44 if portrait else 40, (170, 190, 215), W, stroke=6)
    img.save(path)


def thumbnail_png(path, frame_src=None, t=0.0, lines=("WHO WON?", "BOTH."), color=YELLOW):
    """Thumbnail (1280x720): a dramatic frame from the footage with big text."""
    W, H = 1280, 720
    if frame_src:
        tmp = path + ".frame.png"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{t:.2f}", "-i", os.path.join(FOOTAGE, frame_src + ".mp4"),
                        "-frames:v", "1", "-vf", f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}", tmp], check=True)
        img = Image.open(tmp).convert("RGB")
        os.remove(tmp)
    else:
        img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W, H], fill=(0, 0, 0, 70))
    draw_centered(d, list(lines), H * 0.32, 150, color, W, stroke=14)
    img.save(path)


# --- The videos --------------------------------------------------------------
# Segment times are in seconds of the source clip (see its .events file);
# caption and sfx times are in seconds of the finished video, counted from
# the first gameplay frame (after any intro card). The game's own sounds (bat,
# crowd, the duck, the sad trombone, the stadium horn) are already in the
# footage; "sfx" adds extra stingers on top.

T1 = ["silly point", "game trailer", "indie game trailer", "cricket video game"]
SH = ["shorts"]

VIDEOS = [
    {
        "id": "01-trailer", "orient": "landscape", "music": "stadium",
        "intro": ("OLD BALLS. CRACKED PITCHES.\nJUST BAT.", 2.6),
        "segments": [
            ("l-sixes1", 12.0, 18.5, 1.0), ("l-googly", 5.2, 10.4, 1.0), ("l-reverse", 31.3, 36.0, 1.0),
            ("l-snicko", 47.0, 56.0, 1.0), ("l-pigeon", 29.6, 38.0, 1.0), ("l-charge", 8.6, 13.0, 1.0),
            ("l-duck", 1.0, 6.5, 1.0),
        ],
        "captions": [
            (0.2, 6.4, "Time it. Hit it.", "low"),
            (6.5, 11.6, "Read the googly.", "low"),
            (11.7, 16.3, "Old ball? It swings the other way.", "low"),
            (16.4, 25.3, "Wrong decision? Review it.", "low"),
            (25.4, 33.7, "Pigeon-Eye sees everything.", "low"),
            (33.8, 38.1, "Charge the spinner. Maybe.", "low"),
            (38.2, 43.6, "Out for nought? Quack.", "low"),
        ],
        "sfx": [(-2.4, "pop"), (-0.5, "slide_up")],
        "cut_whoosh": True, "caption_pop": False, "outro": 4.5,
        "thumb": ("l-sixes1", 14.0, ("REVERSE", "SWING!")),
        "title": "Silly Point: the cricket game where the ball gets old (free browser game trailer)",
        "blurb": "A 3D batting game about everything strange a cricket ball does: swing, reverse swing, seam, googlies, cracked Day 5 pitches, LBW reviews and ducks.",
        "tags": BASE_TAGS + T1,
    },
    {
        "id": "02-duck", "orient": "portrait",
        "segments": [("p-duck", 0.4, 9.0, 1.0)],
        "captions": [
            (0.0, 2.2, "First ball of my\ncricket career...", "hook"),
            (2.4, 4.2, "...", "hook"),
            (4.6, 6.0, "OUT FOR\nA DUCK", "big"),
        ],
        "sfx": [(2.0, "uh_oh", 0.6)],
        "title": "First ball. Bowled. For a DUCK. 🦆 #shorts",
        "blurb": "Get out for nought in Silly Point and a duck quacks at you. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["duck", "bowled"],
    },
    {
        "id": "03-googly", "orient": "portrait",
        "segments": [("p-googly", 0.4, 11.0, 1.0)],
        "captions": [
            (0.0, 2.6, "Leg-spinner.\nIt turns AWAY.", "hook"),
            (2.7, 5.4, "So I leave it.\nEasy.", "hook"),
            (5.5, 7.2, "Same action again...", "hook"),
            (7.35, 8.8, "GOOGLY!", "big"),
            (8.9, 10.6, "It turns the\nOTHER way", "hook"),
        ],
        "sfx": [(6.9, "uh_oh", 0.7), (7.35, "record_scratch", 0.6)],
        "title": "Leg-spinner bowls one that turns away... then the GOOGLY 🌀 #shorts",
        "blurb": "Read the ball cam: a googly looks like a leg-break but turns the other way. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["googly", "leg spin", "spin bowling"],
    },
    {
        "id": "04-reverse-swing", "orient": "portrait",
        "segments": [("p-reverse", 29.0, 37.0, 1.0)],
        "captions": [
            (0.0, 2.0, "This ball is\n52 overs old", "hook"),
            (2.1, 4.2, "Shiny side leg =\nswings AWAY... right?", "hook"),
            (4.3, 5.8, "REVERSE\nSWING", "big"),
            (5.9, 8.0, "Old ball swings\nTOWARDS the shine", "hook"),
        ],
        "sfx": [(4.0, "uh_oh", 0.6)],
        "title": "The ball is 52 overs old... so it swings the WRONG way 🏏 #shorts",
        "blurb": "In Silly Point the ball ages: shiny new balls swing away from the shine, scuffed old ones reverse. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["reverse swing", "swing bowling", "fast bowling"],
    },
    {
        "id": "05-snicko", "orient": "portrait",
        "segments": [("p-snicko", 46.6, 57.0, 1.0)],
        "captions": [
            (0.0, 2.2, "Didn't touch it.", "hook"),
            (3.9, 5.4, "Umpire: OUT", "big"),
            (5.5, 7.8, "REVIEW IT", "hook"),
            (7.9, 9.4, "NOT OUT", "big"),
            (9.4, 10.4, "Snick-o-Scope: nothing", "note"),
        ],
        "sfx": [(4.0, "bonk", 0.6)],
        "title": "Umpire says OUT... the Snick-o-Scope says NO 🔍 #shorts",
        "blurb": "Two reviews per innings. Use them wisely. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["drs", "umpire", "review"],
    },
    {
        "id": "06-pigeon-eye", "orient": "portrait",
        "segments": [("p-pigeon", 29.4, 39.0, 1.0)],
        "captions": [
            (0.0, 2.0, "Hit on the pad...", "hook"),
            (3.8, 5.0, "NOT OUT!", "big"),
            (5.0, 7.0, "Fielding side:\n\"Review it\"", "hook"),
            (7.1, 8.6, "PIGEON-EYE\nSAYS OUT", "big"),
            (8.6, 9.6, "...for a duck", "note"),
        ],
        "sfx": [],
        "title": "Not out... until PIGEON-EYE gets involved 🐦 #shorts",
        "blurb": "Ball tracking, umpire's call, and a pigeon that sees everything. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["lbw", "drs", "ball tracking"],
    },
    {
        "id": "07-charge", "orient": "portrait",
        "segments": [("p-charge", 0.3, 13.5, 1.0)],
        "captions": [
            (0.0, 2.0, "Charge the spinner?", "hook"),
            (3.0, 6.2, "SIX!", "big"),
            (6.3, 9.0, "Do it again!", "hook"),
            (9.1, 12.0, "...", "hook"),
            (12.1, 13.2, "STUMPED", "big"),
        ],
        "sfx": [(9.9, "uh_oh", 0.6)],
        "title": "Charging the spinner: works every time* 🏏 #shorts",
        "blurb": "Dance down the pitch... but the bowler might see you coming. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["stumped", "spin bowling", "six"],
    },
    {
        "id": "08-helmet", "orient": "portrait",
        "segments": [("p-helmet", 91.0, 99.0, 1.0)],
        "captions": [
            (0.0, 3.0, "Bumper Barnaby\nwants your helmet", "hook"),
            (3.1, 6.1, "My plan:\njust leave it", "hook"),
            (6.2, 7.6, "BOING", "big"),
        ],
        "sfx": [],
        "title": "Leaving a bouncer: a short tutorial 🪖 #shorts",
        "blurb": "Duck (hold back and play no shot) or wear it. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["bouncer", "fast bowling"],
    },
    {
        "id": "09-day-five", "orient": "portrait",
        "segments": [("p-googly", 14.6, 22.0, 1.0)],
        "captions": [
            (0.0, 3.6, "Day 5 pitch.\nCracks everywhere.", "hook"),
            (3.6, 4.6, "Watch the bounce...", "hook"),
            (4.7, 6.6, "IT NEVER\nBOUNCED", "big"),
        ],
        "sfx": [(4.4, "uh_oh", 0.6)],
        "title": "Day 5 pitch: this ball never bounced 😳 #shorts",
        "blurb": "The pitch wears out over five days: cracks, footmarks, balls that shoot along the ground. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["test cricket", "pitch"],
    },
    {
        "id": "10-sixes", "orient": "portrait",
        "segments": [("p-sixes2", 0.4, 22.5, 1.0)],
        "captions": [
            (0.0, 2.0, "Every six gets\nthe full stadium", "hook"),
            (2.0, 5.8, "SIX x1", "counter"),
            (9.3, 13.1, "SIX x2", "counter"),
            (16.7, 20.9, "SIX x3", "counter"),
        ],
        "sfx": [],
        "title": "Every six gets a slide whistle and an air horn 🎺 #shorts",
        "blurb": "Three in a row on a Day 5 pitch. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["six", "sixes"],
    },
    {
        "id": "11-dropped", "orient": "portrait",
        "segments": [("p-dropped", 63.6, 71.0, 1.0)],
        "captions": [
            (2.1, 4.3, "Straight to the fielder...", "hook"),
            (4.4, 6.4, "DROPPED!", "big"),
            (5.6, 7.4, "(I'll take it)", "note"),
        ],
        "sfx": [],
        "title": "Straight to the fielder... DROPPED 🫣 #shorts",
        "blurb": "Fielders catch, dive, misfield and sometimes drop it. Free cricket game in your browser.",
        "tags": BASE_TAGS + SH + ["dropped catch", "fielding"],
    },
    {
        "id": "12-i-made-a-game", "orient": "portrait",
        "segments": [
            ("p-sixes2", 1.6, 6.5, 1.0), ("p-googly", 6.0, 10.0, 1.0), ("p-reverse", 32.0, 36.0, 1.0),
            ("p-snicko", 50.4, 55.2, 1.0), ("p-charge", 9.2, 12.8, 1.0), ("p-duck", 1.2, 5.6, 1.0),
        ],
        "captions": [
            (0.0, 4.9, "I made a cricket game\nwhere the ball gets OLD", "hook"),
            (4.9, 8.9, "Googlies", "hook"),
            (8.9, 12.9, "Reverse swing", "hook"),
            (12.9, 17.7, "Reviews", "hook"),
            (17.7, 21.3, "Stumpings", "hook"),
            (21.3, 25.7, "...and ducks", "hook"),
        ],
        "sfx": [],
        "cut_whoosh": True,
        "title": "I made a cricket game where the ball gets OLD 🏏 #shorts",
        "blurb": "Swing, reverse swing, cracked pitches, googlies and reviews, all made in code with Godot. Free in your browser.",
        "tags": BASE_TAGS + SH + ["i made a game", "devlog"],
    },
]


# --- Assembly --------------------------------------------------------------------

def run(cmd):
    subprocess.run(cmd, check=True)


def atempo_chain(speed):
    # atempo accepts 0.5..2.0 per stage, so chain stages for bigger changes.
    parts, s = [], speed
    while s > 2.0:
        parts.append("atempo=2.0")
        s /= 2.0
    parts.append(f"atempo={s:.4f}")
    return ",".join(parts)


def cut(src, start, end, speed, path, W, H, keep_audio):
    vf = f"setpts=PTS/{speed},scale={W}:{H},fps=30"
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-to", str(end),
           "-i", os.path.join(FOOTAGE, src + ".mp4"), "-vf", vf]
    if keep_audio:
        cmd += ["-af", atempo_chain(speed) + ",aresample=48000", "-c:a", "aac", "-b:a", "192k", "-ac", "2"]
    else:
        cmd += ["-an"]
    cmd += ["-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p", path]
    run(cmd)


def still(png, seconds, path, keep_audio):
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-loop", "1", "-t", str(seconds), "-i", png]
    if keep_audio:
        cmd += ["-f", "lavfi", "-t", str(seconds), "-i", "anullsrc=r=48000:cl=stereo",
                "-c:a", "aac", "-b:a", "192k", "-shortest"]
    cmd += ["-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "16", path]
    run(cmd)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def build(v, tmp):
    W, H = frame_size(v["orient"])
    clip_audio = True   # always keep the footage's game sound effects
    parts = []
    if "intro" in v:
        text, secs = v["intro"]
        png = os.path.join(tmp, "intro.png")
        card_png(png, v["orient"], text.split("\n"), "intro")
        parts.append(os.path.join(tmp, "intro.mp4"))
        still(png, secs, parts[-1], clip_audio)
    for i, (src, a, b, speed) in enumerate(v["segments"]):
        parts.append(os.path.join(tmp, f"seg{i}.mp4"))
        cut(src, a, b, speed, parts[-1], W, H, clip_audio)
    if v.get("outro"):
        png = os.path.join(tmp, "outro.png")
        card_png(png, v["orient"], [], "outro")
        parts.append(os.path.join(tmp, "outro.mp4"))
        still(png, v["outro"], parts[-1], clip_audio)

    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    total = duration(joined)
    offset = v["intro"][1] if "intro" in v else 0.0   # captions are timed from the first gameplay frame

    # Captions: one transparent full-frame PNG each, shown over its time window.
    # Every video ends with the play link on screen: links in Shorts
    # descriptions aren't clickable, so viewers need to see the address.
    gameplay_end = total - offset - (v.get("outro") or 0)
    captions = list(v["captions"])
    if not v.get("outro"):
        captions.append((max(0.0, gameplay_end - 3.0), gameplay_end, "cta", "cta"))
    inputs, filters, last = [], [], "[0:v]"
    for i, (t0, t1, text, style) in enumerate(captions):
        png = os.path.join(tmp, f"cap{i}.png")
        caption_png(png, text, style, v["orient"])
        # Loop the still image for the whole video: a single-frame input ends
        # immediately, so a caption that starts after an intro card would never show.
        inputs += ["-loop", "1", "-t", f"{total:.2f}", "-i", png]
        filters.append(f"{last}[{i + 1}:v]overlay=0:0:enable='between(t,{t0 + offset:.2f},{t1 + offset:.2f})'[v{i}]")
        last = f"[v{i}]"
    n_caps = len(captions)

    # Audio: the clip's game sound effects (footage is recorded without game
    # music), a playful music bed, comedy stingers from the spec, a soft pop
    # on every caption and a whoosh on every cut.
    cues = [(t + offset, name, vol) for t, name, vol in
            [(c[0], c[1], c[2] if len(c) > 2 else 1.0) for c in v.get("sfx", [])]]
    if v.get("caption_pop", True):
        cues += [(t0 + offset, "pop", 0.3) for t0, _, text, _ in v["captions"] if text]
    if v.get("cut_whoosh"):
        t = offset
        for _, a, b, speed in v["segments"][:-1]:
            t += (b - a) / speed
            cues.append((t - 0.15, "whoosh", 0.5))
    base = n_caps + 1
    audio_inputs = ["-stream_loop", "-1", "-i", music_path(v.get("music", "stadium"))]
    mix = ["[0:a]volume=1.0[g]", f"[{base}:a]volume={v.get('music_volume', 0.2)}[m]"]
    labels = ["[g]", "[m]"]
    for j, (t, name, vol) in enumerate(cues):
        audio_inputs += ["-i", sfx_path(name)]
        ms = max(0, int(t * 1000))
        mix.append(f"[{base + 1 + j}:a]adelay={ms}|{ms},volume={vol * 0.75:.2f}[s{j}]")
        labels.append(f"[s{j}]")
    mix.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,atrim=0:{total:.2f},"
               f"loudnorm=I=-16:TP=-2:LRA=11,afade=t=in:d=0.2,afade=t=out:st={total - 0.8:.2f}:d=0.8,"
               f"aresample=48000[a]")
    audio_filter = ";".join(mix)

    graph = ";".join(filters + [audio_filter]) if filters else audio_filter
    vmap = last if filters else "0:v"
    out = os.path.join(OUT, v["id"] + ".mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", joined, *inputs, *audio_inputs,
         "-filter_complex", graph, "-map", vmap, "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30",
         "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.2f}", out])
    print(f"{v['id']}: {total:.1f}s -> {os.path.relpath(out, ROOT)}")
    return total


def write_metadata(lengths):
    path = os.path.join(ROOT, "docs", "marketing", "youtube.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["# YouTube uploads", "",
             "Generated by `tools/video/make_videos.py`. Audience: **No, it's not made for kids** (family-friendly, all ages).",
             "Upload as **Private** first, then publish after review.", ""]
    for v in VIDEOS:
        lines += [f"## {v['id']} ({'Short' if v['orient'] == 'portrait' else 'video'}, {lengths.get(v['id'], 0):.0f}s)", "",
                  f"**Title:** {v['title']}", "", "**Description:**", "", "```",
                  description(v["blurb"], HASHTAGS),
                  "```", "", f"**Tags:** {', '.join(v['tags'])}", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))
    with open(os.path.join(OUT, "metadata.json"), "w") as f:
        json.dump([{"id": v["id"], "file": v["id"] + ".mp4", "title": v["title"],
                    "description": description(v["blurb"], HASHTAGS),
                    "tags": v["tags"], "short": v["orient"] == "portrait"} for v in VIDEOS], f, indent=2)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    os.makedirs(OUT, exist_ok=True)
    wanted = set(sys.argv[1:])
    lengths = {}
    for v in VIDEOS:
        if wanted and v["id"] not in wanted and v["id"].split("-")[0] not in wanted:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            lengths[v["id"]] = build(v, tmp)
    for v in VIDEOS:
        if "thumb" in v and (not wanted or v["id"] in wanted):
            src, t, lines = v["thumb"]
            thumbnail_png(os.path.join(OUT, v["id"] + "-thumbnail.png"), src, t, lines)
    if not wanted:
        write_metadata(lengths)


if __name__ == "__main__":
    main()
