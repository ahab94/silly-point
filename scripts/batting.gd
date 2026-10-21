extends RefCounted
## Turns a shot input into what happens to the ball.
##
## The batter watches the ball the whole way. Pressing a shot key starts the
## swing, which takes SWING_T seconds to reach the ball. At the moment of the
## press the batter lines the bat up with where they *expect* the ball to be
## (BallSim.naive_predict) and can only correct part of any later surprise
## (ADJUST). So:
## - press too early: the movement that happens afterwards (late swing,
##   seam, cracks, spin) finds the edge or beats the bat;
## - press too late: the bat arrives after the ball;
## - footwork moves the contact point. Forward to the pitch of the ball
##   gives the movement less room; back gives more time to see it.
##
## The input is {shot, foot, aim, t_press, dance, th_adj}: shot is leave /
## defend / attack / loft / sweep; foot is front / neutral / back; aim is -1
## (leg), 0 (straight) or 1 (off). Controls are classic console-cricket style: the 8-way
## direction held when you press the shot key sets both. Up is front foot,
## down is back foot, left and right pick the side (see `from_direction`). Everything is deterministic for a delivery, so
## the autopilot can try shots out before playing one.

const BallSim := preload("res://scripts/ball_sim.gd")

const ADJUST := 0.3
const SWING_T := {"defend": 0.17, "attack": 0.21, "loft": 0.24, "sweep": 0.22}
const WINDOW := {"defend": 0.18, "attack": 0.14, "loft": 0.13, "sweep": 0.14}   # forgiving: a human can hit these
const PERFECT := 0.035
# Where the bat meets the ball, and where the front pad is (z).
const PLANE := {"front": -1.95, "neutral": -1.45, "back": -0.75, "dance": -3.4}
const PAD_Z := {"front": -1.72, "neutral": -1.15, "back": -0.5, "dance": -3.15}
const PAD_X := {"front": -0.03, "neutral": -0.12, "back": 0.0, "dance": 0.0}
const PAD_HALF := 0.13
const PAD_TOP := 0.85

# bat: "v" vertical bat (line matters most) or "h" horizontal (height
# matters most). th: direction in degrees from straight back past the bowler,
# positive towards the off side. el: launch angle. h and x: the ball height
# and line at contact this shot is made for.
const SHOTS := {
	"defend": {"name": "Forward defence", "bat": "v", "th": 0.0, "el": -4.0, "power": 1.5, "h": [0.0, 1.45], "x": [-0.4, 0.5]},
	"defend_back": {"name": "Back-foot defence", "bat": "v", "th": 0.0, "el": -6.0, "power": 1.0, "h": [0.0, 1.5], "x": [-0.4, 0.5]},
	"cover": {"name": "Cover drive", "bat": "v", "th": 45.0, "el": 3.0, "power": 24.0, "h": [0.0, 0.75], "x": [0.04, 0.7]},
	"straight": {"name": "Straight drive", "bat": "v", "th": 3.0, "el": 3.0, "power": 24.0, "h": [0.0, 0.75], "x": [-0.15, 0.25]},
	"flick": {"name": "Flick", "bat": "v", "th": -40.0, "el": 4.0, "power": 22.0, "h": [0.0, 0.8], "x": [-0.6, 0.12]},
	"cut": {"name": "Cut", "bat": "h", "th": 88.0, "el": 3.0, "power": 25.0, "h": [0.35, 1.25], "x": [0.22, 1.0]},
	"punch": {"name": "Back-foot punch", "bat": "v", "th": 22.0, "el": 3.0, "power": 21.0, "h": [0.35, 1.15], "x": [-0.1, 0.45]},
	"pull": {"name": "Pull", "bat": "h", "th": -78.0, "el": 6.0, "power": 26.0, "h": [0.65, 1.55], "x": [-0.7, 0.4]},
	"lofted_cover": {"name": "Lofted cover drive", "bat": "v", "th": 45.0, "el": 27.0, "power": 28.0, "h": [0.0, 0.7], "x": [0.04, 0.7]},
	"lofted_straight": {"name": "Lofted straight drive", "bat": "v", "th": 0.0, "el": 29.0, "power": 30.0, "h": [0.0, 0.75], "x": [-0.2, 0.3]},
	"slog": {"name": "Slog to cow corner", "bat": "v", "th": -55.0, "el": 30.0, "power": 30.0, "h": [0.0, 0.85], "x": [-0.6, 0.3]},
	"upper_cut": {"name": "Upper cut", "bat": "h", "th": 125.0, "el": 34.0, "power": 24.0, "h": [0.9, 1.9], "x": [0.2, 1.0]},
	"lofted_punch": {"name": "Lofted punch", "bat": "v", "th": 12.0, "el": 24.0, "power": 26.0, "h": [0.4, 1.1], "x": [-0.1, 0.45]},
	"hook": {"name": "Hook", "bat": "h", "th": -100.0, "el": 28.0, "power": 28.0, "h": [1.0, 2.0], "x": [-0.8, 0.4]},
	"sweep": {"name": "Sweep", "bat": "h", "th": -95.0, "el": 4.0, "power": 20.0, "h": [0.0, 0.55], "x": [-0.6, 0.45]},
	"slog_sweep": {"name": "Slog sweep", "bat": "h", "th": -65.0, "el": 26.0, "power": 27.0, "h": [0.0, 0.6], "x": [-0.5, 0.4]},
	"reverse_sweep": {"name": "Reverse sweep", "bat": "h", "th": 100.0, "el": 4.0, "power": 18.0, "h": [0.0, 0.55], "x": [-0.2, 0.6]},
}


