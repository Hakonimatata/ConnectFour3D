extends TestCase
## Tester for passord, lagring (users.json), kontoer, statistikk, Elo og analyse av partier.

var lobby: Lobby
var _inbox := {}
var now := 1000
var unix := 1_800_000_000
var _dir := ""


func before_each() -> void:
	lobby = Lobby.new()
	lobby.accounts.iterations = 10   # fort i testene (ekte servere bruker Password.ITERATIONS)
	lobby.send = func(peer: int, msg: Dictionary) -> void:
		_inbox.get_or_add(peer, []).append(Protocol.decode(Protocol.encode(msg)))
	lobby.clock_s = func() -> int: return unix


func after_each() -> void:
	lobby.send = Callable()
	lobby.clock_s = Callable()
	if _dir != "":
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)


func _msg(peer: int, msg: Dictionary) -> void:
	lobby.on_message(peer, msg, now)


func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _hello(peer: int, name: String, session := "") -> void:
	_msg(peer, { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION, "session": session })


func _register(peer: int, name: String) -> String:
	_hello(peer, name)
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })
	return str(_last(peer, "session").get("token", ""))


## Spiller et parti der sete 1 vinner langs x (begge må allerede sitte i et rom).
func _play_win_for_seat1() -> void:
	var a := [[0, 0], [1, 0], [2, 0], [3, 0]]
	var b := [[0, 1], [1, 1], [2, 1]]
	for i in 4:
		_msg(1, { "t": "move", "x": a[i][0], "y": a[i][1], "ply": i * 2 })
		if i < 3:
			_msg(2, { "t": "move", "x": b[i][0], "y": b[i][1], "ply": i * 2 + 1 })


# ---------------------------------------------------------------- Passord

