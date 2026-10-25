extends TestCase
## Tester for turneringer (server/tournaments.gd) gjennom lobbyen, uten nettverk.
## Peer 1 = admin «Ada». Peer 2–5 = spillere. Tiden styres med `now` (ms) og `unix` (sekunder).

var lobby: Lobby
var _inbox := {}
var now := 1000
var unix := 1_800_000_000
var _dir := ""


func before_each() -> void:
	lobby = Lobby.new()
	lobby.accounts.iterations = 10
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


func _user(peer: int, name: String) -> void:
	_msg(peer, { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION })
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })


## Admin lager og publiserer en turnering som starter om 60 s. Gir id.
func _create(format := "knockout", extra := {}) -> int:
	if lobby.store.find_user("Ada").is_empty():
		_user(1, "Ada")
		lobby.accounts.set_admin("Ada", true)
	var data := { "name": "Høstcup", "format": format, "start_time": unix + 60, "signup_deadline": unix + 60,
		"round_gap_s": 30, "show_up_s": 120, "options": { "must_block": false, "no_gift": false } }
	data.merge(extra, true)
	_msg(1, { "t": "tournament_create", "data": data })
	var id := int(_last(1, "tournament_state").tournament.id)
	_msg(1, { "t": "tournament_action", "id": id, "action": "publish" })
	return id


func _t(id: int) -> Dictionary:
	return lobby.tournaments.get_t(id)


func _advance(seconds: int) -> void:
	unix += seconds
	now += seconds * 1000
	lobby.tick(now)


## Begge spillerne i kampen går til rommet, og p1 vinner langs x.
func _play_match(m: Dictionary, peers: Dictionary, p1_wins := true) -> void:
	var a: int = peers[m.p1]
	var b: int = peers[m.p2]
	_msg(a, { "t": "join_room", "code": m.room })
	_msg(b, { "t": "join_room", "code": m.room })
	var start := _last(a, "game_start")
	check(not start.is_empty(), "kampen skal starte når begge er inne")
	var first: int = int(start.first)
	var starter: int = a if first == 1 else b
	var other: int = b if starter == a else a
	var winner_peer: int = a if p1_wins else b
	# Den som skal vinne legger langs y=0, den andre langs y=1. Den som ikke starter, må gi bort et tempo.
	var w := [[0, 0], [1, 0], [2, 0], [3, 0]]
	var l := [[0, 1], [1, 1], [2, 1], [0, 2]]
	var order: Array = [starter, other]
	var room = lobby.rooms.get(m.room)
	var ply := 0
	var wi := 0
	var li := 0
	while ply < 12 and not (room.state != null and room.state.is_over()):
		var peer: int = order[ply % 2]
		var mv: Array
		if peer == winner_peer:
			mv = w[wi]
			wi += 1
		else:
			mv = l[li]
			li += 1
		_msg(peer, { "t": "move", "x": mv[0], "y": mv[1], "ply": ply })
		ply += 1


func test_admin_only_and_login_required() -> void:
	_user(2, "Bobo")
	_msg(2, { "t": "tournament_create", "data": { "name": "Juks" } })
	check_eq(_last(2, "error").code, "admin_only")
	_msg(3, { "t": "hello", "name": "Gjest", "skin": "ocean", "version": Protocol.VERSION })
	var id := _create()
	_msg(3, { "t": "tournament_join", "id": id })
	check_eq(_last(3, "error").code, "login_required")
	_msg(2, { "t": "list_tournaments" })
	check_eq(_last(2, "tournament_list").tournaments.size(), 1)
	check_eq(_last(2, "tournament_list").admin, false)


