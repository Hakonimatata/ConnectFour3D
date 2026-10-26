class_name BracketView
extends Control
## Turneringstreet for utslag. Hver kamp er en boks med de to navnene (vinneren uthevet,
## finalevinneren i gull, ditt eget navn i blått) og streker videre til neste runde.
## Runder som ikke er trukket ennå, vises med tomme bokser, så hele treet synes fra start.
##
## Er det plass, tegnes treet speilvendt: øvre halvdel av første runde til venstre, nedre til høyre,
## og finalen i midten med pokalen over. Ellers (smal skjerm) går treet fra venstre mot høyre, med
## pokalen over finalen. Trykk på en kamp som spilles nå (grønn kant) for å se på (watch_requested).

signal watch_requested(code: String)

const BOX_H := 46.0
const GAP_Y := 12.0
const GAP_X := 18.0
const HEAD := 24.0
const MIN_COL := 92.0
const MIRROR_MIN_COL := 90.0    ## smaleste kolonne før vi heller tegner treet fra venstre mot høyre
const MAX_COL := 170.0
const FONT_SIZE := 13
const GOLD := Color("ffd76a")
const YOU := Color("8fb4ff")   ## navnet ditt

var rounds: Array = []
var you := 0      ## bruker-id til den som ser på: navnet og kampen markeres
var mirrored := false
var _first := 1   ## kamper i første runde
var _cols := 1    ## antall runder (med de som ikke er trukket ennå)
var _boxes: Array = []    ## [{ rect, m, final }]
var _lines: Array = []    ## [{ points, done }]
var _heads: Array = []    ## [{ pos, text }]
var _trophy: TrophyView
static var _styles := {}