## Which shot a key combination plays. Neutral footwork picks front or back
## from how high the batter expects the ball (`pred_h`), but still meets it
## from the crease.
static func shot_key(shot: String, foot: String, aim: int, pred_h: float) -> String:
	var back := foot == "back" or (foot == "neutral" and pred_h > 0.85)
	match shot:
		"defend":
			return "defend_back" if back else "defend"
		"sweep":
			return ["sweep", "slog_sweep", "reverse_sweep"][aim + 1]
		"loft":
			if back:
				return ["hook", "lofted_punch", "upper_cut"][aim + 1]
			return ["slog", "lofted_straight", "lofted_cover"][aim + 1]
	if back:
		return ["pull", "punch", "cut"][aim + 1]
	return ["flick", "straight", "cover"][aim + 1]


## Maps an 8-way direction (x: -1 leg .. 1 off, y: 1 towards the bowler ..
## -1 back) to footwork, side and a squarer aim for pure left/right.
static func from_direction(dir: Vector2i) -> Dictionary:
	var foot := "neutral"
	if dir.y > 0:
		foot = "front"
	elif dir.y < 0:
		foot = "back"
	var th_adj := 0.0
	if dir.y == 0 and dir.x != 0:
		th_adj = 22.0 * dir.x
	return {"foot": foot, "aim": dir.x, "th_adj": th_adj}


static func effective_foot(inp: Dictionary) -> String:
	if inp.get("dance", false):
		return "dance"
	if inp.shot == "sweep":
		return "front"
	return inp.foot


## Ideal time to press for a footwork + shot (the autopilot and tests use it).
static func ideal_press(traj: Dictionary, shot: String, foot: String) -> float:
	var t_arr := BallSim.time_at_z(traj, PLANE[foot])
	return t_arr - float(SWING_T.get(shot, 0.2))


static func _range_out(v: float, r: Array) -> float:
	if v < float(r[0]):
		return v - float(r[0])
	if v > float(r[1]):
		return v - float(r[1])
	return 0.0


