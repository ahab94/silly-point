extends RefCounted
## Deterministic ball physics. A delivery is a Dictionary of numbers made by
## bowling.gd; `simulate` turns it into a trajectory sampled every DT
## seconds. The game, the autopilot and the ball-tracking replay all read the
## same trajectory, so what you see, what the bot plans against and what the
## review shows always agree.
##
## Coordinates (metres): the striker's stumps are at the origin, the bowler
## runs in from negative z, y is up. +x is the off side of a right-handed
## batter (the right of the screen when you look down the pitch).

const G := 9.81
const RADIUS := 0.036
const DT := 1.0 / 240.0
const PITCH_LENGTH := 20.12
const STUMP_HALF := 0.114        # half the width of the three stumps
const STUMP_HEIGHT := 0.711
const POPPING_CREASE := -1.22
const MAX_T := 3.2
const DRAG := 0.0052             # air drag on a hit ball, per (m/s)^2


## Release velocity that lands the ball on `d.pitch` (x, z). The bowler aims
## for the spot knowing roughly how much it will swing, so the lateral pull
## is pre-compensated: the ball starts wide of its target and curves back.
static func launch_velocity(d: Dictionary) -> Vector3:
	var p0: Vector3 = d.release
	var target: Vector2 = d.pitch
	var vz: float = d.speed * 0.985
	var t: float = maxf((target.y - p0.z) / vz, 0.05)
	var lat: float = float(d.swing) + float(d.drift)
	var vx: float = (target.x - p0.x) / t - lat * t / 6.0
	var vy: float = (RADIUS - p0.y + 0.5 * G * t * t) / t
	return Vector3(vx, vy, vz)


static func flight_time(d: Dictionary) -> float:
	var p0: Vector3 = d.release
	var target: Vector2 = d.pitch
	return maxf((target.y - p0.z) / (float(d.speed) * 0.985), 0.05)


## Integrates the delivery. Swing and drift build up through the flight (late
## swing is the dangerous kind) and stop when the ball pitches. On pitching
## the surface takes over: bounce, pace lost to the grip, and sideways
## deviation from the seam, cracks and spin.
static func simulate(d: Dictionary) -> Dictionary:
	var v := launch_velocity(d)
	var p: Vector3 = d.release
	var t_fl := flight_time(d)
	var lat: float = float(d.swing) + float(d.drift)
	var pts := PackedVector3Array()
	var vels := PackedVector3Array()
	var t := 0.0
	var bounces := 0
	var pitch_t := -1.0
	var pitch_pos := Vector3.ZERO
	pts.append(p)
	vels.append(v)
	while t < MAX_T:
		var a := Vector3(0.0, -G, 0.0)
		if bounces == 0:
			a.x = lat * minf(t / t_fl, 1.0)
		v += a * DT
		p += v * DT
		t += DT
		if p.y <= RADIUS and v.y < 0.0:
			p.y = RADIUS
			if bounces == 0:
				pitch_t = t
				pitch_pos = p
				v.y = -v.y * float(d.bounce)
				v.z *= float(d.skid)
				v.x += float(d.deviation)
			else:
				v.y = -v.y * 0.35
				v.x *= 0.8
				v.z *= 0.8
			bounces += 1
		pts.append(p)
		vels.append(v)
		if p.z > 17.0:
			break
	return {"pts": pts, "vels": vels, "pitch_t": pitch_t, "pitch_pos": pitch_pos,
			"end_t": t}


static func pos_at(traj: Dictionary, t: float) -> Vector3:
	var pts: PackedVector3Array = traj.pts
	var f := clampf(t / DT, 0.0, float(pts.size() - 1))
	var i := int(f)
	if i >= pts.size() - 1:
		return pts[pts.size() - 1]
	return pts[i].lerp(pts[i + 1], f - float(i))


static func vel_at(traj: Dictionary, t: float) -> Vector3:
	var vels: PackedVector3Array = traj.vels
	var i := clampi(int(t / DT), 0, vels.size() - 1)
	return vels[i]


## First time the ball's z reaches `z`, or -1 if it never does. z only grows
## along a delivery, so a binary search works.
static func time_at_z(traj: Dictionary, z: float) -> float:
	var pts: PackedVector3Array = traj.pts
	if pts.size() < 2 or pts[pts.size() - 1].z < z:
		return -1.0
	if pts[0].z >= z:
		return 0.0
	var lo := 0
	var hi := pts.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if pts[mid].z < z:
			lo = mid
		else:
			hi = mid
	var dz := pts[hi].z - pts[lo].z
	var f := 0.0 if dz <= 0.0 else (z - pts[lo].z) / dz
	return (float(lo) + f) * DT


## Where a batter *expects* the ball to be at depth `z`, judging from where
## it is now and how it is moving. The batter cannot know what the seam,
## cracks or spin will do off the pitch, or how much more it will swing, so
## this assumes a straight path and an average bounce. The gap between this
## guess and the real path is what beats the bat.
static func naive_predict(p: Vector3, v: Vector3, pitched: bool, z: float) -> Vector3:
	var pos := p
	var vel := v
	var bounced := pitched
	var step := 1.0 / 240.0
	var n := 0
	while pos.z < z and n < 2000:
		vel.y -= G * step
		pos += vel * step
		if pos.y <= RADIUS and vel.y < 0.0:
			pos.y = RADIUS
			if not bounced:
				vel.y = -vel.y * 0.55
				vel.z *= 0.9
				bounced = true
			else:
				vel.y = -vel.y * 0.35
		n += 1
	return pos


## Flight of a hit ball: drag in the air, low bounces and rolling friction on
## the outfield. Returns samples every HIT_DT.
const HIT_DT := 1.0 / 120.0

static func simulate_hit(p0: Vector3, v0: Vector3, max_t: float = 9.0) -> Dictionary:
	var p := p0
	var v := v0
	var pts := PackedVector3Array()
	var t := 0.0
	var first_bounce := -1.0
	pts.append(p)
	while t < max_t:
		var speed := v.length()
		var a := Vector3(0.0, -G, 0.0)
		if p.y > RADIUS + 0.001 or v.y > 0.0:
			a -= v * (DRAG * speed)
		else:
			# Rolling: grass friction slows it, faster when it's slow.
			var flat := Vector3(v.x, 0.0, v.z)
			var fs := flat.length()
			if fs < 0.3:
				v = Vector3.ZERO
			else:
				var decel := 1.6 + 0.012 * fs * fs
				v -= flat / fs * minf(decel * HIT_DT, fs)
			v.y = 0.0
			a = Vector3.ZERO
		v += a * HIT_DT
		p += v * HIT_DT
		t += HIT_DT
		if p.y < RADIUS:
			p.y = RADIUS
			if v.y < -1.0:
				if first_bounce < 0.0:
					first_bounce = t
				v.y = -v.y * 0.32
				v.x *= 0.72
				v.z *= 0.72
			else:
				v.y = 0.0
		pts.append(p)
		if v == Vector3.ZERO:
			break
	return {"pts": pts, "first_bounce": first_bounce, "end_t": t}


static func hit_pos_at(path: Dictionary, t: float) -> Vector3:
	var pts: PackedVector3Array = path.pts
	var f := clampf(t / HIT_DT, 0.0, float(pts.size() - 1))
	var i := int(f)
	if i >= pts.size() - 1:
		return pts[pts.size() - 1]
	return pts[i].lerp(pts[i + 1], f - float(i))
