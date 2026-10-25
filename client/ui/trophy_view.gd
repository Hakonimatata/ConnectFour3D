class_name TrophyView
extends Control
## Tegner en pokal (se net/trophy.gd) i kode: sokkel med navneplate, stett, selve pokalen,
## hanker, et merke foran og glitter for de blanke metallene.
## Alt tegnes i en boks på 100 × 120 som skaleres til størrelsen.
## animate = pulserende glød bak og glitter som blinker (brukes for å hedre vinneren).

const W := 100.0
const H := 120.0

var design: Dictionary = {}
var animate := false:
	set(v):
		animate = v
		set_process(v)
var _time := 0.0


func _init(p_design: Variant = {}, height := 96.0, p_animate := false) -> void:
	design = Trophy.normalize(p_design)
	custom_minimum_size = Vector2(height * W / H, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	animate = p_animate


func _ready() -> void:
	set_process(animate)


func set_design(d: Variant) -> void:
	design = Trophy.normalize(d)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x / W, size.y / H)
	draw_set_transform((size - Vector2(W, H) * s) * 0.5, 0.0, Vector2(s, s))
	var m: Array = Trophy.METAL_COLORS[design.metal]
	var light := Color(m[0])
	var mid := Color(m[1])
	var dark := Color(m[2])
	if animate:
		_draw_glow(mid)
	_draw_base(mid, dark)
	_draw_stem(light, mid, dark)
	var emblem := _draw_body(light, mid, dark)
	_draw_emblem(emblem.pos, emblem.scale, mid, light, dark)
	if design.metal in Trophy.SPARKLY:
		_draw_sparkles(light)
	draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- Delene

func _draw_glow(mid: Color) -> void:
	var pulse := 1.0 + 0.45 * sin(_time * 2.2)
	for i in 6:
		draw_circle(Vector2(50, 44), 26.0 + i * 7.0, Color(mid, 0.045 * pulse))


func _draw_base(mid: Color, dark: Color) -> void:
	var c: Array = Trophy.BASE_COLORS[design.base]
	var top := Color(c[0])
	var bottom := Color(c[1])
	draw_polygon(PackedVector2Array([Vector2(31, 92), Vector2(69, 92), Vector2(72, 99), Vector2(28, 99)]),
		PackedColorArray([top.lightened(0.1), top.lightened(0.1), top, top]))
	draw_polygon(PackedVector2Array([Vector2(22, 99), Vector2(78, 99), Vector2(78, 116), Vector2(22, 116)]),
		PackedColorArray([top, top.lerp(bottom, 0.4), bottom, bottom.lerp(top, 0.25)]))
	_outline(PackedVector2Array([Vector2(22, 99), Vector2(78, 99), Vector2(78, 116), Vector2(22, 116)]),
		bottom.darkened(0.35))
	# Navneplaten
	var plate := PackedVector2Array([Vector2(37, 103), Vector2(63, 103), Vector2(63, 112), Vector2(37, 112)])
	draw_polygon(plate, PackedColorArray([mid.lightened(0.3), mid, dark, mid]))
	_outline(plate, dark.darkened(0.3))
	draw_line(Vector2(41, 106.5), Vector2(59, 106.5), Color(dark, 0.55), 0.8)
	draw_line(Vector2(43, 109), Vector2(57, 109), Color(dark, 0.4), 0.8)


func _draw_stem(light: Color, mid: Color, dark: Color) -> void:
	_metal(PackedVector2Array([Vector2(47.5, 60), Vector2(52.5, 60), Vector2(52.5, 78), Vector2(47.5, 78)]), light, mid, dark)
	_metal(PackedVector2Array([Vector2(43, 92), Vector2(57, 92), Vector2(52.5, 79), Vector2(47.5, 79)]), light, mid, dark)
	_metal(_ellipse(Vector2(50, 78), 7.5, 3.5), light, mid, dark)