func test_pbkdf2_matches_standard_test_vectors() -> void:
	var p := "password".to_utf8_buffer()
	var s := "salt".to_utf8_buffer()
	check_eq(Password.pbkdf2(p, s, 1).hex_encode(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
	check_eq(Password.pbkdf2(p, s, 2).hex_encode(), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
	check_eq(Password.pbkdf2(p, s, 4096).hex_encode(), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")


func test_password_make_and_verify() -> void:
	var rec := Password.make("riktig-passord", 50)
	check(Password.verify("riktig-passord", rec))
	check(not Password.verify("feil-passord", rec))
	check(not rec.has("password"), "klartekst skal aldri lagres")
	check(Password.make("x", 5).salt != Password.make("x", 5).salt, "ulikt salt hver gang")


func test_real_iteration_count_is_fast_enough() -> void:
	var t := Time.get_ticks_msec()
	Password.make("passord123")
	var ms := Time.get_ticks_msec() - t
	print("        (%d runder: %d ms)" % [Password.ITERATIONS, ms])
	check(ms < 2000, "hashing tok %d ms" % ms)


# ---------------------------------------------------------------- Lagring

func _temp_store() -> Store:
	_dir = "user://test_store_%d" % randi()
	var st := Store.new()
	st.open(_dir)
	return st


func test_store_persists_and_reloads_hand_edits() -> void:
	var st := _temp_store()
	var u := st.add_user("hakon", Password.make("hemmelig123", 5))
	check(FileAccess.file_exists(_dir.path_join("users.json")))
	var again := Store.new()
	again.open(_dir)
	check_eq(again.find_user("HAKON").get("id"), u.id, "finnes etter omstart (og store/små bokstaver er like):")

	# Rediger filen for hånd, slik en admin ville gjort
	var text := FileAccess.get_file_as_string(_dir.path_join("users.json"))
	check(text.contains("\"admin\": false"), "lesbar JSON med innrykk")
	FileAccess.open(_dir.path_join("users.json"), FileAccess.WRITE).store_string(text.replace("\"admin\": false", "\"admin\": true"))
	check(again.poll(), "endringen skal oppdages")
	check_eq(again.find_user("hakon").admin, true)
	check(not again.poll(), "ingen ny endring")

	# Ugyldig JSON skal ikke slette brukerne
	FileAccess.open(_dir.path_join("users.json"), FileAccess.WRITE).store_string("{ ødelagt")
	again.poll()
	check(not again.find_user("hakon").is_empty(), "beholder brukerne ved ugyldig fil")


func test_normalize_fills_missing_fields() -> void:
	var u := Store.normalize_user({ "id": 3.0, "username": "ny" })
	check_eq(u.id, 3)
	check_eq(u.elo, Accounts.START_ELO)
	check_eq(u.stats.wins, 0)
	check_eq(u.admin, false)


## Arrangørrettigheten fra tidligere i runde 18 er borte (alle kan lage private turneringer): feltet ryddes
## bort fra users.json når filen leses, og alt annet blir som før.
func test_old_organizer_field_is_cleaned_up() -> void:
	var st := _temp_store()
	st.add_user("arran", Password.make("hemmelig123", 5))
	var path := _dir.path_join("users.json")
	var text := FileAccess.get_file_as_string(path)
	FileAccess.open(path, FileAccess.WRITE).store_string(text.replace("\"admin\": false,",
		"\"admin\": false,\n      \"organizer\": true,"))
	check(FileAccess.get_file_as_string(path).contains("organizer"), "som en gammel users.json")
	var again := Store.new()
	again.open(_dir)
	check(not again.find_user("arran").has("organizer"), "ikke i minnet")
	check(not FileAccess.get_file_as_string(path).contains("organizer"), "og fjernet fra filen")
	check(Password.verify("hemmelig123", again.find_user("arran").password), "resten er som før")


# ---------------------------------------------------------------- Kontoer

func test_register_login_logout_and_session() -> void:
	var token := _register(1, "Ada")
	check(token != "", "registrering gir økt")
	check_eq(_last(1, "session").user.username, "Ada")
	_hello(2, "Ada2")
	_msg(2, { "t": "register", "username": "ada", "password": "annetpassord" })
	check_eq(_last(2, "auth_error").key, "Brukernavnet er tatt.")
	_msg(2, { "t": "register", "username": "Bobo", "password": "kort" })
	check_eq(_last(2, "auth_error").key, "Passordet må ha minst 8 tegn.")
	_msg(2, { "t": "login", "username": "Ada", "password": "feilfeilfeil" })
	check_eq(_last(2, "auth_error").key, "Feil brukernavn eller passord.")
	_msg(2, { "t": "login", "username": "ADA", "password": "hemmelig123" })
	check(not _last(2, "session").is_empty(), "innlogging med riktig passord")
	# Husket økt på ny tilkobling
	_hello(3, "Gjest", token)
	check_eq(_last(3, "welcome").user.username, "Ada")
	_msg(3, { "t": "logout", "session": token })
	check(not _last(3, "logged_out").is_empty())
	_hello(4, "Gjest", token)
	check_eq(_last(4, "welcome").get("user"), null, "utlogget økt virker ikke lenger")


## Bytte brukernavn: samme krav som ved registrering, alle enhetene får det nye navnet, innloggingen
## følger med, gamle profillenker virker, og det går høyst ett bytte per Protocol.RENAME_DAYS dager.
func test_change_username() -> void:
	var token := _register(1, "Ada")
	_register(2, "Bobo")
	_hello(3, "Gjest", token)   # Ada på en annen enhet
	_hello(5, "Gjest")
	_msg(5, { "t": "rename", "username": "Hacker" })
	check_eq(_last(5, "error").code, "login_required", "gjester kan ikke")
	for bad in [["bobo", "Brukernavnet er tatt."], ["a", "Brukernavnet må være 3–16 tegn (bokstaver, tall, - og _)."],
			["Ada", "Det er allerede brukernavnet ditt."]]:
		_msg(1, { "t": "rename", "username": bad[0] })
		check_eq(_last(1, "error").key, bad[1], "%s:" % bad[0])
	_msg(1, { "t": "rename", "username": "Adelheid" })
	check_eq(_last(1, "renamed").user.username, "Adelheid", "byttet:")
	check_eq(_last(3, "renamed").user.username, "Adelheid", "den andre enheten får også det nye navnet:")
	_msg(2, { "t": "get_stats", "username": "Ada" })
	check_eq(_last(2, "stats").user.username, "Adelheid", "gamle lenker til profilen virker:")
	_hello(6, "Gjest")
	_msg(6, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(6, "auth_error").key, "Feil brukernavn eller passord.", "det gamle navnet logger ikke inn:")
	_msg(6, { "t": "login", "username": "adelheid", "password": "hemmelig123" })
	check(not _last(6, "session").is_empty(), "det nye navnet logger inn")
	# Høyst ett bytte per uke, men store og små bokstaver kan rettes
	_msg(1, { "t": "rename", "username": "Adele" })
	check_eq(_last(1, "error").key, "Du kan bytte brukernavn igjen om %d dager.")
	check_eq(int(_last(1, "error").args[0]), Protocol.RENAME_DAYS)
	_msg(1, { "t": "rename", "username": "ADELHEID" })
	check_eq(_last(1, "renamed").user.username, "ADELHEID", "bare store bokstaver:")
	unix += Protocol.RENAME_DAYS * 86400 + 1
	_msg(1, { "t": "rename", "username": "Adele" })
	check_eq(_last(1, "renamed").user.username, "Adele", "etter en uke går det igjen:")
	# Det gamle navnet er ledig for andre, og da går lenken til den nye eieren
	_msg(5, { "t": "register", "username": "Ada", "password": "annetpassord" })
	check(not _last(5, "session").is_empty(), "det gamle navnet er ledig")
	_msg(2, { "t": "get_stats", "username": "Ada" })
	check(int(_last(2, "stats").user.id) != int(lobby.store.find_user("Adele").id), "et navn noen har nå, går foran")
	check_eq(lobby.store.find_user("Adele").old_names, ["Ada", "ADELHEID"], "tidligere navn huskes (slik de var sist):")


## Samme konto i to faner kan ikke spille mot seg selv: den andre fanen får ikke sette seg, og kommer
## de seg likevel i begge setene (logget inn i rommet), teller ikke partiet.
func test_no_games_against_yourself() -> void:
	var token := _register(1, "Ada")
	_hello(2, "Gjest", token)   # samme konto i en annen fane
	_msg(1, { "t": "create_room", "options": { "must_block": false, "no_gift": false } })
	var code := str(_last(1, "room_state").code)
	_msg(2, { "t": "join_room", "code": code })
	check_eq(_last(2, "error").code, "self_play", "den andre fanen får ikke sette seg:")
	# Omvei: to gjester setter seg, og logger så inn på samme konto i rommet
	_msg(1, { "t": "leave_room" })
	_hello(3, "Gjest3")
	_hello(4, "Gjest4")
	_msg(3, { "t": "create_room", "options": { "must_block": false, "no_gift": false } })
	_msg(4, { "t": "join_room", "code": str(_last(3, "room_state").code) })
	for peer in [3, 4]:
		_msg(peer, { "t": "login", "username": "Ada", "password": "hemmelig123" })
		_msg(peer, { "t": "ready", "ready": true })
	_inbox.clear()
	var a := [[0, 0], [1, 0], [2, 0], [3, 0]]
	var b := [[0, 1], [1, 1], [2, 1]]
	var first := 3 if lobby.rooms.values().any(func(r: Lobby.Room) -> bool: return r.state != null and r.state.first_player == 1) else 4
	var second := 7 - first
	for i in 4:
		_msg(first, { "t": "move", "x": a[i][0], "y": a[i][1], "ply": i * 2 })
		if i < 3:
			_msg(second, { "t": "move", "x": b[i][0], "y": b[i][1], "ply": i * 2 + 1 })
	check(not _last(first, "game_over").is_empty(), "partiet ble spilt")
	var u := lobby.store.find_user("Ada")
	check_eq(int(u.stats.games), 0, "partiet teller ikke i statistikken:")
	check_eq(int(u.stats.best_forced_win), 0, "og gir ingen rekorder")
	check(lobby.social.history_message().messages.all(func(m: Dictionary) -> bool:
		return not str(m.get("text", "")).contains("tvungne trekk")), "og ingen hendelse i chatten")


func test_login_is_rate_limited() -> void:
	_register(1, "Ada")
	_hello(2, "Mallory")
	for i in Accounts.MAX_FAILURES:
		_msg(2, { "t": "login", "username": "Ada", "password": "gjett%d" % i })
	_msg(2, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(2, "auth_error").key, "For mange forsøk. Vent noen minutter og prøv igjen.")
	unix += Accounts.FAILURE_WINDOW_S + 1
	_msg(2, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check(not _last(2, "session").is_empty(), "går igjen etter ventetiden")


func test_stats_and_elo_after_rated_game() -> void:
	_register(1, "Ada")
	_register(2, "Bobo")
	_msg(1, { "t": "create_room", "options": { "must_block": false, "no_gift": false }, "private": true })
	_msg(2, { "t": "join_room", "code": _last(1, "room_state").code })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	_play_win_for_seat1()
	var over := _last(2, "game_over")
	check_eq(over.elo["1"].after, 1216.0, "lik rating: vinneren får +16:")
	check_eq(over.elo["2"].after, 1184.0)
	var ada := lobby.store.find_user("Ada")
	check_eq(ada.stats.wins, 1)
	check_eq(ada.stats.fastest_win, 4)
	check(ada.stats.forced_moves >= 1, "tre på rad med åpen ende er et tvunget trekk")
	check_eq(lobby.store.find_user("Bobo").stats.losses, 1)
	_msg(2, { "t": "get_stats", "username": "ada" })
	check_eq(_last(2, "stats").user.elo, 1216.0)
	_msg(2, { "t": "get_leaderboard" })
	check_eq(_last(2, "leaderboard").boards.elo[0].username, "Ada")


func test_guests_get_no_elo() -> void:
	_register(1, "Ada")
	_hello(2, "Gjest")
	_msg(1, { "t": "create_room", "options": { "must_block": false, "no_gift": false }, "private": true })
	_msg(2, { "t": "join_room", "code": _last(1, "room_state").code })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	_play_win_for_seat1()
	check_eq(_last(1, "game_over").elo, {}, "Elo bare når begge er innlogget:")
	check_eq(lobby.store.find_user("Ada").stats.wins, 1, "statistikk teller likevel:")
	check_eq(lobby.store.find_user("Ada").elo, Accounts.START_ELO)


# ---------------------------------------------------------------- Analyse

func test_analysis_counts_forced_moves_and_double_threats() -> void:
	var o := GameOptions.new()
	# P1 bygger (1,0) (2,0) og (0,1) (0,2), og legger så (0,0): to vinnerplasser på en gang,
	# (3,0) og (0,3). P2 legger spredt og truer aldri.
	var moves := [[1, 0], [3, 3], [2, 0], [2, 2], [0, 1], [3, 1], [0, 2], [1, 2], [0, 0]]
	var a := GameAnalysis.analyze(o, 1, moves)
	check_eq(a[1].double_threats, 1, "dobbel trussel:")
	check_eq(a[1].forced, 1, "tvungne trekk P1:")
	check_eq(a[2].forced, 0, "tvungne trekk P2:")

	# P1: tre på rad (tvungent, P2 kan ikke vinne), P2: tre på rad (ikke tvungent, P1 kan vinne), P1 vinner.
	var win := GameAnalysis.analyze(o, 1, [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0]])
	check_eq(win[1].forced, 1)
	check_eq(win[1].winning_streak, 1, "seier med 1 tvunget trekk:")
	check_eq(win[2].forced, 0, "en trussel teller ikke når motstanderen kan vinne direkte:")


func test_reset_password_from_users_json() -> void:
	var st := _temp_store()
	st.add_user("glemsk", Password.make("gammelt-passord", 5))
	var path := _dir.path_join("users.json")
	var text := FileAccess.get_file_as_string(path)
	text = text.replace("\"username\": \"glemsk\",", "\"username\": \"glemsk\",\n      \"reset_password\": \"nytt-passord-1\",")
	FileAccess.open(path, FileAccess.WRITE).store_string(text)
	check(st.poll(), "endringen oppdages")
	check(Password.verify("nytt-passord-1", st.find_user("glemsk").password), "nytt passord virker")
	check(not FileAccess.get_file_as_string(path).contains("nytt-passord-1"), "klarteksten er fjernet fra filen")
