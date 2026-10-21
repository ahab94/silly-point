extends Node3D
## Silly Point. This script runs a match situation ball by ball: picks the
## bowler and the delivery, flies the ball, takes your shot, plays out the
## fielding, asks the umpire, runs reviews, keeps score and decides the
## result. It also owns the camera, menus, saves and dev flags.
##
## Dev flags go after `--` on the command line, e.g.
##   godot --path . -- --level=2 --autopilot --exit-on-end
## See CLAUDE.md for the full list.

const BallSim := preload("res://scripts/ball_sim.gd")
const Bowling := preload("res://scripts/bowling.gd")
const Batting := preload("res://scripts/batting.gd")
const Fielding := preload("res://scripts/fielding.gd")
const Rules := preload("res://scripts/rules.gd")
const Conditions := preload("res://scripts/conditions.gd")
const Levels := preload("res://scripts/levels.gd")
const Commentary := preload("res://scripts/commentary.gd")
const Stadium := preload("res://scripts/stadium.gd")
const Figures := preload("res://scripts/figures.gd")
const Rig := preload("res://scripts/rig.gd")
const Strokes := preload("res://scripts/strokes.gd")
const Autopilot := preload("res://scripts/autopilot.gd")
const Hud := preload("res://scripts/hud.gd")
const Sound := preload("res://scripts/sound.gd")

const SAVE_PATH := "user://progress.cfg"
const BALL_VISUAL_R := 0.05      # drawn a little bigger than life so you can see it
const BAT_CAM_POS := Vector3(0.45, 2.25, 3.7)
const BAT_CAM_LOOK := Vector3(-0.1, 0.9, -8.0)
# The TV view: a long lens from high behind the bowler's end.
const BOWL_CAM_POS := Vector3(0.0, 9.0, -62.0)
const BOWL_CAM_LOOK := Vector3(-0.1, 0.5, -4.5)
const BOWL_CAM_FOV := 10.5

enum Phase { MENU, INTRO, PRE, RUNUP, FLIGHT, PLAY, DECIDE, REVIEW, DRS, BETWEEN, END }

var phase := Phase.MENU
var phase_t := 0.0
var level_index := 0
var level: Dictionary = {}
var cond
var rng := RandomNumberGenerator.new()
var save_enabled := true
var cam_mode := "batter"           # "batter" (behind the batter, the default) or "bowler" (TV view)
var best_stars := {}

# Scene pieces
var stadium
var batter
var bowler_fig: Node3D
var umpire_fig: Node3D
var fielder_figs: Array = []
var ball: MeshInstance3D
var ball_shadow: MeshInstance3D
var pitch_mark: MeshInstance3D
var track_dots: Node3D
var camera: Camera3D
var hud
var sound

# Innings state
var runs := 0
var wkts := 0
var balls := 0
var reviews := 2
var free_hit := false
var strip: Array = []
var bowler: Dictionary = {}
var field: Array = []
var field_name := ""
var last_ball := ""
var result_stars := 0
var won := false

# Current ball
var d: Dictionary = {}
var traj: Dictionary = {}
var inp: Dictionary = {}
var bat: Dictionary = {}
var out_o: Dictionary = {}
var t := 0.0
var shot_taken := false
var danced := false
var flight_end := 0.0
var play_t := 0.0
var was_out := false
var batter_runs := 0
var _reviewed := false
var _bowler_fielding := false      # the bowler has left the follow-through to chase the ball                 # this batter's score (out for 0 is a duck)
var _decision_shown := false
var _bot_plan: Dictionary = {}
var _since_release := 0.0
var _defl: Dictionary = {}          # the ball's path after a pad, stumps or the keeper
var _keeper_taken := false
var _throw_from := Vector3.ZERO
var _cam_look := BAT_CAM_LOOK

var _flags := {}
var _sim_time := 0.0
var _bot := false
var _rookie_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_setup_input()
	_parse_flags()
	_load_progress()
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.current = true
	add_child(camera)
	_set_bat_cam()
	sound = Sound.new()
	add_child(sound)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.show_touch = DisplayServer.is_touchscreen_available() or _flags.has("touch")
	layer.add_child(hud)
	hud.level_chosen.connect(show_intro)
	hud.start_pressed.connect(func() -> void: start_level(level_index))
	hud.retry_pressed.connect(func() -> void: start_level(level_index))
	hud.next_pressed.connect(_next_level)
	hud.menu_pressed.connect(show_menu)
	hud.review_pressed.connect(_take_review)
	hud.walk_pressed.connect(_walk_off)
	if _flags.has("touch"):
		Input.emulate_touch_from_mouse = true
	_bot = _flags.has("autopilot") or _flags.has("rookie")
	_rookie_rng.seed = int(_flags.get("rookie-seed", "1"))
	if _flags.has("level"):
		start_level(int(_flags.level))
	else:
		_build_world({"format": "test", "day": 3})
		show_menu()


# ---------------------------------------------------------------- setup

