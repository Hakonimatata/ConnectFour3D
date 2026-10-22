extends Node
## Autoload «Settings»: spillerens valg, lagret lokalt i user://settings.cfg
## (på web lagres dette i nettleseren).

signal changed

const PATH := "user://settings.cfg"
const VERSION := 3            ## Øk når standardverdier skal endres for eksisterende spillere
const DEFAULT_LOCAL_SERVER := "ws://localhost:8080"

var player_name := ""         ## Gjestenavnet («Gjest 4821»), laget automatisk. Med konto brukes brukernavnet.
var last_username := ""       ## Brukernavnet fra sist du var innlogget (vises også uten nett)
var solved_puzzles: Array[String] = []   ## Løste oppgaver fra oppgavebanken (id-er)
var skin_id := Skins.DEFAULT_P1
var decal_id := "none"        ## Merke på toppen av brikken (Skins.DECALS)
var win_fx_id := "classic"    ## Seiersanimasjon (Skins.WIN_FX)
var decal_color_id := "auto"  ## Farge på merket (Skins.DECAL_COLORS)
var kit_away := false         ## Drakten du vil bruke: false = hjemme, true = borte
var board_theme := "slate"    ## Brett-tema (Skins.BOARDS), bare for deg selv
var chat_presets: Array[String] = []   ## Egne hurtigmeldinger. Tom = standardmeldinger på valgt språk.
var language := "auto"
var session_token := ""       ## Husket innlogging (nøkkel fra serveren)
var last_elo := -1            ## Siste kjente Elo (låser opp merker også uten nett). -1 = aldri innlogget
var puzzle_day := ""          ## Datoen for sist løste «Dagens oppgave"
var avatar := ""              ## Profilbilde (base64-JPEG fra AvatarData), "" = ingen
var persist := true           ## false = ikke skriv til disk (brukes av testene)
var sound := true
var vibration := true
var server_url := ""          ## Tom = standard (se resolved_server_url)
var last_options: Dictionary = {}
var ai_level := 1


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_name = str(cfg.get_value("player", "name", ""))
		skin_id = str(cfg.get_value("player", "skin", skin_id))
		decal_id = str(cfg.get_value("player", "decal", decal_id))
		win_fx_id = str(cfg.get_value("player", "win_fx", win_fx_id))
		decal_color_id = str(cfg.get_value("player", "decal_color", decal_color_id))
		kit_away = bool(cfg.get_value("player", "kit_away", false))
		board_theme = str(cfg.get_value("app", "board_theme", board_theme))
		chat_presets.assign(cfg.get_value("player", "chat_presets", []))
		language = str(cfg.get_value("app", "language", language))
		session_token = str(cfg.get_value("account", "session", ""))
		last_elo = int(cfg.get_value("account", "last_elo", -1))
		last_username = str(cfg.get_value("account", "last_username", ""))
		solved_puzzles.assign(cfg.get_value("game", "solved_puzzles", []))
		puzzle_day = str(cfg.get_value("game", "puzzle_day", ""))
		if int(cfg.get_value("app", "version", 1)) < 2:
			# Runde 7: «Må blokkere» og «Ikke gi bort seier» er nå på som standard.
			last_options["must_block"] = true
			last_options["no_gift"] = true
		avatar = str(cfg.get_value("player", "avatar", ""))
		sound = bool(cfg.get_value("app", "sound", sound))
		vibration = bool(cfg.get_value("app", "vibration", vibration))
		server_url = str(cfg.get_value("app", "server_url", ""))
		last_options = cfg.get_value("game", "options", {})
		ai_level = int(cfg.get_value("game", "ai_level", ai_level))
	# Runde 10: bare kontoer har eget navn. Gjester får «Gjest» og et tall.
	if not player_name.begins_with("Gjest "):
		player_name = "Gjest %d" % (randi() % 9000 + 1000)
		save()
	if not Skins.is_valid(skin_id):
		skin_id = Skins.DEFAULT_P1
	I18n.apply(language)


## Standard hurtigmeldinger (oversettes til valgt språk).
const DEFAULT_CHAT: Array[String] = ["Lykke til!", "Bra trekk!", "Oi!", "GG"]


## Hurtigmeldingene som vises i chatten: egne hvis satt, ellers standard.
func chat_messages() -> Array[String]:
	if not chat_presets.is_empty():
		return chat_presets.duplicate()
	var out: Array[String] = []
	for m in DEFAULT_CHAT:
		out.append(tr(m))
	return out


## Lagrer egne hurtigmeldinger. Er de like standardmeldingene, lagres ingenting,
## slik at de følger språket.
func set_chat_messages(msgs: Array[String]) -> void:
	chat_presets.clear()
	var defaults := chat_messages()
	if msgs != defaults:
		for m in msgs:
			chat_presets.append(m.substr(0, 40))


## Spillerens eget utseende (skin, merke, seiersanimasjon). Merker du ikke har låst opp (Elo), blir «ingen».
func look() -> Dictionary:
	var decal := decal_id if EloTiers.decal_unlocked(decal_id, known_elo()) else "none"
	return Skins.look(skin_id, decal, win_fx_id, kit_away, decal_color_id)


## Navnet som vises: brukernavnet hvis du har konto, ellers gjestenavnet.
func display_name() -> String:
	if Net.is_logged_in():
		return str(Net.user.get("username", player_name))
	return last_username if last_username != "" else player_name


## Elo-en som låser opp merker: fra serveren når du er innlogget, ellers den sist kjente.
func known_elo() -> int:
	if Net.is_logged_in():
		return int(Net.user.get("elo", last_elo))
	return last_elo


func save() -> void:
	if not persist:
		changed.emit()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "skin", skin_id)
	cfg.set_value("player", "decal", decal_id)
	cfg.set_value("player", "win_fx", win_fx_id)
	cfg.set_value("player", "decal_color", decal_color_id)
	cfg.set_value("player", "kit_away", kit_away)
	cfg.set_value("app", "board_theme", board_theme)
	cfg.set_value("player", "chat_presets", chat_presets)
	cfg.set_value("app", "language", language)
	cfg.set_value("app", "version", VERSION)
	cfg.set_value("account", "session", session_token)
	cfg.set_value("account", "last_elo", last_elo)
	cfg.set_value("account", "last_username", last_username)
	cfg.set_value("game", "solved_puzzles", solved_puzzles)
	cfg.set_value("game", "puzzle_day", puzzle_day)
	cfg.set_value("player", "avatar", avatar)
	cfg.set_value("app", "sound", sound)
	cfg.set_value("app", "vibration", vibration)
	cfg.set_value("app", "server_url", server_url)
	cfg.set_value("game", "options", last_options)
	cfg.set_value("game", "ai_level", ai_level)
	cfg.save(PATH)
	changed.emit()


## Adressen til spillserveren. Rekkefølge:
## 1) ?server=... i nettleseradressen, 2) lagret i innstillinger,
## 3) på web: samme adresse som siden + /ws (Caddy eller serverens egen web-del
##    sender /ws videre til spillserveren),
## 4) ellers localhost.
func resolved_server_url() -> String:
	if OS.has_feature("web"):
		var from_query = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''")
		if from_query is String and from_query != "":
			return from_query
	if server_url.strip_edges() != "":
		return server_url.strip_edges()
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'")
		if origin is String and origin != "":
			return origin
	return DEFAULT_LOCAL_SERVER


func vibrate(ms: int) -> void:
	if vibration:
		Input.vibrate_handheld(ms)
