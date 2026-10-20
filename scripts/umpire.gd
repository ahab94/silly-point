extends RefCounted
## The umpire and the review system ("Pigeon-Eye" ball tracking and the
## "Snick-o-Scope" edge detector).
##
## LBW, in brief, for a right-handed batter:
## - not out if the ball pitched outside leg stump;
## - not out if it hit the pad outside the line of off stump while the batter
##   was playing a shot (leave it alone and that protection is gone);
## - not out if it hit the pad outside leg stump;
## - otherwise out if it would have gone on to hit the stumps.
## The on-field umpire judges by eye (a little noise), so mistakes happen
## and the batter has reviews. Tracking that only clips the stumps is
## "umpire's call": the on-field decision stands either way.

const BallSim := preload("res://scripts/ball_sim.gd")

const ZONE := BallSim.STUMP_HALF + BallSim.RADIUS
const TOO_FAR := 3.0      # metres down the pitch: umpires rarely give these


## Ball-tracking verdict for a pad hit. Each part is a string the review
## screen shows.
static func track(traj: Dictionary, bat: Dictionary) -> Dictionary:
	var pp: Vector3 = traj.pitch_pos
	var pitched_before_pad := float(traj.pitch_t) >= 0.0 and float(traj.pitch_t) <= float(bat.pad_t)
	var pitching := "IN LINE"
	if pitched_before_pad:
		if pp.x < -ZONE:
			pitching = "OUTSIDE LEG"
		elif pp.x > ZONE:
			pitching = "OUTSIDE OFF"
	else:
		pitching = "FULL TOSS"
	var ip: Vector3 = bat.pad_pos
	var impact := "IN LINE"
	if ip.x > ZONE:
		impact = "OUTSIDE OFF"
	elif ip.x < -ZONE:
		impact = "OUTSIDE LEG"
	var t0 := BallSim.time_at_z(traj, 0.0)
	var at := BallSim.pos_at(traj, t0) if t0 >= 0.0 else Vector3(9.0, 9.0, 0.0)
	var wickets := "MISSING"
	var x_in := absf(at.x) <= BallSim.STUMP_HALF
	var y_in := at.y <= BallSim.STUMP_HEIGHT
	if absf(at.x) <= ZONE and at.y <= BallSim.STUMP_HEIGHT + BallSim.RADIUS:
		wickets = "HITTING" if x_in and y_in else "UMPIRE'S CALL"
	var far := ip.z < -TOO_FAR - BallSim.RADIUS
	if far and wickets == "HITTING":
		wickets = "UMPIRE'S CALL"
	var out := pitching != "OUTSIDE LEG" and impact != "OUTSIDE LEG" \
			and not (impact == "OUTSIDE OFF" and bool(bat.played_shot)) and wickets != "MISSING"
	return {"pitching": pitching, "impact": impact, "wickets": wickets,
			"at_stumps": at, "hitting_clean": out and wickets == "HITTING", "out_possible": out,
			"umpires_call": out and wickets == "UMPIRE'S CALL"}


## What the umpire on the field gives, judging by eye.
static func on_field_lbw(tr: Dictionary, bat: Dictionary, seed: int) -> bool:
	if tr.pitching == "OUTSIDE LEG" or tr.impact == "OUTSIDE LEG":
		return false
	if tr.impact == "OUTSIDE OFF" and bool(bat.played_shot):
		return false
	var ip: Vector3 = bat.pad_pos
	if ip.z < -TOO_FAR:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 131 + 17
	var at: Vector3 = tr.at_stumps
	var seen_x := at.x + rng.randfn(0.0, 0.045)
	var seen_y := at.y + rng.randfn(0.0, 0.05)
	return absf(seen_x) <= BallSim.STUMP_HALF + 0.01 and seen_y <= BallSim.STUMP_HEIGHT + 0.02


## Result of a review of an LBW the umpire gave out.
## Returns "overturned", or "stands" (out stays, and an umpire's call keeps the review).
static func review_out(tr: Dictionary) -> String:
	if not tr.out_possible:
		return "overturned"
	return "stands"


## Did the umpire hear a faint edge? Thick edges are always given, the
## thinnest ones are a coin flip. A near miss can fool them the other way.
static func hears_edge(thickness: float, seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 257 + 3
	return rng.randf() < lerpf(0.55, 1.0, clampf(thickness * 2.0, 0.0, 1.0))


static func phantom_edge(edge_gap: float, seed: int) -> bool:
	if edge_gap > 0.025:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 389 + 5
	return rng.randf() < 0.3
