extends SceneTree
## Checks the cricket physics and rules without any graphics. Run:
##   godot --headless --path . --script res://tests/sim_test.gd

const BallSim := preload("res://scripts/ball_sim.gd")
const Bowling := preload("res://scripts/bowling.gd")
const Batting := preload("res://scripts/batting.gd")
const Fielding := preload("res://scripts/fielding.gd")
const Umpire := preload("res://scripts/umpire.gd")
const Conditions := preload("res://scripts/conditions.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok   ", what)


func cond(day: int, overs: float, overcast := false, dew := false):
	var c = Conditions.new()
	c.day = day
	c.overs = overs
	c.overcast = overcast
	c.dew = dew
	c.abrasive = 0.8
	return c


## Average sideways movement (x at the stumps minus x where it pitched and
## the release line) over many deliveries of one kind.
func lateral(bowler: String, kind: String, c, n := 40) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var total := 0.0
	for i in n:
		var d := Bowling.make(Bowling.get_bowler(bowler), c, rng, kind)
		var tr := BallSim.simulate(d)
		var at := BallSim.pos_at(tr, BallSim.time_at_z(tr, -1.5))
		# Compare with where a straight line from release through the
		# first 40% of the flight would have gone.
		var early := BallSim.pos_at(tr, BallSim.flight_time(d) * 0.4)
		var r: Vector3 = d.release
		var dir := (early - r)
		var straight_x := r.x + dir.x / dir.z * (at.z - r.z)
		total += at.x - straight_x
	return total / n


## Average turn off the pitch at the batter: x of the real ball minus the
## same ball with no deviation off the surface.
func turn(bowler: String, kind: String, c, n := 40) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var total := 0.0
	for i in n:
		var d := Bowling.make(Bowling.get_bowler(bowler), c, rng, kind)
		var flat := d.duplicate()
		flat.deviation = 0.0
		var a := BallSim.simulate(d)
		var b := BallSim.simulate(flat)
		total += BallSim.pos_at(a, BallSim.time_at_z(a, -1.5)).x - BallSim.pos_at(b, BallSim.time_at_z(b, -1.5)).x
	return total / n


