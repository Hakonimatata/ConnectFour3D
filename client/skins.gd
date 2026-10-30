class_name Skins
extends RefCounted
## Utseende på brikkene: skins (stil + farger), merker på toppen og seiersanimasjoner.
##
## Hver skin har to drakter, «hjemme» og «borte». Velger begge spillerne samme
## (eller veldig lik) skin, bruker spiller 2 bortedrakten, som i fotball.
## Et «look» er en Dictionary: { skin, decal, win_fx, away, decal_color }.

enum Style { SMOOTH, METAL, LAVA, GALAXY, HOLO, NEON, MARBLE, CARBON, STRIPES, AURORA, ICE, WOOD, CERAMIC,
	GLASS, PATINA, PLASMA, KINTSUGI, DAMASCUS, CIRCUIT, DISCO, OPAL, PIXEL, CODE, TOXIC, BLACK_HOLE }

const DEFAULT_P1 := "ocean"
const DEFAULT_P2 := "ember"
const SIMILAR := 0.35            ## Fargeavstand som regnes som «for lik»
const SIMILAR_LOOK := 0.15       ## Det samme for hele brikken (Oklab, snitt av hoved-, detalj- og UI-farge)

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
	_skin("rose", "Holografisk", Style.HOLO, ["ff9fd0", "ffd27a", "ff9fc8"], ["5ce1f0", "8f7bff", "6fc6f5"]),
	_skin("snow", "Marmor", Style.MARBLE, ["f2f1ee", "8c9096", "e9e9e6"], ["18191c", "d9dadd", "9da1a8"]),
	_skin("carbon", "Karbon", Style.CARBON, ["e8340c", "e8340c", "ff5a2a"], ["1e88ff", "1e88ff", "3a9bff"]),
	_skin("racing", "Racing", Style.STRIPES, ["f2f2f2", "e3261b", "e3261b"], ["1c2640", "ffd23a", "ffd23a"]),
	# Runde 7
	_skin("aurora", "Nordlys", Style.AURORA, ["0b1d2a", "3cf0a0", "3cf0a0"], ["170a26", "c05cff", "c05cff"]),
	_skin("ice", "Is", Style.ICE, ["d6f1ff", "7fc8ff", "a8dcff"], ["ffe8f0", "ff8fb3", "ff9fbf"]),
	_skin("oak", "Eik", Style.WOOD, ["b07a45", "dcae78", "c98b52"], ["3e2416", "6e4127", "7a4a2c"]),
	_skin("ceramic", "Keramikk", Style.CERAMIC, ["f4efe6", "e6d9c6", "efe6d8"], ["2f6f73", "3f8a8f", "3f8a8f"]),
	_skin("glass", "Glass", Style.GLASS, ["5fc0ff", "d8f3ff", "8fd8ff"], ["ff9a3c", "ffe2c4", "ffb36b"]),
	_skin("copper", "Kobber", Style.PATINA, ["a85a26", "f0a36a", "e08a4a"], ["2f8f7a", "8fdcc6", "5fbfa5"]),
	_skin("sunset", "Solnedgang", Style.SMOOTH, ["ff5e62", "ffb347", "ff7f50"], ["5b4bd0", "ff6fa5", "9f6bd8"]),
	_skin("midnight", "Midnatt", Style.STRIPES, ["141c3a", "e9c46a", "e9c46a"], ["f4f1e8", "141c3a", "3a4670"]),
	# Runde 8
	_skin("plasma", "Plasma", Style.PLASMA, ["12062e", "c77dff", "b46bff"], ["021a24", "5ff4ff", "4fe0ff"]),
	_skin("kintsugi", "Kintsugi", Style.KINTSUGI, ["1c1d22", "f0c050", "caa04a"], ["efebe4", "d9a33a", "f4efe6"]),
	_skin("damascus", "Damaskus", Style.DAMASCUS, ["3a4048", "c9d2db", "9aa6b2"], ["24180f", "e0a050", "d48a3a"]),
	_skin("circuit", "Kretskort", Style.CIRCUIT, ["0b2a1a", "3cff8a", "35e07a"], ["160d26", "ff9a1f", "ff9a1f"]),
	_skin("disco", "Disco", Style.DISCO, ["c0c6d0", "ff4fd8", "e6e9ef"], ["d9a640", "4fd8ff", "f2c14e"]),
	_skin("opal", "Opal", Style.OPAL, ["eef3f7", "bfe3ff", "dde8f2"], ["10182a", "3a5ccc", "4a6ad8"]),
	_skin("pixel", "Piksel", Style.PIXEL, ["ff3d7f", "ffd23f", "ff5c8a"], ["1fa9ff", "b6f0ff", "3cb8ff"]),
	_skin("code", "Kode", Style.CODE, ["020a04", "3cff6a", "3cff6a"], ["0a0204", "ff3c5a", "ff3c5a"]),
	_skin("toxic", "Giftig", Style.TOXIC, ["7cff1a", "e6ff5a", "9cff2a"], ["b04cff", "ff7af0", "c060ff"]),
	_skin("blackhole", "Sort hull", Style.BLACK_HOLE, ["ff8a1f", "fff0c0", "ff9a3a"], ["4f7bff", "d6e4ff", "6f8fff"]),
	# Runde 17: låses bare opp av prestasjoner (se core/progression.gd)
	_skin("champion", "Gullmester", Style.KINTSUGI, ["120d05", "ffd76a", "f2c14e"], ["f6f1e4", "2a4fd0", "3f6ae0"]),
	_skin("dawn", "Morgengry", Style.AURORA, ["2a0f2e", "ff9a5c", "ff8a6a"], ["0b1d3a", "5ce1f0", "4fd8e8"]),
]