func _setup_input() -> void:
	var keys := {
		"dir_up": [KEY_W, KEY_UP], "dir_down": [KEY_S, KEY_DOWN],
		"dir_left": [KEY_A, KEY_LEFT], "dir_right": [KEY_D, KEY_RIGHT],
		"shot_defend": [KEY_J, KEY_Z, KEY_SPACE], "shot_attack": [KEY_K, KEY_X],
		"shot_loft": [KEY_L, KEY_C], "shot_sweep": [KEY_I, KEY_V],
		"dance": [KEY_SHIFT], "review": [KEY_R], "confirm": [KEY_ENTER, KEY_KP_ENTER],
		"menu": [KEY_ESCAPE], "camera": [KEY_C],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _parse_flags() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		_flags[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _load_progress() -> void:
	if _flags.has("camera"):
		cam_mode = String(_flags.camera)
	if _flags.has("no-save"):
		save_enabled = false
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for i in Levels.count():
			best_stars[i] = int(cf.get_value("stars", str(i), 0))
		if not _flags.has("camera"):
			cam_mode = String(cf.get_value("settings", "camera", cam_mode))


func _save_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	for i in best_stars:
		cf.set_value("stars", str(i), best_stars[i])
	cf.set_value("settings", "camera", cam_mode)
	cf.save(SAVE_PATH)


func _build_world(l: Dictionary) -> void:
	if stadium:
		stadium.queue_free()
	for f in fielder_figs:
		f.queue_free()
	fielder_figs.clear()
	for n in [batter, bowler_fig, umpire_fig, ball, ball_shadow, pitch_mark, track_dots]:
		if n:
			n.queue_free()
	var night: bool = l.format == "t20"
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(night)
	var c = Conditions.new()
	c.day = int(l.get("day", 3))
	stadium.paint_pitch(c)
	stadium.set_overcast(bool(l.get("overcast", false)))

	var kit := Color(0.2, 0.35, 0.75) if night else Figures.WHITES
	var helmet := Color(0.1, 0.18, 0.4)
	batter = Rig.new()
	add_child(batter)
	batter.build(kit, Figures.SKIN[1], "helmet", helmet, true, true, true)
	_batter_stance()

	var fkit := Color(0.85, 0.45, 0.1) if night else Figures.WHITES
	var cap := Color(0.1, 0.2, 0.45) if not night else Color(0.85, 0.45, 0.1)
	bowler_fig = Rig.new()
	add_child(bowler_fig)
	bowler_fig.build(fkit, Figures.SKIN[0], "none", cap)
	umpire_fig = Rig.new()
	add_child(umpire_fig)
	umpire_fig.build(Color(0.94, 0.94, 0.9), Figures.SKIN[2], "umpire", Color.WHITE)
	umpire_fig.position = Vector3(0.35, 0.0, -BallSim.PITCH_LENGTH - 2.2)
	umpire_fig.set_pose(Strokes.umpire_pose(false))
	# The non-striker, backing up at the other end (freed with the stadium).
	var partner := Rig.new()
	stadium.add_child(partner)
	partner.build(kit, Figures.SKIN[3], "helmet", helmet, true, true, true)
	partner.position = Vector3(1.0, 0.0, -BallSim.PITCH_LENGTH + 1.4)
	var pp := Strokes.ready_pose(Vector3(0, 0, 1), 0.1)
	pp.grip = Vector3(-0.28, 0.8, 0.1)
	pp.bat = Vector3(0.0, -1.0, 0.15).normalized()
	pp.batface = Vector3(0, 0, 1)
	partner.set_pose(pp)
	partner.look_at_world = Vector3(0, 1.0, 0)

	for i in 11:
		var f := Rig.new()
		add_child(f)
		fielder_figs.append(f)
		f.build(fkit, Figures.SKIN[i % 4], "cap", cap)

	ball = MeshInstance3D.new()
	ball.mesh = Figures.sphere(BALL_VISUAL_R)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.95, 0.95, 0.9) if night else Color(0.75, 0.06, 0.06)
	bm.roughness = 0.3
	bm.emission_enabled = true
	bm.emission = bm.albedo_color * 0.25
	ball.material_override = bm
	add_child(ball)
	var seam := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = BALL_VISUAL_R * 0.97
	torus.outer_radius = BALL_VISUAL_R * 1.06
	torus.rings = 16
	torus.ring_segments = 4
	seam.mesh = torus
	var seam_mat := StandardMaterial3D.new()
	seam_mat.albedo_color = Color(0.95, 0.93, 0.85) if not night else Color(0.3, 0.3, 0.3)
	seam.material_override = seam_mat
	seam.rotation.z = PI * 0.5
	ball.add_child(seam)
	ball_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.05
	disc.bottom_radius = 0.05
	disc.height = 0.002
	ball_shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_shadow.material_override = sm
	add_child(ball_shadow)
	pitch_mark = MeshInstance3D.new()
	var pdisc := CylinderMesh.new()
	pdisc.top_radius = 0.07
	pdisc.bottom_radius = 0.07
	pdisc.height = 0.003
	pitch_mark.mesh = pdisc
	var pmm := StandardMaterial3D.new()
	pmm.albedo_color = Color(0.25, 0.18, 0.1, 0.6)
	pmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pitch_mark.material_override = pmm
	add_child(pitch_mark)
	track_dots = Node3D.new()
	add_child(track_dots)


# ---------------------------------------------------------------- flow

func show_menu() -> void:
	phase = Phase.MENU
	sound.crowd(false)
	if not _muted():
		sound.music(true)
	hud.show_menu(Levels.LEVELS, best_stars)
	_set_bat_cam()


func show_intro(i: int) -> void:
	level_index = i
	hud.show_intro(i, Levels.get_level(i), Levels.goal_text(Levels.get_level(i)))
	phase = Phase.INTRO


func start_level(i: int) -> void:
	level_index = clampi(i, 0, Levels.count() - 1)
	level = Levels.get_level(level_index)
	_build_world(level)
	cond = Conditions.new()
	cond.day = level.day
	cond.overs = level.overs
	cond.overcast = level.overcast
	cond.dew = level.dew
	cond.abrasive = level.abrasive
	rng.seed = int(_flags.get("seed", level.seed))
	runs = 0
	batter_runs = 0
	wkts = 0
	balls = 0
	reviews = 2
	free_hit = false
	strip = []
	last_ball = ""
	won = false
	hud.hide_card()
	hud.set_play_visible(true)
	hud.tip(level.tip)
	hud.commentary(level.blurb)
	sound.music(false)
	if not _muted():
		sound.crowd(true)
	_new_ball()


func _next_level() -> void:
	if level_index + 1 < Levels.count():
		show_intro(level_index + 1)
	else:
		show_menu()


func _over() -> int:
	return balls / 6


func _new_ball() -> void:
	var bowlers: Array = level.bowlers
	var new_bowler := Bowling.get_bowler(bowlers[_over() % bowlers.size()])
	if new_bowler != bowler or field.is_empty():
		bowler = new_bowler
		var spin := Bowling.is_spinner(bowler)
		field_name = ("spin_" if spin else "pace_") + String(level.field)
		field = Fielding.make_field(field_name)
	if level.has("new_ball_after") and balls == int(level.new_ball_after) and cond.overs > 20.0:
		cond.take_new_ball()
		hud.commentary(Commentary.line("new_ball", rng))
		hud.flash("NEW BALL", "Shiny again: back to conventional swing", Color(1, 0.85, 0.3))
		if not _muted():
			sound.play("ding", -6.0)
	d = Bowling.make(bowler, cond, rng)
	traj = BallSim.simulate(d)
	inp = {}
	bat = {}
	out_o = {}
	shot_taken = false
	danced = false
	_decision_shown = false
	was_out = false
	t = 0.0
	stadium.reset_stumps()
	_batter_stance()
	_place_fielders()
	_place_bowler(0.0)
	_keeper_taken = false
	_bowler_fielding = false
	bowler_fig.set_meta("state", "")
	_reviewed = false
	_defl = {}
	bowler_fig.set_pose(Strokes.ready_pose(Vector3(0, 0, 1), 0.0))
	umpire_fig.set_pose(Strokes.umpire_pose(false))
	_clear_track()
	pitch_mark.visible = false
	ball.visible = false
	ball_shadow.visible = false
	_set_bat_cam()
	hud.hide_drs()
	hud.hide_review()
	_update_hud()
	if free_hit:
		hud.flash("FREE HIT", "You can't be out (except run out). Swing!", Color(1, 0.6, 0.15), 1.4)
	_bot_plan = {}
	if _bot:
		if _flags.get("bot", "") == "charge":
			# Charges early in the run-up (the bowler may see it coming) and
			# swings for the ball that was planned, not the one that arrives.
			_bot_plan = {"shot": "loft", "foot": "front", "aim": 0, "dance": true, "th_adj": 0.0,
					"t_press": Batting.ideal_press(traj, "loft", "dance"), "charge_early": true}
		elif _flags.get("bot", "") == "leave":
			_bot_plan = {"shot": "leave", "foot": "neutral", "aim": 0, "t_press": 0.0, "dance": false, "th_adj": 0.0}
		elif _flags.has("rookie"):
			_bot_plan = Autopilot.rookie(traj, d, _rookie_rng, float(_flags.rookie), level.mode == "survive")
		else:
			_bot_plan = Autopilot.plan(traj, d, cond, field, free_hit, level.format == "t20", _situation())
	_set_phase(Phase.PRE)


func _situation() -> Dictionary:
	return {"mode": level.mode, "need": maxi(0, int(level.get("target", 0)) - runs),
			"balls_left": int(level.balls) - balls, "wkts_left": int(level.wickets) - wkts,
			"reviews": reviews}


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0.0


func _runup_time() -> float:
	return 0.9 if Bowling.is_spinner(bowler) else 1.4


func _process(delta: float) -> void:
	_sim_time += delta
	_check_flags()
	phase_t += delta
	match phase:
		Phase.PRE:
			if phase_t > 0.7:
				_set_phase(Phase.RUNUP)
				_start_runup()
		Phase.RUNUP:
			_place_bowler(phase_t / _runup_time())
			if _bot and _bot_plan.get("charge_early", false) and not danced and phase_t > _runup_time() - 0.35:
				_dance()
			if phase_t >= _runup_time():
				_release()
		Phase.FLIGHT:
			_flight(delta)
		Phase.PLAY:
			_play(delta)
		Phase.DECIDE:
			# Only linger when there's a decision to make.
			if phase_t > (1.3 if out_o.get("dismissal", "") != "" else 0.35):
				_decide()
		Phase.REVIEW:
			if _bot and phase_t > 0.4:
				if not out_o.truth_out:
					_take_review()
				else:
					_walk_off()
		Phase.DRS:
			if phase_t > 3.2:
				_finish_review()
		Phase.BETWEEN:
			# Linger after a wicket or a review so the verdict can be read.
			if phase_t > (2.2 if _reviewed else (1.6 if was_out else 1.1)):
				_after_ball()
	if phase >= Phase.FLIGHT and phase != Phase.END:
		_since_release += delta
		if not _bowler_fielding:
			_place_bowler(1.0 + _since_release / _runup_time())
	_update_figures(delta)
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		_toggle_camera()
		return
	if event.is_action_pressed("menu") and phase != Phase.MENU:
		show_menu()
		return
	match phase:
		Phase.INTRO:
			if event.is_action_pressed("confirm"):
				start_level(level_index)
		Phase.END:
			if event.is_action_pressed("review"):
				start_level(level_index)
			elif event.is_action_pressed("confirm"):
				if won:
					_next_level()
				else:
					start_level(level_index)
		Phase.REVIEW:
			if event.is_action_pressed("review"):
				_take_review()
			elif event.is_action_pressed("confirm"):
				_walk_off()
		Phase.RUNUP, Phase.FLIGHT:
			if _bot:
				return
			if event.is_action_pressed("dance"):
				_dance()
			for s in ["defend", "attack", "loft", "sweep"]:
				if event.is_action_pressed("shot_" + s):
					_take_shot(s, _held_dir(), t if phase == Phase.FLIGHT else 0.0)


## Direction held, in field terms (+x off side, +y towards the bowler).
## From the bowler's end the off side is on the left of the screen, so
## left and right swap to match what you see.
func _held_dir() -> Vector2i:
	var x := int(Input.is_action_pressed("dir_right")) - int(Input.is_action_pressed("dir_left"))
	if cam_mode == "bowler":
		x = -x
	var y := int(Input.is_action_pressed("dir_up")) - int(Input.is_action_pressed("dir_down"))
	return Vector2i(x, y)


## Charge down the pitch. You have to go early, within DANCE_WINDOW of the
## release. Go during the run-up and the bowler may see you coming and drag
## it shorter and wider: miss it and you're stumped.
const DANCE_WINDOW := 0.3

func _dance() -> void:
	if danced or shot_taken:
		return
	if phase == Phase.FLIGHT and t > DANCE_WINDOW:
		return
	danced = true
	_batter_charge()
	if phase == Phase.RUNUP and rng.randf() < 0.55:
		var pitch: Vector2 = d.pitch
		d.pitch = Vector2(pitch.x + rng.randf_range(0.3, 0.55), pitch.y - rng.randf_range(1.2, 2.2))
		d.label = String(d.label) + " (saw you coming)"
		traj = BallSim.simulate(d)


func _release() -> void:
	_set_phase(Phase.FLIGHT)
	t = 0.0
	ball.visible = true
	ball_shadow.visible = true
	batter.play([[0.3, Strokes.backlift(), "inout"]])
	hud.show_ball_cam(d, 0.55)
	_event("release %s %s" % [String(d.kind), String(bowler.style)])
	if d.no_ball:
		_event("noball")
	_since_release = 0.0
	if d.no_ball:
		hud.flash("NO BALL", "", Color(1, 0.6, 0.15), 1.0)
	hud.tip("")


func _take_shot(s: String, dir: Vector2i, at: float) -> void:
	if shot_taken or phase != Phase.FLIGHT:
		return
	shot_taken = true
	var m := Batting.from_direction(dir)
	inp = {"shot": s, "foot": m.foot, "aim": m.aim, "th_adj": m.th_adj, "dance": danced, "t_press": at}
	_resolve()
	_animate_shot()


## No shot: a leave (and a duck if you're holding back).
func _leave() -> void:
	shot_taken = true
	var dir := _held_dir()
	inp = {"shot": "leave", "foot": "back" if dir.y < 0 else "neutral", "aim": 0, "t_press": t, "dance": danced}
	_resolve()
	var p := BallSim.pos_at(traj, BallSim.time_at_z(traj, -0.6))
	if dir.y < 0 and p.y > 1.1:
		batter.play(Strokes.duck())
	else:
		batter.play(Strokes.leave())


func _resolve() -> void:
	bat = Batting.resolve(traj, d, inp, cond)
	out_o = Rules.outcome(traj, d, bat, field, free_hit, level.format == "t20")
	# Where the ball's own flight ends: bat, pad, stumps, or the keeper.
	if bat.contact in Rules.CONTACTS:
		flight_end = float(bat.t_contact)
	elif bat.pad or bat.body:
		flight_end = float(bat.pad_t)
	elif bat.bowled:
		flight_end = float(bat.t_contact)
	else:
		var tk := BallSim.time_at_z(traj, 14.0 if not Bowling.is_spinner(bowler) else 1.0)
		flight_end = tk if tk > 0.0 else float(traj.end_t)
	if _flags.has("trace"):
		print("[%.1fs] ball %d %s %s %.0fkph pitched %.1fm | %s %s/%s te=%+.3f ex=%+.3f ey=%+.3f -> %s runs=%d %s" % [
			_sim_time, balls, bowler.name, d.label, float(d.speed) * 3.6, -float((traj.pitch_pos as Vector3).z),
			inp.shot, inp.foot, inp.aim, float(bat.te), float(bat.ex), float(bat.ey), bat.contact,
			int(out_o.runs), "%s ump=%s truth=%s" % [out_o.dismissal, out_o.umpire_out, out_o.truth_out] if out_o.dismissal != "" else ""])
		var fr_t: Dictionary = out_o.get("field", {})
		if not fr_t.is_empty():
			print("    fielding: %s by %s at t=%.2f%s" % [fr_t.result, field[int(fr_t.fielder)].name if int(fr_t.fielder) >= 0 else "-",
					float(fr_t.t_end), (" (misfield: %s)" % fr_t.misfield) if String(fr_t.get("misfield", "")) != "" else ""])


func _flight(delta: float) -> void:
	t += delta
	if _bot and _bot_plan.get("dance", false) and not danced and t > 0.05:
		_dance()
	# Autopilot presses its planned key at its planned time.
	if _bot and not shot_taken and not _bot_plan.is_empty() and _bot_plan.shot != "leave" \
			and t >= float(_bot_plan.t_press):
		var p := _bot_plan
		shot_taken = true
		inp = {"shot": p.shot, "foot": p.foot, "aim": p.aim, "th_adj": p.th_adj, "dance": danced, "t_press": float(p.t_press)}
		_resolve()
		_animate_shot()
	# Didn't play a shot by the time it reaches you: that's a leave.
	if not shot_taken and t >= BallSim.time_at_z(traj, Batting.PAD_Z.neutral) - 0.12:
		_leave()
	var p3 := BallSim.pos_at(traj, minf(t, flight_end if shot_taken else t))
	_show_ball(p3)
	# Seam spinning: backspin for the quicks, sidespin for the spinners.
	if Bowling.is_spinner(bowler):
		ball.rotate_object_local(Vector3(0, 0, 1), delta * TAU * 3.0 * (1.0 if int(d.spin_dir) >= 0 else -1.0))
	else:
		ball.rotate_object_local(Vector3(1, 0, 0), -delta * TAU * 5.0)
	if traj.pitch_t > 0.0 and t >= float(traj.pitch_t) and not pitch_mark.visible:
		_dust((traj.pitch_pos as Vector3), 1.0 if d.crack != "" or d.rough else 0.25)
		pitch_mark.visible = true
		pitch_mark.position = Vector3((traj.pitch_pos as Vector3).x, 0.003, (traj.pitch_pos as Vector3).z)
		if d.crack != "":
			hud.commentary(Commentary.line(d.crack, rng))
			_event(String(d.crack))
	if shot_taken and t >= flight_end:
		_begin_play()


func _show_ball(p: Vector3) -> void:
	ball.position = p
	# Grow the ball with distance so it never shrinks to a pixel.
	# With a long lens (narrow fov) things look bigger, so scale by how much
	# of the view the distance takes up, not by the distance alone.
	var spread := camera.global_position.distance_to(p) * tan(deg_to_rad(camera.fov * 0.5))
	ball.scale = Vector3.ONE * clampf(spread / 6.5, 1.3, 6.0)
	ball_shadow.position = Vector3(p.x, 0.004, p.z)


func _begin_play() -> void:
	_set_phase(Phase.PLAY)
	play_t = 0.0
	_defl = {}
	_impact_sound()
	var what: String = bat.contact
	if bat.helmet:
		what = "helmet"
	elif bat.pad:
		what = "pad"
	elif bat.bowled:
		what = "bowled"
	_event("contact %s %s" % [what, String(inp.get("shot", ""))])
	if bat.bowled or bat.played_on:
		stadium.knock_stumps(BallSim.pos_at(traj, BallSim.time_at_z(traj, 0.0)).x)
	if bat.hit_wicket or bat.stumped:
		stadium.knock_stumps(0.0)
	if bat.contact in Rules.CONTACTS:
		hud.timing(bat.te, "%s  %s" % [bat.timing, _contact_word(bat.contact)])
	# Where the ball goes when nobody hits it: off the pad, on through the
	# broken stumps, or into the keeper's gloves.
	var vin := BallSim.vel_at(traj, flight_end)
	var at := BallSim.pos_at(traj, flight_end)
	if bat.pad or bat.body:
		_defl = BallSim.simulate_hit(at, Vector3(vin.x * 0.2 + 0.7, absf(vin.y) * 0.15 + 1.1, -vin.z * 0.12), 3.0)
	elif bat.bowled:
		_defl = BallSim.simulate_hit(at, vin * 0.3 + Vector3(0, 0.6, 0), 3.0)


func _impact_sound() -> void:
	if _muted():
		return
	var c: String = bat.contact
	if c == "middle" or c == "glove":
		# Sweeter and louder the better you time it; a block is a soft tap.
		var q := float(bat.quality)
		if inp.shot == "defend":
			sound.play("tock_soft", -4.0, randf_range(0.95, 1.05))
		else:
			sound.play("tock", lerpf(-8.0, 0.0, q), lerpf(0.9, 1.08, q))
	elif c in Rules.CONTACTS:
		sound.play("edge", -3.0)
	elif bat.helmet:
		sound.play("helmet", -2.0)
	elif bat.pad or bat.body:
		sound.play("pad", -2.0)
	if bat.bowled or bat.played_on or bat.hit_wicket:
		sound.play("stumps", 0.0)
	# Anything that might be out gets a big appeal from the fielders.
	if out_o.dismissal in ["lbw", "caught_behind"]:
		sound.play("howzat", -6.0, randf_range(0.95, 1.05), 0.25)


## Dev flag --log-events: timestamped moments, for cutting videos.
func _event(name: String) -> void:
	if _flags.has("log-events"):
		print("EVENT %.2f %s" % [_sim_time, name])


func _muted() -> bool:
	return _flags.has("mute")


## The crowd, and the comedy: a quacking duck for nought, a sad trombone for
## other wickets, a stadium horn for boundaries, a slide whistle for sixes.
func _crowd_sound(out: bool) -> void:
	if _muted():
		return
	var o := out_o
	if out:
		sound.play("groan", -9.0)
		if batter_runs == 0:
			sound.play("duck", -1.0, 1.0, 0.5)
		else:
			sound.play("sad_trombone", -3.0, 1.0, 0.4)
	elif int(o.runs) == 6:
		sound.play("six", -3.0)       # slide whistle, horn, fanfare and crowd in one
	elif int(o.runs) == 4:
		sound.play("four", -3.0)      # drum, horn and a cheer
	elif o.comment == "dropped":
		sound.play("slide_down", -3.0)
		sound.play("groan", -5.0, 1.0, 0.2)
	elif o.comment in ["beaten", "not_out_pad"]:
		sound.play("ooh", -8.0)
	elif o.comment == "edge_safe":
		sound.play("aah", -8.0)
	elif o.comment in ["dot", "leave"] and randf() < 0.1:
		sound.play("coo", -8.0, randf_range(0.9, 1.1))    # a pigeon wanders across


func _contact_word(c: String) -> String:
	match c:
		"middle": return ""
		"outside_edge": return "outside edge"
		"inside_edge": return "inside edge"
		"top_edge": return "top edge"
		"bottom_edge": return "bottom edge"
		"glove": return "off the glove"
	return ""


func _play(delta: float) -> void:
	play_t += delta
	var fr: Dictionary = out_o.get("field", {})
	if not fr.is_empty() and not bat.played_on and not bat.hit_wicket:
		var t_end: float = fr.t_end
		var result: String = fr.result
		var thrown := result == "runs" or result == "dropped"
		var throw_dur := 0.0
		var catcher: Node3D = _fig(int(fr.fielder)) if int(fr.fielder) >= 0 else null
		if thrown and catcher:
			throw_dur = clampf(catcher.position.distance_to(Vector3(0, 0, 1)) / 26.0, 0.25, 2.2)
		_chase(fr, catcher)
		if play_t <= t_end or result == "four" or result == "six":
			_show_ball(BallSim.hit_pos_at(fr.path, play_t))
		elif result == "caught" and catcher:
			_show_ball(catcher.hands_world())
		elif thrown and catcher:
			# Pick it up, then throw it in to the keeper over the stumps.
			var since := play_t - t_end
			if since < 0.35:
				_throw_from = catcher.hands_world()
				_show_ball(_throw_from)
			else:
				var k := clampf((since - 0.35) / throw_dur, 0.0, 1.0)
				var to := Vector3(0.1, 0.9, 0.6)
				var p := _throw_from.lerp(to, k)
				p.y += sin(k * PI) * minf(_throw_from.distance_to(to) * 0.12, 6.0)
				_show_ball(p)
		var done := t_end + 1.0
		if thrown:
			done = t_end + 0.35 + throw_dur + 0.3
		if play_t >= minf(done, 7.0):
			_set_phase(Phase.DECIDE)
	else:
		if not _defl.is_empty():
			_show_ball(BallSim.hit_pos_at(_defl, play_t))
		elif _keeper_taken:
			var kf: Node3D = fielder_figs[_keeper_index()]
			_show_ball(kf.hands_world())
		else:
			_show_ball(BallSim.pos_at(traj, minf(flight_end + play_t, flight_end + 0.25)))
		if play_t > 0.9:
			_set_phase(Phase.DECIDE)


## Fielders run to the ball (a running gait while they move), then catch it,
## gather it, or chase it to the rope.
## The figure for fielder i. The bowler is a fielder too (stopping it in the
## follow-through), but is drawn by the bowler's own figure.
func _fig(i: int) -> Node3D:
	if i >= 0 and i < field.size() and field[i].name == "Bowler":
		return bowler_fig
	return fielder_figs[i]


func _chase(fr: Dictionary, catcher: Node3D) -> void:
	_misfields(fr)
	for ch in fr.chase:
		var i := int(ch.i)
		var f: Node3D = _fig(i)
		if f == bowler_fig:
			_bowler_fielding = true
		var to: Vector2 = ch.to
		var start: Vector2 = (field[i].pos as Vector2)
		var k := clampf(play_t / maxf(float(ch.t), 0.1), 0.0, 1.0)
		var at := start.lerp(to, k)
		f.position = Vector3(at.x, 0.0, at.y)
		var move := to - start
		var state: String = f.get_meta("state", "")
		if k < 1.0 and move.length() > 0.5:
			if state != "run":
				var dir := Vector3(move.x, 0.0, move.y).normalized()
				var speed := clampf(move.length() / maxf(float(ch.t), 0.1), 2.0, 7.5)
				f.run_procedural(func(tt: float) -> Dictionary: return Strokes.gait(tt, speed, dir))
				f.set_meta("state", "run")
		elif state != "field" and f == catcher:
			f.set_meta("state", "field")
			var face := Vector3(-f.position.x, 0.0, -f.position.z).normalized()
			var ball_local: Vector3 = BallSim.hit_pos_at(fr.path, minf(play_t, float(fr.t_end))) - f.position
			if fr.result == "caught" or fr.result == "dropped":
				f.play([[0.12, Strokes.catch_pose(face, ball_local), "out"], [0.6, {}]])
			else:
				# Bend to gather it, then throw.
				var low := Strokes.catch_pose(face, Vector3(ball_local.x, 0.15, ball_local.z))
				var right := face.cross(Vector3.UP)
				var wind := Strokes.ready_pose(face, 0.1)
				wind.rh = right * 0.3 - face * 0.25 + Vector3.UP * 1.75
				wind.lh = face * 0.5 + Vector3.UP * 1.3
				var release := Strokes.ready_pose(face, 0.1)
				release.rh = face * 0.55 + Vector3.UP * 1.2
				f.play([[0.15, low, "out"], [0.2, wind], [0.15, release, "out"], [0.6, {}]])
		elif state == "run" and k >= 1.0:
			f.set_meta("state", "stop")
			var face2 := Vector3(-f.position.x, 0.0, -f.position.z).normalized()
			f.play([[0.25, Strokes.ready_pose(face2, 0.2)]])


## Fielders who dived and missed: run across, dive full length as the ball
## goes past, then get back up.
func _misfields(fr: Dictionary) -> void:
	for m in fr.get("misfields", []):
		var i := int(m.i)
		var f: Node3D = _fig(i)
		if f == bowler_fig:
			_bowler_fielding = true
		var start: Vector2 = (field[i].pos as Vector2)
		var to: Vector2 = m.to
		var t_dive: float = m.t
		var state: String = f.get_meta("state", "")
		var dir := (to - start)
		var reach_pt := start + dir.limit_length(maxf(0.0, dir.length() - 1.6))
		if play_t < t_dive - 0.25:
			var k := clampf(play_t / maxf(t_dive - 0.25, 0.1), 0.0, 1.0)
			var at := start.lerp(reach_pt, k)
			f.position = Vector3(at.x, 0.0, at.y)
			if state != "run" and dir.length() > 0.6:
				var d3 := Vector3(dir.x, 0.0, dir.y).normalized()
				f.run_procedural(func(tt: float) -> Dictionary: return Strokes.gait(tt, 6.0, d3))
				f.set_meta("state", "run")
		elif state != "dive" and state != "up":
			f.set_meta("state", "dive")
			var d3b := Vector3(dir.x, 0.0, dir.y)
			d3b = d3b.normalized() if d3b.length() > 0.01 else Vector3.FORWARD
			f.play([[0.25, Strokes.dive_pose(d3b), "out"], [0.6, {}], [0.4, Strokes.ready_pose(d3b, 0.3)]])
			f.set_meta("state", "up")


## Heads follow the ball; the keeper takes the ones that go through.
func _update_figures(_delta: float) -> void:
	if batter == null or not is_instance_valid(batter):
		return
	var target: Vector3 = ball.global_position if ball.visible else bowler_fig.global_position + Vector3(0, 1.6, 0)
	batter.look_at_world = target
	umpire_fig.look_at_world = target
	bowler_fig.look_at_world = target if ball.visible else batter.global_position + Vector3(0, 1.0, 0)
	for f in fielder_figs:
		f.look_at_world = target
	if phase == Phase.FLIGHT and shot_taken and not _keeper_taken and not (bat.contact in Rules.CONTACTS) \
			and not bat.pad and not bat.body and not bat.bowled and t >= flight_end - 0.3:
		var ki := _keeper_index()
		if ki >= 0:
			_keeper_taken = true
			var kf: Node3D = fielder_figs[ki]
			var face := Vector3(-kf.position.x, 0.0, -kf.position.z).normalized()
			var ball_local: Vector3 = BallSim.pos_at(traj, flight_end) - kf.position
			kf.play([[0.22, Strokes.catch_pose(face, ball_local), "out"], [0.8, {}]])


## A little puff of dust where the ball pitches (more off a crack).
func _dust(at: Vector3, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(10 + 20 * strength)
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 40.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6 + 1.5 * strength
	p.gravity = Vector3(0, -2.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.025
	m.height = 0.05
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.66, 0.48)
	m.material = mat
	p.mesh = m
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## Shows the umpire's decision, or asks about a review.
func _decide() -> void:
	if _decision_shown:
		return
	_decision_shown = true
	var o := out_o
	if o.snick >= 0.0:
		hud.snicko(float(o.snick))
	if o.dismissal != "" and o.umpire_out:
		_umpire_finger(true)
		if o.reviewable and reviews > 0:
			hud.ask_review(Rules.how_out(o.dismissal), reviews)
			hud.flash("OUT!", Rules.how_out(o.dismissal), Color(1, 0.35, 0.3), 30.0)
			hud.commentary(Commentary.line(o.comment, rng))
			_set_phase(Phase.REVIEW)
			_event("given_out %s" % String(o.dismissal))
			return
		_apply(true)
		return
	if o.dismissal != "" and o.fielding_review:
		hud.flash("NOT OUT...", "but the fielding side reviews!", Color(1, 0.8, 0.3), 2.0)
		hud.commentary("The fielders are convinced. Up goes the review signal.")
		_show_tracking(true)
		_set_phase(Phase.DRS)
		return
	_apply(false)


func _take_review() -> void:
	if phase != Phase.REVIEW:
		return
	_event("review")
	hud.hide_review()
	reviews -= 1
	_show_tracking(false)
	_set_phase(Phase.DRS)


func _walk_off() -> void:
	if phase != Phase.REVIEW:
		return
	hud.hide_review()
	_apply(true)


## Pigeon-Eye: the ball's real path and where it was going, plus the three
## LBW questions. For edges, the Snick-o-Scope.
func _show_tracking(fielding_side: bool) -> void:
	var o := out_o
	if o.dismissal == "lbw":
		var tr: Dictionary = o.track
		_draw_track(tr)
		# Side-on near the stumps, players hidden, like the TV graphic.
		camera.position = Vector3(3.2, 1.8, -8.5)
		_cam_look = Vector3(-0.2, 0.35, -1.2)
		camera.look_at(_cam_look)
		_players_visible(false)
		hud.show_drs([["Pitching", tr.pitching], ["Impact", tr.impact], ["Wickets", tr.wickets]], "")
	else:
		hud.snicko(float(o.snick) if o.snick > 0.0 else 0.0)
		hud.show_drs([["Edge", "SPIKE" if o.truth_out else "NOTHING"]], "", "SNICK-O-SCOPE")
		hud.commentary("Over to the Snick-o-Scope... any sound as it passed the bat?")
	hud.flash("REVIEW", "Fielding side" if fielding_side else "Batter reviews", Color(0.6, 0.85, 1.0), 2.5)
	if not _muted():
		sound.play("coo", -4.0)     # Pigeon-Eye is on the case


func _players_visible(on: bool) -> void:
	for n in [batter, umpire_fig, bowler_fig]:
		n.visible = on


func _finish_review() -> void:
	var o := out_o
	_reviewed = true
	_players_visible(true)
	_set_bat_cam()
	var out: bool
	var verdict := ""
	if o.umpire_out:
		out = o.truth_out
		if not out:
			verdict = "OVERTURNED: NOT OUT (review kept)"
			if not _muted():
				sound.play("record_scratch", -3.0)
				sound.play("aah", -6.0, 1.0, 0.3)
			reviews += 1      # a successful review isn't lost
			hud.commentary(Commentary.line("overturned", rng))
		elif o.track.get("umpires_call", false):
			verdict = "UMPIRE'S CALL: OUT (review kept)"
			reviews += 1
			hud.commentary(Commentary.line("umpires_call", rng))
		else:
			verdict = "DECISION STANDS: OUT"
			hud.commentary(Commentary.line("stands", rng))
	else:
		out = true
		verdict = "OVERTURNED: OUT"
		if not _muted():
			sound.play("record_scratch", -3.0)
		_umpire_finger(true)
	_event("verdict %s" % verdict.to_lower().replace(" ", "_").replace(":", ""))
	if o.dismissal == "lbw":
		var tr: Dictionary = o.track
		hud.show_drs([["Pitching", tr.pitching], ["Impact", tr.impact], ["Wickets", tr.wickets]], verdict)
	else:
		hud.show_drs([["Edge", "SPIKE" if o.truth_out else "NOTHING"]], verdict, "SNICK-O-SCOPE")
	_apply(out)


func _apply(out: bool) -> void:
	var o := out_o
	was_out = out
	runs += int(o.runs) + int(o.extras)
	if o.legal:
		balls += 1
	var symbol := "."
	if out:
		wkts += 1
		symbol = "W"
		hud.flash("OUT!", Rules.how_out(o.dismissal) + (" ... for a DUCK!" if batter_runs == 0 else ""), Color(1, 0.35, 0.3))
		if not _decision_shown or o.comment != "lbw":
			hud.commentary(Commentary.line(o.comment, rng))
		_batter_trudge()
	else:
		_umpire_finger(false)
		if o.wide:
			symbol = "wd"
			hud.flash("WIDE", "+1", Color(1, 0.8, 0.3), 1.0)
		elif o.no_ball:
			symbol = "nb%s" % ("" if int(o.runs) == 0 else str(o.runs))
		elif int(o.runs) == 6:
			symbol = "6"
			hud.flash("SIX!", _shot_line(), Color(1, 0.85, 0.2))
		elif int(o.runs) == 4:
			symbol = "4"
			hud.flash("FOUR!", _shot_line(), Color(0.5, 0.9, 1.0))
		elif int(o.runs) > 0:
			symbol = str(o.runs)
			hud.flash(str(o.runs) + (" RUN" if int(o.runs) == 1 else " RUNS"), _shot_line())
		if o.dismissal == "lbw" and o.umpire_out:
			pass
		elif o.comment == "not_out_pad" or o.dismissal == "":
			hud.commentary(Commentary.line(o.comment, rng))
	if d.no_ball and not o.wide:
		hud.commentary(Commentary.line("no_ball", rng))
	strip.append(symbol)
	if out:
		_event("out %s%s" % [String(o.dismissal), " duck" if batter_runs == 0 else ""])
	elif int(o.runs) == 6:
		_event("six")
	elif int(o.runs) == 4:
		_event("four")
	elif o.comment == "dropped":
		_event("dropped")
	elif o.comment in ["beaten", "edge_safe", "helmet"]:
		_event(String(o.comment))
	else:
		_event("runs %d" % int(o.runs))
	if free_hit:
		_event("freehit_ball")
	_crowd_sound(out)
	batter_runs = 0 if out else batter_runs + int(o.runs)
	free_hit = bool(o.free_hit_next) or (free_hit and not o.legal)
	last_ball = "%d kph %s" % [int(float(d.speed) * 3.6), d.label]
	cond.overs += 1.0 / 6.0 if o.legal else 0.0
	_update_hud()
	_set_phase(Phase.BETWEEN)


func _shot_line() -> String:
	var s: String = bat.get("shot_name", "")
	if bat.contact != "middle":
		s += " (" + _contact_word(bat.contact) + ")"
	return s


func _after_ball() -> void:
	if balls % 6 == 0 and balls > 0 and strip.size() > 0 and String(strip[strip.size() - 1]) not in ["wd"] and not (String(strip[strip.size() - 1]).begins_with("nb")):
		strip = []
	var target := int(level.get("target", 0))
	if level.mode == "chase":
		if runs >= target:
			_end(true)
			return
		if wkts >= int(level.wickets) or balls >= int(level.balls):
			_end(false)
			return
	else:
		if wkts >= int(level.wickets):
			_end(false)
			return
		if balls >= int(level.balls):
			_end(true)
			return
	_new_ball()


func _end(win: bool) -> void:
	won = win
	_set_phase(Phase.END)
	_event("end %s" % ("won" if win else "lost"))
	var stars := 0
	var title := "LOST"
	var summary := ""
	if win:
		title = "WON!"
		stars = 1
		if level.mode == "chase":
			if wkts == 0:
				stars = 2
				if int(level.balls) - balls >= 6:
					stars = 3
			summary = "Chased %d with %d ball%s to spare.\nTwo stars: no wickets lost. Three: no wickets and 6+ balls to spare." % [
				runs, int(level.balls) - balls, "" if int(level.balls) - balls == 1 else "s"]
		else:
			var s2: int = level.stars[0]
			var s3: int = level.stars[1]
			if runs >= s2:
				stars = 2
			if runs >= s3:
				stars = 3
			summary = "Survived with %d runs.\nTwo stars: %d runs. Three: %d runs." % [runs, s2, s3]
	else:
		if level.mode == "chase" and wkts < int(level.wickets):
			summary = "Out of balls. %d short of the target." % (int(level.target) - runs)
		else:
			summary = "All out. %d/%d off %d balls." % [runs, wkts, balls]
	result_stars = stars
	if win and stars > int(best_stars.get(level_index, 0)):
		best_stars[level_index] = stars
		_save_progress()
	hud.show_result(win, stars, title, summary, level_index + 1 < Levels.count())
	if not _muted():
		sound.crowd(false)
		sound.play("win" if win else "sad_trombone", -2.0, 1.0, 0.4)
	if _flags.has("exit-on-end"):
		print("RESULT level=%d %s runs=%d/%d balls=%d stars=%d" % [level_index, "won" if win else "lost", runs, wkts, balls, stars])
		get_tree().quit(0)


# ---------------------------------------------------------------- visuals

func _update_hud() -> void:
	var goal := ""
	if level.mode == "chase":
		goal = "Need %d off %d" % [maxi(0, int(level.target) - runs), int(level.balls) - balls]
	else:
		goal = "Survive %d more" % (int(level.balls) - balls)
	goal += "   Reviews: %d" % reviews
	hud.set_score(runs, wkts, balls, int(level.balls), goal, strip)
	hud.set_bowler(bowler.name, Bowling.STYLE_NAMES[bowler.style], last_ball)
	hud.set_conditions(cond, "%.1f overs" % cond.overs, cond.is_reversing(float(bowler.pace)) and not Bowling.is_spinner(bowler))


func _place_fielders() -> void:
	for i in fielder_figs.size():
		var f: Node3D = fielder_figs[i]
		f.set_meta("state", "")
		if i >= field.size() or field[i].name == "Bowler":
			f.visible = false
			continue
		f.visible = true
		var p: Vector2 = field[i].pos
		f.position = Vector3(p.x, 0.0, p.y)
		var face := Vector3(-p.x, 0.0, -p.y)    # towards the batter
		var crouch := 0.15
		if field[i].keeper:
			crouch = 1.0
		elif field[i].close:
			crouch = 0.7
		f.set_pose(Strokes.ready_pose(face.normalized(), crouch))


func _keeper_index() -> int:
	for i in field.size():
		if field[i].keeper:
			return i
	return -1


## Run-up: k goes 0..1 from the top of the mark to the crease. After the
## release the bowler carries on a few steps in the follow-through.
func _place_bowler(k: float) -> void:
	var spin := Bowling.is_spinner(bowler)
	var start := -BallSim.PITCH_LENGTH - (4.0 if spin else 8.0)
	var stop := -BallSim.PITCH_LENGTH + 0.9
	var z := lerpf(start, stop, pow(clampf(k, 0.0, 1.0), 1.15))
	if k > 1.0:
		z = stop + 2.4 * (1.0 - exp(-(k - 1.0) * 2.0))
	bowler_fig.position = Vector3(-0.3, 0.0, z)


func _start_runup() -> void:
	var r := _runup_time()
	# Two taps of the bat while the bowler runs in, then the trigger movement
	# so the batter is set at release.
	var keys := Strokes.taps(2 if r > 1.2 else 1)
	keys.append([maxf(0.05, r - 0.35 - 0.7), {}])
	keys.append([0.3, Strokes.trigger(), "out"])
	batter.play(keys)
	var spin := Bowling.is_spinner(bowler)
	bowler_fig.run_procedural(func(tt: float) -> Dictionary: return Strokes.bowler_pose(tt, r, spin))


func _umpire_finger(up: bool) -> void:
	umpire_fig.play([[0.3, Strokes.umpire_pose(up), "out"]])


# ---------------------------------------------------------------- batter animation

func _batter_stance() -> void:
	batter.position = Strokes.ROOT
	batter.set_pose(Strokes.stance())


## Down the pitch: a few quick steps, then back into a stance there.
func _batter_charge() -> void:
	batter.run_procedural(func(tt: float) -> Dictionary: return Strokes.gait(tt, 5.0, Vector3(0.2, 0, -1)))
	var tw := create_tween()
	tw.tween_property(batter, "position", Strokes.ROOT + Vector3(0.15, 0.0, -2.25), 0.42)
	tw.tween_callback(func() -> void:
		if not shot_taken:
			batter.play([[0.12, Strokes.stance()], [0.1, Strokes.backlift()]]))


func _animate_shot() -> void:
	var s: String = inp.shot
	var key: String = bat.get("key", "defend")
	var sh: Dictionary = Batting.SHOTS.get(key, Batting.SHOTS.defend)
	var th: float = bat.get("dir_deg", float(sh.th))
	var swing_t: float = maxf(0.08, float(Batting.SWING_T[s]) - (t - float(inp.t_press)))
	var foot := Batting.effective_foot(inp)
	var contact: Vector3 = bat.get("bat_pos", Vector3(0.0, 0.5, float(Batting.PLANE[foot])))
	if bat.contact in Rules.CONTACTS:
		contact = bat.exit_pos
	var local: Vector3 = contact - batter.position
	batter.play(Strokes.shot(key, "front" if foot == "dance" else foot, th, local, swing_t, s == "loft"))


func _batter_trudge() -> void:
	var dir := Vector3(-0.9, 0.0, -0.45).normalized()   # off towards the leg side, away from the camera
	batter.run_procedural(func(tt: float) -> Dictionary:
		var g := Strokes.gait(tt, 1.3, dir)
		g.grip = (g.rh as Vector3) + Vector3(0, 0.05, 0)
		g.bat = Vector3(0.1, -1, 0.3).normalized()
		g.batface = dir
		return g)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(batter, "position", batter.position + dir * 3.5, 2.6)


## Tall screens (phones held upright, Shorts): keep the width in view and
## let the extra height show more pitch and sky.
func _portrait() -> bool:
	var sz := get_viewport().get_visible_rect().size
	return sz.y > sz.x


func _base_fov() -> float:
	return 52.0 if _portrait() else 50.0


func _set_bat_cam() -> void:
	camera.keep_aspect = Camera3D.KEEP_WIDTH if _portrait() else Camera3D.KEEP_HEIGHT
	if _portrait() and cam_mode != "bowler":
		camera.fov = _base_fov()
		camera.position = Vector3(0.45, 2.25, 3.7)
		_cam_look = Vector3(-0.1, 0.9, -8.0)
		camera.look_at(_cam_look)
		if hud:
			hud.mirror = false
		return
	if cam_mode == "bowler":
		camera.fov = BOWL_CAM_FOV
		camera.position = BOWL_CAM_POS
		_cam_look = BOWL_CAM_LOOK
	else:
		camera.fov = _base_fov()
		camera.position = BAT_CAM_POS
		_cam_look = BAT_CAM_LOOK
	camera.look_at(_cam_look)
	if hud:
		hud.mirror = cam_mode == "bowler"


func _toggle_camera() -> void:
	cam_mode = "batter" if cam_mode == "bowler" else "bowler"
	_save_progress()
	if phase in [Phase.PRE, Phase.RUNUP, Phase.FLIGHT, Phase.MENU, Phase.INTRO, Phase.BETWEEN, Phase.END]:
		_set_bat_cam()
	hud.flash("CAMERA", "Bowler's end (TV)" if cam_mode == "bowler" else "Behind the batter", Color(0.8, 0.9, 1.0), 1.0)


func _update_camera(delta: float) -> void:
	# Follow the ball only when it was hit; misses stay in the batter's view.
	var hit: bool = not out_o.get("field", {}).is_empty() and not bat.get("played_on", false)
	# Hold the batting view a moment so you see the stroke and follow-through.
	if hit and ((phase == Phase.PLAY and play_t > 0.45) or phase == Phase.DECIDE):
		var b := ball.position
		if Vector2(b.x, b.z + 1.0).length() > 6.0:
			camera.fov = lerpf(camera.fov, _base_fov(), clampf(delta * 3.0, 0.0, 1.0))
			var want_pos := Vector3(b.x * 0.35, 14.0 + Vector2(b.x, b.z).length() * 0.15, 16.0 + b.z * 0.25)
			camera.position = camera.position.lerp(want_pos, clampf(delta * 2.5, 0.0, 1.0))
			_cam_look = _cam_look.lerp(b, clampf(delta * 5.0, 0.0, 1.0))
			camera.look_at(_cam_look)


func _clear_track() -> void:
	for ch in track_dots.get_children():
		ch.queue_free()


## Ghost balls along the real path (red) and the projected path (orange).
func _draw_track(tr: Dictionary) -> void:
	_clear_track()
	var real := StandardMaterial3D.new()
	real.albedo_color = Color(0.9, 0.15, 0.1)
	real.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var proj := StandardMaterial3D.new()
	proj.albedo_color = Color(1.0, 0.6, 0.1, 0.7)
	proj.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	proj.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := Figures.sphere(0.045)
	var t_pad: float = bat.pad_t
	var t_end := BallSim.time_at_z(traj, 0.05)
	var step := 0.012
	var tt := 0.0
	while tt <= t_end:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = real if tt <= t_pad else proj
		mi.position = BallSim.pos_at(traj, tt)
		track_dots.add_child(mi)
		tt += step
	var hit := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, BallSim.STUMP_HEIGHT, 0.02)
	hit.mesh = box
	var zone := StandardMaterial3D.new()
	var col := Color(0.9, 0.2, 0.2, 0.35)
	if tr.wickets == "UMPIRE'S CALL":
		col = Color(1.0, 0.7, 0.1, 0.35)
	elif tr.wickets == "MISSING":
		col = Color(0.2, 0.8, 0.3, 0.35)
	zone.albedo_color = col
	zone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit.material_override = zone
	hit.position = Vector3(0.0, BallSim.STUMP_HEIGHT * 0.5, 0.02)
	track_dots.add_child(hit)


# ---------------------------------------------------------------- dev flags

func _check_flags() -> void:
	if _flags.has("timeout") and _sim_time > float(_flags.timeout):
		print("RESULT level=%d timeout runs=%d/%d balls=%d stars=0" % [level_index, runs, wkts, balls])
		get_tree().quit(1)
	if _flags.has("screenshot") and _sim_time > float(_flags.get("wait", "2")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_flags.screenshot))
		print("screenshot saved ", _flags.screenshot)
		_flags.erase("screenshot")
		get_tree().quit(0)
