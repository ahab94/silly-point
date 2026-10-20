extends RefCounted
## Match conditions: how old the ball is, how worn the pitch is, and the
## weather. Every "how much will it swing / seam / turn / bounce?" question
## is answered here, so the bowling and physics code never hard-codes them.
##
## The quirks this models:
## - A new ball is shiny and hard. Shine makes it swing (conventional swing),
##   hardness makes it bounce and come onto the bat quickly.
## - The ball scuffs as it ages. On a dry, abrasive square one side gets
##   rough, and from about 25 overs a fast bowler can make it swing the
##   *other* way (reverse swing). A wet ball (dew) does neither.
## - The pitch starts green (seam movement, bounce), flattens out on days
##   2-3, then cracks and crumbles on days 4-5 (turn, uneven bounce).
## - Bowlers' footmarks rough up the area outside the stumps, where
##   spinners get extra grip.
## - Cloud cover helps swing. Dew makes the ball wet: no swing, and
##   spinners cannot grip it.

var overs := 0.0          # overs bowled with this ball
var day := 1              # pitch age, 1..5
var overcast := false
var dew := false
var abrasive := 0.5       # 0..1, how fast a dry square scuffs the ball

const GRASS := [0.9, 0.6, 0.35, 0.2, 0.1]
const BOUNCE := [0.60, 0.57, 0.54, 0.51, 0.47]
const GRIP := [0.3, 0.45, 0.65, 0.85, 1.0]
const CRACKS := [0.0, 0.0, 0.04, 0.12, 0.24]
const ROUGH := [0.0, 0.15, 0.4, 0.75, 1.0]

# The footmark rough at the batter's end: outside both sets of stumps,
# roughly on a spinner's good length (z is metres from the batter's stumps,
# negative towards the bowler).
const ROUGH_X := Vector2(0.28, 0.85)
const ROUGH_Z := Vector2(-6.5, -2.2)


func _d() -> int:
	return clampi(day, 1, 5) - 1


## 1 for a brand new ball, falling to a little as it is used. Bowlers polish
## one side on their trousers, so it never quite reaches zero.
func shine() -> float:
	return clampf(1.0 - overs / 42.0, 0.08, 1.0)


## How scuffed the rough side is. Needed for reverse swing.
func roughness() -> float:
	return clampf((overs - 18.0) / 26.0 * lerpf(0.6, 1.25, abrasive), 0.0, 1.0)


## 1 for a new ball. An old, soft ball bounces less and the bat gets less
## out of it.
func hardness() -> float:
	return 1.0 - 0.32 * clampf(overs / 80.0, 0.0, 1.0)


func grass() -> float:
	return GRASS[_d()]


func bounce() -> float:
	return BOUNCE[_d()]


## How much a spinner can make it turn. Dew makes the ball a bar of soap.
func grip() -> float:
	return GRIP[_d()] * (0.4 if dew else 1.0)


func crack_chance() -> float:
	return CRACKS[_d()]


func rough_strength() -> float:
	return ROUGH[_d()]


func in_rough(x: float, z: float) -> bool:
	var ax := absf(x)
	return rough_strength() > 0.05 and ax > ROUGH_X.x and ax < ROUGH_X.y \
			and z > ROUGH_Z.x and z < ROUGH_Z.y


## Conventional swing strength for a ball released at `speed` m/s. Needs a
## shiny ball; peaks at brisk medium pace and fades for spinners and for the
## very quick.
func conventional(speed: float) -> float:
	var pace := clampf((speed - 24.0) / 7.0, 0.0, 1.0) * clampf((44.0 - speed) / 6.0, 0.45, 1.0)
	var air := (1.35 if overcast else 1.0) * (0.35 if dew else 1.0)
	return shine() * pace * air


## Reverse swing strength: needs a rough ball and real pace.
func reverse(speed: float) -> float:
	var pace := clampf((speed - 34.0) / 5.0, 0.0, 1.0)
	return roughness() * pace * (0.25 if dew else 1.0)


## Positive: the ball swings away from the shiny side (conventional).
## Negative: it swings towards the shiny side (reverse).
func swing_balance(speed: float) -> float:
	return conventional(speed) - 1.25 * reverse(speed)


func is_reversing(speed: float = 40.0) -> bool:
	return swing_balance(speed) < -0.05


func take_new_ball() -> void:
	overs = 0.0


func describe_pitch() -> String:
	match clampi(day, 1, 5):
		1: return "Day 1: green and lively"
		2: return "Day 2: settling down"
		3: return "Day 3: flat, a batting paradise"
		4: return "Day 4: cracks and footmarks"
	return "Day 5: a crumbling dust bowl"
