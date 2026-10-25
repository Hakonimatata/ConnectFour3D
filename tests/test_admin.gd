extends TestCase
## Tester for runde 13 på serveren: utestenging, kunngjøringer og pokaler (net/trophy.gd).
## Peer 1 = admin «Ada».

var lobby: Lobby
var _inbox := {}
var _closed: Array[int] = []
var now := 1000
var unix := 1_800_000_000


func before_each() -> void:
	lobby = Lobby.new()
	lobby.accounts.iterations = 10
	lobby.send = func(peer: int, msg: Dictionary) -> void:
		_inbox.get_or_add(peer, []).append(Protocol.decode(Protocol.encode(msg)))
	lobby.close_peer = func(peer: int) -> void: _closed.append(peer)
	lobby.clock_s = func() -> int: return unix
	_hello(1, "Ada")
	_msg(1, { "t": "register", "username": "Ada", "password": "hemmelig123" })
	lobby.accounts.set_admin("Ada", true)


func after_each() -> void:
	lobby.send = Callable()
	lobby.close_peer = Callable()
	lobby.clock_s = Callable()


func _msg(peer: int, msg: Dictionary) -> void:
	lobby.on_message(peer, msg, now)


func _hello(peer: int, name: String, extra := {}) -> void:
	var m := { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION }
	m.merge(extra, true)
	_msg(peer, m)


func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _register(peer: int, name: String) -> String:
	_hello(peer, name)
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })
	return str(_last(peer, "session").token)


func _admin(msg: Dictionary) -> Dictionary:
	msg.t = "admin"
	_msg(1, msg)
	return _last(1, "admin_result")


# ---------------------------------------------------------------- Utestenging

func test_ban_kicks_blocks_login_and_unban() -> void:
	var session := _register(2, "Bob")
	var bob := int(lobby.store.find_user("Bob").id)
	var res := _admin({ "action": "ban", "username": "bob", "reason": "Banning i chatten" })
	check(res.ok, "admin kan utestenge")
	check_eq(res.text, "Bob er utestengt.")
	check_eq((res.banned as Array).size(), 1, "listen over utestengte:")
	check_eq(res.banned[0].reason, "Banning i chatten")
	# Bob er online: får beskjed, logges ut og kobles fra
	check_eq(_last(2, "error").code, "banned")
	check(str(_last(2, "error").text).contains("Banning i chatten"), "grunnen vises")
	check(2 in _closed, "koblet fra")
	check_eq(lobby.players[lobby._peers[2]].user_id, 0, "logget ut")
	# Kan ikke logge inn, og den gamle økten virker ikke
	_hello(3, "Bob igjen")
	_msg(3, { "t": "login", "username": "Bob", "password": "hemmelig123" })
	check_eq(_last(3, "auth_error").key, "Kontoen din er utestengt. Grunn: %s")
	_hello(4, "Bob med økt", { "session": session })
	check(_last(4, "welcome").user == null, "husket innlogging gir ikke tilgang")
	# Toppliste uten utestengte
	lobby.store.users[bob].stats.games = 3
	check(lobby.accounts.leaderboard().elo.all(func(r: Dictionary) -> bool: return r.username != "Bob"),
		"utestengte vises ikke på topplisten")
	# Opphev
	res = _admin({ "action": "unban", "username": "Bob" })
	check(res.ok)
	check_eq((res.banned as Array).size(), 0)
	_msg(3, { "t": "login", "username": "Bob", "password": "hemmelig123" })
	check_eq(str(_last(3, "session").user.username), "Bob", "kan logge inn igjen")


func test_only_admin_and_not_other_admins() -> void:
	_register(2, "Bob")
	_msg(2, { "t": "admin", "action": "ban", "username": "Ada" })
	check_eq(_last(2, "error").code, "admin_only")
	_msg(2, { "t": "admin", "action": "announce", "text": "Hei" })
	check_eq(_last(2, "error").code, "admin_only")
	var res := _admin({ "action": "ban", "username": "Ada" })
	check(not res.ok, "en admin kan ikke utestenges")
	res = _admin({ "action": "ban", "username": "Ingen" })
	check_eq(res.text, "Fant ikke brukeren Ingen.")