func test_knockout_with_walkover_and_winner() -> void:
	var id := _create()
	var peers := {}
	for i in 4:
		var peer := i + 2
		_user(peer, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = peer
		_msg(peer, { "t": "tournament_join", "id": id })
	check_eq(_t(id).players.size(), 4)
	_msg(2, { "t": "tournament_join", "id": id })
	check_eq(_t(id).players.size(), 4, "kan ikke melde seg på to ganger:")

	_advance(61)   # starttid
	var t := _t(id)
	check_eq(t.status, "running")
	check_eq(t.rounds[0].size(), 2)
	var m0: Dictionary = t.rounds[0][0]
	var m1: Dictionary = t.rounds[0][1]
	check_eq(m0.status, "waiting")
	check(not _last(peers[m0.p1], "tournament_notice").is_empty(), "spilleren varsles om kampen")

	# Kamp 0 spilles. I kamp 1 møter bare p1.
	_play_match(m0, peers)
	check_eq(m0.status, "done")
	check_eq(m0.winner, m0.p1)
	_msg(peers[m1.p1], { "t": "join_room", "code": m1.room })
	_advance(121)   # møtefristen går ut
	check_eq(m1.status, "done")
	check_eq(m1.reason, "walkover")
	check_eq(m1.winner, m1.p1)

	# Finale etter pausen mellom rundene
	check_eq(t.rounds.size(), 2)
	var final: Dictionary = t.rounds[1][0]
	check_eq(final.status, "scheduled")
	_advance(31)
	check_eq(final.status, "waiting")
	_play_match(final, peers, false)
	check_eq(t.status, "finished")
	check_eq(t.winner, final.p2)
	check_eq(lobby.store.users[final.p2].stats.tournaments_won, 1)


func test_winner_gets_the_trophy_and_list_shows_joined() -> void:
	var design := { "seed": 42, "shape": "star", "metal": "ruby", "handles": "none", "emblem": "four", "base": "jade" }
	var id := _create("knockout", { "trophy": design })
	check_eq(_t(id).trophy, Trophy.normalize(design), "turneringen får pokalen admin valgte:")
	var other := _create("knockout", { "name": "Uten valg" })
	check(Trophy.SHAPES.has(str(_t(other).trophy.shape)), "uten valg får den en tilfeldig pokal")
	var peers := {}
	for i in 2:
		var peer := i + 2
		_user(peer, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = peer
		_msg(peer, { "t": "tournament_join", "id": id })
	_msg(2, { "t": "list_tournaments" })
	var listed: Array = _last(2, "tournament_list").tournaments
	var mine: Dictionary = listed.filter(func(s: Dictionary) -> bool: return int(s.id) == id)[0]
	check(mine.joined, "listen sier at du er påmeldt")
	check(not listed.filter(func(s: Dictionary) -> bool: return int(s.id) == other)[0].joined)
	check_eq(mine.trophy.shape, "star", "listen har pokalen:")
	_advance(61)
	var final: Dictionary = _t(id).rounds[0][0]
	_play_match(final, peers)
	var t := _t(id)
	check_eq(t.status, "finished")
	check_eq(t.finished_at, unix, "tidspunktet den ble ferdig:")
	var trophies: Array = lobby.store.users[final.p1].trophies
	check_eq(trophies.size(), 1, "vinneren får pokalen:")
	check_eq(trophies[0].name, "Høstcup")
	check_eq(trophies[0].design, Trophy.normalize(design))
	check_eq(int(trophies[0].tournament), id)
	check_eq(lobby.store.users[final.p2].trophies.size(), 0, "taperen får ingen:")
	_msg(2, { "t": "get_stats", "username": lobby.accounts.username_of(final.p1) })
	check_eq((_last(2, "stats").user.trophies as Array).size(), 1, "pokalen vises i statistikken:")


func test_knockout_draw_is_replayed() -> void:
	var id := _create()
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var m: Dictionary = _t(id).rounds[0][0]
	check_eq(lobby.tournaments.report(m.id, 0, true, unix), "replay")
	check_eq(m.status != "done", true)
	check_eq(lobby.tournaments.report(m.id, 0, true, unix), "replay")
	check_eq(lobby.tournaments.report(m.id, 0, true, unix), "", "etter tre uavgjorte avgjøres det:")
	check_eq(m.status, "done")
	check_eq(m.reason, "draws")
	check_eq(_t(id).status, "finished")


func test_round_robin_with_bye_and_table() -> void:
	var id := _create("round_robin")
	var ids := []
	for i in 3:
		_user(i + 2, "Spiller%d" % i)
		_msg(i + 2, { "t": "tournament_join", "id": id })
		ids.append(int(lobby.store.find_user("Spiller%d" % i).id))
	_advance(61)
	var t := _t(id)
	check_eq(t.rounds.size(), 3, "3 spillere + fri runde = 3 runder:")
	# Avgjør alle kampene direkte: den med lavest id vinner
	for r in 3:
		for m in t.rounds[r]:
			if m.status != "done":
				lobby.tournaments.report(m.id, mini(m.p1, m.p2), false, unix)
		if t.status == "running":
			_advance(31)
	check_eq(t.status, "finished")
	var table := lobby.tournaments.standings(t)
	check_eq(table[0].id, ids.min(), "vinneren har flest poeng:")
	check_eq(table[0].points2, 4, "to seire = 2 poeng (lagret som 4 halve):")
	check_eq(t.winner, ids.min())


func test_too_few_players_cancels_and_deadline() -> void:
	var id := _create()
	_user(2, "Ensom")
	_msg(2, { "t": "tournament_join", "id": id })
	_advance(61)
	check_eq(_t(id).status, "cancelled")
	var id2 := _create("knockout", { "name": "Sen" })
	_advance(61)
	_user(3, "Treig")
	_msg(3, { "t": "tournament_join", "id": id2 })
	check(not _last(3, "error").is_empty(), "påmelding etter fristen avvises")


func test_tournaments_survive_restart() -> void:
	_dir = "user://test_tour_%d" % randi()
	var st := Store.new()
	st.open(_dir)
	lobby.use_store(st)
	lobby.accounts.iterations = 10
	var id := _create()
	_user(2, "Bobo")
	_msg(2, { "t": "tournament_join", "id": id })
	var again := Store.new()
	again.open(_dir)
	var tours := Tournaments.new(again, Accounts.new(again))
	var t := tours.get_t(id)
	check_eq(t.name, "Høstcup")
	check_eq(t.status, "open")
	check_eq(typeof(t.players[0]), TYPE_INT, "tall er heltall igjen etter JSON:")
