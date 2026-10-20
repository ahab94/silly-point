extends RefCounted
## One-line commentary for each kind of moment. Picked with the innings RNG
## so a replay says the same things.

const LINES := {
	"four": ["Cracking shot! That raced away.", "FOUR! The fielder just waved at it.", "Pure timing. No need to run for those.", "That's gone like a rumour in a dressing room."],
	"six": ["SIX! Somebody in row Z has a souvenir.", "That's out of the ground! Well, nearly.", "Enormous! The pigeons have scattered.", "Maximum! The bowler is staring at the sky."],
	"runs": ["Pushed into the gap, they scamper through.", "Good running between the wickets.", "Worked away nicely.", "Nudged, nurdled, accumulated."],
	"dot": ["Solid. Dead bat.", "Well left... or well blocked. Either way, nothing doing.", "Dot ball. The bowler nods approvingly.", "Respect the good ones."],
	"leave": ["Shouldered arms. Judged it perfectly.", "Leaves it alone. Very Test match.", "No interest in that one."],
	"beaten": ["Played and missed! That did a bit.", "Beaten! Lovely bit of bowling.", "Past the outside edge. Oooh.", "Squared up by that one."],
	"edge_safe": ["Edged... and it falls short!", "Thick edge, down to third man.", "Off the edge and away. Lucky!"],
	"bowled": ["BOWLED! Timber!", "Cleaned up! The stumps are doing cartwheels.", "Through the gate! Bat and pad had a gap you could drive a bus through."],
	"played_on": ["Dragged on! Bad luck, but that's out.", "Chopped on! The stumps had other plans."],
	"lbw": ["Big appeal... and the finger goes up!", "Trapped in front!"],
	"caught": ["Caught! Straight to the fielder.", "Taken! What a catch!", "In the air... and held!"],
	"caught_behind": ["Nicked it, and the keeper says thank you.", "Feather of an edge and gone!"],
	"stumped": ["Stumped! Charged down, missed, and the keeper had the bails off.", "Lured out and stumped. The spinner grins."],
	"hit_wicket": ["Hit wicket! Trod on the stumps going back. Oh dear.", "Knocked off the bails with the bat! Cricket's oddest dismissal."],
	"dropped": ["DROPPED! That should have been taken.", "Put down! The bowler can't believe it."],
	"helmet": ["Ouch! Right on the helmet. The physio jogs out.", "Hit on the badge. Shakes it off."],
	"body": ["Hit on the body. That'll leave a bruise.", "Takes one in the ribs."],
	"not_out_pad": ["Appeal... not out, says the umpire.", "Huge shout, turned down."],
	"overturned": ["OVERTURNED! Pigeon-Eye saves the day.", "The review says no. Back to batting!"],
	"stands": ["Decision stands. Off you go.", "Pigeon-Eye agrees with the umpire."],
	"umpires_call": ["Umpire's call! Cricket's way of saying 'it's complicated'.", "Clipping... so it stays with the umpire."],
	"no_ball": ["No-ball! Overstepped!", "NO BALL! Free runs."],
	"free_hit": ["FREE HIT! Can't be out bowled, caught or LBW. Swing away!"],
	"wide": ["Wide! Way down the leg side.", "Wide called. Too wide to reach."],
	"reverse": ["That's reversing! The shiny side has become the dangerous side."],
	"new_ball": ["The umpire hands over a shiny new ball. Here comes the swing."],
	"shooter": ["That one shot along the ground! A crack in the pitch.", "Kept horribly low."],
	"spitter": ["Spat up off a crack! Nasty.", "Leapt off a length. The pitch is misbehaving."],
}


static func line(kind: String, rng: RandomNumberGenerator) -> String:
	var opts: Array = LINES.get(kind, [""])
	return opts[rng.randi_range(0, opts.size() - 1)]