## Tegner selve pokalen og gir hvor merket skal stå: { pos, scale }.
func _draw_body(light: Color, mid: Color, dark: Color) -> Dictionary:
	match design.shape:
		"chalice":
			var bowl := _bowl(14, 66, 21, 3, 1.35)
			_handles(29, 14, 0.85, light, mid, dark)
			_metal(bowl, light, mid, dark)
			var y1 := 33.0
			var y2 := 38.0
			var w1 := _bowl_half(14, 66, 21, 3, 1.35, y1)
			var w2 := _bowl_half(14, 66, 21, 3, 1.35, y2)
			draw_polygon(PackedVector2Array([Vector2(50 - w1, y1), Vector2(50 + w1, y1), Vector2(50 + w2, y2),
				Vector2(50 - w2, y2)]), PackedColorArray([dark, dark, dark, dark]))
			_rim(Vector2(50, 14), 21, light, mid, dark)
			_streak(Vector2(41, 18), Vector2(45, 46), light)
			return { "pos": Vector2(50, 49), "scale": 0.75 }
		"star":
			var star := _star(Vector2(50, 38), 31, 13.5)
			_metal(star, light, mid, dark)
			_metal(_star(Vector2(50, 38), 17, 7.5), light.lerp(mid, 0.3), light, mid, false)
			return { "pos": Vector2(50, 38), "scale": 0.7 }
		"orb":
			var ring := _ellipse(Vector2(50, 44), 36, 8.5, 40)
			var back := PackedVector2Array()
			var front := PackedVector2Array()
			for p in ring:
				(back if p.y <= 44.0 else front).append(p)
			draw_polyline(_sorted_x(back), dark, 3.0, true)
			_metal(_ellipse(Vector2(50, 42), 23, 23, 40), light, mid, dark)
			_streak(Vector2(40, 30), Vector2(38, 44), light)
			draw_polyline(_sorted_x(front), mid.lightened(0.15), 3.2, true)
			return { "pos": Vector2(50, 40), "scale": 0.95 }
		"obelisk":
			var ob := PackedVector2Array([Vector2(41, 72), Vector2(59, 72), Vector2(56, 22), Vector2(50, 7), Vector2(44, 22)])
			_metal(ob, light, mid, dark)
			draw_line(Vector2(50, 9), Vector2(50, 70), Color(dark, 0.35), 0.8)
			_streak(Vector2(46.5, 26), Vector2(45, 60), light)
			return { "pos": Vector2(50, 47), "scale": 0.7 }
		"crown":
			var crown := PackedVector2Array([Vector2(26, 68), Vector2(26, 28), Vector2(35, 42), Vector2(42.5, 20),
				Vector2(50, 36), Vector2(57.5, 20), Vector2(65, 42), Vector2(74, 28), Vector2(74, 68)])
			_metal(crown, light, mid, dark)
			draw_polygon(PackedVector2Array([Vector2(26, 52), Vector2(74, 52), Vector2(74, 55), Vector2(26, 55)]),
				PackedColorArray([dark, dark, dark, dark]))
			for tip in [Vector2(26, 27), Vector2(42.5, 19), Vector2(57.5, 19), Vector2(74, 27)]:
				draw_circle(tip, 3.4, mid)
				draw_circle(tip + Vector2(-1, -1), 1.4, light)
			return { "pos": Vector2(50, 61), "scale": 0.55 }
	# «cup»: klassisk pokal med vid skål
	var cup := _bowl(18, 70, 27, 4, 2.4)
	_handles(24, 18, 1.0, light, mid, dark)
	_metal(cup, light, mid, dark)
	_rim(Vector2(50, 18), 27, light, mid, dark)
	_streak(Vector2(37, 24), Vector2(41, 50), light)
	return { "pos": Vector2(50, 38), "scale": 1.0 }


func _rim(center: Vector2, half: float, light: Color, mid: Color, dark: Color) -> void:
	_metal(_ellipse(center, half, 4.0), light, mid, dark)
	draw_polygon(_ellipse(center + Vector2(0, 0.6), half - 3.0, 2.4), PackedColorArray([dark.darkened(0.25)]))


## Hanker på begge sider. edge = venstre kant av skålen øverst, top = skålens topp.
func _handles(edge: float, top: float, k: float, light: Color, mid: Color, dark: Color) -> void:
	for side in [-1.0, 1.0]:
		var x0 := edge if side < 0 else W - edge
		var mirror := func(p: Vector2) -> Vector2: return Vector2(x0 + (p.x - x0) * (1.0 if side < 0 else -1.0), p.y)
		match design.handles:
			"loop":
				var c: Vector2 = mirror.call(Vector2(x0 - 1.0, top + 15.0 * k))
				var from := PI * 0.5 if side < 0 else -PI * 0.5
				draw_arc(c, 11.0 * k, from, from + PI, 18, dark, 5.0, true)
				draw_arc(c, 11.0 * k, from, from + PI, 18, mid, 3.0, true)
			"wing":
				var pts := PackedVector2Array()
				for p in [Vector2(1, 4), Vector2(-18, -4), Vector2(-12, 10), Vector2(-21, 16), Vector2(-10, 22),
						Vector2(-15, 30), Vector2(3, 28)]:
					pts.append(mirror.call(Vector2(x0, top) + p * k))
				if side > 0:
					pts.reverse()
				_metal(pts, light, mid, dark)
			"angular":
				var line := PackedVector2Array()
				for p in [Vector2(1, 4), Vector2(-12, 4), Vector2(-12, 24), Vector2(6, 34)]:
					line.append(mirror.call(Vector2(x0, top) + p * k))
				draw_polyline(line, dark, 5.0, true)
				draw_polyline(line, mid, 3.0, true)


