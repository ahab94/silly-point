extends Node3D
## The ground, built entirely in code: sky and light, a striped outfield, the
## pitch (its texture is painted from the conditions, so a Day 5 pitch shows
## its cracks and footmarks), stumps at both ends, the boundary rope,
## sightscreens and the crowd.
##
## Godot concept: a MeshInstance3D shows a Mesh (here built-in primitives
## like BoxMesh) with a Material. An Image we paint pixel by pixel becomes an
## ImageTexture that a StandardMaterial3D can use as its colour.

const BallSim := preload("res://scripts/ball_sim.gd")

const PITCH_W := 3.05
const PITCH_Z0 := -21.06       # far end of the painted strip
const PITCH_L := 22.0
const CENTRE_Z := -10.06
const BOUNDARY := 60.0

var env: WorldEnvironment
var sun: DirectionalLight3D
var pitch_mesh: MeshInstance3D
var stumps: Array = []          # the striker's three stumps
var bails: Array = []
var _stump_rest: Array = []
var _bail_rest: Array = []
var night := false
var _mats := {}


func mat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_mats[key] = m
	return m


func add_mesh(mesh: Mesh, material: Material, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


func build(is_night: bool) -> void:
	night = is_night
	_build_sky()
	_build_outfield()
	_build_stands()
	_build_stumps()
	if night:
		_build_floodlights()


func _build_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	if night:
		sky_mat.sky_top_color = Color(0.02, 0.03, 0.09)
		sky_mat.sky_horizon_color = Color(0.12, 0.12, 0.22)
		sky_mat.ground_horizon_color = Color(0.1, 0.1, 0.15)
		sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.05)
	else:
		sky_mat.sky_top_color = Color(0.3, 0.52, 0.85)
		sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.95)
		# Below the horizon (seen over the stands from the high camera): keep it sky-coloured.
		sky_mat.ground_horizon_color = Color(0.72, 0.84, 0.95)
		sky_mat.ground_bottom_color = Color(0.6, 0.72, 0.85)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45 if night else 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	env = WorldEnvironment.new()
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	sun.light_energy = 0.45 if night else 1.0
	sun.light_color = Color(0.85, 0.88, 1.0) if night else Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


## A sky tint for cloudy days.
func set_overcast(on: bool) -> void:
	if night:
		return
	var sm: ProceduralSkyMaterial = env.environment.sky.sky_material
	if on:
		sm.sky_top_color = Color(0.5, 0.55, 0.6)
		sm.sky_horizon_color = Color(0.72, 0.74, 0.76)
		sun.light_energy = 0.75
	else:
		sm.sky_top_color = Color(0.3, 0.52, 0.85)
		sm.sky_horizon_color = Color(0.72, 0.84, 0.95)
		sun.light_energy = 1.15


func _build_outfield() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.2, 0.42, 0.15))
	img.set_pixel(1, 0, Color(0.24, 0.48, 0.18))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(20.0, 1.0, 1.0)
	m.roughness = 0.95
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	add_mesh(plane, m, Vector3(0.0, -0.005, CENTRE_Z))

	var rope := TorusMesh.new()
	rope.inner_radius = BOUNDARY - 0.12
	rope.outer_radius = BOUNDARY + 0.12
	rope.rings = 160
	rope.ring_segments = 6
	add_mesh(rope, mat(Color(0.95, 0.95, 0.95)), Vector3(0.0, 0.05, CENTRE_Z))

	pitch_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(PITCH_W, PITCH_L)
	pitch_mesh.mesh = pm
	pitch_mesh.position = Vector3(0.0, 0.0, PITCH_Z0 + PITCH_L * 0.5)
	add_child(pitch_mesh)

	# The square: a slightly worn, lighter area around the pitch.
	var sq := PlaneMesh.new()
	sq.size = Vector2(14.0, 26.0)
	add_mesh(sq, mat(Color(0.27, 0.46, 0.19)), Vector3(0.0, -0.002, CENTRE_Z))


