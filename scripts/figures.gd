extends RefCounted
## The people: batter, bowler, fielders and umpire, built from capsules,
## boxes and spheres, with simple tweened animations.
##
## Godot concept: a Tween animates any property over time
## (`tween_property(node, "rotation:x", value, seconds)`). Chained tweens run
## one after another; `set_parallel(true)` runs them together.

const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.43), Color(0.6, 0.42, 0.28), Color(0.4, 0.27, 0.18)]
const WHITES := Color(0.95, 0.94, 0.9)

static var _mats := {}


static func mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats[key] = m
	return m


static func part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


## A standing person facing -z (towards the bowler's end) unless rotated.
## Returns the root; named children: Body, Head, ArmL, ArmR, LegL, LegR.
static func person(kit: Color, skin: Color, hat := "cap", hat_color := Color(0.1, 0.2, 0.45)) -> Node3D:
	var root := Node3D.new()
	var leg := capsule(0.08, 0.85)
	var l := part(root, leg, kit, Vector3(-0.1, 0.43, 0.0))
	l.name = "LegL"
	var r := part(root, leg, kit, Vector3(0.1, 0.43, 0.0))
	r.name = "LegR"
	var body := part(root, capsule(0.17, 0.7), kit, Vector3(0.0, 1.15, 0.0))
	body.scale = Vector3(1.0, 1.0, 0.75)
	body.name = "Body"
	var head := part(root, sphere(0.11), skin, Vector3(0.0, 1.62, 0.0))
	head.name = "Head"
	for side in [-1.0, 1.0]:
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(0.22 * side, 1.4, 0.0)
		arm_pivot.name = "ArmL" if side < 0.0 else "ArmR"
		root.add_child(arm_pivot)
		part(arm_pivot, capsule(0.055, 0.62), kit, Vector3(0.0, -0.28, 0.0))
		part(arm_pivot, sphere(0.05), skin, Vector3(0.0, -0.6, 0.0))
	match hat:
		"cap":
			part(head, sphere(0.115), hat_color, Vector3(0.0, 0.04, 0.0)).scale = Vector3(1.0, 0.6, 1.0)
			part(head, box(Vector3(0.16, 0.015, 0.12)), hat_color, Vector3(0.0, 0.04, -0.13))
		"umpire":
			var brim := CylinderMesh.new()
			brim.top_radius = 0.22
			brim.bottom_radius = 0.22
			brim.height = 0.02
			part(head, brim, Color(0.95, 0.95, 0.9), Vector3(0.0, 0.06, 0.0))
			var crown := CylinderMesh.new()
			crown.top_radius = 0.09
			crown.bottom_radius = 0.11
			crown.height = 0.1
			part(head, crown, Color(0.95, 0.95, 0.9), Vector3(0.0, 0.11, 0.0))
		"helmet":
			part(head, sphere(0.135), hat_color, Vector3(0.0, 0.03, 0.01)).scale = Vector3(1.0, 0.85, 1.0)
			part(head, box(Vector3(0.2, 0.015, 0.1)), hat_color, Vector3(0.0, 0.07, -0.13))
			part(head, box(Vector3(0.17, 0.11, 0.015)), Color(0.75, 0.75, 0.78), Vector3(0.0, -0.05, -0.13))
	return root