func test_ban_removes_from_open_tournament() -> void:
	_register(2, "Bob")
	var bob := int(lobby.store.find_user("Bob").id)
	_msg(1, { "t": "tournament_create", "data": { "name": "Cup", "start_time": unix + 600 } })
	var id := int(_last(1, "tournament_state").tournament.id)
	_msg(1, { "t": "tournament_action", "id": id, "action": "publish" })
	_msg(2, { "t": "tournament_join", "id": id })
	check(bob in lobby.tournaments.get_t(id).players)
	_admin({ "action": "ban", "username": "Bob" })
	check(not bob in lobby.tournaments.get_t(id).players, "fjernet fra påmeldingen")


func test_banned_in_users_json_is_kicked_on_reload() -> void:
	_register(2, "Bob")
	lobby.store.find_user("Bob").banned = true   # som å skrive "banned": true i users.json
	lobby.on_users_reloaded()
	check_eq(_last(2, "error").code, "banned")
	check(2 in _closed)


# ---------------------------------------------------------------- Kunngjøringer

func test_announcement_reaches_everyone_and_history() -> void:
	_hello(2, "Gjest")
	var res := _admin({ "action": "announce", "text": "  Turnering i kveld kl. 20!  " })
	check(res.ok)
	var m := _last(2, "global_msg")
	check_eq(m.kind, "announcement")
	check_eq(m.text, "Turnering i kveld kl. 20!")
	check_eq(m.from, "Ada")
	_hello(3, "Ny")
	check_eq(_last(3, "global_history").messages[-1].kind, "announcement", "nye ser den i historikken:")
	res = _admin({ "action": "announce", "text": "   " })
	check(not res.ok, "tom kunngjøring sendes ikke")


# ---------------------------------------------------------------- Pokaler

func test_admin_awards_a_trophy() -> void:
	_register(2, "Bob")
	var design := Trophy.generate(7)
	var res := _admin({ "action": "award", "username": "bob", "name": "Årets spiller", "design": design })
	check(res.ok)
	check_eq(res.text, "Bob fikk pokalen «Årets spiller».")
	var trophies: Array = lobby.store.find_user("Bob").trophies
	check_eq(trophies.size(), 1)
	check_eq(trophies[0].name, "Årets spiller")
	check_eq(trophies[0].design, design)
	check_eq(int(trophies[0].tournament), 0, "gitt av admin, ingen turnering:")
	check_eq(_last(2, "global_msg").key, "%s fikk pokalen «%s»!", "kunngjøres i chatten:")
	res = _admin({ "action": "award", "username": "Ingen", "name": "X" })
	check(not res.ok)


func test_trophy_generate_and_normalize() -> void:
	check_eq(Trophy.generate(123), Trophy.generate(123), "samme frø gir samme pokal:")
	var differ := false
	for s in 20:
		if Trophy.generate(s) != Trophy.generate(1000):
			differ = true
	check(differ, "ulike frø gir ulike pokaler")
	var fixed := Trophy.normalize({ "seed": 5, "shape": "tull", "metal": "gold", "base": 3 })
	check(fixed.shape in Trophy.SHAPES, "ukjent form byttes ut")
	check_eq(fixed.metal, "gold", "gyldige verdier beholdes:")
	check(fixed.base in Trophy.BASES)
	var entry := Trophy.normalize_entry({ "name": "", "design": "søppel", "date": "2026-10-25T20:00" })
	check_eq(entry.name, Trophy.DEFAULT_NAME)
	check_eq(entry.date, "2026-10-25")
	check(Trophy.normalize_entry(5).is_empty())
	# Brukere fra før pokalene (og hånd-redigerte) får en gyldig liste
	var u := Store.normalize_user({ "id": 1, "username": "X", "trophies": [{ "name": "A" }, "tull"] })
	check_eq((u.trophies as Array).size(), 1)
	check_eq(u.banned, false)
