extends Node3D
## An articulated person: hips, spine, head, arms and legs, drawn as limbs
## between joints that are solved every frame from a *pose*.
##
## A pose is a Dictionary of a few targets, in this node's local space
## (which is aligned with the world, so +x is the off side and -z points at
## the bowler):
##   pelvis    hip centre position
##   face      direction the chest faces (horizontal)
##   hip_face  direction the hips face (defaults to face)
##   lean      offset of the chest from straight above the pelvis
##   lf, rf    left and right ankle positions
##   lfd, rfd  directions the feet point
##   lh, rh    hand positions, or grip + bat for a batter (both hands on the
##             handle: the top hand at `grip`, the bottom hand just below)
##   bat       direction from the handle to the toe of the bat
##   batface   direction the face of the bat points
##   lpole, rpole  which way the elbows point
##
## Knees and elbows come from two-bone inverse kinematics (IK): given the
## hip and the ankle, and the two bone lengths, there is exactly one place
## the knee can be on the side the knee should bend towards.
##
## Animation: `play([[seconds, pose, ease], ...])` blends from the current
## pose through each pose in turn. `procedural` (a Callable taking the time)
## generates poses every frame instead, for running and bowling.
##
## Godot concept: a Transform3D is a Basis (three axis vectors: rotation and
## scale) plus an origin. Building one from "this axis points from the knee
## to the ankle" places a cylinder exactly along a limb.

const THIGH := 0.46
const SHIN := 0.45
const UPPER_ARM := 0.3
const FOREARM := 0.29
const SPINE := 0.5
const SHOULDER := 0.172
const HIP := 0.1
const BAT_LEN := 0.86
const SWEET := 0.6          # from the top hand to the middle of the bat

var pose: Dictionary = {}
var look_at_world := Vector3.ZERO     # where the head looks (world space)
var procedural: Callable
var proc_t := 0.0
var has_bat := false
var crouch_helmet := false

var _keys: Array = []
var _life_t := 0.0
var _life_phase := 0.0       # so a field full of people doesn't breathe in step
var _from: Dictionary = {}
var _key_t := 0.0
var _parts := {}
var _mats := {}


static func base_pose() -> Dictionary:
	return {
		"pelvis": Vector3(0.0, 0.93, 0.0), "face": Vector3(0, 0, -1), "lean": Vector3.ZERO,
		"lf": Vector3(-0.12, 0.07, 0.0), "rf": Vector3(0.12, 0.07, 0.0),
		"lh": Vector3(-0.25, 0.75, -0.05), "rh": Vector3(0.25, 0.75, -0.05),
	}


func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		_mats[k] = m
	return _mats[k]


