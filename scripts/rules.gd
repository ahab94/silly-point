extends RefCounted
## The referee: given a delivery and what the bat did, decide the result of
## the ball (runs, extras, out or not, what the umpire says, whether a review
## would change it). Pure and deterministic, so the game and the autopilot
## share it.

const BallSim := preload("res://scripts/ball_sim.gd")
const Fielding := preload("res://scripts/fielding.gd")
const Umpire := preload("res://scripts/umpire.gd")

const CONTACTS := ["middle", "glove", "outside_edge", "inside_edge", "top_edge", "bottom_edge"]


## `protected`: a free hit, where you can't be out bowled, caught, LBW or
## stumped. `t20` turns on wides.
static func outcome(traj: Dictionary, d: Dictionary, bat: Dictionary, field: Array, protected: bool, t20: bool) -> Dictionary:
	var o := {
		"runs": 0, "extras": 0, "legal": true, "dismissal": "", "umpire_out": false,
		"truth_out": false, "reviewable": false, "fielding_review": false, "field": {},
		"track": {}, "comment": "dot", "edge": false, "wide": false, "no_ball": false,
		"snick": -1.0, "free_hit_next": false,
	}
	var seed: int = d.seed
	var protect: bool = protected or bool(d.no_ball)
	if d.no_ball:
		o.extras = 1
		o.legal = false
		o.no_ball = true
		o.free_hit_next = t20
	var contact: String = bat.contact
	if contact in CONTACTS:
		o.edge = contact.ends_with("edge")
		if bat.played_on and not protect:
			_out(o, "played_on", true)
			return o
		if bat.hit_wicket and not protect:
			_out(o, "hit_wicket", true)
			return o
		var fr := Fielding.play(bat.exit_pos, bat.exit_vel, field, seed)
		o.field = fr
		match fr.result:
			"caught":
				var catcher: Dictionary = field[fr.fielder]
				if protect:
					o.comment = "dot"
				elif catcher.keeper and contact == "outside_edge":
					# Faint edges: the umpire may not hear it, but the fielding
					# side will review and the Snick-o-Scope shows the spike.
					o.snick = clampf(1.0 - float(bat.thickness), 0.2, 1.0)
					o.dismissal = "caught_behind"
					o.truth_out = true
					o.umpire_out = Umpire.hears_edge(float(bat.thickness), seed)
					o.fielding_review = not o.umpire_out
					o.comment = "caught_behind"
				else:
					_out(o, "caught", true)
			"four", "six":
				o.runs = fr.runs
				o.comment = fr.result
			"dropped":
				o.runs = fr.runs
				o.comment = "dropped"
			_:
				o.runs = fr.runs
				# A dead-bat block that dribbles a few metres isn't worth the risk.
				if bat.shot == "defend":
					var stop: Vector3 = BallSim.hit_pos_at(fr.path, float(fr.t_end))
					if Vector2(stop.x, stop.z).length() < 12.0:
						o.runs = 0
				if o.edge and o.runs > 0:
					o.comment = "edge_safe"
				else:
					o.comment = "runs" if o.runs > 0 else "dot"
		return o
	if bat.pad:
		var tr := Umpire.track(traj, bat)
		o.track = tr
		o.comment = "not_out_pad"
		if protect:
			return o
		o.umpire_out = Umpire.on_field_lbw(tr, bat, seed)
		o.dismissal = "lbw"
		if o.umpire_out:
			o.truth_out = tr.out_possible     # umpire's call keeps it out
			o.reviewable = true
			o.comment = "lbw"
		else:
			o.truth_out = false
			if tr.hitting_clean:
				o.fielding_review = true
				o.truth_out = true
				o.comment = "lbw"
			else:
				o.dismissal = ""
		return o
	if bat.body:
		o.comment = "helmet" if bat.helmet else "body"
		return o
	if bat.bowled:
		if protect:
			o.comment = "dot"
			return o
		_out(o, "bowled", true)
		return o
	if bat.stumped and not protect:
		_out(o, "stumped", true)
		return o
	# Through to the keeper. A very near miss might fool the umpire.
	if t20:
		var t0 := BallSim.time_at_z(traj, 0.0)
		if t0 >= 0.0:
			var at := BallSim.pos_at(traj, t0)
			if at.x > 0.9 or at.x < -0.55:
				o.wide = true
				o.legal = false
				o.extras = maxi(int(o.extras), 1)
				o.comment = "wide"
				return o
	o.comment = "leave" if contact == "none" else "beaten"
	if contact == "miss" and not protect and Umpire.phantom_edge(float(bat.edge_gap), seed):
		o.dismissal = "caught_behind"
		o.umpire_out = true
		o.truth_out = false
		o.reviewable = true
		o.snick = 0.0
		o.comment = "caught_behind"
	return o


static func _out(o: Dictionary, how: String, umpire: bool) -> void:
	o.dismissal = how
	o.umpire_out = umpire
	o.truth_out = true
	o.comment = how


## Final decision after any reviews: the batter reviews if they have one
## left and the umpire gave it out; the fielding side reviews clear misses.
static func final_out(o: Dictionary, batter_reviews: bool) -> bool:
	if o.dismissal == "":
		return false
	if o.umpire_out:
		if o.reviewable and batter_reviews:
			return o.truth_out
		return true
	return bool(o.fielding_review)


static func how_out(dismissal: String) -> String:
	match dismissal:
		"bowled": return "Bowled"
		"played_on": return "Played on"
		"lbw": return "LBW"
		"caught": return "Caught"
		"caught_behind": return "Caught behind"
		"stumped": return "Stumped"
		"hit_wicket": return "Hit wicket"
	return ""
