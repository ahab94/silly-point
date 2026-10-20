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
const Autopilot := preload("res://scripts/autopilot.gd")
const Hud := preload("res://scripts/hud.gd")
const Sound := preload("res://scripts/sound.gd")

const SAVE_PATH := "user://progress.cfg"
const BALL_VISUAL_R := 0.05      # drawn a little bigger than life so you can see it
const BAT_CAM_POS := Vector3(0.55, 2.75, 5.0)
const BAT_CAM_LOOK := Vector3(-0.05, 0.45, -12.0)

enum Phase { MENU, INTRO, PRE, RUNUP, FLIGHT, PLAY, DECIDE, REVIEW, DRS, BETWEEN, END }

var phase := Phase.MENU
var phase_t := 0.0
var level_index := 0
var level: Dictionary = {}
var cond
var rng := RandomNumberGenerator.new()
var save_enabled := true
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
var _decision_shown := false
var _bot_plan: Dictionary = {}
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
		"menu": [KEY_ESCAPE],
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
	if _flags.has("no-save"):
		save_enabled = false
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for i in Levels.count():
			best_stars[i] = int(cf.get_value("stars", str(i), 0))


func _save_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	for i in best_stars:
		cf.set_value("stars", str(i), best_stars[i])
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
	batter = Figures.Batter.new()
	add_child(batter)
	batter.build(kit, Figures.SKIN[1], Color(0.1, 0.18, 0.4))

	var fkit := Color(0.85, 0.45, 0.1) if night else Figures.WHITES
	bowler_fig = Figures.person(fkit, Figures.SKIN[0], "none")
	add_child(bowler_fig)
	umpire_fig = Figures.person(Color(0.15, 0.15, 0.2), Figures.SKIN[2], "umpire")
	var coat := Figures.part(umpire_fig, Figures.capsule(0.2, 0.75), Color(0.95, 0.95, 0.92), Vector3(0, 1.12, 0))
	coat.scale = Vector3(1.0, 1.0, 0.8)
	umpire_fig.position = Vector3(0.35, 0.0, -BallSim.PITCH_LENGTH - 2.2)
	umpire_fig.rotation.y = PI
	add_child(umpire_fig)
	# The non-striker, backing up at the other end (freed with the stadium).
	var partner := Figures.Batter.new()
	stadium.add_child(partner)
	partner.build(kit, Figures.SKIN[3], Color(0.1, 0.18, 0.4))
	partner.set_process(false)
	partner.position = Vector3(1.0, 0.0, -BallSim.PITCH_LENGTH + 1.4)
	partner.rotation.y = PI

	for i in 11:
		var f := Figures.person(fkit, Figures.SKIN[i % 4], "cap", Color(0.1, 0.2, 0.45) if not night else Color(0.85, 0.45, 0.1))
		add_child(f)
		fielder_figs.append(f)

	ball = MeshInstance3D.new()
	ball.mesh = Figures.sphere(BALL_VISUAL_R)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.95, 0.95, 0.9) if night else Color(0.75, 0.06, 0.06)
	bm.roughness = 0.3
	bm.emission_enabled = true
	bm.emission = bm.albedo_color * 0.25
	ball.material_override = bm
	add_child(ball)
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
	if not _flags.has("mute"):
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
	batter.stance()
	_place_fielders()
	_place_bowler(0.0)
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
		if _flags.get("bot", "") == "leave":
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
		Phase.RUNUP:
			_place_bowler(phase_t / _runup_time())
			if phase_t >= _runup_time():
				_release()
		Phase.FLIGHT:
			_flight(delta)
		Phase.PLAY:
			_play(delta)
		Phase.DECIDE:
			if phase_t > 1.3:
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
			if phase_t > (1.6 if was_out else 1.1):
				_after_ball()
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
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


func _held_dir() -> Vector2i:
	var x := int(Input.is_action_pressed("dir_right")) - int(Input.is_action_pressed("dir_left"))
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
	batter.step("dance", 0.45)
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
	batter.backlift()
	hud.show_ball_cam(d, 0.55)
	_swing_arm(bowler_fig)
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
	var foot := Batting.effective_foot(inp)
	var swing_t: float = Batting.SWING_T[s]
	if foot != "dance":
		batter.step("sweep" if s == "sweep" else foot, swing_t)
	var key: String = bat.get("key", "defend")
	var sh: Dictionary = Batting.SHOTS.get(key, Batting.SHOTS.defend)
	var th: float = bat.get("dir_deg", float(sh.th))
	batter.swing(sh.bat, th, swing_t, s == "defend")