func _build_stands() -> void:
	var img := Image.create(256, 24, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var shirts := [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.85), Color(0.95, 0.85, 0.3),
			Color(0.95, 0.95, 0.95), Color(0.2, 0.6, 0.3), Color(0.9, 0.5, 0.2), Color(0.5, 0.3, 0.6)]
	for y in 24:
		for x in 256:
			var c: Color = shirts[rng.randi_range(0, shirts.size() - 1)]
			if (y % 3) == 2:
				c = Color(0.35, 0.35, 0.38)      # the row of seats in front
			img.set_pixel(x, y, c.darkened(rng.randf_range(0.0, 0.35)))
	var crowd := StandardMaterial3D.new()
	crowd.albedo_texture = ImageTexture.create_from_image(img)
	crowd.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crowd.roughness = 1.0
	var segs := 36
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var dir := Vector3(sin(a), 0.0, cos(a))
		# Leave gaps for the sightscreens behind each end.
		if absf(dir.x) < 0.2:
			continue
		for tier in 3:
			var r := 70.0 + tier * 6.0
			var box := BoxMesh.new()
			box.size = Vector3(2.0 * r * tan(PI / float(segs)) + 0.2, 4.0, 6.0)
			var mi := add_mesh(box, crowd, Vector3(dir.x * r, 2.0 + tier * 4.0, CENTRE_Z + dir.z * r))
			mi.rotation.y = a
	# Advertising boards and the sightscreens (white, so the red ball shows).
	var white := mat(Color(0.96, 0.96, 0.94))
	for z in [CENTRE_Z - 66.0, CENTRE_Z + 66.0]:
		var screen := BoxMesh.new()
		screen.size = Vector3(22.0, 9.0, 0.6)
		add_mesh(screen, white, Vector3(0.0, 4.5, z))
	var board_cols := [Color(0.1, 0.25, 0.55), Color(0.75, 0.15, 0.15), Color(0.1, 0.45, 0.25), Color(0.85, 0.6, 0.1)]
	for i in 64:
		var a := TAU * float(i) / 64.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		if absf(dir.x) < 0.17:
			continue
		var b := BoxMesh.new()
		b.size = Vector3(6.2, 0.9, 0.15)
		var mi := add_mesh(b, mat(board_cols[i % board_cols.size()]), Vector3(dir.x * 63.0, 0.45, CENTRE_Z + dir.z * 63.0))
		mi.rotation.y = a


func _build_floodlights() -> void:
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var base := Vector3(corner.x * 62.0, 0.0, CENTRE_Z + corner.y * 62.0)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.5
		pole.bottom_radius = 0.8
		pole.height = 45.0
		add_mesh(pole, mat(Color(0.5, 0.5, 0.55)), base + Vector3(0.0, 22.5, 0.0))
		var panel := BoxMesh.new()
		panel.size = Vector3(6.0, 4.0, 0.5)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(1.0, 1.0, 0.95)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 1.0, 0.9)
		lm.emission_energy_multiplier = 3.0
		var p := add_mesh(panel, lm, base + Vector3(0.0, 46.0, 0.0))
		p.look_at(Vector3(0.0, 0.0, CENTRE_Z), Vector3.UP)
		var spot := SpotLight3D.new()
		spot.position = base + Vector3(0.0, 45.0, 0.0)
		spot.spot_range = 140.0
		spot.spot_angle = 40.0
		spot.light_energy = 6.0
		add_child(spot)
		spot.look_at(Vector3(0.0, 0.0, CENTRE_Z), Vector3.UP)


func _build_stumps() -> void:
	var wood := mat(Color(0.93, 0.88, 0.72), 0.6)
	for end_z in [0.0, -BallSim.PITCH_LENGTH]:
		for i in 3:
			var st := CylinderMesh.new()
			st.top_radius = 0.018
			st.bottom_radius = 0.018
			st.height = BallSim.STUMP_HEIGHT
			var x := (i - 1) * 0.096
			var mi := add_mesh(st, wood, Vector3(x, BallSim.STUMP_HEIGHT * 0.5, end_z))
			if end_z == 0.0:
				stumps.append(mi)
				_stump_rest.append(mi.transform)
		for i in 2:
			var b := BoxMesh.new()
			b.size = Vector3(0.105, 0.022, 0.022)
			var bx := (i - 0.5) * 0.096
			var mi := add_mesh(b, wood, Vector3(bx, BallSim.STUMP_HEIGHT + 0.012, end_z))
			if end_z == 0.0:
				bails.append(mi)
				_bail_rest.append(mi.transform)


func reset_stumps() -> void:
	for i in stumps.size():
		stumps[i].transform = _stump_rest[i]
	for i in bails.size():
		bails[i].transform = _bail_rest[i]