## Merker på toppen av brikken (indeksen brukes i shaderen). Noen låses opp av Elo (EloTiers.DECAL_TIERS).
const DECALS: Array[Dictionary] = [
	{ "id": "none", "name": "Ingen" },
	{ "id": "star", "name": "Stjerne" },
	{ "id": "dot", "name": "Prikk" },
	{ "id": "ring", "name": "Ring" },
	{ "id": "cross", "name": "Kryss" },
	{ "id": "diamond", "name": "Diamant" },
	{ "id": "heart", "name": "Hjerte" },
	{ "id": "hexagon", "name": "Sekskant" },
	{ "id": "moon", "name": "Måne" },
	{ "id": "crown", "name": "Krone" },
	{ "id": "bolt", "name": "Lyn" },
	{ "id": "chevron", "name": "Pil" },
	# Runde 9: merker for de høyeste Elo-nivåene (se core/elo_tiers.gd)
	{ "id": "flame", "name": "Flamme" },
	{ "id": "laurel", "name": "Laurbær" },
]

## Farge på merket
const DECAL_COLORS: Array[Dictionary] = [
	{ "id": "auto", "name": "Automatisk" },
	{ "id": "white", "name": "Hvit" },
	{ "id": "black", "name": "Svart" },
	{ "id": "gold", "name": "Gull" },
	{ "id": "kit", "name": "Draktfarge" },
]

## Brett-temaer (bare for deg selv). grain = treverk.
static var BOARDS: Array[Dictionary] = [
	{ "id": "slate", "name": "Skifer", "base": Color("2b2f37"), "line": Color("3c4049"), "side": Color("1f232b"), "grain": 0.0 },
	{ "id": "oak", "name": "Eik", "base": Color("8a6440"), "line": Color("6b4a2e"), "side": Color("553a23"), "grain": 1.0 },
	{ "id": "marble", "name": "Lys stein", "base": Color("d4d3ce"), "line": Color("b4b3ae"), "side": Color("a3a29d"), "grain": 0.0 },
	{ "id": "midnight", "name": "Midnatt", "base": Color("18213d"), "line": Color("2b3a66"), "side": Color("10162b"), "grain": 0.0 },
	{ "id": "felt", "name": "Filt", "base": Color("1f4d3b"), "line": Color("2e6b53"), "side": Color("163a2c"), "grain": 0.0 },
]

## Bakgrunner bak brettet (tegnes i assets/shaders/background.gdshader, «style»). Bare for deg selv.
const BACKGROUNDS: Array[Dictionary] = [
	{ "id": "standard", "name": "Standard", "style": 0 },
	{ "id": "nebula", "name": "Nebula", "style": 1 },
	{ "id": "stars", "name": "Stjernehimmel", "style": 2 },
	{ "id": "cafe", "name": "Kaffebar", "style": 3 },
]


static func background_style(id: String) -> int:
	for b in BACKGROUNDS:
		if b.id == id:
			return int(b.style)
	return 0


## Seiersanimasjoner (se client/fx/win_fx.gd)
const WIN_FX: Array[Dictionary] = [
	{ "id": "classic", "name": "Klassisk" },
	{ "id": "fireworks", "name": "Fyrverkeri" },
	{ "id": "confetti", "name": "Konfetti" },
	{ "id": "shockwave", "name": "Sjokkbølge" },
	{ "id": "lightning", "name": "Lyn" },
	{ "id": "supernova", "name": "Supernova" },
	{ "id": "glitter", "name": "Glitter" },
	{ "id": "chaos", "name": "Kaos" },
]

