class_name Store
extends RefCounted
## Varig lagring i JSON-filer i én datamappe, laget for å være lett å lese og redigere:
##   users.json        brukere: brukernavn, admin, Elo, statistikk, profil og passord-hash
##   avatars.json      profilbilder (base64), adskilt så users.json er lett å lese
##   sessions.json     innloggede økter (bare en hash av nøkkelen lagres)
##   tournaments.json  turneringer
##   games.jsonl       ett ferdig parti per linje (repriser; id = linjenummer)
##   puzzles.json      dagens oppgave og hvem som har løst den, de siste dagene
##   global_chat.json  de siste meldingene og hendelsene i den globale chatten (per kanal)
##   feedback.jsonl    tilbakemeldinger fra kanalen «tilbakemelding», én per linje
##
## Endrer du users.json (f.eks. setter "admin": true eller "banned": true) mens serveren kjører,
## merker serveren det innen et sekund og laster filen inn på nytt. En utestengt bruker som er
## online, blir kastet ut.
## Glemt passord: skriv "reset_password": "nytt-passord" på brukeren. Serveren lager en
## hash av det og fjerner klarteksten fra filen med en gang. Ugyldig JSON blir ikke lastet; da
## beholdes det gamle og en feil skrives til loggen.
## dir = "" betyr lagring bare i minnet (brukes av testene).

var dir := ""
var users: Dictionary = {}          ## id (int) -> bruker
var avatars: Dictionary = {}        ## id (int) -> base64
var sessions: Dictionary = {}       ## hash av nøkkel -> { user, created }
var tournaments: Array = []         ## turneringer (eies av Tournaments)
var games: Array = []               ## ferdige partier (også i minnet, for repriser). id = indeks + 1
var puzzles: Dictionary = {}        ## { days: { dato: { puzzle, solvers } } } (eies av Puzzles)
var global_chat: Array = []         ## siste meldinger i den globale chatten (eies av Social)
var next_user_id := 1
var next_tournament_id := 1
var _known: Dictionary = {}         ## fil -> hash av innholdet da vi sist leste/skrev det
var _known_mtime: Dictionary = {}   ## fil -> endringstid da vi sist så på innholdet


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
	var pz = _read_json("puzzles.json", {})
	if pz is Dictionary:
		puzzles = pz
	var gc = _read_json("global_chat.json", [])
	if gc is Array:
		global_chat = gc
	_load_games()


