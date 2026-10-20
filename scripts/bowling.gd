extends RefCounted
## The bowlers and the deliveries they bowl. `make` turns a bowler, a kind of
## delivery and the match conditions into the numbers ball_sim.gd flies.
## All randomness comes from the RandomNumberGenerator passed in, so a
## seeded innings is the same every time (the autopilot gate relies on it).
##
## Every name here is made up.

const SWING_K := 9.5       # m/s^2 of sideways pull for "full" swing
const SEAM_K := 0.5        # m/s of sideways kick off the seam on a green pitch
const TURN_DEG := 6.0      # degrees of turn for a big-spinning ball on a raging turner

const BOWLERS := {
	"dave": {
		"name": "Dibbly-Dobbly Dave", "style": "medium", "pace": 33.5, "accuracy": 0.82,
		"skill": 0.8, "noball": 0.01,
		"reps": {"seam": 5, "outswing": 2, "inswing": 2, "cutter": 2, "slower": 1},
	},
	"banana": {
		"name": "Captain Banana", "style": "fast", "pace": 37.5, "accuracy": 0.78,
		"skill": 1.0, "noball": 0.02,
		"reps": {"outswing": 6, "inswing": 3, "yorker": 1, "short": 1, "seam": 1},
	},
	"grassy": {
		"name": "Grassy Gertrude", "style": "medium", "pace": 35.0, "accuracy": 0.86,
		"skill": 1.0, "noball": 0.01,
		"reps": {"seam": 7, "cutter": 3, "outswing": 1, "short": 1},
	},
	"barnaby": {
		"name": "Bumper Barnaby", "style": "fast", "pace": 40.5, "accuracy": 0.72,
		"skill": 0.9, "noball": 0.04,
		"reps": {"bouncer": 4, "short": 3, "seam": 2, "yorker": 1, "slower": 1},
	},
	"tim": {
		"name": "Tweaky Tim", "style": "offspin", "pace": 23.0, "accuracy": 0.85,
		"skill": 0.9, "noball": 0.005,
		"reps": {"offbreak": 7, "arm": 2, "other": 1},
	},
	"wizard": {
		"name": "The Wizard of Wrist", "style": "legspin", "pace": 21.5, "accuracy": 0.74,
		"skill": 1.0, "noball": 0.01,
		"reps": {"legbreak": 6, "googly": 2, "topspin": 2, "flipper": 1},
	},
	"oz": {
		"name": "Old Ball Oz", "style": "fast", "pace": 40.0, "accuracy": 0.8,
		"skill": 1.0, "noball": 0.03,
		"reps": {"outswing": 3, "inswing": 4, "yorker": 3, "short": 1},
	},
	"zoltan": {
		"name": "Zoom-Zoom Zoltan", "style": "fast", "pace": 42.0, "accuracy": 0.74,
		"skill": 1.0, "noball": 0.04,
		"reps": {"outswing": 3, "inswing": 2, "bouncer": 2, "yorker": 2, "short": 1, "slower": 1},
	},
}

const LABELS := {
	"outswing": "outswinger", "inswing": "inswinger", "seam": "seamer",
	"cutter": "cutter", "slower": "slower ball", "yorker": "yorker",
	"bouncer": "bouncer", "short": "short of a length",
	"offbreak": "off-break", "arm": "arm ball", "other": "the other one",
	"legbreak": "leg-break", "googly": "googly", "topspin": "top-spinner",
	"flipper": "flipper",
}

const STYLE_NAMES := {
	"fast": "Right-arm fast", "medium": "Right-arm medium",
	"offspin": "Right-arm off-spin", "legspin": "Right-arm leg-spin",
}


static func get_bowler(id: String) -> Dictionary:
	return BOWLERS[id]


static func is_spinner(bowler: Dictionary) -> bool:
	return bowler.style == "offspin" or bowler.style == "legspin"


static func pick_kind(bowler: Dictionary, rng: RandomNumberGenerator) -> String:
	var reps: Dictionary = bowler.reps
	var total := 0
	for k in reps:
		total += int(reps[k])
	var roll := rng.randi_range(1, total)
	for k in reps:
		roll -= int(reps[k])
		if roll <= 0:
			return k
	return reps.keys()[0]


## Length: distance from the batter's stumps to where it pitches (metres).
static func _length(kind: String, spin: bool, rng: RandomNumberGenerator) -> float:
	if spin:
		var roll := rng.randf()
		if kind == "flipper":
			return rng.randf_range(2.6, 3.8)
		if roll < 0.2:
			return rng.randf_range(2.2, 3.1)     # tossed up
		if roll < 0.92:
			return rng.randf_range(3.1, 4.8)     # good length
		return rng.randf_range(6.0, 7.2)         # long hop, a gift
	match kind:
		"yorker":
			return rng.randf_range(0.9, 1.7)
		"bouncer":
			return rng.randf_range(10.0, 12.0)
		"short":
			return rng.randf_range(8.0, 9.5)
	var r := rng.randf()
	if r < 0.25:
		return rng.randf_range(3.0, 4.5)         # full, drivable
	if r < 0.92:
		return rng.randf_range(5.0, 7.5)         # good length
	return rng.randf_range(8.0, 9.0)


## Line where the bowler wants it to pitch (x). Positive is the off side.
static func _line(kind: String) -> float:
	match kind:
		"outswing": return 0.12
		"inswing": return 0.0
		"seam", "cutter", "slower": return 0.12
		"yorker": return 0.0
		"bouncer": return -0.1
		"short": return 0.05
		"offbreak": return 0.3
		"arm": return 0.12
		"other": return 0.0
		"legbreak": return -0.18
		"googly": return 0.25
		"topspin", "flipper": return 0.04
	return 0.1


