extends TestCase
## Ende-til-ende-test av en hel turnering over ekte WebSockets, slik den vil gå på en server:
## fire spillere med konto, admin lager turneringen, alle melder seg på, utslag med to runder,
## en gjest ser på en kamp, og vinneren publiseres i den globale chatten.
## Klokka på serveren styres av testen (clock_s), så vi slipper å vente på starttid og pauser.

const PORT := 18780
const NO_RULES := { "must_block": false, "no_gift": false }


class RawClient:
	var ws := WebSocketPeer.new()
	var inbox: Array[Dictionary] = []
	var user_id := 0

	func poll() -> void:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			inbox.append(Protocol.decode(ws.get_packet().get_string_from_utf8()))

	func send(msg: Dictionary) -> void:
		ws.send_text(Protocol.encode(msg))

	func last(t: String) -> Dictionary:
		for i in range(inbox.size() - 1, -1, -1):
			if inbox[i].t == t:
				return inbox[i]
		return {}


var server: ServerMain
var clients: Array[RawClient] = []
var unix := 1_800_000_000


func after_each() -> void:
	for c in clients:
		c.ws.close()
	clients.clear()
	if server:
		server.lobby.clock_s = Callable()
		server.queue_free()
		server = null
	await tree.process_frame


func _pump(cond: Callable, timeout_s := 5.0) -> bool:
	return await wait_until(func() -> bool:
		for c in clients:
			c.poll()
		return cond.call()
	, timeout_s)


func _client(name: String, register: bool) -> RawClient:
	var c := RawClient.new()
	clients.append(c)
	c.ws.connect_to_url("ws://127.0.0.1:%d" % PORT)
	check(await _pump(func() -> bool: return c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN), "%s koblet ikke til" % name)
	c.send({ "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION })
	if register:
		c.send({ "t": "register", "username": name, "password": "hemmelig123" })
		check(await _pump(func() -> bool: return not c.last("session").is_empty()), "%s fikk ikke konto" % name)
		c.user_id = int(c.last("session").user.id)
	else:
		check(await _pump(func() -> bool: return not c.last("welcome").is_empty()), "%s fikk ikke welcome" % name)
	return c


## Spiller én kamp: begge går inn i rommet, og den som starter vinner langs x.
func _play_match(m: Dictionary, by_uid: Dictionary) -> int:
	var a: RawClient = by_uid[int(m.p1)]
	var b: RawClient = by_uid[int(m.p2)]
	a.inbox.clear()
	b.inbox.clear()
	a.send({ "t": "join_room", "code": m.room })
	b.send({ "t": "join_room", "code": m.room })
	check(await _pump(func() -> bool: return not a.last("game_start").is_empty() and not b.last("game_start").is_empty()),
		"kampen %s startet ikke" % m.id)
	var starter: RawClient = a if int(a.last("game_start").first) == 1 else b
	var other: RawClient = b if starter == a else a
	for i in 4:
		starter.send({ "t": "move", "x": i, "y": 0, "ply": i * 2 })
		check(await _pump(func() -> bool: return other.inbox.any(func(x: Dictionary) -> bool:
			return x.t == "move_made" and int(x.ply) == i * 2)), "trekket kom ikke fram")
		if i < 3:
			other.send({ "t": "move", "x": i, "y": 1, "ply": i * 2 + 1 })
			check(await _pump(func() -> bool: return starter.inbox.any(func(x: Dictionary) -> bool:
				return x.t == "move_made" and int(x.ply) == i * 2 + 1)), "svaret kom ikke fram")
	check(await _pump(func() -> bool: return not a.last("game_over").is_empty()), "partiet ble ikke ferdig")
	return starter.user_id


func test_full_tournament_over_websockets() -> void:
	server = ServerMain.new()
	server.data_dir = ":memory:"
	server.port = PORT
	server.lobby.clock_s = func() -> int: return unix
	root.add_child(server)
	server.lobby.accounts.iterations = 10   # etter oppstart (lagringen lager kontoene på nytt)

	var ada := await _client("Ada", true)
	var bob := await _client("Bob", true)
	var cyd := await _client("Cyd", true)
	var dag := await _client("Dag", true)
	var guest := await _client("Gjest 1234", false)
	var by_uid := {}
	for c in [ada, bob, cyd, dag]:
		by_uid[c.user_id] = c
	check(server.lobby.accounts.set_admin("Ada", true), "Ada blir admin")

	# Admin lager og publiserer turneringen, og alle melder seg på
	ada.send({ "t": "tournament_create", "data": { "name": "Testcup", "format": "knockout", "start_time": unix + 60,
		"signup_deadline": unix + 60, "round_gap_s": 30, "show_up_s": 120, "options": NO_RULES } })
	check(await _pump(func() -> bool: return not ada.last("tournament_state").is_empty()), "turneringen ble ikke laget")
	var id := int(ada.last("tournament_state").tournament.id)
	ada.send({ "t": "tournament_action", "id": id, "action": "publish" })
	for c in [ada, bob, cyd, dag]:
		c.send({ "t": "tournament_join", "id": id })
	check(await _pump(func() -> bool: return server.lobby.tournaments.get_t(id).players.size() == 4), "alle fire er påmeldt")
	guest.send({ "t": "list_tournaments" })
	check(await _pump(func() -> bool: return not guest.last("tournament_list").is_empty()), "gjester ser listen")
	check_eq(guest.last("tournament_list").tournaments[0].status, "open")

	# Starttid: turneringen starter, kampene får rom, og spillerne varsles
	unix += 61
	check(await _pump(func() -> bool: return server.lobby.tournaments.get_t(id).status == "running"), "turneringen startet ikke")
	check(await _pump(func() -> bool: return not ada.last("tournament_notice").is_empty()), "varsel om kamp")
	var round1: Array = server.lobby.tournaments.get_t(id).rounds[0]
	check_eq(round1.size(), 2, "to kamper i første runde:")

	# En gjest ser på den første kampen
	guest.send({ "t": "watch", "code": round1[0].room })
	check(await _pump(func() -> bool: return int(guest.last("room_state").get("you", -1)) == 0), "tilskueren kom inn")
	var winners := []
	for m in round1:
		winners.append(await _play_match(m, by_uid))
	check(not guest.last("game_over").is_empty(), "tilskueren så slutten på kampen")

	# Pause mellom rundene, så finalen
	unix += 31
	check(await _pump(func() -> bool:
		var t := server.lobby.tournaments.get_t(id)
		return t.rounds.size() == 2 and str(t.rounds[1][0].room) != ""
	), "finalen fikk ikke rom")
	var final: Dictionary = server.lobby.tournaments.get_t(id).rounds[1][0]
	check(int(final.p1) in winners and int(final.p2) in winners, "vinnerne møtes i finalen")
	var champion := await _play_match(final, by_uid)

	check(await _pump(func() -> bool: return server.lobby.tournaments.get_t(id).status == "finished"), "turneringen ble ikke ferdig")
	check_eq(int(server.lobby.tournaments.get_t(id).winner), champion, "riktig vinner:")
	var name: String = server.lobby.accounts.username_of(champion)
	check(await _pump(func() -> bool: return guest.inbox.any(func(x: Dictionary) -> bool:
		return x.t == "global_msg" and x.get("key") == "%s vant turneringen «%s»!" and x.args[0] == name)),
		"vinneren publiseres i den globale chatten")
	check_eq(server.lobby.store.users[champion].stats.tournaments_won, 1)
	check_eq(server.lobby.store.games.size(), 3, "tre partier lagret til repriser:")
