class_name Skins
extends RefCounted
## Utseende på brikkene: skins (stil + farger), merker på toppen og seiersanimasjoner.
##
## Hver skin har to drakter, «hjemme» og «borte». Velger begge spillerne samme
## (eller veldig lik) skin, bruker spiller 2 bortedrakten, som i fotball.
## Et «look» er en Dictionary: { skin, decal, win_fx, away }.

enum Style { SMOOTH, METAL, LAVA, GALAXY, HOLO, NEON, MARBLE, CARBON, STRIPES }

const DEFAULT_P1 := "ocean"
const DEFAULT_P2 := "ember"
const SIMILAR := 0.35            ## Fargeavstand som regnes som «for lik»

## a = hovedfarge (nederst), b = detaljfarge (øverst), ui = farge i menyer, ringer og effekter
static var ALL: Array[Dictionary] = [
	_skin("ocean", "Havblå", Style.SMOOTH, ["0a6cff", "4cc4ff", "2a90ff"], ["e9eef5", "b9d6ff", "9cc4f2"]),
	_skin("ember", "Glør", Style.SMOOTH, ["d8300a", "ff7a1a", "f2541b"], ["ffd9a8", "fff1dc", "ffc27a"]),
	_skin("lime", "Lime", Style.SMOOTH, ["5cc10a", "b8f046", "8bd92a"], ["14300d", "2e5c1a", "3d7a22"]),
	_skin("gold", "Gull", Style.METAL, ["b07a1e", "ffd76a", "f2c14e"], ["8f99a3", "eef2f5", "c9d1d8"]),
	_skin("chrome", "Krom", Style.METAL, ["9aa4ae", "ffffff", "dfe5ea"], ["2c3036", "6b737c", "7f8790"]),
	_skin("violet", "Galakse", Style.GALAXY, ["1a0838", "7a3ae0", "9b5cff"], ["061430", "2f7ae0", "4f9bff"]),
	_skin("lava", "Lava", Style.LAVA, ["ff5a12", "2a0d06", "ff6a1a"], ["3ad6ff", "061c2a", "4fdcff"]),
	_skin("mint", "Neon", Style.NEON, ["12e6b4", "3cf0ff", "25e8c8"], ["ff3df0", "ff8af5", "ff5cf2"]),
	_skin("rose", "Holografisk", Style.HOLO, ["ffd1ea", "ff7ac0", "ff8ac8"], ["cffaff", "5fd8ee", "6fdcf0"]),
	_skin("snow", "Marmor", Style.MARBLE, ["f2f1ee", "8c9096", "e9e9e6"], ["18191c", "d9dadd", "9da1a8"]),
	_skin("carbon", "Karbon", Style.CARBON, ["e8340c", "e8340c", "ff5a2a"], ["1e88ff", "1e88ff", "3a9bff"]),
	_skin("racing", "Racing", Style.STRIPES, ["f2f2f2", "e3261b", "e3261b"], ["1c2640", "ffd23a", "ffd23a"]),
]

## Merker på toppen av brikken (indeksen brukes i shaderen)
const DECALS: Array[Dictionary] = [
	{ "id": "none", "name": "Ingen" },
	{ "id": "star", "name": "Stjerne" },
	{ "id": "dot", "name": "Prikk" },
	{ "id": "ring", "name": "Ring" },
	{ "id": "cross", "name": "Kryss" },
	{ "id": "diamond", "name": "Diamant" },
	{ "id": "heart", "name": "Hjerte" },
]

## Seiersanimasjoner (se client/fx/win_fx.gd)
const WIN_FX: Array[Dictionary] = [
	{ "id": "classic", "name": "Klassisk" },
	{ "id": "fireworks", "name": "Fyrverkeri" },
	{ "id": "confetti", "name": "Konfetti" },
	{ "id": "shockwave", "name": "Sjokkbølge" },
	{ "id": "lightning", "name": "Lyn" },
]

static var _shader: Shader
static var _swatches: Dictionary = {}


static func _skin(id: String, name: String, style: Style, home: Array, away: Array) -> Dictionary:
	return { "id": id, "name": name, "style": style, "home": _variant(home), "away": _variant(away) }


