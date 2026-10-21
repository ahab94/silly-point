extends SceneTree
## Renders the batter at contact and at the end of the follow-through for
## every stroke, from two angles, with a red ball where the ball is met.
## For checking that strokes look right. Not headless:
##   godot --path . --script res://tools/pose_sheet.gd -- --out=/tmp/poses
## Then tile the PNGs (see CLAUDE.md).

const Rig := preload("res://scripts/rig.gd")
const Strokes := preload("res://scripts/strokes.gd")
const Batting := preload("res://scripts/batting.gd")

# name, shot key, footwork, direction, contact point (world), swing time, loft
const SHOTS := [
	["stance", "", "", 0.0, Vector3.ZERO, 0.0, false],
	["backlift", "", "", 0.0, Vector3.ZERO, 0.0, false],
	["forward defence", "defend", "front", 0.0, Vector3(0.05, 0.35, -1.95), 0.17, false],
	["back defence", "defend_back", "back", 0.0, Vector3(0.05, 0.9, -0.75), 0.17, false],
	["straight drive", "straight", "front", 3.0, Vector3(0.08, 0.3, -1.95), 0.21, false],
	["cover drive", "cover", "front", 45.0, Vector3(0.35, 0.3, -1.95), 0.21, false],
	["flick", "flick", "front", -40.0, Vector3(-0.05, 0.35, -1.95), 0.21, false],
	["lofted drive", "lofted_straight", "front", 0.0, Vector3(0.1, 0.3, -1.95), 0.24, true],
	["cut", "cut", "back", 88.0, Vector3(0.5, 0.85, -0.75), 0.21, false],
	["punch", "punch", "back", 22.0, Vector3(0.15, 0.8, -0.75), 0.21, false],
	["pull", "pull", "back", -78.0, Vector3(0.0, 1.1, -0.75), 0.21, false],
	["hook", "hook", "back", -100.0, Vector3(-0.05, 1.5, -0.75), 0.24, true],
	["sweep", "sweep", "front", -95.0, Vector3(0.05, 0.3, -1.95), 0.22, false],
	["reverse sweep", "reverse_sweep", "front", 100.0, Vector3(0.15, 0.3, -1.95), 0.22, false],
	["leave", "leave", "", 0.0, Vector3.ZERO, 0.0, false],
	["duck", "duck", "", 0.0, Vector3.ZERO, 0.0, false],
]

var out_dir := "/tmp/poses"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(560, 420)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.75, 0.68, 0.48)
	ground.material_override = gm
	world.add_child(ground)
	for i in 3:
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = 0.71
		st.mesh = cm
		st.position = Vector3((i - 1) * 0.096, 0.355, 0.0)
		world.add_child(st)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.036
	sm.height = 0.072
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.05, 0.05)
	ball.material_override = bm
	world.add_child(ball)
	var batter := Rig.new()
	world.add_child(batter)
	batter.build(Color(0.95, 0.94, 0.9), Color(0.82, 0.6, 0.43), "helmet", Color(0.1, 0.18, 0.4), true, true, true)
	batter.set_process(false)
	batter.position = Strokes.ROOT
	batter.look_at_world = Vector3(0, 1.0, -15)
	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.current = true

	if "--bowler" in OS.get_cmdline_user_args() or "--gait" in OS.get_cmdline_user_args():
		batter.visible = false
		ball.visible = false
		var bw := Rig.new()
		world.add_child(bw)
		bw.build(Color(0.95, 0.94, 0.9), Color(0.96, 0.8, 0.66), "cap", Color(0.1, 0.2, 0.45))
		bw.set_process(false)
		var spin := "--spin" in OS.get_cmdline_user_args()
		var gait := "--gait" in OS.get_cmdline_user_args()
		var times := [0.3, 0.6, 0.9, 1.0, 1.1, 1.2, 1.3, 1.36, 1.4, 1.46, 1.55, 1.7, 1.9, 2.2, 2.6, 3.0]
		var n := 0
		for tt in times:
			if gait:
				bw.set_pose(Strokes.gait(float(tt), 6.5, Vector3(0, 0, 1)))
			else:
				bw.set_pose(Strokes.bowler_pose(float(tt), 1.4, spin))
			bw.position = Vector3(0, 0, -5)
			bw.look_at_world = Vector3(0, 1.0, 10)
			cam.position = Vector3(4.0, 1.3, -5.0)
			cam.look_at(Vector3(0, 1.0, -5.0))
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("%s/%02d_0_t%.2f.png" % [out_dir, n, tt])
			n += 1
		print("POSES DONE ", n)
		quit(0)
		return
	var idx := 0
	for sh in SHOTS:
		var name: String = sh[0]
		var key: String = sh[1]
		var stages := [["", 0.0]]
		batter.set_pose(Strokes.stance())
		ball.visible = false
		if name == "backlift":
			batter.play([[0.3, Strokes.backlift()]])
			stages = [["", 0.35]]
		elif key == "leave":
			batter.play(Strokes.leave())
			stages = [["", 0.3]]
		elif key == "duck":
			batter.play(Strokes.duck())
			stages = [["", 0.2]]
		elif key != "":
			var c: Vector3 = sh[4]
			batter.set_pose(Strokes.backlift())
			batter.play(Strokes.shot(key, sh[2], sh[3], c - Strokes.ROOT, sh[5], sh[6]))
			ball.position = c
			ball.visible = true
			stages = [["contact", sh[5]], ["follow", 0.32]]
		for st in stages:
			_advance(batter, float(st[1]))
			for view in 2:
				if view == 0:
					cam.position = Vector3(3.0, 1.3, -2.6)          # from point, side-on
					cam.look_at(Vector3(-0.35, 0.85, -1.0))
				else:
					cam.position = Vector3(0.6, 1.6, -6.5)          # from the bowler's end
					cam.look_at(Vector3(-0.3, 0.85, -0.9))
				await process_frame
				await process_frame
				var img := root.get_texture().get_image()
				var label := "%s %s" % [name, st[0]]
				img.save_png("%s/%02d_%d_%s.png" % [out_dir, idx, view, label.strip_edges().replace(" ", "_")])
			idx += 1
	print("POSES DONE ", idx)
	quit(0)


func _advance(rig, seconds: float) -> void:
	var step := 1.0 / 120.0
	var tt := 0.0
	while tt < seconds - 0.0001:
		rig._process(step)
		tt += step
	rig._process(0.0)
