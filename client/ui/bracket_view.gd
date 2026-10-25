class_name BracketView
extends Control
## Turneringstreet for utslag: én kolonne per runde, hver kamp som en boks med de to navnene
## (vinneren uthevet, finalevinneren i gull, ditt eget navn i blått) og streker videre til neste runde.
## Runder som ikke er trukket ennå, vises med tomme bokser, så hele treet synes fra start.
## Kolonnene deler bredden. Er det for trangt, blir treet bredere enn kortet (legg det i en ScrollContainer).

const BOX_H := 46.0
const GAP_Y := 12.0
const GAP_X := 18.0
const HEAD := 24.0
const MIN_COL := 92.0
const MAX_COL := 170.0
const FONT_SIZE := 13
const GOLD := Color("ffd76a")
const YOU := Color("8fb4ff")   ## navnet ditt

var rounds: Array = []
var you := 0      ## bruker-id til den som ser på: navnet og kampen markeres
var _first := 1   ## kamper i første runde
var _cols := 1
static var _styles := {}


func _init(p_rounds: Array, p_you := 0) -> void:
	rounds = p_rounds
	you = p_you
	_first = maxi(1, (rounds[0] as Array).size()) if not rounds.is_empty() else 1
	var n := _first
	while n > 1:
		n = (n + 1) / 2
		_cols += 1
	custom_minimum_size = Vector2(_cols * MIN_COL + (_cols - 1) * GAP_X, HEAD + _first * (BOX_H + GAP_Y) - GAP_Y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var font := get_theme_default_font()
	var col_w := clampf((size.x - (_cols - 1) * GAP_X) / _cols, MIN_COL, MAX_COL)
	var x0 := maxf(0.0, (size.x - (_cols * col_w + (_cols - 1) * GAP_X)) * 0.5)
	# Midten av hver kamp: første runde jevnt fordelt, senere runder midt mellom de to kampene før.
	var centers := []
	for r in _cols:
		var ys := []
		var count := _first if r == 0 else ((centers[r - 1] as Array).size() + 1) / 2
		for i in count:
			if r == 0:
				ys.append(HEAD + i * (BOX_H + GAP_Y) + BOX_H * 0.5)
			else:
				var prev: Array = centers[r - 1]
				ys.append((prev[i * 2] + prev[mini(i * 2 + 1, prev.size() - 1)]) * 0.5)
		centers.append(ys)
	for r in _cols:
		var x := x0 + r * (col_w + GAP_X)
		draw_string(font, Vector2(x + 2, 15), _fit(font, round_name(r, _cols), col_w, 12), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 12, UI.MUTED)
		for i in (centers[r] as Array).size():
			var y: float = centers[r][i]
			var m: Dictionary = rounds[r][i] if r < rounds.size() and i < (rounds[r] as Array).size() else {}
			if r < _cols - 1:
				var ny: float = centers[r + 1][i / 2]
				var mid := x + col_w + GAP_X * 0.5
				var done := int(m.get("winner", 0)) != 0
				draw_polyline(PackedVector2Array([Vector2(x + col_w, y), Vector2(mid, y), Vector2(mid, ny),
					Vector2(x + col_w + GAP_X, ny)]), Color(UI.ACCENT, 0.8) if done else UI.BORDER.lightened(0.15), 1.5, true)
			_draw_match(font, Rect2(x, y - BOX_H * 0.5, col_w, BOX_H), m, r == _cols - 1)


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
			_fit(font, name, rect.size.x - 16, FONT_SIZE), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	if m.get("status") == "playing":
		draw_circle(Vector2(rect.end.x - 8, rect.position.y + 8), 3.0, UI.SUCCESS)


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