static func make(bowler: Dictionary, c, rng: RandomNumberGenerator, kind: String = "") -> Dictionary:
	if kind == "":
		kind = pick_kind(bowler, rng)
	var spin := is_spinner(bowler)
	var acc: float = bowler.accuracy
	var skill: float = bowler.skill
	var speed: float = float(bowler.pace) * (1.0 + rng.randfn(0.0, 0.015))
	match kind:
		"slower": speed *= 0.8
		"bouncer": speed *= 1.02
		"yorker": speed *= 1.01
		"arm", "flipper": speed *= 1.08
		"googly": speed *= 0.97

	var length := _length(kind, spin, rng) + rng.randfn(0.0, 0.25 + 0.7 * (1.0 - acc))
	length = clampf(length, 0.4, 13.0)
	var line := _line(kind) + rng.randfn(0.0, 0.03 + 0.16 * (1.0 - acc))
	var release := Vector3(-0.55, 2.0 if spin else 2.25, -18.8)

	var d := {
		"kind": kind, "label": LABELS.get(kind, kind), "speed": speed, "style": bowler.style,
		"release": release, "pitch": Vector2(line, -length),
		"swing": 0.0, "drift": 0.0, "deviation": 0.0, "bounce": c.bounce(),
		"skid": 0.9, "seam_dir": 0, "shiny_side": 0, "spin_dir": 0,
		"crack": "", "rough": false, "no_ball": rng.randf() < float(bowler.noball),
		"seed": rng.randi(),
	}
	var hard: float = c.hardness()
	d.bounce = c.bounce() * (0.82 + 0.18 * hard)

	if not spin:
		_pace(d, kind, c, rng, skill, hard)
	else:
		_spin(d, kind, c, rng, skill)

	# Cracks: some balls hit a crack and shoot along the ground, others spit up.
	if rng.randf() < c.crack_chance():
		if rng.randf() < 0.6:
			d.crack = "shooter"
			d.bounce = float(d.bounce) * 0.45
		else:
			d.crack = "spitter"
			d.bounce = float(d.bounce) * 1.3
		d.deviation = float(d.deviation) + rng.randfn(0.0, 0.7)
	return d


static func _pace(d: Dictionary, kind: String, c, rng: RandomNumberGenerator, skill: float, hard: float) -> void:
	var speed: float = d.speed
	# Which way the seam points decides the swing. Seam towards the slips
	# (+1) means the shiny side faces leg. A shiny ball swings away from the
	# shine (outswing); a rough, reversing ball swings towards it (inswing).
	var seam_dir := 0
	var factor := 1.0
	var seam_q := 1.0
	match kind:
		"outswing":
			seam_dir = 1
		"inswing":
			seam_dir = -1
		"seam":
			factor = 0.3
			seam_q = 1.6
		"cutter":
			factor = 0.35
			seam_q = 0.6
		"slower":
			factor = 0.6
		"yorker":
			factor = 0.85
		"bouncer":
			factor = 0.15
			seam_q = 0.4
		"short":
			factor = 0.3
	if seam_dir == 0:
		seam_dir = 1 if rng.randf() < 0.5 else -1
	d.seam_dir = seam_dir
	d.shiny_side = -seam_dir
	d.swing = seam_dir * factor * c.swing_balance(speed) * SWING_K * skill * rng.randf_range(0.8, 1.15)
	d.deviation = rng.randfn(0.0, 1.0) * SEAM_K * c.grass() * hard * seam_q
	if kind == "cutter":
		var cut := 1.0 if rng.randf() < 0.5 else -1.0
		d.deviation = float(d.deviation) + cut * (0.55 + 0.5 * c.grip())
		d.label = "leg-cutter" if cut > 0.0 else "off-cutter"
	d.skid = 0.9 * (0.94 + 0.06 * hard)
	if kind == "slower":
		d.skid = 0.86


static func _spin(d: Dictionary, kind: String, c, rng: RandomNumberGenerator, skill: float) -> void:
	var pitch: Vector2 = d.pitch
	var grip: float = c.grip()
	var rough: bool = c.in_rough(pitch.x, pitch.y)
	if rough:
		d.rough = true
		grip *= 1.0 + 0.35 * c.rough_strength()
		d.bounce = float(d.bounce) * rng.randf_range(0.8, 1.2)
	# spin_dir: which way it turns off the pitch (+1 towards off).
	var turn := 1.0
	var spin_dir := 0
	var drift := 0.0
	match kind:
		"offbreak":
			spin_dir = -1
			drift = 1.4
		"arm":
			spin_dir = 0
			turn = 0.0
			drift = 2.6
		"other":
			spin_dir = 1
			turn = 0.75
			drift = -0.6
		"legbreak":
			spin_dir = 1
			drift = -1.6
		"googly":
			spin_dir = -1
			turn = 0.8
			drift = 0.5
		"topspin":
			spin_dir = 0
			turn = 0.0
			d.bounce = float(d.bounce) * 1.18
		"flipper":
			spin_dir = 0
			turn = 0.0
			d.bounce = float(d.bounce) * 0.68
	d.spin_dir = spin_dir
	d.drift = drift * skill * (0.5 if c.dew else 1.0)
	var skid := 0.85
	if kind == "flipper" or kind == "arm":
		skid = 0.97
	if c.dew:
		skid = minf(skid + 0.07, 0.97)    # wet ball skids on
	d.skid = skid
	var ang := deg_to_rad(TURN_DEG * grip * skill * turn * rng.randf_range(0.75, 1.15))
	d.deviation = spin_dir * float(d.speed) * skid * tan(ang) + rng.randfn(0.0, 0.12)
	# Seam position for the ball cam: a spinner's seam is angled by the wrist.
	d.seam_dir = spin_dir
	d.shiny_side = 0
