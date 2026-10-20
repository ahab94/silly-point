extends RefCounted
## The expert batting bot. Because the physics and rules are deterministic,
## it can try every shot, direction, footwork and a few press timings on the
## real trajectory before the ball arrives, and play the best one. It is the
## "this match is winnable" gate in checks/autoplay.sh, not a fair opponent.
##
## `rookie` makes it human: it only sees what a batter sees (the naive
## prediction, no knowledge of late movement) and its timing wobbles. Used to
## measure the difficulty curve.

const BallSim := preload("res://scripts/ball_sim.gd")
const Batting := preload("res://scripts/batting.gd")
const Rules := preload("res://scripts/rules.gd")

const DIRS := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, 0),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1)]


## situation: {mode, need (runs still needed), balls_left, wkts_left, reviews}
static func plan(traj: Dictionary, d: Dictionary, c, field: Array, protect: bool, t20: bool, sit: Dictionary) -> Dictionary:
	var spin: bool = d.style == "offspin" or d.style == "legspin"
	var wicket_cost := _wicket_cost(sit)
	var best := {"shot": "leave", "foot": "neutral", "aim": 0, "t_press": 0.0, "dance": false, "th_adj": 0.0}
	var leave_bat := Batting.resolve(traj, d, best, c)
	var best_v := _value(Rules.outcome(traj, d, leave_bat, field, protect, t20), wicket_cost, sit)
	for shot in ["defend", "attack", "loft", "sweep"]:
		for dir in DIRS:
			var dances := [false, true] if spin and shot != "sweep" and shot != "defend" else [false]
			for dance in dances:
				var m := Batting.from_direction(dir)
				var inp := {"shot": shot, "foot": m.foot, "aim": m.aim, "th_adj": m.th_adj, "dance": dance, "t_press": 0.0}
				var ideal := Batting.ideal_press(traj, shot, Batting.effective_foot(inp))
				for off in [0.0, -0.012, 0.012]:
					inp.t_press = ideal + off
					var r := Batting.resolve(traj, d, inp, c)
					var o := Rules.outcome(traj, d, r, field, protect, t20)
					var v := _value(o, wicket_cost, sit)
					if v > best_v + 0.001:
						best_v = v
						best = inp.duplicate()
	best.value = best_v
	return best


static func _wicket_cost(sit: Dictionary) -> float:
	if sit.mode == "survive":
		return 100.0
	var need: float = sit.need
	var balls: float = maxf(1.0, float(sit.balls_left))
	var wl: int = sit.wkts_left
	# Chasing: a wicket hurts more with few in hand; the required rate
	# makes runs worth more.
	return (40.0 if wl <= 1 else 14.0) + need / balls * 2.0


static func _value(o: Dictionary, wicket_cost: float, sit: Dictionary) -> float:
	var runs := float(o.runs) + float(o.extras)
	if sit.mode == "chase" and float(sit.need) > 0.0:
		runs = minf(runs, float(sit.need) + 0.5)
	var out := Rules.final_out(o, int(sit.reviews) > 0)
	var v := runs - (wicket_cost if out else 0.0)
	# A dropped catch was a catch that happened to be dropped: count it as risky.
	if o.comment == "dropped":
		v -= wicket_cost * 0.5
	return v


## A human-ish batter: decides from what it can see shortly before the ball
## pitches (the naive prediction, so late movement fools it), plays the
## textbook shot for the length and line, aims at a random gap, and its
## timing is off by a random amount (less with more skill).
static func rookie(traj: Dictionary, d: Dictionary, rng: RandomNumberGenerator, skill: float, survive := false) -> Dictionary:
	var spin: bool = d.style == "offspin" or d.style == "legspin"
	# Against pace you decide before it pitches; spin is slow enough to watch
	# it land and turn first.
	var decide_t := 0.3
	if float(traj.pitch_t) > 0.0:
		decide_t = float(traj.pitch_t) + 0.06 if spin else maxf(0.05, float(traj.pitch_t) - 0.1)
	var p := BallSim.pos_at(traj, decide_t)
	var v := BallSim.vel_at(traj, decide_t)
	var at := BallSim.naive_predict(p, v, decide_t >= float(traj.pitch_t), -1.45)
	var length := -float(traj.pitch_pos.z) if float(traj.pitch_t) > 0.0 else 0.0
	var full := length < (3.2 if spin else 4.6)
	var short := length > (6.0 if spin else 7.8)
	var dir := Vector2i(0, 0)
	var shot := "attack"
	if short:
		dir.y = -1
		dir.x = 1 if at.x > 0.25 else -1          # cut it or pull it
		if at.y > 1.5 and rng.randf() < 0.5:
			shot = "leave"                         # duck the bouncer
	elif full:
		dir.y = 1
		dir.x = 1 if at.x > 0.12 else (-1 if at.x < -0.08 else 0)
		if rng.randf() < 0.25:
			shot = "loft"
		if spin and rng.randf() < 0.2:
			shot = "sweep"
			dir.x = -1
	else:
		# Good length: respect it. Leave it outside off, block it on the stumps,
		# sometimes punch it.
		if at.x > 0.45:
			shot = "leave"
		elif rng.randf() < 0.6:
			shot = "defend"
			dir.y = 1
		else:
			dir.y = -1
	# Reading the ball cam: a decent batter often plays with the movement
	# it shows (turn for spinners; for pace, away from the shine on a new
	# ball and towards it on a reversing one).
	if shot != "leave" and dir.y >= 0 and rng.randf() < skill * 0.7:
		var moves := 0
		if spin:
			moves = int(d.spin_dir)
		else:
			moves = int(signf(float(d.swing)))
		if moves != 0:
			dir.x = moves
	# Batting to survive: block more of the drivable ones too.
	if survive and shot == "attack" and not short and rng.randf() < 0.5:
		shot = "defend"
	# Free choice of gap: nudge the direction sometimes.
	if shot == "attack" and dir.y >= 0 and rng.randf() < 0.3:
		dir.x = clampi(dir.x + (1 if rng.randf() < 0.5 else -1), -1, 1)
	var m := Batting.from_direction(dir)
	var inp := {"shot": shot, "foot": m.foot, "aim": m.aim, "th_adj": m.th_adj, "dance": false, "t_press": 0.0}
	var ideal := Batting.ideal_press(traj, shot if shot != "leave" else "attack", Batting.effective_foot(inp))
	inp.t_press = ideal + rng.randfn(0.0, lerpf(0.06, 0.018, skill))
	return inp