func _mesh_node(name: String, mesh: Mesh, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	add_child(mi)
	_parts[name] = mi
	return mi


## A limb with a shape: a surface of revolution along y (from -0.5 at the
## joint the limb starts at, to +0.5 at the joint it ends at) whose radius
## follows `profile`, a list of [u, radius] with u from 0 to 1. This is what
## turns a stick into a thigh with a muscle, or a sleeve that is fuller at
## the shoulder than the wrist.
##
## Godot concept: SurfaceTool builds a mesh vertex by vertex; generate_normals
## works out the shading so the surface looks smooth.
static var _limb_cache := {}

static func _limb_mesh(profile: Array) -> ArrayMesh:
	var key := str(profile)
	if _limb_cache.has(key):
		return _limb_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var rows := []
	var n := 12
	for i in n + 1:
		var u := float(i) / float(n)
		# Smooth (cosine) interpolation between the profile's control points.
		var r := float(profile[0][1])
		for k in profile.size() - 1:
			var u0: float = profile[k][0]
			var u1: float = profile[k + 1][0]
			if u >= u0 and u <= u1:
				var f := (u - u0) / maxf(u1 - u0, 0.0001)
				f = 0.5 - 0.5 * cos(f * PI)
				r = lerpf(float(profile[k][1]), float(profile[k + 1][1]), f)
		rows.append([u - 0.5, r])
	for i in n:
		for j in seg:
			var a0 := TAU * float(j) / float(seg)
			var a1 := TAU * float(j + 1) / float(seg)
			var y0: float = rows[i][0]
			var r0: float = rows[i][1]
			var y1: float = rows[i + 1][0]
			var r1: float = rows[i + 1][1]
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	_limb_cache[key] = m
	return m


static func _cyl(r_top: float, r_bot: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = 1.0
	m.radial_segments = 16
	m.rings = 1
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


## A child mesh of `parent` (not driven by the solver: it rides along).
func _child(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	return m


## kit: the shirt colour (trousers are a shade darker, like real whites).
## hat: "helmet", "cap", "umpire" or "none". pads: batter's leg guards.
## bat: give them a bat. gloves: batting gloves.
func build(kit: Color, skin: Color, hat: String, hat_color: Color, pads := false, bat := false, gloves := false) -> void:
	has_bat = bat
	var shirt := kit
	var trousers := kit.darkened(0.06)
	var hair := Color(0.12, 0.09, 0.07)
	var shoe := Color(0.9, 0.9, 0.88)
	var pad_col := Color(0.92, 0.92, 0.9)
	# Body: hips, belly and chest as smooth ellipsoids, joined by a waist.
	_mesh_node("torso", _limb_mesh([[0.0, 0.15], [0.5, 0.155], [1.0, 0.16]]), shirt)
	_mesh_node("hips", _sphere(0.15), trousers)
	_mesh_node("belly", _sphere(0.14), shirt)
	_mesh_node("chest", _sphere(0.18), shirt)
	_mesh_node("belt", _cyl(0.155, 0.155), Color(0.18, 0.16, 0.14))
	_mesh_node("collar", _cyl(0.07, 0.085), shirt.lightened(0.05))
	_mesh_node("neck", _limb_mesh([[0.0, 0.062], [1.0, 0.052]]), skin)
	var head := _mesh_node("head", _sphere(0.113), skin)
	# Face, seen on fielders and the umpire: the head looks along -z.
	_child(head, _sphere(0.02), skin.darkened(0.08), Vector3(0, -0.025, -0.112), Vector3(0.9, 1.2, 1.0))         # nose
	for side in [-1.0, 1.0]:
		_child(head, _sphere(0.012), Color(0.08, 0.06, 0.05), Vector3(0.038 * side, 0.01, -0.1))          # eyes
		_child(head, _sphere(0.025), skin.darkened(0.05), Vector3(0.11 * side, -0.005, 0.005), Vector3(0.45, 1.0, 0.8))   # ears
		_child(head, _box(Vector3(0.035, 0.008, 0.01)), hair, Vector3(0.038 * side, 0.035, -0.103))           # eyebrows
	_child(head, _sphere(0.117), hair, Vector3(0, 0.03, 0.012), Vector3(1.0, 0.85, 1.0))                   # hair
	head.scale = Vector3(0.92, 1.08, 1.0)
	for s in ["l", "r"]:
		_mesh_node(s + "hipj", _sphere(0.096), trousers)
		# Thigh: full at the hip, the quad bulging, narrowing to the knee.
		_mesh_node(s + "thigh", _limb_mesh([[0.0, 0.094], [0.35, 0.098], [0.8, 0.072], [1.0, 0.066]]), trousers)
		# Shin: the calf muscle just below the knee, slim at the ankle.
		_mesh_node(s + "shin", _limb_mesh([[0.0, 0.062], [0.28, 0.07], [0.75, 0.05], [1.0, 0.046]]), pad_col if pads else trousers)
		_mesh_node(s + "ankle", _sphere(0.046), pad_col if pads else trousers)
		if pads:
			var pad := _mesh_node(s + "pad", _box(Vector3(0.17, 1.0, 0.13)), pad_col)
			# Vertical ribs down the front, and two straps round the back.
			for k in [-1.0, 0.0, 1.0]:
				_child(pad, _box(Vector3(0.035, 0.92, 0.04)), pad_col.lightened(0.04), Vector3(k * 0.052, 0.0, 0.07))
			for y in [-0.25, 0.2]:
				_child(pad, _box(Vector3(0.18, 0.04, 0.14)), Color(0.25, 0.22, 0.2), Vector3(0, y, -0.01))
			_mesh_node(s + "kneeroll", _sphere(0.088), pad_col)
		_mesh_node(s + "knee", _sphere(0.07), pad_col if pads else trousers)
		# Shoe: white upper, darker sole, rounded toe.
		var foot := _mesh_node(s + "foot", _box(Vector3(0.095, 0.07, 0.24)), shoe)
		_child(foot, _box(Vector3(0.1, 0.025, 0.27)), Color(0.3, 0.3, 0.32), Vector3(0, -0.045, -0.01))
		_child(foot, _sphere(0.05), shoe, Vector3(0, -0.005, -0.12), Vector3(1.0, 0.7, 1.0))
		_mesh_node(s + "shoulder", _sphere(0.07), shirt)
		# Sleeves: loose and full at the shoulder, the bicep under them,
		# slimmer at the elbow; the forearm tapers to the wrist.
		_mesh_node(s + "upper", _limb_mesh([[0.0, 0.066], [0.4, 0.064], [0.85, 0.054], [1.0, 0.052]]), shirt)
		_mesh_node(s + "fore", _limb_mesh([[0.0, 0.052], [0.3, 0.053], [0.85, 0.042], [1.0, 0.04]]), shirt)
		_mesh_node(s + "elbow", _sphere(0.054), shirt)
		var hand := _mesh_node(s + "hand", _sphere(0.062 if gloves else 0.048), Color(0.93, 0.93, 0.9) if gloves else skin)
		if gloves:
			hand.scale = Vector3(1.0, 0.9, 1.25)
			_child(hand, _box(Vector3(0.09, 0.03, 0.06)), Color(0.15, 0.25, 0.55), Vector3(0, 0.035, 0.0))    # padded back
	var hat_root := Node3D.new()
	head.add_child(hat_root)
	_parts.hat = hat_root
	match hat:
		"helmet":
			_child(hat_root, _sphere(0.135), hat_color, Vector3(0, 0.035, 0.015), Vector3(1.0, 0.86, 1.06))
			_child(hat_root, _box(Vector3(0.21, 0.014, 0.1)), hat_color, Vector3(0, 0.075, -0.13), Vector3.ONE, Vector3(0.12, 0, 0))
			_child(hat_root, _box(Vector3(0.2, 0.06, 0.03)), hat_color.darkened(0.2), Vector3(0, -0.07, 0.12))  # neck guard
			# Grille: three bars across the face and one down the middle.
			var steel := Color(0.62, 0.63, 0.67)
			for k in 3:
				_child(hat_root, _box(Vector3(0.19, 0.008, 0.008)), steel, Vector3(0, -0.005 - k * 0.04, -0.145))
			_child(hat_root, _box(Vector3(0.008, 0.09, 0.008)), steel, Vector3(0, -0.045, -0.148))
			for side in [-1.0, 1.0]:
				_child(hat_root, _box(Vector3(0.008, 0.09, 0.05)), steel, Vector3(0.095 * side, -0.045, -0.125))
		"cap":
			_child(hat_root, _sphere(0.115), hat_color, Vector3(0, 0.045, 0.005), Vector3(1.0, 0.62, 1.05))
			_child(hat_root, _box(Vector3(0.15, 0.01, 0.11)), hat_color.darkened(0.1), Vector3(0, 0.055, -0.135), Vector3.ONE, Vector3(0.15, 0, 0))
			_child(hat_root, _sphere(0.012), hat_color.lightened(0.2), Vector3(0, 0.12, 0.0))                    # button
		"umpire":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.105
			cm.height = 0.1
			_child(hat_root, cm, Color(0.93, 0.92, 0.88), Vector3(0, 0.1, 0))
			var brim := CylinderMesh.new()
			brim.top_radius = 0.22
			brim.bottom_radius = 0.22
			brim.height = 0.012
			_child(hat_root, brim, Color(0.93, 0.92, 0.88), Vector3(0, 0.055, 0))
			_child(hat_root, _cyl(0.092, 0.092), Color(0.15, 0.15, 0.2), Vector3(0, 0.07, 0), Vector3(1, 0.02, 1))   # band
	if bat:
		var bn := Node3D.new()
		add_child(bn)
		_parts.bat = bn
		var willow := Color(0.85, 0.74, 0.52)
		_child(bn, _cyl(0.018, 0.018), Color(0.55, 0.12, 0.12), Vector3(0, -0.12, 0), Vector3(1, 0.3, 1))       # rubber grip
		_child(bn, _cyl(0.02, 0.02), Color(0.2, 0.2, 0.2), Vector3(0, 0.03, 0), Vector3(1, 0.02, 1))            # handle cap
		var blade := _child(bn, _box(Vector3(0.108, 0.56, 0.03)), willow, Vector3(0, -0.55, 0.01))
		_child(blade, _box(Vector3(0.06, 0.5, 0.03)), willow.darkened(0.05), Vector3(0, -0.01, -0.025))      # the spine
		_child(blade, _box(Vector3(0.1, 0.08, 0.004)), Color(0.12, 0.3, 0.6), Vector3(0, 0.19, 0.017))          # sticker
		_child(blade, _box(Vector3(0.1, 0.02, 0.004)), Color(0.85, 0.15, 0.15), Vector3(0, 0.13, 0.017))
		_child(bn, _box(Vector3(0.05, 0.06, 0.04)), willow, Vector3(0, -0.28, 0.005))                        # shoulders
	pose = base_pose()
	_solve()


# ---------------------------------------------------------------- animation

func set_pose(p: Dictionary) -> void:
	pose = _merge(pose, p)
	_keys = []
	procedural = Callable()
	_solve()


func play(keys: Array) -> void:
	procedural = Callable()
	_keys = keys.duplicate()
	_from = pose.duplicate()
	_key_t = 0.0


func is_playing() -> bool:
	return not _keys.is_empty()


func run_procedural(fn: Callable) -> void:
	_keys = []
	procedural = fn
	proc_t = 0.0


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out


static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := a.duplicate()
	for key in b:
		var vb = b[key]
		if not a.has(key):
			out[key] = vb
			continue
		var va = a[key]
		if vb is Vector3:
			var v: Vector3 = (va as Vector3).lerp(vb, k)
			if key in ["face", "hip_face", "bat", "batface", "lfd", "rfd"]:
				v = v.normalized() if v.length() > 0.001 else (vb as Vector3)
			out[key] = v
		elif vb is float:
			out[key] = lerpf(va, vb, k)
		else:
			out[key] = vb
	return out


func _process(delta: float) -> void:
	_life_t += delta
	if procedural.is_valid():
		proc_t += delta
		pose = _merge(pose, procedural.call(proc_t))
	elif not _keys.is_empty():
		_key_t += delta
		var key: Array = _keys[0]
		var dur: float = maxf(float(key[0]), 0.001)
		var k := clampf(_key_t / dur, 0.0, 1.0)
		var ease := String(key[2]) if key.size() > 2 else "inout"
		var e := k
		match ease:
			"in": e = k * k
			"out": e = 1.0 - (1.0 - k) * (1.0 - k)
			"inout": e = k * k * (3.0 - 2.0 * k)
			"back":
				# Overshoots a little and settles, like a real follow-through.
				var c := 1.5
				e = 1.0 + (c + 1.0) * pow(k - 1.0, 3.0) + c * pow(k - 1.0, 2.0)
		pose = blend(_from, key[1], e)
		if k >= 1.0:
			_keys.pop_front()
			_from = pose.duplicate()
			_key_t = 0.0
	_solve()


# ---------------------------------------------------------------- solving

## Where the knee (or elbow) goes for a two-bone limb from `a` to `b`.
static func ik(a: Vector3, b: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var ab := b - a
	var d := clampf(ab.length(), 0.01, l1 + l2 - 0.001)
	var dir := ab.normalized() if ab.length() > 0.0001 else Vector3.DOWN
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, l1 * l1 - along * along))
	var side := pole - dir * pole.dot(dir)
	if side.length() < 0.001:
		side = dir.cross(Vector3.RIGHT)
	return a + dir * along + side.normalized() * h


## The end of the limb actually reached (the target, or as far as it goes).
static func reach(a: Vector3, b: Vector3, l: float) -> Vector3:
	var ab := b - a
	if ab.length() <= l:
		return b
	return a + ab.normalized() * l


func _limb(name: String, a: Vector3, b: Vector3) -> void:
	var mi: MeshInstance3D = _parts.get(name)
	if mi == null:
		return
	var axis := b - a
	var len := axis.length()
	if len < 0.0001:
		return
	var y := axis / len
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)


func _at(name: String, p: Vector3) -> void:
	var mi: MeshInstance3D = _parts.get(name)
	if mi:
		mi.position = p


func _solve() -> void:
	if _life_phase == 0.0:
		_life_phase = randf_range(0.1, TAU)
	# Alive: breathing (the chest rises a touch) and a slow sway of the
	# weight, layered on whatever pose is playing.
	var p := pose.duplicate()
	var br := sin(_life_t * 1.7 + _life_phase)
	var sw := sin(_life_t * 0.55 + _life_phase * 2.0)
	p.pelvis = (p.pelvis as Vector3) + Vector3(0.0, br * 0.004, 0.0)
	p.lean = (p.get("lean", Vector3.ZERO) as Vector3) + Vector3(sw * 0.012, br * 0.01, 0.0)
	var pelvis: Vector3 = p.pelvis
	var face: Vector3 = (p.face as Vector3)
	face.y = 0.0
	face = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	var hip_face: Vector3 = p.get("hip_face", face)
	hip_face.y = 0.0
	hip_face = hip_face.normalized() if hip_face.length() > 0.01 else face
	var right := face.cross(Vector3.UP).normalized()
	var hip_right := hip_face.cross(Vector3.UP).normalized()
	var lean: Vector3 = p.get("lean", Vector3.ZERO)
	var chest := pelvis + (Vector3.UP * SPINE + lean).normalized() * SPINE
	var spine_up := (chest - pelvis).normalized()
	var neck := chest + spine_up * 0.12
	var head := neck + spine_up * 0.13

	# Torso and head.
	_limb("torso", pelvis + spine_up * 0.05, chest)
	var tb := Basis(right, spine_up, -face).orthonormalized()
	var chest_mi: MeshInstance3D = _parts.chest
	chest_mi.transform = Transform3D(tb.scaled(Vector3(1.06, 0.84, 0.72)), chest - spine_up * 0.05)
	var belly_mi: MeshInstance3D = _parts.belly
	belly_mi.transform = Transform3D(tb.scaled(Vector3(1.0, 1.0, 0.82)), pelvis + spine_up * 0.2)
	var hips_mi: MeshInstance3D = _parts.hips
	hips_mi.transform = Transform3D(Basis(hip_right, Vector3.UP, -hip_face).orthonormalized().scaled(Vector3(1.12, 0.72, 0.85)), pelvis)
	var belt_mi: MeshInstance3D = _parts.get("belt")
	if belt_mi:
		belt_mi.transform = Transform3D(Basis(hip_right, Vector3.UP, -hip_face).orthonormalized().scaled(Vector3(1.02, 0.028, 0.8)), pelvis + Vector3.UP * 0.075)
	var collar_mi: MeshInstance3D = _parts.get("collar")
	if collar_mi:
		collar_mi.transform = Transform3D(tb.scaled(Vector3(1.0, 0.05, 1.0)), chest + spine_up * 0.1)
	_limb("neck", chest, neck + spine_up * 0.03)
	var head_mi: MeshInstance3D = _parts.head
	var look := to_local(look_at_world) - head if look_at_world != Vector3.ZERO else face
	if look.length() < 0.05:
		look = face
	look = look.normalized()
	# Don't let the head turn further than a person's neck allows.
	var flat_look := Vector3(look.x, 0.0, look.z)
	if flat_look.length() > 0.01 and flat_look.normalized().dot(face) < -0.1:
		look = (look + face * 1.2).normalized()
	var hb := Basis.looking_at(look, Vector3.UP if absf(look.y) < 0.95 else Vector3.BACK)
	head_mi.transform = Transform3D(hb, head)

	# Legs: hips to ankles, knees bend forward (towards the hip facing).
	for s in ["l", "r"]:
		var hip := pelvis + hip_right * (HIP if s == "r" else -HIP) + Vector3.DOWN * 0.04
		_at(s + "hipj", hip)
		var ankle: Vector3 = p[s + "f"]
		ankle = reach(hip, ankle, THIGH + SHIN - 0.002)
		var knee := ik(hip, ankle, THIGH, SHIN, hip_face + hip_right * (0.15 if s == "r" else -0.15))
		_limb(s + "thigh", hip, knee)
		_limb(s + "shin", knee, ankle)
		_at(s + "knee", knee)
		_at(s + "ankle", ankle)
		if _parts.has(s + "pad"):
			var pad: MeshInstance3D = _parts[s + "pad"]
			var y := (knee - ankle).normalized()
			var fwd := hip_face - y * hip_face.dot(y)
			fwd = fwd.normalized() if fwd.length() > 0.01 else hip_face
			var x := y.cross(fwd).normalized()
			var plen := (knee - ankle).length() + 0.12
			pad.transform = Transform3D(Basis(x, y * plen, fwd * 1.0), (knee + ankle) * 0.5 + fwd * 0.05 + y * 0.04)
			_at(s + "kneeroll", knee + fwd * 0.06 + y * 0.03)
		var fdir: Vector3 = p.get(s + "fd", hip_face)
		fdir.y = 0.0
		fdir = fdir.normalized() if fdir.length() > 0.01 else hip_face
		var foot: MeshInstance3D = _parts[s + "foot"]
		var fx := fdir.cross(Vector3.UP).normalized()
		foot.transform = Transform3D(Basis(fx, Vector3.UP, -fdir), Vector3(ankle.x, maxf(0.04, ankle.y - 0.03), ankle.z) + fdir * 0.07)

	# Arms: hands come from the bat grip if there is one.
	var lh: Vector3 = p.get("lh", Vector3.ZERO)
	var rh: Vector3 = p.get("rh", Vector3.ZERO)
	var bat_dir: Vector3 = p.get("bat", Vector3.DOWN)
	if has_bat and p.has("grip"):
		bat_dir = (bat_dir as Vector3).normalized()
		lh = p.grip
		rh = (p.grip as Vector3) + bat_dir * 0.11
	var lpole: Vector3 = p.get("lpole", Vector3.DOWN + (-face) * 0.3 - right * 0.4)
	var rpole: Vector3 = p.get("rpole", Vector3.DOWN + (-face) * 0.3 + right * 0.4)
	var sh_drop := Vector3.DOWN * 0.04
	var top_hand := lh
	for s in ["l", "r"]:
		var sh := chest + right * (SHOULDER if s == "r" else -SHOULDER) + sh_drop
		var hand: Vector3 = lh if s == "l" else rh
		var got := reach(sh, hand, UPPER_ARM + FOREARM - 0.002)
		_at(s + "shoulder", sh)
		var elbow := ik(sh, got, UPPER_ARM, FOREARM, lpole if s == "l" else rpole)
		_limb(s + "upper", sh, elbow)
		_limb(s + "fore", elbow, got)
		_at(s + "elbow", elbow)
		_at(s + "hand", got)
		if s == "l":
			top_hand = got
	if has_bat and _parts.has("bat"):
		var bn: Node3D = _parts.bat
		var y := -bat_dir
		var fc: Vector3 = p.get("batface", -face)
		var z := fc - y * fc.dot(y)
		if z.length() < 0.01:
			z = right
		z = z.normalized()
		var x := y.cross(z).normalized()
		# The bat stays in the top hand even when the hands can't quite reach.
		bn.transform = Transform3D(Basis(x, y, z), top_hand - y * 0.03)


## World position between the hands (where a caught ball sits).
func hands_world() -> Vector3:
	var l: MeshInstance3D = _parts.get("lhand")
	var r: MeshInstance3D = _parts.get("rhand")
	if l == null or r == null:
		return global_position + Vector3(0, 1.0, 0)
	return (l.global_position + r.global_position) * 0.5


## World position of the middle of the bat right now (for tests and cameras).
func bat_middle() -> Vector3:
	if not pose.has("grip"):
		return global_position
	return to_global((pose.grip as Vector3) + (pose.bat as Vector3).normalized() * SWEET)