## No shot: a leave (and a duck if you're holding back).
func _leave() -> void:
	shot_taken = true
	var dir := _held_dir()
	inp = {"shot": "leave", "foot": "back" if dir.y < 0 else "neutral", "aim": 0, "t_press": t, "dance": danced}
	_resolve()
	var p := BallSim.pos_at(traj, BallSim.time_at_z(traj, -0.6))
	if dir.y < 0 and p.y > 1.1:
		batter.step("duck", 0.15)
	else:
		batter.shoulder_arms()


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
		var foot := Batting.effective_foot(inp)
		var swing_t: float = Batting.SWING_T[p.shot]
		if foot != "dance":
			batter.step("sweep" if p.shot == "sweep" else foot, swing_t)
		var sh: Dictionary = Batting.SHOTS.get(bat.get("key", "defend"), Batting.SHOTS.defend)
		batter.swing(sh.bat, float(bat.get("dir_deg", float(sh.th))), swing_t, p.shot == "defend")
	# Didn't play a shot by the time it reaches you: that's a leave.
	if not shot_taken and t >= BallSim.time_at_z(traj, Batting.PAD_Z.neutral) - 0.12:
		_leave()
	var p3 := BallSim.pos_at(traj, minf(t, flight_end if shot_taken else t))
	_show_ball(p3)
	if traj.pitch_t > 0.0 and t >= float(traj.pitch_t) and not pitch_mark.visible:
		pitch_mark.visible = true
		pitch_mark.position = Vector3((traj.pitch_pos as Vector3).x, 0.003, (traj.pitch_pos as Vector3).z)
		if d.crack != "":
			hud.commentary(Commentary.line(d.crack, rng))
	if shot_taken and t >= flight_end:
		_begin_play()


func _show_ball(p: Vector3) -> void:
	ball.position = p
	# Grow the ball with distance so it never shrinks to a pixel.
	ball.scale = Vector3.ONE * clampf(camera.global_position.distance_to(p) / 14.0, 1.0, 6.0)
	ball_shadow.position = Vector3(p.x, 0.004, p.z)


func _begin_play() -> void:
	_set_phase(Phase.PLAY)
	play_t = 0.0
	_impact_sound()
	if bat.bowled or bat.played_on:
		stadium.knock_stumps(BallSim.pos_at(traj, BallSim.time_at_z(traj, 0.0)).x)
	if bat.hit_wicket:
		stadium.knock_stumps(0.0)
	if bat.contact in Rules.CONTACTS:
		hud.timing(bat.te, "%s  %s" % [bat.timing, _contact_word(bat.contact)])


func _impact_sound() -> void:
	if _flags.has("mute"):
		return
	var c: String = bat.contact
	if c == "middle" or c == "glove":
		# Sweeter and louder the better you time it.
		sound.play("tock", lerpf(-8.0, 0.0, float(bat.quality)), lerpf(0.9, 1.08, float(bat.quality)))
	elif c in Rules.CONTACTS:
		sound.play("edge", -3.0)
	elif bat.pad or bat.body:
		sound.play("pad", -2.0)
	if bat.bowled or bat.played_on or bat.hit_wicket:
		sound.play("stumps", 0.0)


func _crowd_sound(out: bool) -> void:
	if _flags.has("mute"):
		return
	var o := out_o
	if out:
		sound.play("groan", -4.0)
	elif int(o.runs) == 6:
		sound.play("roar", -2.0)
	elif int(o.runs) == 4:
		sound.play("cheer", -3.0)
	elif o.comment in ["beaten", "dropped", "edge_safe", "not_out_pad"]:
		sound.play("ooh", -5.0)


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
		var tt := minf(play_t, float(fr.t_end))
		_show_ball(BallSim.hit_pos_at(fr.path, tt))
		for ch in fr.chase:
			var f: Node3D = fielder_figs[int(ch.i)]
			var to: Vector2 = ch.to
			var start: Vector2 = (field[int(ch.i)].pos as Vector2)
			var k := clampf(play_t / maxf(float(ch.t), 0.1), 0.0, 1.0)
			var at := start.lerp(to, k)
			f.position = Vector3(at.x, 0.0, at.y)
		if fr.result in ["caught", "dropped"] and play_t >= float(fr.t_end) - 0.05:
			if fr.result == "caught":
				var f2: Node3D = fielder_figs[int(fr.fielder)]
				ball.position = f2.position + Vector3(0, 1.3, 0)
		if play_t >= minf(float(fr.t_end) + 0.7, 6.0):
			_set_phase(Phase.DECIDE)
	else:
		# Ball stopped at the pad/body, crashed into the stumps, or went
		# through to the keeper: settle it.
		if bat.pad or bat.body:
			var pp: Vector3 = bat.pad_pos
			_show_ball(pp.lerp(Vector3(pp.x + 0.4, BallSim.RADIUS, pp.z - 1.2), clampf(play_t / 0.6, 0.0, 1.0)))
		else:
			var tt2 := minf(flight_end + play_t, flight_end + 0.25)
			_show_ball(BallSim.pos_at(traj, tt2))
		if play_t > 0.7:
			_set_phase(Phase.DECIDE)


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
		hud.show_drs([["Edge", "SPIKE" if o.truth_out else "NOTHING"]], "")
	hud.flash("REVIEW", "Fielding side" if fielding_side else "Batter reviews", Color(0.6, 0.85, 1.0), 2.5)