func _draw_emblem(c: Vector2, k: float, mid: Color, light: Color, dark: Color) -> void:
	var col := dark.darkened(0.2) if mid.get_luminance() > 0.45 else light
	var pts := func(list: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in list:
			out.append(c + p * k)
		return out
	match design.emblem:
		"four":
			# Fire på rad: fire brikker på skrå med en tynn linje gjennom
			draw_line(c + Vector2(-10, 8) * k, c + Vector2(10, -8) * k, Color(col, 0.45), 1.6 * k, true)
			for i in 4:
				draw_circle(c + Vector2(-9 + i * 6, 7 - i * 4.667) * k, 2.8 * k, col)
		"star":
			draw_polygon(_star(c, 9.5 * k, 4.2 * k), PackedColorArray([col]))
		"crown":
			draw_polygon(pts.call([Vector2(-9, 5), Vector2(-9, -4), Vector2(-4, 1), Vector2(0, -7), Vector2(4, 1),
				Vector2(9, -4), Vector2(9, 5)]), PackedColorArray([col]))
		"bolt":
			draw_polygon(pts.call([Vector2(2, -10), Vector2(-6, 1), Vector2(-1, 1), Vector2(-3, 10), Vector2(6, -2),
				Vector2(1, -2)]), PackedColorArray([col]))
		"one":
			var font := ThemeDB.fallback_font
			var fs := int(20 * k)
			draw_string(font, c + Vector2(-12 * k, fs * 0.36), "1", HORIZONTAL_ALIGNMENT_CENTER, 24 * k, fs, col)


func _draw_sparkles(light: Color) -> void:
	var spots := [Vector2(16, 14), Vector2(85, 22), Vector2(12, 58), Vector2(88, 60), Vector2(30, 5), Vector2(72, 6)]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(design.seed) + 17
	for i in 3:
		var p: Vector2 = spots[rng.randi() % spots.size()]
		var tw := 1.0 if not animate else 0.55 + 0.45 * sin(_time * 3.1 + i * 2.1)
		draw_polygon(_star(p, 5.0 * tw, 1.3 * tw, 4), PackedColorArray([Color(light, 0.9)]))


# ---------------------------------------------------------------- Hjelpere

## Fyller en flate med metall: lys til venstre, mørkere mot høyre, og en mørk kant.
func _metal(points: PackedVector2Array, light: Color, mid: Color, dark: Color, outline := true) -> void:
	var min_x := INF
	var max_x := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	var colors := PackedColorArray()
	for p in points:
		var f := (p.x - min_x) / maxf(max_x - min_x, 0.01)
		var c := mid.lerp(light, clampf(0.75 - f * 1.6, 0.0, 1.0))
		c = c.lerp(dark, clampf((f - 0.5) * 1.5, 0.0, 1.0))
		if design.metal == "aurora":
			c = Color.from_hsv(fposmod(p.y / 95.0 + f * 0.25 + _time * 0.06, 1.0), 0.38, 1.0).lerp(dark, clampf((f - 0.55) * 1.2, 0.0, 0.6))
		if design.metal == "crystal":
			c.a = 0.82
		colors.append(c)
	draw_polygon(points, colors)
	if outline:
		_outline(points, dark.darkened(0.3))


func _outline(points: PackedVector2Array, color: Color) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, 1.1, true)


## Et lyst glimt på metallet.
func _streak(a: Vector2, b: Vector2, light: Color) -> void:
	draw_line(a, b, Color(light, 0.6), 2.6, true)
	draw_circle(a + Vector2(1, -3), 1.3, Color(light, 0.7))


## Halv bredde på skålen i høyde y (skålen smalner av som t^power mot bunnen).
static func _bowl_half(top: float, bottom: float, half_top: float, half_bottom: float, power: float, y: float) -> float:
	var t := clampf((y - top) / (bottom - top), 0.0, 1.0)
	return half_bottom + (half_top - half_bottom) * (1.0 - pow(t, power))


static func _bowl(top: float, bottom: float, half_top: float, half_bottom: float, power: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 14
	for i in n + 1:
		var y := top + (bottom - top) * float(i) / n
		pts.append(Vector2(50 + _bowl_half(top, bottom, half_top, half_bottom, power, y), y))
	for i in range(n, -1, -1):
		var y := top + (bottom - top) * float(i) / n
		pts.append(Vector2(50 - _bowl_half(top, bottom, half_top, half_bottom, power, y), y))
	return pts


static func _ellipse(c: Vector2, rx: float, ry: float, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _star(c: Vector2, outer: float, inner: float, points := 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI / 2.0 + i * PI / points
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


static func _sorted_x(pts: PackedVector2Array) -> PackedVector2Array:
	var arr := Array(pts)
	arr.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return PackedVector2Array(arr)
