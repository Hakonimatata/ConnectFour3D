class_name EloBadge
extends RefCounted
## Elo-merker: et lite merke ved spillernavnet som viser nivået, fra Bronse til Stormester.
## Merkene tegnes i kode (ingen bildefiler) og caches per nivå og størrelse.
##   Bronse, Sølv, Gull  skjold med 1, 2 og 3 vinkler
##   Platina             sekskant med stjerne
##   Diamant             slipt edelstein
##   Mester              krone
##   Stormester          gullkrone på rødt merke

const TIERS: Array[Dictionary] = [
	{ "id": "bronze", "name": "Bronse", "min": 0, "color": Color("c8814a"), "shape": "shield", "marks": 1 },
	{ "id": "silver", "name": "Sølv", "min": 1100, "color": Color("c3cad3"), "shape": "shield", "marks": 2 },
	{ "id": "gold", "name": "Gull", "min": 1250, "color": Color("f2c14e"), "shape": "shield", "marks": 3 },
	{ "id": "platinum", "name": "Platina", "min": 1400, "color": Color("4fd8c4"), "shape": "hexagon", "marks": 0 },
	{ "id": "diamond", "name": "Diamant", "min": 1550, "color": Color("6fb4ff"), "shape": "gem", "marks": 0 },
	{ "id": "master", "name": "Mester", "min": 1700, "color": Color("b67cff"), "shape": "crown", "marks": 0 },
	{ "id": "grandmaster", "name": "Stormester", "min": 1850, "color": Color("ff5470"), "shape": "seal", "marks": 0 },
]

const _SHIELD := [Vector2(-0.8, -0.85), Vector2(0.8, -0.85), Vector2(0.8, 0.1), Vector2(0.6, 0.5), Vector2(0.3, 0.78),
	Vector2(0.0, 0.92), Vector2(-0.3, 0.78), Vector2(-0.6, 0.5), Vector2(-0.8, 0.1)]
const _GEM := [Vector2(-0.92, -0.3), Vector2(-0.5, -0.8), Vector2(0.5, -0.8), Vector2(0.92, -0.3), Vector2(0.0, 0.92)]
const _GEM_FACETS := [[Vector2(-0.92, -0.3), Vector2(0.92, -0.3)], [Vector2(-0.28, -0.3), Vector2(0.0, 0.92)],
	[Vector2(0.28, -0.3), Vector2(0.0, 0.92)], [Vector2(-0.5, -0.8), Vector2(-0.28, -0.3)],
	[Vector2(0.5, -0.8), Vector2(0.28, -0.3)], [Vector2(0.0, -0.8), Vector2(-0.28, -0.3)], [Vector2(0.0, -0.8), Vector2(0.28, -0.3)]]
const _CROWN := [Vector2(-0.82, 0.6), Vector2(0.82, 0.6), Vector2(0.9, -0.45), Vector2(0.45, 0.02), Vector2(0.0, -0.72),
	Vector2(-0.45, 0.02), Vector2(-0.9, -0.45)]

static var _cache: Dictionary = {}


## Nivået for en Elo-verdi.
static func tier(elo: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if elo >= int(t.min):
			out = t
	return out


## Neste nivå over denne Elo-verdien, eller {} på toppen.
static func next_tier(elo: int) -> Dictionary:
	for t in TIERS:
		if int(t.min) > elo:
			return t
	return {}


## «Gull · Elo 1312» (oversatt).
static func describe(elo: int) -> String:
	return "%s · Elo %d" % [str(TranslationServer.translate(tier(elo).name)), elo]


## Merket som et lite bilde med verktøytips. elo < 0 (gjest) gir et tomt, usynlig bilde.
static func make(elo: int, size := 20) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	set_elo(r, elo, size)
	return r


static func set_elo(r: TextureRect, elo: int, size := 20) -> void:
	r.visible = elo >= 0
	if elo < 0:
		return
	r.texture = icon(elo, size)
	r.tooltip_text = describe(elo)


## Bildet av merket (cachet). Tegnes i dobbel oppløsning for skarpe kanter på skjermer med høy DPI.
static func icon(elo: int, size := 20) -> Texture2D:
	var t := tier(elo)
	var px := size * 2
	var key := "%s:%d" % [t.id, px]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_draw(t, px))
	return _cache[key]


# ---------------------------------------------------------------- Tegning