func _players_visible(on: bool) -> void:
	for n in [batter, umpire_fig, bowler_fig]:
		n.visible = on


func _finish_review() -> void:
	var o := out_o
	_players_visible(true)
	_set_bat_cam()
	var out: bool
	var verdict := ""
	if o.umpire_out:
		out = o.truth_out
		if not out:
			verdict = "OVERTURNED: NOT OUT (review kept)"
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
		_umpire_finger(true)
	if o.dismissal == "lbw":
		var tr: Dictionary = o.track
		hud.show_drs([["Pitching", tr.pitching], ["Impact", tr.impact], ["Wickets", tr.wickets]], verdict)
	else:
		hud.show_drs([["Edge", "SPIKE" if o.truth_out else "NOTHING"]], verdict)
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
		hud.flash("OUT!", Rules.how_out(o.dismissal), Color(1, 0.35, 0.3))
		if not _decision_shown or o.comment != "lbw":
			hud.commentary(Commentary.line(o.comment, rng))
		batter.trudge()
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
	_crowd_sound(out)
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
		if i >= field.size() or field[i].name == "Bowler":
			f.visible = false
			continue
		f.visible = true
		var p: Vector2 = field[i].pos
		f.position = Vector3(p.x, 0.0, p.y)
		f.scale = Vector3(1, 0.72, 1) if field[i].keeper or field[i].close else Vector3.ONE
		if field[i].keeper and p.y < 3.0:
			f.scale = Vector3(1, 0.55, 1)    # crouched right behind the stumps
		f.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)   # face the batter


## Run-up: k goes 0..1 from the top of the mark to the crease.
func _place_bowler(k: float) -> void:
	var spin := Bowling.is_spinner(bowler)
	var start := -BallSim.PITCH_LENGTH - (6.0 if spin else 14.0)
	var stop := -BallSim.PITCH_LENGTH + 1.0
	var z := lerpf(start, stop, clampf(k, 0.0, 1.0))
	bowler_fig.position = Vector3(-0.3, absf(sin(k * 18.0)) * 0.06, z)
	bowler_fig.rotation.y = PI


func _swing_arm(fig: Node3D) -> void:
	var arm: Node3D = fig.get_node("ArmR")
	var tw := create_tween()
	arm.rotation.x = 0.0
	tw.tween_property(arm, "rotation:x", -TAU, 0.35)
	tw.tween_property(arm, "rotation:x", 0.0, 0.01)
	var follow := create_tween()
	follow.tween_property(fig, "position:z", fig.position.z + 3.0, 0.6)


func _umpire_finger(up: bool) -> void:
	var arm: Node3D = umpire_fig.get_node("ArmR")
	var tw := create_tween()
	tw.tween_property(arm, "rotation:x", -PI * 0.92 if up else 0.0, 0.3)


func _set_bat_cam() -> void:
	camera.position = BAT_CAM_POS
	_cam_look = BAT_CAM_LOOK
	camera.look_at(_cam_look)


func _update_camera(delta: float) -> void:
	# Follow the ball only when it was hit; misses stay in the batter's view.
	var hit: bool = not out_o.get("field", {}).is_empty() and not bat.get("played_on", false)
	if hit and (phase == Phase.PLAY or phase == Phase.DECIDE):
		var b := ball.position
		if Vector2(b.x, b.z + 1.0).length() > 6.0:
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