func _initialize() -> void:
	var c1 = cond(1, 0.0, true)
	var out_new := lateral("banana", "outswing", c1)
	var in_new := lateral("banana", "inswing", c1)
	print("  new ball outswing %.2f m, inswing %.2f m" % [out_new, in_new])
	check(out_new > 0.15, "a new outswinger moves away (towards off)")
	check(in_new < -0.15, "a new inswinger moves in")
	var c_old = cond(3, 55.0)
	var out_old := lateral("oz", "outswing", c_old)
	print("  55-over-old ball, 'outswing' grip: %.2f m" % out_old)
	check(out_old < -0.1, "an old rough ball reverses: the outswing grip comes in")
	check(c_old.is_reversing(), "conditions report reverse swing")
	var dew = cond(3, 55.0, false, true)
	check(absf(lateral("oz", "outswing", dew)) < absf(out_old) * 0.5, "dew kills reverse swing")

	var off4 := turn("tim", "offbreak", cond(4, 40.0))
	var off1 := turn("tim", "offbreak", cond(1, 10.0))
	var leg4 := turn("wizard", "legbreak", cond(4, 40.0))
	var goog := turn("wizard", "googly", cond(4, 40.0))
	print("  turn at the batter: off-break day4 %.2f m, day1 %.2f m, leg-break %.2f, googly %.2f" % [off4, off1, leg4, goog])
	check(off4 < -0.12, "an off-break turns into the right-hander")
	check(absf(off4) > absf(off1) * 1.8, "a day-4 pitch turns far more than day 1")
	check(leg4 > 0.12, "a leg-break turns away")
	check(goog < -0.08, "the googly turns the other way")
	check(absf(turn("tim", "offbreak", cond(4, 40.0, false, true))) < absf(off4) * 0.6, "dew stops the spinners gripping")

	# Bounce: height at the stumps for a good length ball, day 1 vs day 5.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var h1 := 0.0
	var h5 := 0.0
	for i in 30:
		var d1 := Bowling.make(Bowling.get_bowler("grassy"), cond(1, 5.0), rng, "seam")
		d1.pitch = Vector2(0.1, -6.0)
		d1.bounce = cond(1, 5.0).bounce()
		var d5 := d1.duplicate()
		d5.bounce = cond(5, 5.0).bounce()
		h1 += BallSim.pos_at(BallSim.simulate(d1), BallSim.time_at_z(BallSim.simulate(d1), 0.0)).y
		h5 += BallSim.pos_at(BallSim.simulate(d5), BallSim.time_at_z(BallSim.simulate(d5), 0.0)).y
	print("  good length height at stumps: day1 %.2f m, day5 %.2f m" % [h1 / 30.0, h5 / 30.0])
	check(h1 > h5 + 0.03 * 30.0 / 30.0, "a day-1 pitch bounces more than day 5")

	# Typical heights.
	var bouncer := Bowling.make(Bowling.get_bowler("barnaby"), cond(2, 20.0), rng, "bouncer")
	var bt := BallSim.simulate(bouncer)
	var bh := BallSim.pos_at(bt, BallSim.time_at_z(bt, -0.5)).y
	print("  bouncer height at the batter: %.2f m (pitched %.1f m out)" % [bh, -bt.pitch_pos.z])
	check(bh > 1.2, "a bouncer reaches chest/head height")

	# Batting: perfect timing on a straight half-volley middles it.
	var c3 = cond(3, 25.0)
	var d := Bowling.make(Bowling.get_bowler("dave"), c3, rng, "seam")
	d.pitch = Vector2(0.15, -3.5)
	d.deviation = 0.0
	d.swing = 0.0
	var tr := BallSim.simulate(d)
	var tp := Batting.ideal_press(tr, "attack", "front")
	var r := Batting.resolve(tr, d, {"shot": "attack", "foot": "front", "aim": 1, "t_press": tp}, c3)
	print("  cover drive: contact=%s quality=%.2f speed=%.1f" % [r.contact, r.quality, (r.exit_vel as Vector3).length()])
	check(r.contact == "middle" and r.quality > 0.8, "a perfectly timed cover drive middles it")
	var fr := Fielding.play(r.exit_pos, r.exit_vel, Fielding.make_field("pace_attack"), 1)
	print("  -> fielding: ", fr.result, " runs=", fr.runs)
	var late := Batting.resolve(tr, d, {"shot": "attack", "foot": "front", "aim": 1, "t_press": tp + 0.2}, c3)
	check(late.contact == "miss", "far too late misses")
	var leave := Batting.resolve(tr, d, {"shot": "leave", "foot": "neutral", "aim": 0, "t_press": 0.0}, c3)
	print("  leave: pad=%s bowled=%s" % [leave.pad, leave.bowled])

	# Getting forward to the pitch of the ball smothers seam movement: fewer
	# edges than playing the same ball from the crease.
	var edges_crease := 0
	var edges_forward := 0
	for i in 60:
		var dd := Bowling.make(Bowling.get_bowler("grassy"), cond(1, 2.0), rng, "seam")
		dd.pitch = Vector2(0.15, -4.5)
		var tt := BallSim.simulate(dd)
		var a := Batting.resolve(tt, dd, {"shot": "defend", "foot": "neutral", "aim": 0,
				"t_press": Batting.ideal_press(tt, "defend", "neutral")}, cond(1, 2.0))
		var b := Batting.resolve(tt, dd, {"shot": "defend", "foot": "front", "aim": 0,
				"t_press": Batting.ideal_press(tt, "defend", "front")}, cond(1, 2.0))
		if a.contact != "middle":
			edges_crease += 1
		if b.contact != "middle":
			edges_forward += 1
	print("  seaming ball, not middled: from the crease %d/60, forward %d/60" % [edges_crease, edges_forward])
	check(edges_forward < edges_crease, "getting forward smothers the seam movement")

	# Umpire: a straight ball hitting the pad in front is out, one pitching
	# outside leg is not.
	var lbw := Bowling.make(Bowling.get_bowler("dave"), c3, rng, "seam")
	lbw.pitch = Vector2(-0.08, -3.0)
	lbw.deviation = 0.0
	lbw.swing = 0.0
	var lt := BallSim.simulate(lbw)
	var miss := Batting.resolve(lt, lbw, {"shot": "leave", "foot": "back", "aim": 0, "t_press": 0.0}, c3)
	check(miss.pad, "a straight ball hits the back pad")
	if miss.pad:
		var trk := Umpire.track(lt, miss)
		print("  tracking: ", trk.pitching, " / ", trk.impact, " / ", trk.wickets)
		check(trk.out_possible, "plumb LBW is out on tracking")
	var leg := lbw.duplicate()
	leg.pitch = Vector2(-0.35, -4.0)
	leg.drift = 0.0
	leg.deviation = 2.0
	var lgt := BallSim.simulate(leg)
	var lr := Batting.resolve(lgt, leg, {"shot": "leave", "foot": "neutral", "aim": 0, "t_press": 0.0}, c3)
	if lr.pad:
		check(Umpire.track(lgt, lr).pitching == "OUTSIDE LEG", "pitching outside leg is spotted")

	# Fielding: a huge straight hit is six; a gentle push is no run.
	var six := Fielding.play(Vector3(0, 0.6, -1.9), Vector3(0, 20, -31), Fielding.make_field("pace_attack"), 3)
	check(six.result == "six", "a big lofted hit clears the rope (got %s)" % six.result)
	var push := Fielding.play(Vector3(0, 0.3, -1.9), Vector3(0.3, -0.3, -3), Fielding.make_field("pace_attack"), 3)
	check(push.result == "runs" and push.runs == 0, "a defensive push is a dot ball (got %s %d)" % [push.result, push.runs])

	print("SIM FAILURES: %d" % fails if fails > 0 else "SIM OK")
	quit(1 if fails > 0 else 0)
