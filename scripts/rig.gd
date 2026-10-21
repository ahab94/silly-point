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
const SHOULDER := 0.19
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


static func _cyl(r_top: float, r_bot: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = 1.0
	m.radial_segments = 10
	m.rings = 1
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


## kit: shirt and trousers. extra: "helmet", "cap", "umpire", "keeper".
## pads: batter's or keeper's leg guards. bat: give them a bat.
func build(kit: Color, skin: Color, hat: String, hat_color: Color, pads := false, bat := false, gloves := false) -> void:
	has_bat = bat
	var trousers := kit
	_mesh_node("torso", _cyl(0.17, 0.14), kit)
	_mesh_node("hips", _sphere(0.15), trousers).scale = Vector3(1.0, 0.75, 0.8)
	_mesh_node("chest", _sphere(0.18), kit).scale = Vector3(1.0, 0.8, 0.75)
	_mesh_node("neck", _cyl(0.05, 0.05), skin)
	_mesh_node("head", _sphere(0.11), skin)
	for s in ["l", "r"]:
		_mesh_node(s + "thigh", _cyl(0.085, 0.065), trousers)
		_mesh_node(s + "shin", _cyl(0.065, 0.05), Color(0.97, 0.97, 0.97) if pads else trousers)
		if pads:
			_mesh_node(s + "pad", _box(Vector3(0.16, 1.0, 0.13)), Color(0.98, 0.98, 0.98))
			_mesh_node(s + "kneeroll", _sphere(0.085), Color(0.98, 0.98, 0.98))
		_mesh_node(s + "knee", _sphere(0.068), Color(0.98, 0.98, 0.98) if pads else trousers)
		_mesh_node(s + "foot", _box(Vector3(0.1, 0.08, 0.27)), Color(0.95, 0.95, 0.95))
		_mesh_node(s + "upper", _cyl(0.055, 0.045), kit)
		_mesh_node(s + "fore", _cyl(0.045, 0.038), skin if not gloves else kit)
		_mesh_node(s + "elbow", _sphere(0.048), kit)
		_mesh_node(s + "hand", _sphere(0.065 if gloves else 0.045), Color(0.97, 0.97, 0.97) if gloves else skin)
	var head: MeshInstance3D = _parts.head
	var hat_root := Node3D.new()
	head.add_child(hat_root)
	_parts.hat = hat_root
	match hat:
		"helmet":
			var shell := MeshInstance3D.new()
			shell.mesh = _sphere(0.135)
			shell.material_override = _mat(hat_color)
			shell.position = Vector3(0, 0.03, 0.01)
			shell.scale = Vector3(1.0, 0.88, 1.05)
			hat_root.add_child(shell)
			var peak := MeshInstance3D.new()
			peak.mesh = _box(Vector3(0.2, 0.015, 0.1))
			peak.material_override = _mat(hat_color)
			peak.position = Vector3(0, 0.075, -0.13)
			hat_root.add_child(peak)
			var grill := MeshInstance3D.new()
			grill.mesh = _box(Vector3(0.18, 0.12, 0.015))
			grill.material_override = _mat(Color(0.7, 0.7, 0.74))
			grill.position = Vector3(0, -0.04, -0.14)
			hat_root.add_child(grill)
		"cap":
			var crown := MeshInstance3D.new()
			crown.mesh = _sphere(0.118)
			crown.material_override = _mat(hat_color)
			crown.position = Vector3(0, 0.04, 0)
			crown.scale = Vector3(1, 0.62, 1)
			hat_root.add_child(crown)
			var brim := MeshInstance3D.new()
			brim.mesh = _box(Vector3(0.16, 0.012, 0.12))
			brim.material_override = _mat(hat_color)
			brim.position = Vector3(0, 0.045, -0.14)
			hat_root.add_child(brim)
		"umpire":
			var b := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.1
			cm.bottom_radius = 0.22
			cm.height = 0.13
			b.mesh = cm
			b.material_override = _mat(Color(0.95, 0.95, 0.9))
			b.position = Vector3(0, 0.1, 0)
			hat_root.add_child(b)
	if bat:
		var bn := Node3D.new()
		add_child(bn)
		_parts.bat = bn
		var handle := MeshInstance3D.new()
		var hm := _cyl(0.017, 0.017)
		handle.mesh = hm
		handle.material_override = _mat(Color(0.12, 0.12, 0.12))
		handle.scale = Vector3(1, 0.3, 1)
		handle.position = Vector3(0, -0.12, 0)
		bn.add_child(handle)
		var blade := MeshInstance3D.new()
		blade.mesh = _box(Vector3(0.108, 0.56, 0.05))
		blade.material_override = _mat(Color(0.9, 0.78, 0.53))
		blade.position = Vector3(0, -0.27 - 0.28, 0.008)
		bn.add_child(blade)
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
	var p := pose
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
	_at("hips", pelvis)
	var chest_mi: MeshInstance3D = _parts.chest
	chest_mi.transform = Transform3D(Basis(right, spine_up, -face).orthonormalized().scaled(Vector3(1.0, 0.8, 0.75)), chest - spine_up * 0.03)
	var hips_mi: MeshInstance3D = _parts.hips
	hips_mi.transform = Transform3D(Basis(hip_right, Vector3.UP, -hip_face).orthonormalized().scaled(Vector3(1.0, 0.75, 0.8)), pelvis)
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
		var ankle: Vector3 = p[s + "f"]
		ankle = reach(hip, ankle, THIGH + SHIN - 0.002)
		var knee := ik(hip, ankle, THIGH, SHIN, hip_face + hip_right * (0.15 if s == "r" else -0.15))
		_limb(s + "thigh", hip, knee)
		_limb(s + "shin", knee, ankle)
		_at(s + "knee", knee)
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
