extends RefCounted
## Field placings and what the fielders do with a hit ball: catch it, cut it
## off (and how many runs the batters get meanwhile), or watch it go to the
## boundary. Deterministic for a given seed.

const BallSim := preload("res://scripts/ball_sim.gd")

const CENTRE := Vector2(0.0, -10.06)    # middle of the pitch, centre of the ground
const BOUNDARY := 60.0
const RUN_SPEED := 6.8
const THROW_SPEED := 28.0

# Fielders as [name, angle, distance] from the batter's stumps. Angle in
# degrees from straight back past the bowler, positive towards the off side
# (180 is the wicketkeeper). "close" fielders crouch and react faster.
const FIELDS := {
	"pace_attack": [
		["Wicketkeeper", 179.0, 15.0], ["First slip", 174.0, 15.5], ["Second slip", 169.0, 15.3],
		["Gully", 138.0, 11.0], ["Point", 96.0, 25.0], ["Cover", 55.0, 29.0],
		["Mid-off", 14.0, 33.0], ["Mid-on", -14.0, 33.0], ["Square leg", -95.0, 27.0],
		["Fine leg", -158.0, 55.0],
	],
	"pace_defend": [
		["Wicketkeeper", 179.0, 15.0], ["Third man", 155.0, 57.0], ["Point", 95.0, 27.0],
		["Cover", 50.0, 30.0], ["Long-off", 10.0, 59.0], ["Long-on", -12.0, 59.0],
		["Deep midwicket", -62.0, 57.0], ["Square leg", -95.0, 27.0],
		["Fine leg", -155.0, 56.0], ["Midwicket", -50.0, 28.0],
	],
	"spin_attack": [
		["Wicketkeeper", 160.0, 1.3], ["Slip", 165.0, 2.8], ["Short leg", -100.0, 3.4],
		["Silly point", 95.0, 3.2], ["Mid-off", 14.0, 26.0], ["Mid-on", -14.0, 26.0],
		["Cover", 52.0, 26.0], ["Midwicket", -58.0, 27.0], ["Deep square leg", -95.0, 56.0],
		["Point", 92.0, 26.0],
	],
	"spin_defend": [
		["Wicketkeeper", 160.0, 1.3], ["Long-off", 10.0, 59.0], ["Long-on", -12.0, 59.0],
		["Deep midwicket", -60.0, 57.0], ["Deep square leg", -98.0, 57.0], ["Deep cover", 50.0, 58.0],
		["Point", 92.0, 26.0], ["Mid-off", 18.0, 25.0], ["Mid-on", -18.0, 25.0],
		["Short fine leg", -150.0, 18.0],
	],
}


