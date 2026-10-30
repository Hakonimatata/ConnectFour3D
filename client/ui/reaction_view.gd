class_name ReactionView
extends Control
## En reaksjon fra en tilskuer (hjerte, flamme, latter eller «wow»), tegnet med kode.
## Spillets skrift har ikke emoji, så ikonene tegnes med polygoner og sirkler. Se Protocol.REACTIONS.

const FACE := Color("ffcf3a")
const FACE_DARK := Color("6b3d12")

var kind := "heart"


func _init(p_kind := "heart", px := 32.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	match kind:
		"heart":
			draw_colored_polygon(_heart(c + Vector2(0, s * 0.02), s * 0.46), Color("ff4d6d"))
			draw_circle(c + Vector2(-s * 0.17, -s * 0.15), s * 0.07, Color(1, 1, 1, 0.55))   # glans
		"fire":
			# Tre flammetunger i hverandre: rød ytterst, så oransje og gul innerst
			draw_colored_polygon(_flame(c + Vector2(0, s * 0.06), s * 0.46, 0.0), Color("ff3d1f"))
			draw_colored_polygon(_flame(c + Vector2(0, s * 0.15), s * 0.34, 0.6), Color("ff8a1f"))
			draw_colored_polygon(_flame(c + Vector2(0, s * 0.24), s * 0.21, 1.3), Color("ffd84a"))
		"laugh":
			_face(c, s)
			# Lukkede, smilende øyne (^ ^) og stor åpen munn
			for side in [-1, 1]:
				draw_arc(c + Vector2(side * s * 0.15, -s * 0.06), s * 0.08, PI * 1.1, PI * 1.9, 8, FACE_DARK, s * 0.05)
			var mouth := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				mouth.append(c + Vector2(cos(a) * s * 0.24, s * 0.06 + sin(a) * s * 0.2))
			draw_colored_polygon(mouth, FACE_DARK)
			draw_circle(c + Vector2(0, s * 0.2), s * 0.07, Color("ff6b6b"))   # tunge
			# Gledestårer
			for side in [-1, 1]:
				draw_circle(c + Vector2(side * s * 0.36, s * 0.02), s * 0.06, Color("7fd4ff"))
		"wow":
			_face(c, s)
			for side in [-1, 1]:
				draw_circle(c + Vector2(side * s * 0.14, -s * 0.08), s * 0.075, FACE_DARK)
				draw_arc(c + Vector2(side * s * 0.14, -s * 0.25), s * 0.08, PI * 1.15, PI * 1.85, 8, FACE_DARK, s * 0.04)
			draw_circle(c + Vector2(0, s * 0.19), s * 0.1, FACE_DARK)   # åpen munn: «oi!»


func _face(c: Vector2, s: float) -> void:
	draw_circle(c, s * 0.46, FACE)
	draw_arc(c, s * 0.46, 0, TAU, 32, Color("e0a420"), s * 0.03)


static func _heart(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		pts.append(c + Vector2(x, -y - 2.0) * r / 17.0)
	return pts


## En flammetunge: rund nederst, med bølgete sider som smalner til en spiss som bøyer seg litt.
static func _flame(c: Vector2, r: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 28
	for i in n:
		var t := float(i) / n   # 0 = spissen, venstre side ned, rundt bunnen, høyre side opp
		var a := t * TAU
		var y := -cos(a) * r                                  # -r øverst, r nederst
		var h := (y + r) / (2.0 * r)                          # 0 øverst, 1 nederst
		var width := r * 0.72 * pow(h, 0.7) * (1.0 + 0.12 * sin(h * 9.0 + phase))
		var x := -sin(a) * width + (1.0 - h) * (1.0 - h) * r * 0.25   # spissen bøyer seg mot høyre
		pts.append(c + Vector2(x, y))
	return pts


## Lar en reaksjon fly opp og forsvinne fra et punkt i parent (brukes i spillskjermen).
static func float_up(parent: Control, kind: String, from: Vector2) -> void:
	var r := ReactionView.new(kind, 34)
	r.size = Vector2(34, 34)
	r.position = from + Vector2(randf_range(-24, 24), 0)
	r.pivot_offset = r.size * 0.5
	parent.add_child(r)
	var t := r.create_tween().set_parallel()
	t.tween_property(r, "position:y", from.y - randf_range(150, 230), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(r, "position:x", r.position.x + randf_range(-30, 30), 1.8)
	t.tween_property(r, "scale", Vector2.ONE * 1.25, 0.25).from(Vector2.ONE * 0.4).set_trans(Tween.TRANS_BACK)
	t.tween_property(r, "modulate:a", 0.0, 0.6).set_delay(1.2)
	t.chain().tween_callback(r.queue_free)
