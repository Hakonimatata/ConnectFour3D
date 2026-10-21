class_name Store
extends RefCounted
## Varig lagring i JSON-filer i én datamappe, laget for å være lett å lese og redigere:
##   users.json        brukere: brukernavn, admin, Elo, statistikk, profil og passord-hash
##   avatars.json      profilbilder (base64), adskilt så users.json er lett å lese
##   sessions.json     innloggede økter (bare en hash av nøkkelen lagres)
##   tournaments.json  turneringer
##   games.jsonl       ett ferdig parti per linje (kan brukes til replays senere)
##
## Endrer du users.json (f.eks. setter "admin": true) mens serveren kjører, merker serveren
## det innen et sekund og laster filen inn på nytt.
## Glemt passord: skriv "reset_password": "nytt-passord" på brukeren. Serveren lager en
## hash av det og fjerner klarteksten fra filen med en gang. Ugyldig JSON blir ikke lastet; da
## beholdes det gamle og en feil skrives til loggen.
## dir = "" betyr lagring bare i minnet (brukes av testene).

var dir := ""
var users: Dictionary = {}          ## id (int) -> bruker
var avatars: Dictionary = {}        ## id (int) -> base64
var sessions: Dictionary = {}       ## hash av nøkkel -> { user, created }
var tournaments: Array = []         ## turneringer (eies av Tournaments)
var next_user_id := 1
var next_tournament_id := 1
var _known: Dictionary = {}         ## fil -> hash av innholdet da vi sist leste/skrev det


func open(p_dir: String) -> void:
	dir = p_dir
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	# Godot skal ikke prøve å importere datafilene hvis mappen ligger i prosjektet.
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).store_string("")
	_load_users()
	var av = _read_json("avatars.json", {})
	if av is Dictionary:
		for k in av:
			avatars[int(k)] = str(av[k])
	var se = _read_json("sessions.json", {})
	if se is Dictionary:
		for k in se:
			sessions[str(k)] = { "user": int(se[k].get("user", 0)), "created": int(se[k].get("created", 0)) }
	var tu = _read_json("tournaments.json", {})
	if tu is Dictionary:
		tournaments = tu.get("tournaments", [])
		next_tournament_id = int(tu.get("next_id", 1))


## Kalles jevnlig. Laster users.json på nytt hvis noen har endret den. Gir true hvis lastet.
func poll() -> bool:
	if dir == "":
		return false
	var path := dir.path_join("users.json")
	if not FileAccess.file_exists(path):
		return false
	# Sammenlign innholdet (ikke bare endringstid, som bare har hele sekunder).
	if FileAccess.get_file_as_string(path).hash() == _known.get(path, 0):
		return false
	var ok := _load_users()
	if ok:
		print("users.json er endret – lastet inn på nytt.")
	return ok


# ---------------------------------------------------------------- Brukere

func find_user(username: String) -> Dictionary:
	var key := username.strip_edges().to_lower()
	for u in users.values():
		if str(u.username).to_lower() == key:
			return u
	return {}


func add_user(username: String, password_record: Dictionary) -> Dictionary:
	var u := normalize_user({ "id": next_user_id, "username": username, "password": password_record,
		"created": Time.get_datetime_string_from_system(false, true) })
	users[u.id] = u
	next_user_id += 1
	save_users()
	return u


## Fyller inn manglende felt med standardverdier (så hånd-redigerte brukere alltid virker).
static func normalize_user(d: Dictionary) -> Dictionary:
	var stats: Dictionary = d.get("stats", {}) if d.get("stats") is Dictionary else {}
	var clean_stats := {}
	for k in STAT_KEYS:
		clean_stats[k] = int(stats.get(k, 0))
	var profile: Dictionary = d.get("profile", {}) if d.get("profile") is Dictionary else {}
	return {
		"id": int(d.get("id", 0)),
		"username": str(d.get("username", "")),
		"admin": bool(d.get("admin", false)),
		"created": str(d.get("created", "")),
		"elo": int(d.get("elo", 1200)),
		"stats": clean_stats,
		"profile": { "skin": str(profile.get("skin", "ocean")), "decal": str(profile.get("decal", "none")),
			"win_fx": str(profile.get("win_fx", "classic")) },
		"password": d.get("password", {}),
	}


const STAT_KEYS := ["games", "wins", "losses", "draws", "current_streak", "best_streak", "fastest_win",
	"forced_moves", "double_threats", "best_forced_win", "wins_line", "wins_time", "wins_resign",
	"wins_walkover", "losses_time", "losses_resign", "tournaments_won"]


func save_users() -> void:
	var list := []
	var ids := users.keys()
	ids.sort()
	for id in ids:
		list.append(users[id])
	_write_json("users.json", { "users": list, "next_id": next_user_id })


func _load_users() -> bool:
	var path := dir.path_join("users.json")
	if not FileAccess.file_exists(path):
		return false
	var data = _read_json("users.json", null)
	if not data is Dictionary or not data.get("users") is Array:
		push_warning("users.json kunne ikke leses (ugyldig JSON?). Beholder brukerne i minnet.")
		_known[path] = FileAccess.get_file_as_string(path).hash()   # ikke prøv igjen før neste endring
		return false
	users.clear()
	var max_id := 0
	var reset := false
	for raw in data.users:
		if raw is Dictionary:
			var u := normalize_user(raw)
			if raw.get("reset_password") is String and str(raw.reset_password).length() >= Password.MIN_LENGTH:
				u.password = Password.make(str(raw.reset_password))
				reset = true
			if u.id > 0 and u.username != "":
				users[u.id] = u
				max_id = maxi(max_id, u.id)
	next_user_id = maxi(int(data.get("next_id", 1)), max_id + 1)
	if reset:
		save_users()   # skriv bare hashen tilbake, aldri klarteksten
		print("Nytt passord satt fra users.json.")
	return true


# ---------------------------------------------------------------- Annet

func save_avatars() -> void:
	var out := {}
	for id in avatars:
		out[str(id)] = avatars[id]
	_write_json("avatars.json", out)


func save_sessions() -> void:
	_write_json("sessions.json", sessions)


func save_tournaments() -> void:
	_write_json("tournaments.json", { "tournaments": tournaments, "next_id": next_tournament_id })


func append_game(record: Dictionary) -> void:
	if dir == "":
		return
	var path := dir.path_join("games.jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(record))


# ---------------------------------------------------------------- Filer

func _read_json(name: String, fallback: Variant) -> Variant:
	var path := dir.path_join(name)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		DirAccess.rename_absolute(path + ".tmp", path)   # en lagring ble avbrutt: bruk den nye filen
	if not FileAccess.file_exists(path):
		return fallback
	var text := FileAccess.get_file_as_string(path)
	_known[path] = text.hash()
	var json := JSON.new()
	if json.parse(text) != OK:
		return fallback
	return json.data


## Skriver trygt: først til en midlertidig fil, så bytte navn. En krasj midt i ødelegger ikke filen.
func _write_json(name: String, data: Variant) -> void:
	if dir == "":
		return
	var path := dir.path_join(name)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Kunne ikke skrive %s" % tmp)
		return
	var text := JSON.stringify(data, "  ", false)
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
	_known[path] = text.hash()
