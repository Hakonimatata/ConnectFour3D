class_name EvalBar
extends Control
## Stillingsmåleren («sjakkpila»): en stolpe i spillernes farger som viser hvem som leder og hvor mye,
## med vinnersjansen («62 %») eller «Seier om 3» på siden til den som leder. Brukes i reprisen
## (AI-analysen), av tilskuere og i treningen. Verdien glir over når den endres.

var colors := { 1: Color("2a90ff"), 2: Color("f2541b") }
var _value := 50.0          ## vinnersjansen til spiller 1 (%) som vises nå
var _target := 50.0
var _text := ""
var _leader := 0            ## 1 eller 2 leder (teksten står på den siden), 0 = jevnt
var _known := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Ny verdi: vinnersjansen til spiller 1 (0–100), teksten og hvem som leder.
func set_eval(p1_percent: float, text: String, leader: int) -> void:
	_target = clampf(p1_percent, 0.0, 100.0)
	if not _known:
		_value = _target
	_known = true
	_text = text
	_leader = leader
	queue_redraw()


## Ingen verdi ennå (analysen regner): grå stolpe med «…».
func set_unknown() -> void:
	_known = false
	_text = "…"
	_leader = 0
	queue_redraw()


## Ny stilling som ikke er vurdert ennå: forrige verdi blir stående, med «…».
func set_pending() -> void:
	_text = "…"
	_leader = 0
	queue_redraw()


func _process(delta: float) -> void:
	if absf(_value - _target) > 0.05:
		_value = lerpf(_value, _target, minf(1.0, delta * 8.0))
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var radius := size.y * 0.5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.11, 0.14, 0.85)
	bg.set_corner_radius_all(int(radius))
	draw_style_box(bg, r)
	if _known:
		var split := size.x * _value / 100.0
		_draw_part(Rect2(0, 0, split, size.y), colors[1], true)
		_draw_part(Rect2(split, 0, size.x - split, size.y), colors[2], false)
	# Midtstrek: 50 %
	draw_line(Vector2(size.x * 0.5, 2), Vector2(size.x * 0.5, size.y - 2), Color(1, 1, 1, 0.35), 1.0)
	if _text == "":
		return
	var font := get_theme_default_font()
	var fs := int(size.y * 0.62)
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (size.x - w) * 0.5
	if _leader == 1:
		x = 8.0
	elif _leader == 2:
		x = size.x - w - 8.0
	var y := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var c: Color = colors.get(_leader, Color(1, 1, 1))
	var ink := Color("15171c") if _leader != 0 and c.get_luminance() > 0.55 else Color(1, 1, 1)
	draw_string(font, Vector2(x + 1, y + 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.35 if ink.r > 0.5 else 0.0))
	draw_string(font, Vector2(x, y), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _draw_part(r: Rect2, c: Color, left: bool) -> void:
	if r.size.x <= 0.5:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = c
	var radius := int(size.y * 0.5)
	box.corner_radius_top_left = radius if left else 0
	box.corner_radius_bottom_left = radius if left else 0
	box.corner_radius_top_right = 0 if left else radius
	box.corner_radius_bottom_right = 0 if left else radius
	draw_style_box(box, r)
