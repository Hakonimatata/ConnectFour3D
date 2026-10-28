class_name ReactionView
extends Control
## En reaksjon fra en tilskuer (hjerte, stjerne, flamme eller lyn), tegnet med kode.
## Spillets skrift har ikke emoji, så ikonene tegnes som polygoner. Se Protocol.REACTIONS.

const COLORS := {
	"heart": Color("ff5277"), "star": Color("ffd23a"), "fire": Color("ff8a2a"), "bolt": Color("7fd4ff"),
}

var kind := "heart"


func _init(p_kind := "heart", px := 32.0) -> void:
	kind = p_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var color: Color = COLORS.get(kind, Color.WHITE)
	match kind:
		"heart":
			draw_colored_polygon(_heart(c, s * 0.46), color)
		"star":
			draw_colored_polygon(_star(c + Vector2(0, s * 0.03), s * 0.5, s * 0.21), color)
		"fire":
			draw_colored_polygon(_flame(c + Vector2(0, s * 0.08), s * 0.42), color)
			draw_colored_polygon(_flame(c + Vector2(0, s * 0.22), s * 0.22), Color("ffe25a"))
		"bolt":
			var pts := PackedVector2Array()
			for p in [Vector2(0.12, -0.5), Vector2(-0.3, 0.06), Vector2(-0.02, 0.06), Vector2(-0.14, 0.5),
					Vector2(0.3, -0.08), Vector2(0.03, -0.08), Vector2(0.18, -0.5)]:
				pts.append(c + p * s)
			draw_colored_polygon(pts, color)


static func _heart(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		pts.append(c + Vector2(x, -y - 2.0) * r / 17.0)
	return pts


static func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


## Dråpeform med spissen opp.
static func _flame(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		var x := sin(t) * r * 0.62 * (1.0 - 0.55 * (1.0 + cos(t)) * 0.5)
		var y := -cos(t) * r * 1.05
		pts.append(c + Vector2(x * (1.0 + 0.25 * sin(t * 2.0)), y))
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
