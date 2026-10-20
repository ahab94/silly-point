extends SceneTree
## Live gameplay checks: real key presses through the input system, a full
## ball played out, the leave, a review, and level data sanity. Run:
##   godot --headless --path . --script res://tests/game_test.gd

const Levels := preload("res://scripts/levels.gd")
const Bowling := preload("res://scripts/bowling.gd")
const BallSim := preload("res://scripts/ball_sim.gd")
const Batting := preload("res://scripts/batting.gd")

var fails := 0
var game


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok   ", what)


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_run.call_deferred()


func press(action: String, on := true) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)


func wait_phase(p: int, max_frames := 2000) -> bool:
	for i in max_frames:
		if game.phase == p:
			return true
		await process_frame
	return false


func _run() -> void:
	await process_frame
	# Level data: every bowler exists, numbers are sensible.
	for i in Levels.count():
		var l: Dictionary = Levels.get_level(i)
		for b in l.bowlers:
			check(Bowling.BOWLERS.has(b), "level %d bowler %s exists" % [i, b])
		check(int(l.balls) > 0 and int(l.wickets) > 0, "level %d has balls and wickets" % i)
		check(l.mode == "chase" or l.mode == "survive", "level %d mode" % i)

	# A real shot: start level 0, wait for the release, then press K with W
	# held at the ideal moment.
	game.start_level(0)
	check(await wait_phase(game.Phase.FLIGHT), "the bowler runs in and releases")
	var ideal: float = Batting.ideal_press(game.traj, "attack", "front")
	while game.t < ideal - 0.005:
		await process_frame
	press("dir_up")
	press("shot_attack")
	await process_frame
	press("shot_attack", false)
	press("dir_up", false)
	check(game.shot_taken, "pressing K plays a shot")
	check(game.inp.get("foot", "") == "front", "holding W plays off the front foot")
	check(game.bat.contact != "", "the shot is resolved (%s)" % game.bat.contact)
	check(await wait_phase(game.Phase.BETWEEN), "the ball is played out and scored")
	check(game.balls == 1 or not game.out_o.legal, "a legal ball is counted")

	# A leave: no key at all.
	check(await wait_phase(game.Phase.FLIGHT), "next ball released")
	check(await wait_phase(game.Phase.PLAY), "the ball arrives")
	check(game.inp.get("shot", "") == "leave", "no key means a leave")

	# Charging down the pitch after the window is ignored.
	check(await wait_phase(game.Phase.FLIGHT), "third ball released")
	while game.t < 0.4:
		await process_frame
	press("dance")
	await process_frame
	press("dance", false)
	check(not game.danced, "too late to charge once the ball is on its way")

	# Review flow: fake an LBW the umpire wrongly gave, and review it.
	await wait_phase(game.Phase.BETWEEN)
	game.out_o = {"dismissal": "lbw", "umpire_out": true, "truth_out": false, "reviewable": true,
			"fielding_review": false, "snick": -1.0, "comment": "lbw", "runs": 0, "extras": 0,
			"legal": true, "wide": false, "no_ball": false, "free_hit_next": false, "field": {},
			"track": {"pitching": "IN LINE", "impact": "IN LINE", "wickets": "MISSING", "umpires_call": false}}
	game.bat = {"pad_t": 0.5, "contact": "none", "played_on": false, "hit_wicket": false}
	var w0: int = game.wkts
	var r0: int = game.reviews
	game._decision_shown = false
	game._set_phase(game.Phase.DECIDE)
	game._decide()
	check(game.phase == game.Phase.REVIEW, "a wrong-looking LBW offers a review")
	press("review")
	await process_frame
	press("review", false)
	check(game.phase == game.Phase.DRS, "R starts the review")
	await wait_phase(game.Phase.BETWEEN)
	check(game.wkts == w0, "the review overturns it: not out")
	check(game.reviews == r0, "a successful review is kept")

	print("GAME FAILURES: %d" % fails if fails > 0 else "GAME OK")
	quit(1 if fails > 0 else 0)
