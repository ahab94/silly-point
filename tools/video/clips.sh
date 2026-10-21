# Clip list for record_footage.sh: record <name> <WxH> <seconds> <game flags...>
# Seeds were picked by scanning innings with --log-events for the moment each
# video needs (e.g. "out bowled duck", "release googly", "verdict overturned").
P=1080x1920
L=1920x1080
record p-duck    $P 9   --level=1 --seed=10 --autopilot --bot=leave
record p-googly  $P 22  --level=8 --seed=1 --autopilot --bot=leave
record p-reverse $P 36  --level=6 --seed=2 --autopilot --bot=leave
record p-snicko  $P 57  --level=2 --rookie=0.7 --rookie-seed=5
record p-pigeon  $P 42  --level=9 --seed=28 --autopilot --bot=leave
record p-charge  $P 15  --level=4 --seed=3 --autopilot --bot=charge
record p-helmet  $P 99  --level=3 --seed=12 --autopilot --bot=leave
record p-sixes1  $P 30  --level=1 --autopilot
record p-sixes2  $P 26  --level=8 --autopilot
record p-dropped $P 35  --level=2 --seed=9 --rookie=0.7 --rookie-seed=2
record l-charge  $L 15  --level=4 --seed=3 --autopilot --bot=charge
record l-googly  $L 22  --level=8 --seed=1 --autopilot --bot=leave
record l-reverse $L 36  --level=6 --seed=2 --autopilot --bot=leave
record l-snicko  $L 57  --level=2 --rookie=0.7 --rookie-seed=5
record l-pigeon  $L 42  --level=9 --seed=28 --autopilot --bot=leave
record l-sixes1  $L 30  --level=1 --autopilot
record l-duck    $L 9   --level=1 --seed=10 --autopilot --bot=leave