func _init(p_rounds: Array, p_you := 0, trophy: Variant = {}) -> void:
	rounds = p_rounds
	you = p_you
	_first = maxi(1, (rounds[0] as Array).size()) if not rounds.is_empty() else 1
	var n := _first
	while n > 1:
		n = (n + 1) / 2
		_cols += 1
	custom_minimum_size = Vector2(_cols * MIN_COL + (_cols - 1) * GAP_X, HEAD + _first * (BOX_H + GAP_Y) - GAP_Y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_trophy = TrophyView.new(trophy, 96, true)
	add_child(_trophy)
	resized.connect(_relayout)


func _ready() -> void:
	_relayout()


## Hvor bred treet må være for å tegnes speilvendt.
func mirror_width() -> float:
	var cols := 2 * _cols - 1
	return cols * MIRROR_MIN_COL + (cols - 1) * GAP_X


func _match(r: int, i: int) -> Dictionary:
	return rounds[r][i] if r < rounds.size() and i < (rounds[r] as Array).size() else {}


func _relayout() -> void:
	_boxes.clear()
	_lines.clear()
	_heads.clear()
	mirrored = _first >= 2 and size.x >= mirror_width()
	var height := _layout_mirrored() if mirrored else _layout_one_sided()
	if absf(custom_minimum_size.y - height) > 0.5:
		custom_minimum_size.y = height
	queue_redraw()


## Fra venstre mot høyre: runde 1 først, finalen til høyre med pokalen over.
func _layout_one_sided() -> float:
	var col_w := clampf((size.x - (_cols - 1) * GAP_X) / _cols, MIN_COL, MAX_COL)
	var x0 := maxf(0.0, (size.x - (_cols * col_w + (_cols - 1) * GAP_X)) * 0.5)
	var trophy_h := minf(96.0, col_w)
	var centers := _centers(_first, HEAD, _cols)
	# Plass til pokalen over finalen: skyv alt ned hvis finalen står for høyt
	var final_y: float = centers[_cols - 1][0]
	var shift := maxf(0.0, HEAD + trophy_h + 8.0 - (final_y - BOX_H * 0.5))
	for r in _cols:
		var x := x0 + r * (col_w + GAP_X)
		_heads.append({ "pos": Vector2(x + 2, 15), "text": round_name(r, _cols) })
		for i in (centers[r] as Array).size():
			var y: float = centers[r][i] + shift
			var m := _match(r, i)
			if r < _cols - 1:
				var ny: float = centers[r + 1][i / 2] + shift
				var mid := x + col_w + GAP_X * 0.5
				_lines.append({ "points": PackedVector2Array([Vector2(x + col_w, y), Vector2(mid, y), Vector2(mid, ny),
					Vector2(x + col_w + GAP_X, ny)]), "done": int(m.get("winner", 0)) != 0 })
			_boxes.append({ "rect": Rect2(x, y - BOX_H * 0.5, col_w, BOX_H), "m": m, "final": r == _cols - 1 })
	var fx := x0 + (_cols - 1) * (col_w + GAP_X)
	_place_trophy(Vector2(fx + col_w * 0.5, final_y + shift - BOX_H * 0.5 - 6.0), trophy_h)
	return HEAD + _first * (BOX_H + GAP_Y) - GAP_Y + shift


## Speilvendt: halve treet på hver side, finalen og pokalen i midten.
func _layout_mirrored() -> float:
	var cols := 2 * _cols - 1
	var col_w := clampf((size.x - (cols - 1) * GAP_X) / cols, MIRROR_MIN_COL, MAX_COL)
	var x0 := maxf(0.0, (size.x - (cols * col_w + (cols - 1) * GAP_X)) * 0.5)
	var half := _first / 2
	var trophy_h := minf(110.0, col_w * 1.05)
	var centers := _centers(half, HEAD, _cols - 1)   # én side (samme høyder på begge sider)
	var final_y: float = (centers[_cols - 2][0] if _cols >= 2 else HEAD + BOX_H * 0.5)
	var shift := maxf(0.0, HEAD + trophy_h + 8.0 - (final_y - BOX_H * 0.5))
	var col_x := func(c: int) -> float: return x0 + c * (col_w + GAP_X)
	for r in _cols - 1:
		var count := (centers[r] as Array).size()
		for side in 2:
			var c: int = r if side == 0 else cols - 1 - r
			var x: float = col_x.call(c)
			_heads.append({ "pos": Vector2(x + 2, 15), "text": round_name(r, _cols) })
			for i in count:
				var idx := i + side * count   # venstre: første halvdel, høyre: andre halvdel
				var y: float = centers[r][i] + shift
				var m := _match(r, idx)
				var ny: float = (centers[r + 1][i / 2] if r + 1 < _cols - 1 else final_y) + shift
				var edge := x + col_w if side == 0 else x
				var next_edge: float = x + col_w + GAP_X if side == 0 else x - GAP_X
				var mid := (edge + next_edge) * 0.5
				_lines.append({ "points": PackedVector2Array([Vector2(edge, y), Vector2(mid, y), Vector2(mid, ny),
					Vector2(next_edge, ny)]), "done": int(m.get("winner", 0)) != 0 })
				_boxes.append({ "rect": Rect2(x, y - BOX_H * 0.5, col_w, BOX_H), "m": m, "final": false })
	var fx: float = col_x.call(_cols - 1)
	_heads.append({ "pos": Vector2(fx + 2, 15), "text": round_name(_cols - 1, _cols) })
	_boxes.append({ "rect": Rect2(fx, final_y + shift - BOX_H * 0.5, col_w, BOX_H), "m": _match(_cols - 1, 0), "final": true })
	_place_trophy(Vector2(fx + col_w * 0.5, final_y + shift - BOX_H * 0.5 - 6.0), trophy_h)
	return HEAD + half * (BOX_H + GAP_Y) - GAP_Y + shift


## Midten av hver kamp, runde for runde: første runde jevnt fordelt, senere midt mellom de to før.
static func _centers(first: int, top: float, cols: int) -> Array:
	var centers := []
	for r in cols:
		var ys := []
		var count := first if r == 0 else ((centers[r - 1] as Array).size() + 1) / 2
		for i in count:
			if r == 0:
				ys.append(top + i * (BOX_H + GAP_Y) + BOX_H * 0.5)
			else:
				var prev: Array = centers[r - 1]
				ys.append((prev[i * 2] + prev[mini(i * 2 + 1, prev.size() - 1)]) * 0.5)
		centers.append(ys)
	return centers


## Pokalen står midt over finalen (bottom_center = midt på undersiden av pokalen).
func _place_trophy(bottom_center: Vector2, h: float) -> void:
	var w := h * TrophyView.W / TrophyView.H
	_trophy.custom_minimum_size = Vector2.ZERO
	_trophy.position = bottom_center - Vector2(w * 0.5, h)
	_trophy.size = Vector2(w, h)


func _draw() -> void:
	var font := get_theme_default_font()
	for h in _heads:
		draw_string(font, h.pos, h.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)
	for l in _lines:
		draw_polyline(l.points, Color(UI.ACCENT, 0.8) if l.done else UI.BORDER.lightened(0.15), 1.5, true)
	for b in _boxes:
		_draw_match(font, b.rect, b.m, b.final)


func _draw_match(font: Font, rect: Rect2, m: Dictionary, final: bool) -> void:
	var winner := int(m.get("winner", 0))
	var champion := final and winner != 0
	var mine: bool = you != 0 and you in [int(m.get("p1", 0)), int(m.get("p2", 0))] and m.get("status") != "done"
	var style := "gold" if champion else ("live" if m.get("status") == "playing" else ("mine" if mine else "normal"))
	draw_style_box(_style(style), rect)
	draw_line(Vector2(rect.position.x + 6, rect.get_center().y), Vector2(rect.end.x - 6, rect.get_center().y),
		Color(UI.BORDER, 0.9), 1.0)
	for slot in 2:
		var uid := int(m.get("p1" if slot == 0 else "p2", 0))
		var name := str(m.get("p1_name" if slot == 0 else "p2_name", "")) if not m.is_empty() else ""
		if name == "" or name == "—":
			name = "—" if not m.is_empty() and m.get("status") == "done" else "?"
		var won := winner != 0 and uid == winner
		var color := UI.TEXT if won or winner == 0 else Color(UI.MUTED, 0.75)
		if you != 0 and uid == you:
			color = YOU if won or winner == 0 else Color(YOU, 0.6)
		if won and champion:
			color = GOLD
		var top := rect.position.y + slot * rect.size.y * 0.5
		if won:
			draw_rect(Rect2(rect.position.x + 1, top + 4, 3, rect.size.y * 0.5 - 8), GOLD if champion else UI.ACCENT_HOVER)
		draw_string(font, Vector2(rect.position.x + 10, top + rect.size.y * 0.25 + FONT_SIZE * 0.36),
			_fit(font, name, rect.size.x - 20, FONT_SIZE), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	if m.get("status") == "playing":
		draw_circle(Vector2(rect.end.x - 8, rect.position.y + 8), 3.0, UI.SUCCESS)


## Trykk på en kamp som spilles nå: se på den.
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		var code := live_room_at(mb.position)
		if code != "":
			watch_requested.emit(code)
	elif event is InputEventMouseMotion:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if live_room_at(event.position) != "" \
			else Control.CURSOR_ARROW


## Romkoden til kampen som spilles nå på dette punktet, eller "".
func live_room_at(pos: Vector2) -> String:
	for b in _boxes:
		if (b.rect as Rect2).has_point(pos) and b.m.get("status") == "playing" and str(b.m.get("room", "")) != "":
			return str(b.m.room)
	return ""


## «Finale», «Semifinale», «Kvartfinale» eller «Runde N».
static func round_name(r: int, cols: int) -> String:
	var from_end := cols - 1 - r
	match from_end:
		0: return TranslationServer.translate("Finale")
		1: return TranslationServer.translate("Semifinale")
		2: return TranslationServer.translate("Kvartfinale")
	return TranslationServer.translate("Runde %d") % (r + 1)


## Korter teksten med «…» til den får plass.
static func _fit(font: Font, text: String, width: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		t = t.left(t.length() - 1)
	return t + "…"


static func _style(kind: String) -> StyleBoxFlat:
	if not _styles.has(kind):
		match kind:
			"gold": _styles[kind] = UI._box(Color("2a2617"), 8, Color("b8913a"), 0, 0)
			"live": _styles[kind] = UI._box(UI.PANEL_LIGHT, 8, UI.SUCCESS.darkened(0.2), 0, 0)
			"mine": _styles[kind] = UI._box(Color("1d2a42"), 8, YOU, 0, 0)
			_: _styles[kind] = UI._box(UI.PANEL_LIGHT, 8, UI.BORDER, 0, 0)
	return _styles[kind]
