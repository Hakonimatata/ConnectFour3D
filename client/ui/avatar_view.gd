class_name AvatarView
extends Control
## Rundt profilbilde med en tynn ring i spillerens farge.
## Uten bilde vises forbokstaven i navnet på en farget sirkel.

var texture: Texture2D
var initial := "?"
var color := Color("6a83b8")      ## Ringfarge og bakgrunn når det ikke er bilde
var ring := true


func _init(diameter := 36.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Oppdaterer bildet (base64 fra AvatarData), navnet (for forbokstav) og fargen.
func set_avatar(avatar_b64: String, name: String, p_color: Color) -> void:
	texture = AvatarData.to_texture(avatar_b64)
	initial = name.strip_edges().left(1).to_upper() if name.strip_edges() != "" else "?"
	color = p_color
	queue_redraw()


func _draw() -> void:
	var d := minf(size.x, size.y)
	var c := size / 2.0
	var r := d / 2.0 - (1.5 if ring else 0.0)
	if texture:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			var dir := Vector2(cos(a), sin(a))
			pts.append(c + dir * r)
			uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
		draw_colored_polygon(pts, Color.WHITE, uvs, texture)
	else:
		draw_circle(c, r, color.darkened(0.25), true, -1.0, true)
		var font := get_theme_default_font()
		var fs := int(d * 0.48)
		var text_size := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-text_size.x / 2.0, text_size.y * 0.32), initial,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if ring:
		draw_arc(c, r + 0.5, 0.0, TAU, 48, color, 2.0, true)