static var _base_code := ""
static var _shaders: Dictionary = {}     ## stil * 100 + merke -> Shader
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


static func is_valid_decal_color(id: String) -> bool:
	return DECAL_COLORS.any(func(d: Dictionary) -> bool: return d.id == id)


static func get_board(id: String) -> Dictionary:
	for b in BOARDS:
		if b.id == id:
			return b
	return BOARDS[0]


static func decal_index(id: String) -> int:
	for i in DECALS.size():
		if DECALS[i].id == id:
			return i
	return 0


## Et komplett look med gyldige verdier.
static func look(skin: String, decal := "none", win_fx := "classic", away := false, decal_color := "auto") -> Dictionary:
	return {
		"skin": skin if is_valid(skin) else DEFAULT_P1,
		"decal": decal if is_valid_decal(decal) else "none",
		"win_fx": win_fx if is_valid_fx(win_fx) else "classic",
		"away": away,
		"decal_color": decal_color if is_valid_decal_color(decal_color) else "auto",
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


## Gjør to looks lette å skille. Hver spiller velger selv drakt (hjemme eller borte). Bare når
## begge har samme skin og drakt, eller brikkene er ganske like (too_similar), bytter spiller 2 til den
## andre drakten. Er den fortsatt for lik, byttes spiller 2 til en annen skin.
static func resolve_pair(l1: Dictionary, l2: Dictionary) -> Array[Dictionary]:
	var a := l1.duplicate()
	var b := l2.duplicate()
	a.away = bool(a.get("away", false))
	b.away = bool(b.get("away", false))
	if (a.skin == b.skin and a.away == b.away) or too_similar(a, b):
		b.away = not b.away
	if too_similar(a, b):
		for candidate in [DEFAULT_P2, DEFAULT_P1, "lime", "violet"]:
			b.skin = candidate
			b.away = false
			if not too_similar(a, b):
				break
	var out: Array[Dictionary] = [a, b]
	return out


## Er brikkene så like at de kan forveksles? Ser på hele brikken (hoved-, detalj- og UI-fargen) i
## Oklab, der avstand følger hvordan øyet ser forskjell. Før så vi bare på UI-fargen i RGB, og
## f.eks. Glør mot Kobber eller Is mot Opal ble ikke byttet.
static func too_similar(l1: Dictionary, l2: Dictionary) -> bool:
	var x := variant(l1)
	var y := variant(l2)
	if _distance(x.ui, y.ui) < SIMILAR:
		return true
	var d := 0.0
	for k in ["a", "b", "ui"]:
		d += _oklab(x[k]).distance_to(_oklab(y[k]))
	return d / 3.0 < SIMILAR_LOOK


static func _oklab(c: Color) -> Vector3:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = lin.call(c.r)
	var g: float = lin.call(c.g)
	var b: float = lin.call(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817104540 * g + 0.6299787999 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


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
	var s := get_skin(str(l.get("skin", DEFAULT_P1)))
	var v := variant(l)
	var m := ShaderMaterial.new()
	m.shader = shader_for(int(s.style), decal_index(str(l.get("decal", "none"))))
	m.set_shader_parameter("color_a", v.a)
	m.set_shader_parameter("color_b", v.b)
	m.set_shader_parameter("decal_color", Color(decal_color_of(l), 0.92))
	return m


## Brikke-shaderen spesialisert for én stil og ett merke (se toppen av piece.gdshader).
## Små shadere kompileres raskt, så det første bildet med brikker ikke henger.
static func shader_for(style: int, decal: int) -> Shader:
	var key := style * 100 + decal
	if not _shaders.has(key):
		if _base_code == "":
			_base_code = (load("res://assets/shaders/piece.gdshader") as Shader).code
		var sh := Shader.new()
		sh.code = _base_code.replace("// @SPECIALIZE", "#define STYLE %d\n#define DECAL %d" % [style, decal])
		_shaders[key] = sh
	return _shaders[key]


static func decal_color_of(l: Dictionary) -> Color:
	var v := variant(l)
	match str(l.get("decal_color", "auto")):
		"white": return Color(1, 1, 1)
		"black": return Color("16181d")
		"gold": return Color("e8c35a")
		"kit": return v.ui
	return v.decal