## Kalles jevnlig. Laster users.json på nytt hvis noen har endret den. Gir true hvis lastet.
func poll() -> bool:
	if dir == "":
		return false
	var path := dir.path_join("users.json")
	if not FileAccess.file_exists(path):
		return false
	# Billig sjekk først: er endringstiden den samme som sist, og ikke helt fersk, er filen urørt.
	# (Endringstiden har bare hele sekunder, så de første sekundene etter en endring leses innholdet.)
	var mtime := FileAccess.get_modified_time(path)
	if mtime == int(_known_mtime.get(path, -1)) and int(Time.get_unix_time_from_system()) - mtime > 2:
		return false
	_known_mtime[path] = mtime
	# Sammenlign innholdet (så serverens egne lagringer ikke regnes som endringer).
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
	var trophies: Array = (d.get("trophies", []) if d.get("trophies") is Array else []).map(Trophy.normalize_entry) \
		.filter(func(e: Dictionary) -> bool: return not e.is_empty())
	# Runde 17: XP og opplåste ting. Kontoer fra før får XP ut fra statistikken, og beholder skinnet og
	# seiersanimasjonen de bruker (selv om nivået ikke holder).
	var xp := int(d.get("xp", -1))
	var unlocks: Array = (d.get("unlocks", []) as Array).map(func(v: Variant) -> String: return str(v)) \
		if d.get("unlocks") is Array else []
	if xp < 0:
		xp = Progression.backfill_xp(clean_stats)
		var progress := { "xp": xp, "unlocks": unlocks, "tournaments_won": clean_stats.tournaments_won,
			"best_puzzle_streak": clean_stats.best_puzzle_streak }
		for item in ["skin:" + str(profile.get("skin", "ocean")), "fx:" + str(profile.get("win_fx", "classic"))]:
			if not Progression.is_unlocked(item, progress):
				unlocks.append(item)
	var xp_day: Dictionary = d.get("xp_day", {}) if d.get("xp_day") is Dictionary else {}
	return {
		"id": int(d.get("id", 0)),
		"username": str(d.get("username", "")),
		"admin": bool(d.get("admin", false)),
		"banned": bool(d.get("banned", false)),
		"ban_reason": str(d.get("ban_reason", "")),
		"trophies": trophies,
		"friends": _ids(d.get("friends", [])),                  # venner (bruker-id-er, begge veier)
		"friend_requests": _ids(d.get("friend_requests", [])),  # venneforespørsler til denne brukeren
		"created": str(d.get("created", "")),
		"elo": int(d.get("elo", 1200)),
		"stats": clean_stats,
		"last_puzzle": str(d.get("last_puzzle", "")),   # dato for sist løste oppgave (for rekken)
		"xp": xp,
		"unlocks": unlocks,                              # låst opp uten nivå: premier og det de brukte før XP
		"xp_day": { "day": str(xp_day.get("day", "")), "games": int(xp_day.get("games", 0)),
			"opponents": xp_day.get("opponents", {}) if xp_day.get("opponents") is Dictionary else {} },
		"profile": { "skin": str(profile.get("skin", "ocean")), "decal": str(profile.get("decal", "none")),
			"win_fx": str(profile.get("win_fx", "classic")), "decal_color": str(profile.get("decal_color", "auto")),
			"away": bool(profile.get("away", false)),
			"avatar_removed": bool(profile.get("avatar_removed", false)) },   # fjernet bildet: ikke hent det fra en annen enhet
		"password": d.get("password", {}),
	}


## En liste med bruker-id-er fra JSON (desimaltall og søppel blir borte, ingen duplikater).
static func _ids(v: Variant) -> Array:
	var out := []
	if v is Array:
		for x in v:
			if (x is int or x is float) and int(x) > 0 and not int(x) in out:
				out.append(int(x))
	return out


const STAT_KEYS := ["games", "wins", "losses", "draws", "current_streak", "best_streak", "fastest_win",
	"forced_moves", "double_threats", "best_forced_win", "wins_line", "wins_time", "wins_resign",
	"wins_walkover", "losses_time", "losses_resign", "tournaments_won", "puzzles_solved", "puzzle_streak",
	"best_puzzle_streak"]


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


func save_puzzles() -> void:
	_write_json("puzzles.json", puzzles)


func save_global_chat() -> void:
	_write_json("global_chat.json", global_chat)


## Tilbakemeldinger fra kanalen «tilbakemelding» i chatten: én per linje, til admin.
func append_feedback(record: Dictionary) -> void:
	if dir == "":
		return
	var path := dir.path_join("feedback.jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(record))


## Lagrer et ferdig parti (gir det en id) og gir id-en.
func append_game(record: Dictionary) -> int:
	record.id = games.size() + 1
	games.append(record)
	if dir == "":
		return record.id
	var path := dir.path_join("games.jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(record))
	return record.id


func get_game(id: int) -> Dictionary:
	return games[id - 1] if id >= 1 and id <= games.size() else {}


## De siste partiene til en bruker, nyeste først.
func games_of(user_id: int, limit := 20) -> Array:
	var out := []
	for i in range(games.size() - 1, -1, -1):
		var g: Dictionary = games[i]
		for p in g.get("players", []):
			if p is Dictionary and int(p.get("user", 0)) == user_id:
				out.append(g)
				break
		if out.size() >= limit:
			break
	return out


func _load_games() -> void:
	games.clear()
	var path := dir.path_join("games.jsonl")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	while f and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var json := JSON.new()
		var g = json.data if json.parse(line) == OK else null
		if g is Dictionary:
			g.id = games.size() + 1
			games.append(g)


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
