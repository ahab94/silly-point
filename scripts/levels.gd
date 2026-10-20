extends RefCounted
## The career: ten match situations, each built around one cricket quirk.
##
## Fields per level:
##   name, blurb (the situation), tip (shown before play)
##   format: "test" or "t20" (T20 has wides and free hits after no-balls)
##   day: pitch age 1-5. overs: how old the ball is at the start.
##   overcast, dew, abrasive (0-1, how quickly the square scuffs the ball)
##   bowlers: bowler ids, one per over in turn (see bowling.gd)
##   field: "attack" or "defend" (pace/spin is picked from the bowler)
##   balls: how many balls you face. wickets: how many you can lose.
##   mode: "chase" (score `target` runs) or "survive" (do not lose
##   `wickets`, and runs earn stars)
##   stars: [two-star runs, three-star runs]. In a chase, two stars mean
##   no wickets lost, three mean no wickets lost with 6+ balls to spare.
##   new_ball_after: take the new ball after this many balls (optional).
##   seed: makes the innings repeatable for the autopilot gate.

const LEVELS := [
	{
		"name": "Net Session",
		"blurb": "A friendly net on a flat Day 3 pitch. The ball's old, the bowler's gentle, and nothing is moving.",
		"tip": "Hold a direction (W A S D) and press K for a ground shot as the ball arrives. W is front foot, S is back foot, A/D pick leg or off side.",
		"format": "test", "day": 3, "overs": 30.0, "overcast": false, "dew": false, "abrasive": 0.2,
		"bowlers": ["dave"], "field": "attack", "balls": 18, "wickets": 3,
		"mode": "chase", "target": 9, "stars": [0, 0], "seed": 101,
	},
	{
		"name": "The New Ball",
		"blurb": "Day 1, first over, grey skies. The ball is shiny and it is going to swing.",
		"tip": "Watch the ball cam at release. A new ball swings AWAY from the shiny side. Leave the ones going wide (no key).",
		"format": "test", "day": 1, "overs": 0.0, "overcast": true, "dew": false, "abrasive": 0.4,
		"bowlers": ["banana"], "field": "attack", "balls": 12, "wickets": 3,
		"mode": "survive", "target": 0, "stars": [5, 10], "seed": 202,
	},
	{
		"name": "Green Top",
		"blurb": "A pitch so green they nearly mowed it. The ball nips off the seam after it bounces.",
		"tip": "Movement off the pitch beats a bat that commits early. Get forward to the pitch of the ball (W) or wait on the back foot (S).",
		"format": "test", "day": 1, "overs": 6.0, "overcast": false, "dew": false, "abrasive": 0.4,
		"bowlers": ["grassy"], "field": "attack", "balls": 18, "wickets": 2,
		"mode": "chase", "target": 12, "stars": [0, 0], "seed": 303,
	},
	{
		"name": "Chin Music",
		"blurb": "Bumper Barnaby has decided your helmet is the target.",
		"tip": "Short balls: hold S+A and press K to pull, or L to hook it in the air. Or duck: hold S and play no shot.",
		"format": "test", "day": 2, "overs": 20.0, "overcast": false, "dew": false, "abrasive": 0.4,
		"bowlers": ["barnaby"], "field": "attack", "balls": 18, "wickets": 2,
		"mode": "chase", "target": 16, "stars": [0, 0], "seed": 404,
	},
	{
		"name": "Tweak Week",
		"blurb": "Day 4. The pitch is cracking and Tweaky Tim is turning it into your pads.",
		"tip": "Off-spin turns in from off. Charge down the pitch (Shift) to smother the turn, or sweep it (I). Miss after charging and you are stumped!",
		"format": "test", "day": 4, "overs": 45.0, "overcast": false, "dew": false, "abrasive": 0.5,
		"bowlers": ["tim"], "field": "attack", "balls": 18, "wickets": 3,
		"mode": "chase", "target": 10, "stars": [0, 0], "seed": 505,
	},
	{
		"name": "The Wizard of Wrist",
		"blurb": "A leg-spinner with a googly, a top-spinner and a flipper. Which one is coming?",
		"tip": "Read the ball cam: the spin arrow shows which way it will turn. The googly looks like a leg-break but turns the other way.",
		"format": "test", "day": 4, "overs": 50.0, "overcast": false, "dew": false, "abrasive": 0.5,
		"bowlers": ["wizard"], "field": "attack", "balls": 18, "wickets": 3,
		"mode": "chase", "target": 9, "stars": [0, 0], "seed": 606,
	},
	{
		"name": "Old Ball, New Tricks",
		"blurb": "Over 52 on a dry, abrasive square. The ball is scuffed on one side and Oz is bowling at 145.",
		"tip": "Reverse swing! An old rough ball at pace swings TOWARDS the shiny side. Watch for late inswinging yorkers.",
		"format": "test", "day": 3, "overs": 52.0, "overcast": false, "dew": false, "abrasive": 0.9,
		"bowlers": ["oz"], "field": "attack", "balls": 18, "wickets": 3,
		"mode": "survive", "target": 0, "stars": [8, 14], "seed": 707,
	},
	{
		"name": "Dew Drop Inn",
		"blurb": "A night T20 chase. The outfield is wet, the ball is soap, and the spinners cannot grip it.",
		"tip": "Dew: no swing, no turn, the ball skids on. Free hit after a no-ball: you cannot be out, so swing hard!",
		"format": "t20", "day": 1, "overs": 10.0, "overcast": false, "dew": true, "abrasive": 0.3,
		"bowlers": ["tim", "barnaby", "wizard"], "field": "defend", "balls": 18, "wickets": 3,
		"mode": "chase", "target": 13, "stars": [0, 0], "seed": 808,
	},
	{
		"name": "Day Five Dust Bowl",
		"blurb": "Save the match. Four overs to survive on a crumbling Day 5 pitch with spin from both ends.",
		"tip": "Cracks make some balls shoot low or spit up. Footmarks outside the stumps turn square. Defend (J) and leave (no key).",
		"format": "test", "day": 5, "overs": 70.0, "overcast": false, "dew": false, "abrasive": 0.6,
		"bowlers": ["wizard", "tim"], "field": "attack", "balls": 24, "wickets": 4,
		"mode": "survive", "target": 0, "stars": [6, 12], "seed": 909,
	},
	{
		"name": "The Second New Ball",
		"blurb": "Over 79. The old ball is reversing, and after this over they take the shiny new one.",
		"tip": "Reverse swing first, then the new ball swings the conventional way again. Watch the shiny side flip back.",
		"format": "test", "day": 2, "overs": 79.0, "overcast": true, "dew": false, "abrasive": 0.9,
		"bowlers": ["oz", "zoltan", "banana", "zoltan"], "field": "attack", "balls": 24, "wickets": 3,
		"mode": "chase", "target": 13, "stars": [0, 0], "seed": 1010, "new_ball_after": 6,
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[i]


static func goal_text(l: Dictionary) -> String:
	if l.mode == "chase":
		return "Score %d off %d balls (%d wicket%s in hand)" % [l.target, l.balls, l.wickets, "" if int(l.wickets) == 1 else "s"]
	var spare := int(l.wickets) - 1
	if spare == 0:
		return "Survive %d balls without losing a wicket" % l.balls
	return "Survive %d balls, losing no more than %d wicket%s" % [l.balls, spare, "" if spare == 1 else "s"]
