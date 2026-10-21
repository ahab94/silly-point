extends RefCounted
## Poses and keyframes for everyone on the field: the batter's stance and
## strokes, the bowler's run-up and action, fielders running and crouching,
## the umpire.
##
## Batting poses are in the batter's local space: origin between the feet
## at the crease (ROOT in world space), +x the off side, -z the bowler.
##
## How a stroke is built (`shot`):
## 1. Footwork places the feet and hips: forward to the pitch of the ball,
##    back and across, or down on one knee for a sweep.
## 2. At contact the bat's sweet spot sits exactly where the ball is met,
##    with the face pointing where the ball will go.
## 3. The swing is that contact pose rotated about the shoulders, around
##    the axis bat x face: backwards for the downswing, forwards for the
##    follow-through. So the arc always matches the shot's direction.

const Rig := preload("res://scripts/rig.gd")

const ROOT := Vector3(-0.42, 0.0, -0.92)


static func _n(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()


# ---------------------------------------------------------------- batter

static func stance() -> Dictionary:
	return {
		"pelvis": Vector3(0.02, 0.86, 0.0), "face": _n(1, 0, -0.15), "hip_face": _n(1, 0, 0.05),
		"lean": Vector3(0.08, 0.0, -0.02),
		"lf": Vector3(0.04, 0.07, -0.27), "rf": Vector3(0.0, 0.07, 0.2),
		"lfd": _n(0.6, 0, -0.8), "rfd": _n(1, 0, 0.15),
		"grip": Vector3(0.3, 0.84, 0.06), "bat": _n(0.05, -0.95, 0.28), "batface": _n(0.15, 0, -1),
		"lpole": _n(0.3, -0.2, -1), "rpole": _n(0.2, -1, 0.6),
	}


static func backlift() -> Dictionary:
	return {
		"pelvis": Vector3(0.02, 0.85, 0.0), "grip": Vector3(0.16, 1.18, 0.18),
		"bat": _n(0.05, 0.62, 0.8), "batface": _n(1, 0, 0.2), "lean": Vector3(0.07, 0.0, -0.04),
	}


static func _rot_pose(p: Dictionary, pivot: Vector3, axis: Vector3, ang: float) -> Dictionary:
	var out := p.duplicate()
	var b := Basis(axis, ang)
	out.grip = pivot + b * ((p.grip as Vector3) - pivot)
	out.bat = (b * (p.bat as Vector3)).normalized()
	out.batface = (b * (p.batface as Vector3)).normalized()
	return out


## The body for a footwork choice, given where the ball is met (local).
static func _body(foot: String, c: Vector3, kind: String) -> Dictionary:
	var s := stance()
	var b := {}
	match foot:
		"front", "dance":
			var lf := Vector3(clampf(c.x - 0.3, -0.12, 0.38), 0.07, clampf(c.z + 0.3, -1.05, -0.45))
			var rf: Vector3 = (s.rf as Vector3) + Vector3(0.02, 0.0, 0.03)
			# Weight forward over a bent front knee, back leg long behind.
			b = {"lf": lf, "rf": rf, "pelvis": Vector3(lerpf(lf.x, rf.x, 0.45) + 0.04, 0.74, lerpf(lf.z, rf.z, 0.38)),
				"lean": Vector3(0.1, -0.02, -0.2), "hip_face": _n(0.9, 0, -0.45), "lfd": _n(0.45, 0, -0.9)}
		"back":
			var rf2 := Vector3(clampf(c.x - 0.18, 0.0, 0.32), 0.07, 0.33)
			var lf2 := Vector3(0.1, 0.07, -0.02)
			b = {"lf": lf2, "rf": rf2, "pelvis": Vector3((lf2.x + rf2.x) * 0.5 + 0.03, 0.9, (lf2.z + rf2.z) * 0.5),
				"lean": Vector3(0.05, 0.02, -0.02)}
		"sweep":
			# Down on the back knee, front leg bent out towards the line.
			b = {"lf": Vector3(0.2, 0.07, -0.78), "rf": Vector3(-0.02, 0.07, 0.36), "pelvis": Vector3(0.06, 0.45, -0.2),
				"lean": Vector3(0.16, -0.05, -0.22), "hip_face": _n(0.9, 0, -0.4), "lfd": _n(0.5, 0, -0.85)}
		_:
			b = {"pelvis": Vector3(0.04, 0.84, 0.0), "lean": Vector3(0.08, 0.0, -0.07)}
	if kind == "pull":
		b.face = _n(0.45, 0, -0.9)      # chest opens up to the bowler
		b.hip_face = _n(0.35, 0, -1)
	return b


## Keyframes for a stroke. `key` is the shot (batting.gd SHOTS), `foot` the
## footwork, `dir_deg` where the ball goes, `c` the contact point (local),
## `t` the time from the key press to contact.
static func shot(key: String, foot: String, dir_deg: float, c: Vector3, t: float, loft: bool) -> Array:
	var d := Vector3(sin(deg_to_rad(dir_deg)), 0.0, -cos(deg_to_rad(dir_deg)))
	var horizontal := key in ["cut", "pull", "hook", "upper_cut", "sweep", "slog_sweep", "reverse_sweep"]
	var defend := key.begins_with("defend")
	var body_foot := "sweep" if key.contains("sweep") else foot
	var body := _body(body_foot, c, "pull" if key in ["pull", "hook"] else "")
	var pose := stance()
	for k in body:
		pose[k] = body[k]
	var pelvis: Vector3 = pose.pelvis
	var chest := pelvis + Vector3(0.1, 0.48, -0.05)

	var bat_c: Vector3
	var face_c: Vector3
	if defend:
		bat_c = _n(0.0, -0.95, 0.3)          # handle ahead of the blade: soft, angled down
		face_c = _n(d.x * 0.3, -0.25, -1)
	elif not horizontal:
		bat_c = _n(d.x * 0.08, -1.0, 0.06)
		face_c = (d + Vector3(0, 0.4 if loft else -0.12, 0)).normalized()
	else:
		match key:
			"cut", "upper_cut":
				# Reaching out to the width, coming down on it.
				bat_c = _n(0.7, -0.45 if key == "cut" else 0.15, -0.55)
			"sweep", "slog_sweep":
				bat_c = _n(0.45, -0.55, -0.7)
			"reverse_sweep":
				bat_c = _n(-0.4, -0.5, -0.77)
			_:
				var v := c - chest
				v.y = 0.0
				bat_c = (v.normalized() + Vector3(0, -0.2 if key == "pull" else 0.05, 0)).normalized()
		face_c = d - bat_c * d.dot(bat_c)
		face_c = face_c.normalized() if face_c.length() > 0.05 else d
		face_c = (face_c + Vector3(0, 0.3 if loft else -0.05, 0)).normalized()
	var grip := c - bat_c * Rig.SWEET
	# Make sure the hands can get there: lean or shift the hips towards it.
	var gap := grip - chest
	if gap.length() > 0.58:
		var shift := gap.normalized() * (gap.length() - 0.58)
		pose.pelvis = pelvis + Vector3(shift.x, minf(shift.y, 0.0), shift.z) * 0.8
		pose.lean = (pose.lean as Vector3) + shift * 0.6
		chest += shift
	pose.grip = grip
	pose.bat = bat_c
	pose.batface = face_c
	if key in ["pull", "hook", "sweep", "slog_sweep"]:
		pose.lpole = _n(-0.3, -0.6, -0.6)
	var axis := bat_c.cross(face_c)
	axis = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
	var pivot := chest + Vector3(0.0, 0.02, 0.0)
	var back_ang := 0.55 if defend else 1.7
	var follow_ang := 0.12 if defend else (2.5 if loft else (1.2 if key == "punch" else 2.2))
	var top := _rot_pose(pose, pivot, axis, -back_ang)
	var follow := _rot_pose(pose, pivot, axis, follow_ang)
	follow.lean = (pose.lean as Vector3) + (Vector3(-0.05, 0, 0.08) if loft else d * 0.06)
	if key in ["pull", "hook", "sweep", "slog_sweep", "reverse_sweep"]:
		# Horizontal shots finish up over the shoulder, not along the ground.
		follow.bat = ((follow.bat as Vector3) + Vector3.UP * 0.9).normalized()
		follow.grip = (follow.grip as Vector3) + Vector3.UP * 0.3
	if defend:
		return [[t * 0.5, top, "out"], [t * 0.5, pose, "in"], [0.25, follow, "out"], [0.6, follow]]
	return [[t * 0.42, top, "out"], [t * 0.58, pose, "in"], [0.3, follow, "out"], [0.7, follow]]


static func leave() -> Array:
	return [[0.25, {"grip": Vector3(0.04, 1.45, 0.14), "bat": _n(0.12, 0.85, 0.5), "batface": _n(1, 0, 0),
			"lf": Vector3(0.1, 0.07, -0.5), "pelvis": Vector3(0.05, 0.84, -0.12), "lean": Vector3(0.05, 0.0, -0.08),
			"lpole": _n(0.2, 0.3, -1)}, "out"], [0.8, {}]]


static func duck() -> Array:
	return [[0.16, {"pelvis": Vector3(0.0, 0.5, 0.12), "lean": Vector3(0.4, -0.05, 0.08),
			"grip": Vector3(0.22, 0.42, 0.06), "bat": _n(0.1, -0.85, 0.5), "rf": Vector3(0.02, 0.07, 0.3)}, "out"], [0.8, {}]]


# ---------------------------------------------------------------- running

## A walking or running cycle in place (the game moves the root). `speed`
## in m/s; `face` the direction of travel.
static func gait(t: float, speed: float, face: Vector3) -> Dictionary:
	face.y = 0.0
	face = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	var right := face.cross(Vector3.UP).normalized()
	var run := clampf(speed / 6.0, 0.0, 1.0)
	var freq := 0.9 + 0.75 * run
	var ph := t * freq * TAU
	var stride := lerpf(0.2, 0.42, run)
	var lift := lerpf(0.06, 0.22, run)
	var lf := -right * 0.1 + face * sin(ph) * stride + Vector3.UP * (0.07 + maxf(0.0, cos(ph)) * lift)
	var rf := right * 0.1 - face * sin(ph) * stride + Vector3.UP * (0.07 + maxf(0.0, -cos(ph)) * lift)
	var arm := lerpf(0.18, 0.32, run)
	var hand_y := lerpf(0.72, 0.95, run)
	return {
		"pelvis": Vector3(0, lerpf(0.93, 0.91, run) + absf(sin(ph)) * 0.03 * (0.5 + run), 0) + face * 0.02 * run,
		"face": face, "hip_face": face, "lean": face * lerpf(0.02, 0.12, run),
		"lf": lf, "rf": rf, "lfd": face, "rfd": face,
		"lh": -right * 0.24 - face * sin(ph) * arm + Vector3.UP * hand_y + face * 0.08 * run,
		"rh": right * 0.24 + face * sin(ph) * arm + Vector3.UP * hand_y + face * 0.08 * run,
		"lpole": Vector3.DOWN - face * 0.6, "rpole": Vector3.DOWN - face * 0.6,
	}


static func ready_pose(face: Vector3, crouch: float) -> Dictionary:
	var right := face.cross(Vector3.UP).normalized()
	var h := lerpf(0.9, 0.55, crouch)
	return {
		"pelvis": Vector3(0, h, 0), "face": face, "hip_face": face, "lean": face * lerpf(0.04, 0.3, crouch),
		"lf": -right * 0.2 + Vector3.UP * 0.07, "rf": right * 0.2 + Vector3.UP * 0.07, "lfd": face, "rfd": face,
		"lh": -right * 0.15 + face * (0.25 + 0.15 * crouch) + Vector3.UP * lerpf(0.75, 0.35, crouch),
		"rh": right * 0.15 + face * (0.25 + 0.15 * crouch) + Vector3.UP * lerpf(0.75, 0.35, crouch),
		"lpole": Vector3.DOWN - right * 0.5, "rpole": Vector3.DOWN + right * 0.5,
	}


## Hands reaching for a ball at `at` (local), body stretching towards it.
static func catch_pose(face: Vector3, at: Vector3) -> Dictionary:
	var right := face.cross(Vector3.UP).normalized()
	var p := ready_pose(face, 0.2)
	var h := clampf(at.y, 0.2, 2.2)
	var flat := Vector3(at.x, 0, at.z)
	var lean := flat.limit_length(0.35) + Vector3.UP * 0.0
	p.pelvis = Vector3(0, clampf(h * 0.55 + 0.35, 0.5, 0.95), 0) + flat.limit_length(0.3)
	p.lean = lean
	p.lh = at - right * 0.07
	p.rh = at + right * 0.07
	return p


## Full-length dive towards `dir`: body low and stretched, arms reaching.
static func dive_pose(dir: Vector3) -> Dictionary:
	dir.y = 0.0
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	return {
		"pelvis": Vector3(0, 0.3, 0) + dir * 0.6, "face": dir, "hip_face": dir,
		"lean": dir * 1.6 + Vector3.DOWN * 0.2,
		"lf": -dir * 0.4 - right * 0.15 + Vector3.UP * 0.12, "rf": -dir * 0.55 + right * 0.15 + Vector3.UP * 0.2,
		"lfd": dir, "rfd": dir,
		"lh": dir * 1.6 - right * 0.12 + Vector3.UP * 0.25, "rh": dir * 1.6 + right * 0.12 + Vector3.UP * 0.25,
		"lpole": Vector3.DOWN, "rpole": Vector3.DOWN,
	}


# ---------------------------------------------------------------- bowler

## Bowler's action over the run-up. `t` from the start, release at
## `release`. Right-arm over the wicket, running towards +z.
static func bowler_pose(t: float, release: float, spin: bool) -> Dictionary:
	var face := Vector3(0, 0, 1)
	var bound := 0.42 if not spin else 0.3
	var tb := release - bound          # start of the bound and delivery stride
	if t < tb:
		var sp := lerpf(2.5, 6.5 if not spin else 3.0, clampf(t / maxf(tb, 0.01), 0.0, 1.0))
		return gait(t, sp, face)
	var side := Vector3(-1, 0, 0)       # side-on: chest to the bowler's left, left shoulder at the batter
	var k := clampf((t - tb) / bound, 0.0, 1.0)
	var after := t - release
	if after < 0.0:
		# Gather: leap, front arm reaching up, bowling arm coming round low.
		var air := sin(k * PI) * 0.18
		var a := lerpf(-2.6, 0.0, k)          # bowling arm angle: 0 is straight up
		var sh := Vector3(0.0, 1.38 + air, -0.19)
		return {
			"pelvis": Vector3(0, 0.95 + air, 0), "face": side.lerp(face, 0.15).normalized(), "hip_face": side,
			"lean": Vector3(0, 0, -0.05),
			"lf": Vector3(0.05, 0.07 + air + 0.25 * (1.0 - k), 0.25 + 0.45 * k), "rf": Vector3(-0.05, 0.07 + air, -0.35),
			"lfd": face, "rfd": side,
			"lh": Vector3(0.0, 1.95 + air, 0.35 - 0.3 * k),
			"rh": sh + Vector3(0.0, cos(a), sin(a)) * 0.58,
			"lpole": Vector3(0, -0.3, 1), "rpole": Vector3(0, 0, -1),
		}
	# Release and follow-through: arm over the top and down past the hip,
	# chest swivels round to the batter, back leg comes through.
	var f := clampf(after / 0.45, 0.0, 1.0)
	var a2 := lerpf(0.0, 2.6, clampf(after / 0.25, 0.0, 1.0))
	var sh2 := Vector3(0.0, 1.38 - 0.25 * f, 0.0)
	if after > 0.6:
		var g := gait(after, lerpf(3.5, 0.0, clampf((after - 0.6) / 1.2, 0.0, 1.0)), face)
		return g
	return {
		"pelvis": Vector3(0, 0.9 - 0.12 * sin(f * PI), 0.1 * f), "face": side.lerp(face, f).normalized(),
		"hip_face": side.lerp(face, f).normalized(), "lean": Vector3(0, -0.05, 0.25 * sin(f * PI)),
		"lf": Vector3(0.05, 0.07, 0.6), "rf": Vector3(-0.05, 0.07 + 0.2 * sin(f * PI), lerpf(-0.35, 0.8, f)),
		"lh": Vector3(0.2, 0.75, -0.1), "rh": sh2 + Vector3(-0.1 * f, cos(a2), sin(a2)) * 0.58,
		"lpole": Vector3(0, -1, -0.5), "rpole": Vector3(1, 0, 0),
	}


# ---------------------------------------------------------------- umpire

static func umpire_pose(finger: bool) -> Dictionary:
	var p := ready_pose(Vector3(0, 0, 1), 0.0)
	p.lh = Vector3(0.1, 0.85, -0.12)
	p.rh = Vector3(-0.1, 0.85, -0.12) if not finger else Vector3(-0.3, 2.05, 0.1)
	p.lean = Vector3(0, 0, 0.03)
	return p
