extends SceneTree
## Outcome statistics for the rookie batter against one level's bowling.
##   godot --headless --path . --script res://tests/stats.gd -- --level=0 --skill=0.6 --n=300
const BallSim := preload("res://scripts/ball_sim.gd")
const Bowling := preload("res://scripts/bowling.gd")
const Batting := preload("res://scripts/batting.gd")
const Fielding := preload("res://scripts/fielding.gd")
const Rules := preload("res://scripts/rules.gd")
const Conditions := preload("res://scripts/conditions.gd")
const Levels := preload("res://scripts/levels.gd")
const Autopilot := preload("res://scripts/autopilot.gd")

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var l: Dictionary = Levels.get_level(int(args.get("level", "0")))
	var c = Conditions.new()
	c.day = l.day; c.overs = l.overs; c.overcast = l.overcast; c.dew = l.dew; c.abrasive = l.abrasive
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var rr := RandomNumberGenerator.new(); rr.seed = 2
	var n := int(args.get("n", "300"))
	var tally := {}
	var runs := 0
	var outs := 0
	for i in n:
		var b := Bowling.get_bowler(l.bowlers[i % l.bowlers.size()])
		var field := Fielding.make_field(("spin_" if Bowling.is_spinner(b) else "pace_") + String(l.field))
		var d := Bowling.make(b, c, rng)
		var tr := BallSim.simulate(d)
		var inp := Autopilot.rookie(tr, d, rr, float(args.get("skill", "0.6")), l.mode == "survive")
		var r := Batting.resolve(tr, d, inp, c)
		var o := Rules.outcome(tr, d, r, field, false, l.format == "t20")
		var out := Rules.final_out(o, true)
		runs += int(o.runs)
		outs += 1 if out else 0
		if args.has("show") and inp.shot == "attack" and r.contact == "middle" and int(o.runs) == 0 and not o.field.is_empty():
			var fr: Dictionary = o.field
			print("  %s q=%.2f speed=%.1f dir=%.0f el=%.0f -> %s by %s at t=%.2f pos=%s" % [r.shot_name, r.quality, (r.exit_vel as Vector3).length(), r.dir_deg, rad_to_deg(asin((r.exit_vel as Vector3).normalized().y)), fr.result, field[fr.fielder].name if fr.fielder >= 0 else "-", fr.t_end, BallSim.hit_pos_at(fr.path, fr.t_end)])
		if args.has("caught") and out and o.dismissal == "caught" and inp.shot == "defend":
			var fr2: Dictionary = o.field
			print("  defend caught by %s: dir=%.0f speed=%.1f el=%.0f exit=%s te=%+.3f ey=%+.3f" % [field[fr2.fielder].name, r.dir_deg, (r.exit_vel as Vector3).length(), rad_to_deg(asin((r.exit_vel as Vector3).normalized().y)), r.exit_pos, r.te, r.ey])
		if args.has("misses") and r.contact == "miss":
			print("  %s %s aim=%d foot=%s te=%+.3f ex=%+.3f ey=%+.3f pitch=%.1f dev=%.2f" % [d.label, inp.shot, inp.aim, r.foot, r.te, r.ex, r.ey, -tr.pitch_pos.z, d.deviation])
		var key := "%s/%s -> %s" % [inp.shot, r.contact, ("OUT " + o.dismissal) if out else str(o.runs)]
		tally[key] = int(tally.get(key, 0)) + 1
	var keys := tally.keys()
	keys.sort_custom(func(a, b): return tally[a] > tally[b])
	for k in keys:
		print("%4d  %s" % [tally[k], k])
	print("runs/ball %.2f   balls/wicket %.1f" % [float(runs) / n, float(n) / maxf(1, outs)])
	quit()