static func _variant(hexes: Array) -> Dictionary:
	var a := Color(hexes[0])
	var b := Color(hexes[1])
	var mid := a.lerp(b, 0.5)
	# Mørkt merke på lyse brikker, lyst merke på mørke
	var decal := Color("1b1e24") if mid.get_luminance() > 0.62 else Color(1, 1, 1)
	return { "a": a, "b": b, "ui": Color(hexes[2]), "decal": decal }


# ---------------------------------------------------------------- Oppslag

static func get_skin(id: String) -> Dictionary:
	for s in ALL:
		if s.id == id:
			return s
	return ALL[0]


static func is_valid(id: String) -> bool:
	return ALL.any(func(s: Dictionary) -> bool: return s.id == id)


static func is_valid_decal(id: String) -> bool:
	return DECALS.any(func(d: Dictionary) -> bool: return d.id == id)


static func is_valid_fx(id: String) -> bool:
	return WIN_FX.any(func(d: Dictionary) -> bool: return d.id == id)


static func decal_index(id: String) -> int:
	for i in DECALS.size():
		if DECALS[i].id == id:
			return i
	return 0


## Et komplett look med gyldige verdier.
static func look(skin: String, decal := "none", win_fx := "classic", away := false) -> Dictionary:
	return {
		"skin": skin if is_valid(skin) else DEFAULT_P1,
		"decal": decal if is_valid_decal(decal) else "none",
		"win_fx": win_fx if is_valid_fx(win_fx) else "classic",
		"away": away,
	}


static func variant(l: Dictionary) -> Dictionary:
	var s := get_skin(str(l.get("skin", DEFAULT_P1)))
	return s.away if bool(l.get("away", false)) else s.home


## Fargen som representerer et look i UI-et (ringer, tekst, partikler).
static func ui_color(l: Dictionary) -> Color:
	return variant(l).ui


## Hjemmefargen til en skin (for lister og swatches).
static func color_of(id: String) -> Color:
	return get_skin(id).home.ui


## Gjør to looks lette å skille: spiller 2 får bortedrakt ved lik skin eller lik farge.
## Er den fortsatt for lik, byttes spiller 2 til en annen skin.
static func resolve_pair(l1: Dictionary, l2: Dictionary) -> Array[Dictionary]:
	var a := l1.duplicate()
	var b := l2.duplicate()
	a.away = false
	b.away = false
	if a.skin == b.skin or _distance(ui_color(a), ui_color(b)) < SIMILAR:
		b.away = true
	if _distance(ui_color(a), ui_color(b)) < SIMILAR:
		for candidate in [DEFAULT_P2, DEFAULT_P1, "lime", "violet"]:
			b.skin = candidate
			b.away = false
			if _distance(ui_color(a), ui_color(b)) >= SIMILAR:
				break
	var out: Array[Dictionary] = [a, b]
	return out


static func _distance(x: Color, y: Color) -> float:
	return Vector3(x.r - y.r, x.g - y.g, x.b - y.b).length()


## Et lite rundt ikon med skinnets hjemmefarger (gradient), til knapper og lister.
static func swatch(id: String, size := 30) -> Texture2D:
	var key := "%s:%d" % [id, size]
	if _swatches.has(key):
		return _swatches[key]
	var v: Dictionary = get_skin(id).home
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(r, r))
			var c: Color = (v.b as Color).lerp(v.a, float(y) / size)
			c = c.lerp(Color.WHITE, clampf(0.35 - Vector2(x - r * 0.6, y - r * 0.6).length() / size, 0.0, 0.35))
			c.a = clampf(r - 0.5 - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_swatches[key] = tex
	return tex


# ---------------------------------------------------------------- Materialer

## Lager et materiale for en brikke med dette lookets skin, drakt og merke.
static func make_material(l: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://assets/shaders/piece.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	var s := get_skin(str(l.get("skin", DEFAULT_P1)))
	var v := variant(l)
	m.set_shader_parameter("style", int(s.style))
	m.set_shader_parameter("color_a", v.a)
	m.set_shader_parameter("color_b", v.b)
	m.set_shader_parameter("decal", decal_index(str(l.get("decal", "none"))))
	m.set_shader_parameter("decal_color", Color(v.decal, 0.92))
	return m