## Small deterministic jitter from the delivery seed, so identical inputs
## always give identical results but different deliveries vary.
static func _jit(d: Dictionary, salt: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = int(d.seed) * 31 + salt
	return r.randf_range(-1.0, 1.0)


static func resolve(traj: Dictionary, d: Dictionary, inp: Dictionary, c) -> Dictionary:
	var foot := effective_foot(inp)
	var shot: String = inp.shot
	var r := {
		"contact": "none", "shot": shot, "foot": foot, "shot_name": "Leave",
		"te": 0.0, "ex": 0.0, "ey": 0.0, "quality": 0.0, "timing": "",
		"t_contact": -1.0, "exit_pos": Vector3.ZERO, "exit_vel": Vector3.ZERO,
		"pad": false, "pad_t": -1.0, "pad_pos": Vector3.ZERO, "body": false, "helmet": false,
		"bowled": false, "played_on": false, "stumped": false, "hit_wicket": false,
		"thickness": 0.0, "edge_gap": 9.0, "played_shot": shot != "leave",
	}
	var plane_z: float = PLANE[foot]
	var t_arr := BallSim.time_at_z(traj, plane_z)

	if shot != "leave" and t_arr >= 0.0:
		var t_press: float = inp.t_press
		var p_now := BallSim.pos_at(traj, t_press)
		var v_now := BallSim.vel_at(traj, t_press)
		var pitched := float(traj.pitch_t) >= 0.0 and t_press >= float(traj.pitch_t)
		var pred := p_now
		if p_now.z < plane_z:
			pred = BallSim.naive_predict(p_now, v_now, pitched, plane_z)
		var actual := BallSim.pos_at(traj, t_arr)
		var key := shot_key(shot, foot, int(inp.aim), pred.y)
		var s: Dictionary = (SHOTS[key] as Dictionary).duplicate()
		# Pure left/right (no forward or back) aims squarer.
		s.th = float(s.th) + float(inp.get("th_adj", 0.0))
		r.shot_name = s.name
		r.key = key
		# Slow balls give more time to adjust the bat on the way down.
		var adjust := ADJUST + 0.25 * clampf((30.0 - float(d.speed)) / 10.0, 0.0, 1.0)
		var bat := pred + (actual - pred) * adjust
		r.bat_pos = bat           # where the bat goes (for the animation)
		var te := t_arr - (t_press + float(SWING_T[shot]))
		var window: float = WINDOW[shot]
		r.te = te
		r.timing = "Perfect" if absf(te) <= PERFECT else ("Early" if te > 0.0 else "Late")
		var ex := actual.x - bat.x
		var ey := actual.y - bat.y
		# Shots played at the wrong ball: count the mismatch as bat error.
		var h_out := _range_out(actual.y, s.h)
		var x_out := _range_out(actual.x, s.x)
		var aerial := 0.0
		var q_shape := 1.0
		if s.bat == "v":
			if h_out > 0.0:
				aerial = h_out * 70.0      # driving a short ball goes in the air
				q_shape *= clampf(1.0 - h_out, 0.4, 1.0)
			if absf(x_out) > 0.2:
				ex += x_out * 0.5          # across the line: edge or miss
			else:
				q_shape *= 1.0 - absf(x_out) * 2.0
		else:
			ey += h_out * 0.6
			if absf(x_out) > 0.25:
				ey += -absf(x_out) * 0.25  # cramped or reaching: under-edge
			else:
				q_shape *= 1.0 - absf(x_out) * 1.5
		# Driving on the up: a front-foot attacking shot to a ball that pitched
		# well short of the contact point. Good length is "too short to drive":
		# it goes in the air and is harder to middle. Drives are for full balls.
		var tol_mul := 1.0
		var pitch_z: float = (traj.pitch_pos as Vector3).z
		if shot in ["attack", "loft"] and s.bat == "v" and foot != "back" and float(traj.pitch_t) >= 0.0:
			var over := maxf(0.0, (plane_z - pitch_z) - 2.5)
			aerial += over * 9.0
			q_shape *= clampf(1.0 - over * 0.18, 0.45, 1.0)
			tol_mul = clampf(1.0 - over * 0.15, 0.5, 1.0)
		# Sweeping the quicks: no time to get down and across, top edges galore.
		if shot == "sweep":
			ey += maxf(0.0, (float(d.speed) - 27.0) * 0.016)
		r.ex = ex
		r.ey = ey

		if absf(te) <= window:
			var primary := ex if s.bat == "v" else ey
			var mid := (0.04 if s.bat == "v" else 0.05) * tol_mul
			var edge := 0.09 if s.bat == "v" else 0.11
			if shot == "defend":
				mid = 0.05
				edge = 0.1
			var other_miss := false
			if s.bat == "v" and ey < -0.32:
				other_miss = true          # shot under the bat (a shooter)
			if s.bat == "h" and absf(ex) > 0.35:
				other_miss = true
			# Play with the movement: a bat angled the way you aim covers a ball
			# moving that way (flick the inswinger, drive the leg-break), but
			# playing across it shrinks the margin on the other side.
			var cover := 0.0
			if s.bat == "v" and int(inp.aim) != 0:
				if signf(primary) == signf(float(inp.aim)):
					cover = 0.06
				else:
					cover = -0.01
			primary = signf(primary) * maxf(0.0, absf(primary) - cover)
			r.edge_gap = absf(primary) - edge
			if not other_miss and absf(primary) <= edge:
				var v_in := BallSim.vel_at(traj, t_arr)
				_contact(r, d, s, key, shot, primary, mid, edge, te, window, q_shape, aerial,
						actual, v_in, c, traj, foot)
				r.t_contact = t_arr
				return r
		elif absf(te) <= window + 0.03:
			r.edge_gap = 0.02

	# No bat on it: pad, body, stumps or through to the keeper.
	_no_contact(r, traj, d, foot, inp)
	return r


static func _contact(r: Dictionary, d: Dictionary, s: Dictionary, key: String, shot: String,
		primary: float, mid: float, edge: float, te: float, window: float, q_shape: float,
		aerial: float, actual: Vector3, v_in: Vector3, c, traj: Dictionary, foot: String) -> void:
	var speed_in := v_in.length()
	var hard: float = c.hardness()
	var q_t := 1.0 - pow(absf(te) / window, 1.6)
	var th: float = s.th
	var el: float = s.el + aerial
	var speed := 0.0
	r.exit_pos = actual
	if absf(primary) <= mid:
		r.contact = "middle"
		var q := q_t * q_shape * (1.0 - 0.35 * absf(primary) / mid)
		if foot == "neutral":
			q *= 0.9
		if foot == "dance":
			q *= 1.05
		r.quality = q
		speed = q * (float(s.power) + 0.3 * speed_in) * (0.85 + 0.15 * hard)
		if shot == "defend":
			speed = (0.18 + 0.1 * q) * speed_in * 0.6 + 1.0
		th -= te / 0.06 * 22.0                 # early: to leg, late: to off
		if shot == "loft" and q < 0.55:
			el += (0.55 - q) * 80.0            # skied
		elif shot != "loft" and q < 0.4 and shot != "defend":
			el = minf(el, 2.0)                 # bottom-handed squirt along the ground
		if s.bat == "v" and r.ey > 0.25:
			# Ball climbed on the batter: off the glove or the shoulder of the bat.
			r.contact = "glove"
			th = _jit(d, 3) * 70.0
			el = 48.0 + 14.0 * absf(_jit(d, 4))
			speed = 6.5 + 2.5 * absf(_jit(d, 5))
		th += _jit(d, 1) * 5.0
		el += _jit(d, 2) * 3.0
	else:
		var thick := 1.0 - (absf(primary) - mid) / (edge - mid)
		r.thickness = thick
		r.quality = 0.25 * q_t
		var soft := 0.55 if shot == "defend" else 1.0     # soft hands
		if s.bat == "v":
			if primary > 0.0:
				r.contact = "outside_edge"
				th = 180.0 - lerpf(7.0, 50.0, thick)
				speed = speed_in * lerpf(0.78, 0.42, thick) * soft
				el = 2.0 + 7.0 * absf(_jit(d, 6))
			else:
				r.contact = "inside_edge"
				th = -(180.0 - lerpf(10.0, 60.0, thick))
				speed = speed_in * lerpf(0.6, 0.35, thick) * soft
				el = -6.0 + 10.0 * absf(_jit(d, 7))
		else:
			if primary > 0.0:
				r.contact = "top_edge"
				th = (-160.0 if float(s.th) < 0.0 else 155.0) + _jit(d, 8) * 15.0
				el = 55.0 + 12.0 * absf(_jit(d, 9))
				speed = 9.0 + 0.25 * speed_in
			else:
				r.contact = "bottom_edge"
				th = (-170.0 if float(s.th) < 0.0 else 172.0) + _jit(d, 10) * 8.0
				el = -12.0
				speed = speed_in * 0.4
		# Inside/bottom edges can deflect onto the stumps: "played on".
		if r.contact == "inside_edge" or r.contact == "bottom_edge":
			var at_stumps := BallSim.pos_at(traj, BallSim.time_at_z(traj, 0.0))
			if absf(at_stumps.x) < BallSim.STUMP_HALF + 0.17 and thick > 0.25 and _jit(d, 11) > 0.0:
				r.played_on = true
		if key == "hook" or key == "pull":
			if q_t < 0.5 and foot == "back" and _jit(d, 12) > 0.8:
				r.hit_wicket = true      # trod on the stumps going back
	r.timing = r.timing
	var rad_th := deg_to_rad(th)
	var rad_el := deg_to_rad(el)
	var dir := Vector3(sin(rad_th) * cos(rad_el), sin(rad_el), -cos(rad_th) * cos(rad_el))
	r.exit_vel = dir * maxf(speed, 1.0)
	r.dir_deg = th


static func _no_contact(r: Dictionary, traj: Dictionary, d: Dictionary, foot: String, inp: Dictionary) -> void:
	r.contact = "none" if inp.shot == "leave" else "miss"
	var pad_z: float = PAD_Z[foot]
	var pad_x: float = PAD_X[foot]
	if inp.shot == "sweep":
		pad_x = 0.02
	var t_pad := BallSim.time_at_z(traj, pad_z)
	if t_pad >= 0.0:
		var p := BallSim.pos_at(traj, t_pad)
		if absf(p.x - pad_x) <= PAD_HALF + BallSim.RADIUS:
			if p.y <= PAD_TOP:
				r.pad = true
				r.pad_t = t_pad
				r.pad_pos = p
				return
			if p.y <= 1.85:
				var ducking: bool = inp.shot == "leave" and inp.foot == "back" and p.y > 1.15
				if not ducking:
					r.body = true
					r.helmet = p.y > 1.45
					r.pad_t = t_pad
					r.pad_pos = p
					return
	var t0 := BallSim.time_at_z(traj, 0.0)
	if t0 >= 0.0:
		var s := BallSim.pos_at(traj, t0)
		if absf(s.x) <= BallSim.STUMP_HALF + BallSim.RADIUS and s.y <= BallSim.STUMP_HEIGHT + BallSim.RADIUS:
			r.bowled = true
			r.t_contact = t0
			return
	if foot == "dance" and d.style in ["offspin", "legspin"]:
		r.stumped = true