## The striker. A right-hander standing side-on: chest to the off side (+x),
## front shoulder to the bowler. `hands` is the pivot the bat swings around.
class Batter extends Node3D:
	const F = preload("res://scripts/figures.gd")
	const STANCE := Vector3(-0.38, 0.0, -0.95)
	var hands: Node3D
	var bat: Node3D
	var body: Node3D
	var _tw: Tween

	func build(kit: Color, skin: Color, helmet: Color) -> void:
		body = F.person(kit, skin, "helmet", helmet)
		body.rotation.y = -PI * 0.5    # face +x (the off side)
		add_child(body)
		# Pads on both legs.
		for leg_name in ["LegL", "LegR"]:
			var leg: Node3D = body.get_node(leg_name)
			F.part(leg, F.box(Vector3(0.17, 0.6, 0.15)), Color(0.98, 0.98, 0.98), Vector3(0.0, -0.08, -0.04))
		# Gloved hands holding the bat out in front of the body.
		hands = Node3D.new()
		hands.position = Vector3(0.3, 0.95, -0.05)
		add_child(hands)
		F.part(hands, F.sphere(0.065), Color(0.95, 0.95, 0.95), Vector3.ZERO)
		bat = Node3D.new()
		hands.add_child(bat)
		var handle := CylinderMesh.new()
		handle.top_radius = 0.017
		handle.bottom_radius = 0.017
		handle.height = 0.3
		F.part(bat, handle, Color(0.15, 0.15, 0.15), Vector3(0.0, -0.1, 0.0))
		F.part(bat, F.box(Vector3(0.108, 0.56, 0.045)), Color(0.9, 0.78, 0.52), Vector3(0.0, -0.53, 0.0))
		stance()

	## Point both arms at the hands every frame, so they hold the bat
	## whatever the swing is doing.
	func _process(_delta: float) -> void:
		var target := hands.global_position
		for arm_name in ["ArmL", "ArmR"]:
			var arm: Node3D = body.get_node(arm_name)
			var dir := target - arm.global_position
			if dir.length() < 0.05:
				continue
			# looking_at aims -z at the target; turning 90 degrees about x
			# makes the arm's -y (its length) point there instead.
			var b := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD)
			arm.global_basis = b * Basis(Vector3.RIGHT, PI * 0.5)
			arm.scale = Vector3(1.0, clampf(dir.length() / 0.6, 0.6, 1.3), 1.0)

	func stance() -> void:
		if _tw:
			_tw.kill()
		position = STANCE
		body.position = Vector3.ZERO
		body.rotation.x = 0.0
		hands.position = Vector3(0.3, 0.95, -0.05)
		hands.rotation = Vector3(-0.35, 0.0, 0.0)
		visible = true

	## Bat up as the bowler lets go.
	func backlift() -> void:
		_tw = create_tween()
		_tw.tween_property(hands, "rotation:x", -1.9, 0.3).set_trans(Tween.TRANS_SINE)

	## Footwork. `foot`: front, back, neutral, dance, sweep, duck.
	func step(foot: String, dur: float) -> void:
		var t := create_tween().set_parallel(true)
		var to := STANCE
		match foot:
			"front":
				to += Vector3(0.12, 0.0, -0.55)
			"back":
				to += Vector3(0.12, 0.0, 0.4)
			"dance":
				to += Vector3(0.25, 0.0, -2.25)
			"sweep":
				to += Vector3(0.15, -0.38, -0.55)
			"duck":
				to += Vector3(0.0, -0.55, 0.15)
		t.tween_property(self, "position", to, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if foot == "duck":
			t.tween_property(body, "rotation:x", 0.0, dur)

	## The swing: reaches the contact angle after `dur` seconds, then follows
	## through. `bat_kind` "v" swings in a vertical plane aimed at `dir_deg`,
	## "h" is a horizontal bat (pull, cut, sweep).
	func swing(bat_kind: String, dir_deg: float, dur: float, is_defend: bool) -> void:
		if _tw:
			_tw.kill()
		_tw = create_tween()
		if is_defend:
			hands.rotation = Vector3(-0.9, deg_to_rad(-dir_deg) * 0.3, 0.0)
			_tw.tween_property(hands, "rotation:x", 0.25, dur).set_trans(Tween.TRANS_SINE)
			_tw.tween_interval(0.4)
			return
		if bat_kind == "v":
			hands.rotation = Vector3(-2.2, deg_to_rad(-dir_deg), 0.0)
			_tw.tween_property(hands, "rotation:x", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_tw.tween_property(hands, "rotation:x", 2.3, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			# Horizontal: bat held out flat, swept round from one side to the other.
			var from := deg_to_rad(-dir_deg + 120.0 * signf(dir_deg if dir_deg != 0.0 else 1.0))
			var to := deg_to_rad(-dir_deg - 90.0 * signf(dir_deg if dir_deg != 0.0 else 1.0))
			hands.rotation = Vector3(1.45, from, 0.0)
			_tw.tween_property(hands, "rotation:y", deg_to_rad(-dir_deg), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_tw.tween_property(hands, "rotation:y", to, 0.25)

	## Bat raised high out of harm's way: a leave.
	func shoulder_arms() -> void:
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_property(hands, "position:y", 1.55, 0.2)
		_tw.parallel().tween_property(hands, "rotation:x", -2.6, 0.2)

	func trudge() -> void:
		var t := create_tween()
		t.tween_interval(0.6)
		t.tween_property(self, "position", position + Vector3(-6.0, 0.0, 4.0), 2.5)
