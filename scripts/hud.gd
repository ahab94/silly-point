extends Control
## Everything on screen that isn't 3D: scoreboard, conditions meters, the
## ball cam, timing feedback, commentary, the review screens, menus and the
## touch controls. Built in code.
##
## Godot concept: a Control is a 2D UI node. Labels and Buttons are
## Controls; anything custom (meters, the ball cam, stars) is painted in
## `_draw()`, which Godot calls again whenever we `queue_redraw()`.

signal level_chosen(index: int)
signal start_pressed
signal retry_pressed
signal next_pressed
signal menu_pressed
signal review_pressed
signal walk_pressed

const INK := Color(0.08, 0.1, 0.14)
const CREAM := Color(0.98, 0.96, 0.9)
const PANEL := Color(0.05, 0.08, 0.12, 0.72)
const GOLD := Color(1.0, 0.8, 0.25)
const RED := Color(0.9, 0.25, 0.2)
const GREEN := Color(0.35, 0.85, 0.4)
const ORANGE := Color(1.0, 0.6, 0.15)
const BALL_RED := Color(0.72, 0.08, 0.08)

var show_touch := false
var mirror := false        # bowler's-end camera: the off side is on the left

var _score: Label
var _goal: Label
var _over_strip: Label
var _bowler: Label
var _cond: Label
var _big: Label
var _sub: Label
var _comm: Label
var _tip: Label
var _review: PanelContainer
var _review_label: Label
var _review_btn: Button
var _walk_btn: Button
var _drs: PanelContainer
var _drs_label: Label
var _card: PanelContainer
var _card_box: VBoxContainer
var _menu: PanelContainer
var _menu_grid: GridContainer
var _touch: Control
var _help: Label

var _cond_data := {}
var _ballcam := {}
var _ballcam_t := 0.0
var _timing_te := 0.0
var _timing_t := 0.0
var _timing_label := ""
var _big_t := 0.0
var _snick := -1.0
var _snick_t := 0.0
var _card_stars := -1
var _menu_stars := {}


func _ready() -> void:
	# A Control under a CanvasLayer has no parent Control to stretch to, so
	# follow the viewport's size ourselves.
	get_viewport().size_changed.connect(_fit)
	_fit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_score = _label(34, CREAM)
	_goal = _label(19, CREAM)
	_over_strip = _label(22, CREAM)
	_bowler = _label(19, CREAM)
	_cond = _label(17, CREAM)
	_big = _label(64, CREAM, true)
	_sub = _label(26, CREAM, true)
	_comm = _label(22, CREAM, true)
	_tip = _label(20, GOLD, true)
	for l in [_big, _sub, _comm, _tip]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_review()
	_build_drs()
	_build_card()
	_build_menu()
	_build_touch()
	resized.connect(_layout)
	_layout()


func _label(size_px: int, col: Color, outline := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8 if outline else 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.36, 0.2)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = CREAM
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.48, 0.27)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.1, 0.28, 0.16)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", CREAM)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.1, 0.13, 0.93)
	panel.set_corner_radius_all(16)
	panel.set_border_width_all(3)
	panel.border_color = Color(0.9, 0.85, 0.7)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", CREAM)
	return t


