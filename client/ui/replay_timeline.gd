class_name ReplayTimeline
extends Control
## Tidslinjen i repriser: én bit per trekk i spillerens farge. Prikker over viser tvungne
## trekk (oransje), doble trusler (rød) og vinnertrekket (gull). Trykk eller dra for å hoppe.

signal seek_requested(ply: int)

const FORCED := Color("ffae42")
const DOUBLE := Color("ff5a5a")
const WIN := Color("ffd76a")

var entries: Array = []           ## fra GameAnalysis.timeline
var colors := { 1: Color.WHITE, 2: Color.WHITE }
var ply := 0:
	set(v):
		ply = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, 30)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var n := entries.size()
	if n == 0:
		return
	var w := size.x / n
	draw_rect(Rect2(0, 12, size.x, 10), UI.PANEL_LIGHT)
	for i in n:
		var e: Dictionary = entries[i]
		var x := i * w
		var c: Color = colors[int(e.player)]
		c.a = 1.0 if i < ply else 0.3
		draw_rect(Rect2(x + 0.5, 12, maxf(1.0, w - 1.0), 10), c)
		var mark := Color(0, 0, 0, 0)
		if e.won:
			mark = WIN
		elif e.double:
			mark = DOUBLE
		elif e.forced:
			mark = FORCED
		if mark.a > 0.0:
			draw_circle(Vector2(x + w * 0.5, 5), clampf(w * 0.35, 2.0, 4.0), mark)
	var cx := clampf(ply * w, 1.0, size.x - 1.0)
	draw_line(Vector2(cx, 8), Vector2(cx, 26), UI.TEXT, 2.0)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var x := -1.0
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		x = mb.position.x
	elif mm and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		x = mm.position.x
	if x < 0.0 or entries.is_empty():
		return
	var target := clampi(roundi(x / size.x * entries.size()), 0, entries.size())
	if target != ply:
		seek_requested.emit(target)
	accept_event()
