# Silly Point: notes for Claude

A 3D cricket batting game in Godot 4.7 (GDScript, Compatibility renderer, so it runs in the browser). README.md holds the design, the quirks and the roadmap.

## Run and check
- Play: `godot --path .`, or open the project in the editor and press F5.
- Every change: `bash checks/verify.sh` must end with `silly-point: all good` (about 10 s). It runs:
  - `tests/sim_test.gd`: physics and rules, e.g. "an old ball reverses" or "the googly turns the other way";
  - `tests/smoke_test.gd`;
  - `tests/game_test.gd`: real key presses, a leave, the charge window and a review;
  - `checks/autoplay.sh`: the expert autopilot must win every match.
- Difficulty: `bash checks/difficulty.sh [N] [skill]` runs the rookie bot N times per match. Win rates should fall steadily from match 1 to 10, from about 80% to about 25% at skill 0.6.
- Per-ball statistics for one match: `godot --headless --path . --script res://tests/stats.gd -- --level=N --n=400`. Extra options:
  - `--show`: where middled shots that scored no runs went;
  - `--misses`: bat errors on misses;
  - `--caught`: blocks that were caught.
- Dev flags go after `--`:
  - `--level=N` skips the menu.
  - `--autopilot` runs the expert bot. `--bot=leave` makes it leave every ball, which is good for LBWs and reviews.
  - `--rookie=SKILL` runs the human-ish bot.
  - `--seed=S` sets the innings seed.
  - `--trace` prints every ball with its sim time, delivery, shot, errors and result.
  - `--exit-on-end` prints `RESULT level=… won|lost runs=R/W balls=B stars=S`.
  - `--timeout=S` stops after S simulated seconds.
  - `--screenshot=path.png --wait=S` saves a frame (not headless).
  - `--touch` shows the touch controls. `--mute` silences sound. `--no-save` doesn't write progress.
  - Put `--fixed-fps 60` before `--` to run faster than real time.
- Each ball takes about 6–7 s of sim time. The first release is at 2.1 s (0.7 s pause plus 1.4 s run-up; spinners 0.9 s). Use `--trace` timestamps to aim screenshots.

## Layout
- Physics and rules (pure, deterministic, shared by the game and the bots):
  - `scripts/conditions.gd`: ball age, pitch day and weather. Swing balance (conventional minus reverse), grip, bounce, cracks, footmark rough.
  - `scripts/ball_sim.gd`: delivery integration, `naive_predict` (what a batter expects), and hit-ball flight. Coordinates: striker's stumps at the origin, the bowler comes from -z, +x is the off side.
  - `scripts/bowling.gd`: bowlers (all invented names) and `make()`, which turns a delivery kind plus conditions into sim numbers. Tuning constants are SWING_K, SEAM_K and TURN_DEG.
  - `scripts/batting.gd`: SHOTS table, `from_direction` (the Cricket 07 mapping) and `resolve` (timing, bat placement, edges, pad/body/bowled). Key ideas:
    - ADJUST is the fraction of late movement the bat can still follow;
    - "play with the movement" is the `cover` term;
    - driving on the up is the `over` term.
  - `scripts/fielding.gd`: field settings as polar coordinates, catches (with dive timing), ground fielding with misfields, and runs.
  - `scripts/umpire.gd`: LBW tracking, the on-field umpire (with noise), edges heard or missed.
  - `scripts/rules.gd`: one ball's outcome and `final_out` after reviews.
- `scripts/autopilot.gd`: `plan` (expert search over shots × directions × charge × timing) and `rookie` (the human-ish bot).
- `scripts/levels.gd`: the 10 matches as data (the format is at the top of the file).
- Presentation:
  - `scripts/game.gd`: the phase machine (PRE → RUNUP → FLIGHT → PLAY → DECIDE → REVIEW/DRS → BETWEEN → END). Also input, cameras, the tracking ghosts, saves (`user://progress.cfg`) and flags.
  - `scripts/stadium.gd`: the ground. The pitch texture is painted from the conditions.
  - `scripts/figures.gd`: people from primitives. `Batter` has tweened strokes, and its arms follow the bat each frame.
  - `scripts/hud.gd`: scoreboard, meters, ball cam, timing bar, Snick-o-Scope, review panels, menu and cards, touch stick and buttons.
  - `scripts/sound.gd` plays the files from `tools/make_audio.py`. Regenerate the audio with `/usr/bin/python3 tools/make_audio.py`.

## Conventions
- After changing physics, rules or levels: run verify, then the difficulty curve.
  - Tune outliers with each level's balls, target and wickets first.
  - Then change bowler skill and accuracy.
  - Change the physics constants last.
- The autopilot is clairvoyant, so it scores very fast. It is a winnability gate, not a balance measure.
- Text fonts lack symbol glyphs, so stars are drawn as polygons.
- Scripts reference each other with `preload`, not `class_name`. Inner classes preload their own file (`const F = preload(...)`).
- Never show real player, team, country or brand names. Bowlers, "Pigeon-Eye" and "Snick-o-Scope" are invented.
- The user is learning Godot, so explain new engine concepts briefly in comments.