func _button(text: String, parent: Node, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- in-play HUD

func set_score(runs: int, wkts: int, balls: int, total: int, goal: String, strip: Array) -> void:
	_score.text = "%d/%d" % [runs, wkts]
	_goal.text = "Ball %d of %d\n%s" % [mini(balls + 1, total), total, goal]
	_over_strip.text = "This over:  " + "  ".join(strip)


func set_bowler(name: String, style: String, last: String) -> void:
	_bowler.text = "%s\n%s%s" % [name, style, ("\nLast ball: " + last) if last != "" else ""]


## Conditions panel: pitch, weather, and meters for the ball's shine and
## roughness, plus a hint when it has started to reverse.
func set_conditions(c, overs_label: String, reversing: bool) -> void:
	var weather := "Sunny"
	if c.overcast:
		weather = "Overcast: swing helped"
	if c.dew:
		weather = "Dew: wet ball, no grip"
	_cond.text = "%s\n%s\nBall: %s old" % [c.describe_pitch(), weather, overs_label]
	_cond_data = {"shine": c.shine(), "rough": c.roughness(), "hard": c.hardness(), "rev": reversing}
	queue_redraw()


## The ball cam: a close-up of the ball in the bowler's hand at release.
## Pace: the seam angle and which side is shiny. Spin: which way it spins.
func show_ball_cam(d: Dictionary, seconds: float) -> void:
	_ballcam = d
	_ballcam_t = seconds
	queue_redraw()


func flash(text: String, sub: String = "", col: Color = CREAM, seconds := 1.6) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", col)
	_sub.text = sub
	_big_t = seconds
	_big.visible = true
	_sub.visible = true


func timing(te: float, label: String) -> void:
	_timing_te = te
	_timing_label = label
	_timing_t = 1.8
	queue_redraw()


func commentary(text: String) -> void:
	_comm.text = text


func tip(text: String) -> void:
	_tip.text = text
	queue_redraw()


func snicko(spike: float) -> void:
	_snick = spike
	_snick_t = 3.0
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	for k in ["_ballcam_t", "_timing_t", "_snick_t"]:
		var v: float = get(k)
		if v > 0.0:
			set(k, v - delta)
			dirty = true
	if _big_t > 0.0:
		_big_t -= delta
		if _big_t <= 0.0:
			_big.visible = false
			_sub.visible = false
	if dirty:
		queue_redraw()
	if show_touch and _touch.visible:
		_touch.queue_redraw()


func set_play_visible(on: bool) -> void:
	for l in [_score, _goal, _over_strip, _bowler, _cond, _comm, _tip]:
		l.visible = on
	_touch.visible = on and show_touch
	queue_redraw()


func _draw() -> void:
	if not _score.visible:
		return
	var s := size
	# Panels behind the text blocks.
	draw_rect(Rect2(10, 10, 300, 128), PANEL)
	draw_rect(Rect2(s.x - 330, 10, 320, 160), PANEL)
	draw_rect(_bowler_rect(), PANEL)
	# Ball meters.
	if not _cond_data.is_empty():
		var x0 := s.x - 318.0
		var y0 := 104.0
		_meter(Vector2(x0, y0), "Shine", float(_cond_data.shine), GOLD)
		_meter(Vector2(x0, y0 + 20), "Rough", float(_cond_data.rough), ORANGE)
		_meter(Vector2(x0, y0 + 40), "Hard", float(_cond_data.hard), Color(0.6, 0.8, 1.0))
		if _cond_data.rev:
			draw_string(get_theme_default_font(), Vector2(x0 + 200, y0 + 14), "REVERSING", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ORANGE)
	if _ballcam_t > 0.0 and not _ballcam.is_empty():
		# Left side, clear of the batter and slips (right side on tall screens,
		# where the bowler panel sits under the scoreboard).
		_draw_ball_cam(Vector2(90.0, 330.0) if size.y > size.x else Vector2(90.0, 240.0), 52.0)
	if _tip.visible and _tip.text != "":
		# A dark panel behind the tip so it reads over the crowd.
		var tr := Rect2(_tip.position - Vector2(14, 8), Vector2(_tip.size.x + 28, _tip.get_minimum_size().y + 16))
		draw_rect(tr, PANEL)
	if _timing_t > 0.0:
		# Above the touch controls on tall screens.
		_draw_timing(Vector2(s.x * 0.5, (s.y - 450.0) if (show_touch and s.y > s.x) else (s.y - 150.0)))
	if _snick_t > 0.0 and _snick >= 0.0:
		_draw_snicko(Vector2(s.x * 0.5 - 200, s.y * 0.5 + 120))


## Text with a dark outline so it reads over the sky or the grass.
func _text(p: Vector2, text: String, size_px: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, p, text, align, width, size_px, 6, INK)
	draw_string(font, p, text, align, width, size_px, col)


func _meter(p: Vector2, label: String, v: float, col: Color) -> void:
	var font := get_theme_default_font()
	draw_string(font, p + Vector2(0, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CREAM)
	draw_rect(Rect2(p + Vector2(56, 2), Vector2(130, 12)), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(p + Vector2(56, 2), Vector2(130 * clampf(v, 0.0, 1.0), 12)), col)


func _draw_ball_cam(c: Vector2, r: float) -> void:
	var font := get_theme_default_font()
	draw_circle(c, r + 8.0, PANEL)
	var d := _ballcam
	var spin: bool = d.style == "offspin" or d.style == "legspin"
	if not spin:
		# Shiny half bright and glossy, rough half dull and scuffed.
		var flip := -1 if mirror else 1
		var shiny: int = int(d.shiny_side) * flip
		var tilt := deg_to_rad(28.0) * float(d.seam_dir) * flip
		var seam_dir := Vector2(sin(tilt), -cos(tilt))
		var across := Vector2(seam_dir.y, -seam_dir.x) * -1.0    # points to +x when tilt is 0
		draw_circle(c, r, BALL_RED.darkened(0.35))
		var pts := PackedVector2Array()
		for i in 25:
			var a := -PI * 0.5 + PI * float(i) / 24.0
			var v := seam_dir.rotated(a + PI * 0.5) if shiny > 0 else seam_dir.rotated(a - PI * 0.5)
			pts.append(c + v * r)
		pts.append(c)
		draw_colored_polygon(pts, BALL_RED.lightened(0.15))
		var glint := c + across * float(shiny) * r * 0.45 + Vector2(0, -r * 0.35)
		draw_circle(glint, r * 0.16, Color(1, 1, 1, 0.7))
		# Scuffs on the rough half.
		for k in 7:
			var off := across * float(-shiny) * r * (0.2 + 0.09 * k) + seam_dir * r * (0.5 - 0.15 * k)
			draw_line(c + off, c + off + Vector2(6, 3), Color(0.35, 0.15, 0.1), 2.0)
		draw_line(c - seam_dir * r, c + seam_dir * r, CREAM, 4.0)
		_text(c + Vector2(-110, r + 32), "SHINY SIDE %s" % ("OFF" if int(d.shiny_side) > 0 else "LEG"), 18, GOLD, 220, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		draw_circle(c, r, BALL_RED)
		var sd: int = int(d.spin_dir) * (-1 if mirror else 1)
		draw_line(c + Vector2(0, -r), c + Vector2(0, r), CREAM, 4.0)
		if sd != 0:
			# Arrow curling the way it will turn.
			var start := PI * (0.15 if sd > 0 else 0.85)
			var pts := PackedVector2Array()
			for i in 13:
				var a := start + (PI * 0.7) * float(i) / 12.0 * float(sd) * -1.0
				pts.append(c + Vector2(cos(a), -sin(a)) * (r + 2.0))
			draw_polyline(pts, GOLD, 5.0)
			var tip_p := pts[pts.size() - 1]
			draw_circle(tip_p, 7.0, GOLD)
			_text(c + Vector2(-110, r + 32), "TURNS TO %s" % ("OFF" if int(d.spin_dir) > 0 else "LEG"), 18, GOLD, 220, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			draw_circle(c, r * 0.3, CREAM)
			_text(c + Vector2(-110, r + 32), "STRAIGHT ON", 18, GOLD, 220, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_timing(c: Vector2) -> void:
	var w := 320.0
	draw_rect(Rect2(c.x - w * 0.5 - 6, c.y - 30, w + 12, 54), PANEL)
	draw_rect(Rect2(c.x - w * 0.5, c.y, w, 12), Color(1, 1, 1, 0.15))
	# The green "Perfect" zone, to scale with batting.gd's PERFECT (0.035 s
	# of a 0.16 s half-width).
	draw_rect(Rect2(c.x - 35, c.y, 70, 12), Color(0.35, 0.85, 0.4, 0.8))
	var font := get_theme_default_font()
	draw_string(font, Vector2(c.x - w * 0.5, c.y - 6), "EARLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)
	draw_string(font, Vector2(c.x + w * 0.5 - 34, c.y - 6), "LATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)
	var x := c.x - clampf(_timing_te / 0.16, -1.0, 1.0) * w * 0.5
	draw_rect(Rect2(x - 3, c.y - 6, 6, 24), GOLD)
	draw_string(font, Vector2(c.x - 100, c.y - 8), _timing_label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, GOLD)


func _draw_snicko(p: Vector2) -> void:
	var w := 400.0
	draw_rect(Rect2(p - Vector2(10, 40), Vector2(w + 20, 110)), PANEL)
	var font := get_theme_default_font()
	draw_string(font, p + Vector2(0, -16), "SNICK-O-SCOPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 120:
		var x := float(i) / 119.0
		var amp := rng.randf_range(-3.0, 3.0)
		if _snick > 0.0 and absf(x - 0.5) < 0.05:
			amp *= 1.0 + 10.0 * _snick * (1.0 - absf(x - 0.5) / 0.05)
		pts.append(p + Vector2(x * w, 30 + amp))
	draw_polyline(pts, GREEN, 2.0)


# ---------------------------------------------------------------- review

func _build_review() -> void:
	_review = PanelContainer.new()
	add_child(_review)
	var v := VBoxContainer.new()
	_review.add_child(v)
	_review_label = Label.new()
	_review_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_review_label)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	_review_btn = _button("Review (R)", h, func() -> void: review_pressed.emit())
	_walk_btn = _button("Walk off (Enter)", h, func() -> void: walk_pressed.emit())
	_review.visible = false


func ask_review(how: String, reviews_left: int) -> void:
	_review_btn.text = "REVIEW" if show_touch else "Review (R)"
	_walk_btn.text = "Walk off" if show_touch else "Walk off (Enter)"
	_review_label.text = "OUT! %s\nReview it? %d review%s left" % [how, reviews_left, "" if reviews_left == 1 else "s"]
	_review.visible = true
	_layout()


func hide_review() -> void:
	_review.visible = false


func _build_drs() -> void:
	_drs = PanelContainer.new()
	add_child(_drs)
	_drs_label = Label.new()
	_drs_label.add_theme_font_size_override("font_size", 22)
	_drs.add_child(_drs_label)
	_drs.visible = false


func show_drs(rows: Array, verdict: String, title := "PIGEON-EYE BALL TRACKING") -> void:
	var lines := [title]
	for r in rows:
		lines.append("%-10s %s" % [r[0], r[1]])
	if verdict != "":
		lines.append("")
		lines.append(verdict)
	_drs_label.text = "\n".join(lines)
	_drs.visible = true
	_layout()


func hide_drs() -> void:
	_drs.visible = false


# ---------------------------------------------------------------- cards and menu

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(620, 0)
	add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 12)
	_card.add_child(_card_box)
	_card.draw.connect(_draw_card_stars)
	_card.visible = false


func _clear_card() -> void:
	for ch in _card_box.get_children():
		ch.queue_free()
	_card_stars = -1


func _card_label(text: String, size_px: int, col := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_box.add_child(l)
	return l


func show_intro(index: int, level: Dictionary, goal: String) -> void:
	_clear_card()
	set_play_visible(false)      # no leftover scoreboard from the last match
	_card_label("Match %d" % (index + 1), 18, GOLD)
	_card_label(level.name, 40)
	_card_label(level.blurb, 21)
	_card_label(goal, 22, GOLD)
	_card_label("Tip: " + level.tip, 19, Color(0.8, 0.9, 1.0))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	_card_box.add_child(h)
	_button("Bat!" if show_touch else "Bat! (Enter)", h, func() -> void: start_pressed.emit())
	_button("Menu", h, func() -> void: menu_pressed.emit())
	_card.visible = true
	_menu.visible = false
	_layout.call_deferred()


func show_result(won: bool, stars: int, title: String, summary: String, has_next: bool) -> void:
	_clear_card()
	_card_label(title, 44, GREEN if won else RED)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60 if won else 0)
	_card_box.add_child(spacer)
	_card_label(summary, 22)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	_card_box.add_child(h)
	_button("Retry" if show_touch else "Retry (R)", h, func() -> void: retry_pressed.emit())
	if won and has_next:
		_button("Next" if show_touch else "Next (Enter)", h, func() -> void: next_pressed.emit())
	_button("Menu", h, func() -> void: menu_pressed.emit())
	_card_stars = stars if won else -1
	_card.visible = true
	_layout.call_deferred()
	_card.queue_redraw()


func hide_card() -> void:
	_card.visible = false


func _draw_card_stars() -> void:
	if _card_stars < 0:
		return
	var cx := _card.size.x * 0.5
	for i in 3:
		_star(_card, Vector2(cx + (i - 1) * 64.0, 104.0), 26.0, GOLD if i < _card_stars else Color(1, 1, 1, 0.18))


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_menu.add_child(v)
	var title := Label.new()
	title.text = "SILLY POINT"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Old balls. Cracked pitches. Reverse swing. Just bat."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_menu_grid = GridContainer.new()
	_menu_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_grid.columns = 2     # 1 on tall screens (see _layout)
	_menu_grid.add_theme_constant_override("h_separation", 12)
	_menu_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_menu_grid)
	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 16)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(620, 0)
	v.add_child(_help)
	_menu.visible = false


const HELP_KEYS := "W A S D (or arrows): shot direction and footwork  |  J defend  K ground shot  L lofted  I sweep\nNo key: leave it  |  Shift: charge down the pitch  |  R: review  |  C: camera  |  Esc: menu"
const HELP_TOUCH := "Stick: up = front foot, down = back foot, left/right = leg or off side.\nHIT, LOFT, BLOCK or SWEEP as the ball arrives. Tap nothing to leave it. CHARGE dances down the pitch."


func show_menu(levels: Array, best: Dictionary) -> void:
	_help.text = HELP_TOUCH if show_touch else HELP_KEYS
	for ch in _menu_grid.get_children():
		ch.queue_free()
	_menu_stars = best
	for i in levels.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, levels[i].name]
		b.custom_minimum_size = Vector2(380, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func() -> void: level_chosen.emit(idx))
		var stars := int(best.get(i, 0))
		b.draw.connect(func() -> void:
			for k in 3:
				_star(b, Vector2(b.size.x - 80 + k * 26, b.size.y * 0.5), 10.0, GOLD if k < stars else Color(1, 1, 1, 0.2)))
		_menu_grid.add_child(b)
	_menu.visible = true
	_card.visible = false
	set_play_visible(false)
	_layout.call_deferred()


# ---------------------------------------------------------------- touch controls

## A virtual 8-way stick on the left (direction and footwork) and shot
## buttons on the right. They press the same input actions as the keys.
## Touch buttons: [action, label, radius, offset]. Offsets are from the
## bottom-right corner (CAM's is from the top-right). HIT is the big one
## under the thumb; the rarer ones sit further away.
const TOUCH_LAYOUT := {
	"shot_attack": [66.0, Vector2(-95, -95)], "shot_defend": [52.0, Vector2(-240, -72)],
	"shot_loft": [52.0, Vector2(-88, -252)], "shot_sweep": [44.0, Vector2(-222, -205)],
	"dance": [40.0, Vector2(-345, -150)], "camera": [30.0, Vector2(-60, 215)],
	"menu": [30.0, Vector2(-130, 215)],
}
const TOUCH_SHOTS := [["shot_defend", "BLOCK"], ["shot_attack", "HIT"], ["shot_loft", "LOFT"], ["shot_sweep", "SWEEP"], ["dance", "CHARGE"], ["camera", "CAM"], ["menu", "MENU"]]
var _stick_center := Vector2.ZERO
var _stick_touch := -1
var _stick_vec := Vector2.ZERO
var _buttons: Array = []


func _build_touch() -> void:
	_touch = Control.new()
	_touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch.draw.connect(_draw_touch)
	add_child(_touch)
	for s in TOUCH_SHOTS:
		var b := TouchScreenButton.new()
		var circle := CircleShape2D.new()
		circle.radius = float(TOUCH_LAYOUT[s[0]][0]) * 1.15   # a little bigger than drawn, for thumbs
		b.shape = circle
		b.shape_centered = true
		b.action = s[0]
		b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		_touch.add_child(b)
		_buttons.append(b)
	_touch.visible = false


func _input(event: InputEvent) -> void:
	if not (_touch.visible and show_touch):
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _stick_touch < 0 and st.position.distance_to(_stick_center) < 150.0:
			_stick_touch = st.index
			_update_stick(st.position)
		elif not st.pressed and st.index == _stick_touch:
			_stick_touch = -1
			_update_stick(_stick_center)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_touch:
			_update_stick(sd.position)


func _update_stick(p: Vector2) -> void:
	_stick_vec = (p - _stick_center).limit_length(80.0)
	var n := _stick_vec / 80.0
	_set_action("dir_up", n.y < -0.4)
	_set_action("dir_down", n.y > 0.4)
	_set_action("dir_left", n.x < -0.4)
	_set_action("dir_right", n.x > 0.4)


func _set_action(a: String, on: bool) -> void:
	if on and not Input.is_action_pressed(a):
		Input.action_press(a)
	elif not on and Input.is_action_pressed(a):
		Input.action_release(a)


func _draw_touch() -> void:
	var font := get_theme_default_font()
	_touch.draw_circle(_stick_center, 95.0, Color(0, 0, 0, 0.3))
	_touch.draw_arc(_stick_center, 95.0, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	_touch.draw_circle(_stick_center + _stick_vec, 40.0, Color(1, 1, 1, 0.55))
	_touch.draw_string(font, _stick_center + Vector2(-60, -105), "FRONT FOOT", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, CREAM)
	_touch.draw_string(font, _stick_center + Vector2(-60, 120), "BACK FOOT", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, CREAM)
	for i in _buttons.size():
		var b: TouchScreenButton = _buttons[i]
		var col := Color(0.15, 0.45, 0.25, 0.85 if b.is_pressed() else 0.55)
		var r: float = TOUCH_LAYOUT[TOUCH_SHOTS[i][0]][0]
		if TOUCH_SHOTS[i][0] == "shot_attack":
			col = Color(0.75, 0.45, 0.1, 0.9 if b.is_pressed() else 0.65)
		_touch.draw_circle(b.position, r, col)
		_touch.draw_arc(b.position, r, 0, TAU, 32, CREAM, 2.0)
		var fs := 22 if r > 60.0 else (17 if r > 35.0 else 13)
		_touch.draw_string(font, b.position + Vector2(-r, fs * 0.38), TOUCH_SHOTS[i][1], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, CREAM)


# ---------------------------------------------------------------- layout

## Bottom-left normally; top-centre on touch screens, where the stick lives
## in the bottom-left corner.
func _bowler_rect() -> Rect2:
	if size.y > size.x:
		return Rect2(10.0, 145.0, 300.0, 102.0)     # tall screen: under the scoreboard
	if show_touch:
		return Rect2(size.x * 0.5 - 165.0, 10.0, 330.0, 102.0)
	return Rect2(10.0, size.y - 112.0, 330.0, 102.0)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _layout() -> void:
	if _menu == null or _touch == null:
		return
	var s := size
	var cols := 1 if s.y > s.x else 2
	if _menu_grid.columns != cols:
		_menu_grid.columns = cols
		_layout.call_deferred()     # containers resize next frame; centre again then
	_score.position = Vector2(24, 14)
	_goal.position = Vector2(24, 62)
	_goal.size.x = 280
	_over_strip.position = Vector2(s.x * 0.5 - 150, s.y - 46)
	if show_touch and s.y > s.x:
		_over_strip.position = Vector2(30.0, s.y - 330.0)
	_bowler.position = _bowler_rect().position + Vector2(12, 6)
	_cond.position = Vector2(s.x - 318, 18)
	_big.size = Vector2(s.x, 90)
	_big.position = Vector2(0, s.y * 0.3)
	_sub.size = Vector2(s.x, 40)
	_sub.position = Vector2(0, s.y * 0.3 + 86)
	_comm.size = Vector2(clampf(s.x - 720.0, 300.0, 900.0), 40)
	_comm.position = Vector2((s.x - _comm.size.x) * 0.5, s.y - 112)
	if show_touch and s.y > s.x:
		# Tall screen: the controls own the bottom, so commentary sits above them.
		_comm.size.x = s.x - 60.0
		_comm.position = Vector2(30.0, s.y - 400.0)
	_tip.size = Vector2(clampf(s.x - 700, 300, 640), 40)
	_tip.position = Vector2((s.x - _tip.size.x) * 0.5, 190)
	if s.y > s.x:
		_tip.size = Vector2(s.x - 80.0, 40)
		_tip.position = Vector2(40.0, 275.0)     # below the bowler panel
	for p in [_card, _menu, _review]:
		p.reset_size()
		p.position = (s - p.size) * 0.5
	_drs.reset_size()
	_drs.position = Vector2(s.x - _drs.size.x - 20, s.y * 0.5 - _drs.size.y * 0.5)
	_stick_center = Vector2(150, s.y - 150)
	for i in _buttons.size():
		var off: Vector2 = TOUCH_LAYOUT[TOUCH_SHOTS[i][0]][1]
		_buttons[i].position = Vector2(s.x + off.x, (off.y if off.y > 0.0 else s.y + off.y))
	var br := _bowler_rect()
	_bowler.position = br.position + Vector2(12, 6)