static func _draw(t: Dictionary, px: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var base: Color = t.color
	var outline := base.darkened(0.55)
	var mark := base.darkened(0.6)
	var aa := 2.4 / px    # omtrent én piksel i normaliserte koordinater
	for y in px:
		for x in px:
			var p := Vector2((x + 0.5) / px * 2.0 - 1.0, (y + 0.5) / px * 2.0 - 1.0)
			var d := _shape(t.shape, p)
			var cover := clampf(0.5 - d / aa, 0.0, 1.0)
			if cover <= 0.0:
				continue
			# Lys øverst, mørkere nederst, og en mørk kant rundt
			var c := base.lightened(0.3).lerp(base.darkened(0.25), (p.y + 1.0) * 0.5)
			c = c.lerp(outline, clampf(0.5 - (-d - 0.1) / aa, 0.0, 1.0))
			var m := _mark(t, p)
			if m.a > 0.0:
				c = c.lerp(Color(m, 1.0), m.a)
			elif t.shape != "seal":
				c = c.lerp(mark, clampf(0.5 - _symbol(t, p) / aa, 0.0, 1.0))
			c.a = cover
			img.set_pixel(x, y, c)
	return img


## Avstand til omrisset (negativ inni).
static func _shape(shape: String, p: Vector2) -> float:
	match shape:
		"shield": return _poly(p, _SHIELD)
		"hexagon": return _hexagon(p, 0.86)
		"gem": return _poly(p, _GEM)
		"crown": return minf(_poly(p, _CROWN), _tips(p, 1.0))
		"seal": return p.length() - 0.95
	return p.length() - 0.9


## Avstand til symbolet inni merket (vinkler, stjerne, fasetter).
static func _symbol(t: Dictionary, p: Vector2) -> float:
	match t.shape:
		"shield":
			var n := int(t.marks)
			var d := 1.0
			for i in n:
				var y := (i - (n - 1) * 0.5) * 0.3 - 0.06
				d = minf(d, _chevron(p, y))
			return d
		"hexagon":
			return _star(p * 1.0, 0.46, 0.2)
		"gem":
			var d := 1.0
			for f in _GEM_FACETS:
				d = minf(d, _segment(p, f[0], f[1]) - 0.035)
			return d
		"crown":
			return absf(p.y - 0.4) - 0.07
	return 1.0


## Stormester: gullkrone oppå det røde merket (egen farge, så den returnerer en farge med dekning).
static func _mark(t: Dictionary, p: Vector2) -> Color:
	if t.shape != "seal":
		return Color(0, 0, 0, 0)
	var q := p / 0.68 + Vector2(0.0, 0.06)
	var d := minf(_poly(q, _CROWN), _tips(q, 1.0)) * 0.68
	var cover := clampf(0.5 - d / 0.04, 0.0, 1.0)
	var gold := Color("ffd76a").lerp(Color("c99a2e"), (q.y + 1.0) * 0.5)
	return Color(gold.r, gold.g, gold.b, cover)


static func _chevron(p: Vector2, y: float) -> float:
	var hw := 0.42
	var pts := [Vector2(-hw, y + 0.16), Vector2(0.0, y - 0.16), Vector2(hw, y + 0.16), Vector2(hw, y + 0.33),
		Vector2(0.0, y + 0.01), Vector2(-hw, y + 0.33)]
	return _poly(p, pts)


static func _tips(p: Vector2, s: float) -> float:
	var d := (p - Vector2(-0.9, -0.52) * s).length() - 0.13 * s
	d = minf(d, (p - Vector2(0.0, -0.8) * s).length() - 0.13 * s)
	return minf(d, (p - Vector2(0.9, -0.52) * s).length() - 0.13 * s)


static func _hexagon(p: Vector2, r: float) -> float:
	var q := Vector2(absf(p.y), absf(p.x))    # spiss opp
	var k := Vector3(-0.866025404, 0.5, 0.577350269)
	q -= 2.0 * minf(k.x * q.x + k.y * q.y, 0.0) * Vector2(k.x, k.y)
	q -= Vector2(clampf(q.x, -k.z * r, k.z * r), r)
	return q.length() * signf(q.y)


static func _star(p: Vector2, r_out: float, r_in: float) -> float:
	var pts := []
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(a), sin(a)) * r)
	return _poly(p, pts)


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


## Avstand til en polygon (negativ inni).
static func _poly(p: Vector2, v: Array) -> float:
	var v0: Vector2 = v[0]
	var d := (p - v0).length_squared()
	var s := 1.0
	var n := v.size()
	for i in n:
		var vi: Vector2 = v[i]
		var vj: Vector2 = v[(i + n - 1) % n]
		var e := vj - vi
		var w := p - vi
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.length_squared())
		var c1 := p.y >= vi.y
		var c2 := p.y < vj.y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
	return s * sqrt(d)