static func polar(angle_deg: float, dist: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(sin(a) * dist, -cos(a) * dist)


static func make_field(name: String) -> Array:
	var out := []
	for f in FIELDS[name]:
		var dist: float = f[2]
		out.append({"name": f[0], "pos": polar(f[1], dist), "close": dist < 17.0,
				"keeper": f[0] == "Wicketkeeper"})
	# The bowler finishes the follow-through just down the pitch.
	# Where the run-up's follow-through finishes (game.gd _place_bowler).
	out.append({"name": "Bowler", "pos": Vector2(-0.3, -16.8), "close": false, "keeper": false, "slow": true})
	return out


static func _react(f: Dictionary) -> float:
	if f.get("slow", false):
		return 0.55      # still finishing the follow-through
	return 0.15 if f.close else 0.35


static func _reach(f: Dictionary, t: float) -> float:
	return maxf(0.0, t - _react(f)) * RUN_SPEED


## How far a dive adds: it takes a moment to launch.
static func _dive(f: Dictionary, t: float) -> float:
	return clampf((t - _react(f)) * 5.0, 0.0, 1.6)


static func _rng(seed: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 7919 + salt
	return r


## Plays out a hit. Returns {result: "caught"|"dropped"|"runs"|"four"|"six",
## runs, fielder (index), t_end, catch_pos, path, chase: [{i, to, t}]}.
static func play(exit_pos: Vector3, exit_vel: Vector3, field: Array, seed: int) -> Dictionary:
	var path := BallSim.simulate_hit(exit_pos, exit_vel)
	var pts: PackedVector3Array = path.pts
	var dt := BallSim.HIT_DT
	var res := {"result": "runs", "runs": 0, "fielder": -1, "t_end": float(path.end_t),
			"catch_pos": Vector3.ZERO, "path": path, "chase": [], "catch_chance": 0.0, "misfield": "", "misfields": []}
	var catch_try := _best_catch(pts, dt, field)
	var missed: Array = []
	var bounced := false
	for i in pts.size():
		var t := i * dt
		var p := pts[i]
		if p.y <= BallSim.RADIUS + 0.01 and i > 0:
			bounced = true
		var flat := Vector2(p.x, p.z)
		if flat.distance_to(CENTRE) >= BOUNDARY:
			res.result = "four" if bounced else "six"
			res.runs = 4 if bounced else 6
			res.t_end = t
			_add_chasers(res, field, flat, t)
			return res
		if not catch_try.is_empty() and i == int(catch_try.i):
			var fi: int = catch_try.f
			var chance: float = catch_try.chance
			res.catch_chance = chance
			res.fielder = fi
			res.catch_pos = p
			res.chase = [{"i": fi, "to": flat, "t": t}]
			if _rng(seed, fi).randf() < chance:
				res.result = "caught"
				res.t_end = t
			else:
				res.result = "dropped"
				res.t_end = t + 1.0
				res.runs = 1 if flat.length() > 8.0 else 0
			return res
		# Ground fielding: anyone who can get to the ball's spot in time. A
		# dive at a hard-hit ball might not stop it; then it runs on past.
		if bounced or p.y < 1.0:
			if t < 0.25 and p.y > 0.5:
				continue
			for fi in field.size():
				if fi in missed:
					continue
				var f: Dictionary = field[fi]
				var dist: float = (f.pos as Vector2).distance_to(flat)
				var reach := _reach(f, t)
				if dist <= reach + 0.8:
					var speed := (pts[mini(i + 1, pts.size() - 1)] - p).length() / dt
					var stretch := dist - maxf(0.0, reach - 2.0)
					var stop := clampf(1.05 - maxf(0.0, stretch - 1.0) * 0.3 - maxf(0.0, speed - 14.0) * 0.025, 0.15, 1.0)
					if _rng(seed, 100 + fi).randf() > stop:
						missed.append(fi)
						res.misfield = field[fi].name
						res.misfields.append({"i": fi, "t": t, "to": flat})
						continue
					res.fielder = fi
					res.t_end = t
					res.chase = [{"i": fi, "to": flat, "t": t}]
					var moved := dist > 3.0
					res.runs = _runs(flat, t + (0.25 if moved else 0.0))
					res.result = "runs"
					return res
	# Stopped somewhere nobody reached in time (rare): nearest fielder walks to it.
	var last := pts[pts.size() - 1]
	var lf := Vector2(last.x, last.z)
	var best := 0
	var best_d := 1e9
	for fi in field.size():
		var dd: float = (field[fi].pos as Vector2).distance_to(lf)
		if dd < best_d:
			best_d = dd
			best = fi
	var t_get := float(path.end_t)
	t_get = maxf(t_get, best_d / RUN_SPEED + 0.3)
	res.fielder = best
	res.t_end = t_get
	res.chase = [{"i": best, "to": lf, "t": t_get}]
	res.runs = _runs(lf, t_get)
	return res


## The catch a fielder gets to first: a clean one if anybody can get there
## comfortably, otherwise the best dive. Empty if nobody can reach it.
static func _best_catch(pts: PackedVector3Array, dt: float, field: Array) -> Dictionary:
	var best := {}
	var dive := {}
	for i in range(1, pts.size()):
		var p := pts[i]
		if p.y <= BallSim.RADIUS + 0.01:
			break
		var flat := Vector2(p.x, p.z)
		if flat.distance_to(CENTRE) >= BOUNDARY:
			break
		if p.y < 0.05 or p.y > 2.6:
			continue
		var t := i * dt
		for fi in field.size():
			var f: Dictionary = field[fi]
			var dist: float = (f.pos as Vector2).distance_to(flat)
			var reach := _reach(f, t)
			var hands := 1.2 if f.keeper else 0.9
			if dist <= reach + hands:
				if best.is_empty():
					best = {"i": i, "f": fi,
							"chance": _catch_chance(f, dist, reach, hands, pts[1].distance_to(pts[0]) / dt, t, p.y)}
			elif dist <= reach + hands + _dive(f, t):
				var chance := _catch_chance(f, dist, reach, hands, pts[1].distance_to(pts[0]) / dt, t, p.y)
				if dive.is_empty() or chance > float(dive.chance):
					dive = {"i": i, "f": fi, "chance": chance}
		if not best.is_empty():
			return best
	if not dive.is_empty() and float(dive.chance) > 0.0:
		return dive
	return {}


static func _catch_chance(f: Dictionary, dist: float, reach: float, hands: float, speed: float, t: float, h: float) -> float:
	var stretch := dist - reach           # how far beyond a comfortable run
	var c := 0.97
	if f.keeper:
		c = 0.98
	if stretch > hands:
		c -= 0.35 + (stretch - hands) * 0.25    # diving
	if f.close and t < 0.45:
		c -= clampf((speed - 15.0) / 30.0, 0.0, 0.45)    # reflex catch
	if h > 2.2 or h < 0.2:
		c -= 0.15
	return clampf(c, 0.0, 0.98)


## Runs the batters can safely complete before the ball comes back.
static func _runs(at: Vector2, t: float) -> int:
	var throw_t := 0.6 + minf(at.distance_to(Vector2(0.0, 0.0)), at.distance_to(Vector2(0.0, -20.12))) / THROW_SPEED
	var avail := t + throw_t
	var runs := 0
	# Batters back up and run on the hit: a single takes about 3 s, each
	# further run about 2.7 s.
	var need := 3.0
	while runs < 3 and avail >= need:
		runs += 1
		need += 2.7
	return runs


static func _add_chasers(res: Dictionary, field: Array, at: Vector2, t: float) -> void:
	var best := -1
	var best_d := 1e9
	for fi in field.size():
		var dd: float = (field[fi].pos as Vector2).distance_to(at)
		if dd < best_d and not field[fi].keeper:
			best_d = dd
			best = fi
	if best >= 0:
		var f: Dictionary = field[best]
		var dir: Vector2 = (at - (f.pos as Vector2))
		var go := minf(dir.length(), RUN_SPEED * maxf(0.0, t - 0.3))
		res.chase = [{"i": best, "to": (f.pos as Vector2) + dir.normalized() * go, "t": t}]