## Timber! `hit_x` is where the ball struck, so the right stump goes first.
func knock_stumps(hit_x: float) -> void:
	var tw := create_tween().set_parallel(true)
	for i in stumps.size():
		var s: MeshInstance3D = stumps[i]
		var x := (i - 1) * 0.096
		var power := clampf(1.0 - absf(x - hit_x) * 4.0, 0.3, 1.0)
		var r := s.rotation + Vector3(-1.2 * power, 0.0, (x - hit_x) * 3.0)
		tw.tween_property(s, "rotation", r, 0.25)
		tw.tween_property(s, "position", s.position + Vector3(0.0, -0.1 * power, 0.4 * power), 0.25)
	for i in bails.size():
		var b: MeshInstance3D = bails[i]
		var target := b.position + Vector3((i - 0.5) * 1.2, 0.0, 2.5)
		tw.tween_property(b, "position:x", target.x, 0.6)
		tw.tween_property(b, "position:z", target.z, 0.6)
		tw.tween_property(b, "rotation", Vector3(6.0, 3.0, 2.0), 0.6)
		var up := create_tween()
		up.tween_property(b, "position:y", 1.6, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		up.tween_property(b, "position:y", 0.02, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Paints the pitch for the conditions: greener on Day 1, dustier later,
## cracks from Day 3 and footmark rough from Day 2 on.
func paint_pitch(c) -> void:
	var w := 128
	var h := 924
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + c.day
	var grass: float = c.grass()
	var base := Color(0.72, 0.62, 0.43).lerp(Color(0.4, 0.52, 0.27), grass)
	for y in h:
		for x in w:
			var n := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n * 0.5))
	# Footmark rough: darker scuffed patches outside the stumps.
	var rs: float = c.rough_strength()
	if rs > 0.05:
		for side in [-1.0, 1.0]:
			for k in int(40 * rs):
				var px := _px(side * rng.randf_range(0.3, 0.8))
				var py := _py(rng.randf_range(-6.3, -2.4))
				var rad := rng.randi_range(2, 5)
				_blob(img, px, py, rad, Color(0.45, 0.38, 0.27), 0.5 * rs)
			for k in int(20 * rs):
				var px2 := _px(side * rng.randf_range(0.3, 0.8))
				var py2 := _py(-20.12 + rng.randf_range(2.2, 6.0))
				_blob(img, px2, py2, rng.randi_range(2, 4), Color(0.45, 0.38, 0.27), 0.45 * rs)
	# Cracks: wandering dark lines.
	var cracks := int(c.crack_chance() * 160.0)
	for k in cracks:
		var x := float(rng.randi_range(10, w - 10))
		var y := float(rng.randi_range(40, h - 40))
		var ang := rng.randf_range(0.0, TAU)
		for s in rng.randi_range(15, 50):
			ang += rng.randf_range(-0.5, 0.5)
			x += cos(ang)
			y += sin(ang) * 1.5
			if x > 0 and x < w and y > 0 and y < h:
				img.set_pixel(int(x), int(y), Color(0.3, 0.24, 0.17))
	# Crease markings.
	var white := Color(0.97, 0.97, 0.95)
	for z in [BallSim.POPPING_CREASE, -BallSim.PITCH_LENGTH - BallSim.POPPING_CREASE]:
		_rect(img, 0, _py(z) - 1, w, 3, white)
	for z in [0.0, -BallSim.PITCH_LENGTH]:
		_rect(img, _px(-1.32), _py(z) - 1, _px(1.32) - _px(-1.32), 3, white)
	for side in [-1.32, 1.32]:
		_rect(img, _px(side) - 1, _py(BallSim.POPPING_CREASE), 3, _py(0.94) - _py(BallSim.POPPING_CREASE), white)
		_rect(img, _px(side) - 1, 0, 3, _py(-BallSim.PITCH_LENGTH - BallSim.POPPING_CREASE), white)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.95
	pitch_mesh.material_override = m


func _px(x: float) -> int:
	return int((x + PITCH_W * 0.5) / PITCH_W * 128.0)


func _py(z: float) -> int:
	return int((z - PITCH_Z0) / PITCH_L * 924.0)


func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height())), c)


func _blob(img: Image, cx: int, cy: int, r: int, c: Color, alpha: float) -> void:
	for y in range(cy - r * 2, cy + r * 2 + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := float(x - cx) / float(r)
			var dy := float(y - cy) / float(r * 2)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, alpha))
