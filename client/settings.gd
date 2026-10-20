extends Node
## Autoload «Settings»: spillerens valg, lagret lokalt i user://settings.cfg
## (på web lagres dette i nettleseren).

signal changed

const PATH := "user://settings.cfg"
const DEFAULT_LOCAL_SERVER := "ws://localhost:8080"

var player_name := ""
var skin_id := Skins.DEFAULT_P1
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
		avatar = str(cfg.get_value("player", "avatar", ""))
		sound = bool(cfg.get_value("app", "sound", sound))
		vibration = bool(cfg.get_value("app", "vibration", vibration))
		server_url = str(cfg.get_value("app", "server_url", ""))
		last_options = cfg.get_value("game", "options", {})
		ai_level = int(cfg.get_value("game", "ai_level", ai_level))
	if player_name.strip_edges() == "":
		player_name = "Spiller%d" % (randi() % 900 + 100)
		save()
	if not Skins.is_valid(skin_id):
		skin_id = Skins.DEFAULT_P1


func save() -> void:
	if not persist:
		changed.emit()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "skin", skin_id)
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
