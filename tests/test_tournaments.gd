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


## Uranket uten pokal: ingen Elo, ingen pokal, ingen turneringsseier og ingen kunngjøring.
func test_unranked_tournament_without_trophy() -> void:
	var id := _create("knockout", { "ranked": false, "with_trophy": false })
	var peers := {}
	for i in 2:
		var peer := i + 2
		_user(peer, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = peer
		_msg(peer, { "t": "tournament_join", "id": id })
	_msg(2, { "t": "list_tournaments" })
	var listed: Dictionary = _last(2, "tournament_list").tournaments[0]
	check_eq(listed.ranked, false, "listen sier at den er uranket:")
	check_eq(listed.with_trophy, false)
	_advance(61)
	var final: Dictionary = _t(id).rounds[0][0]
	_play_match(final, peers)
	check_eq(_t(id).status, "finished")
	var winner: Dictionary = lobby.store.users[final.p1]
	check_eq(winner.elo, Accounts.START_ELO, "Elo endres ikke:")
	check_eq(winner.stats.wins, 1, "men seieren telles i statistikken:")
	check_eq(winner.stats.tournaments_won, 0, "ingen turneringsseier:")
	check_eq(winner.trophies.size(), 0, "ingen pokal:")
	var said: Array = lobby.social.history_message().messages.map(func(m: Dictionary) -> String: return str(m.get("text", "")))
	check(not said.any(func(s: String) -> bool: return s.contains("Høstcup")), "ikke kunngjort i chatten: %s" % str(said))


## Pokal uten Elo og omvendt er hvert sitt valg.
func test_ranked_without_trophy_still_counts() -> void:
	var id := _create("knockout", { "with_trophy": false })
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var final: Dictionary = _t(id).rounds[0][0]
	_play_match(final, peers)
	var winner: Dictionary = lobby.store.users[final.p1]
	check(winner.elo > Accounts.START_ELO, "Elo teller")
	check_eq(winner.stats.tournaments_won, 1)
	check_eq(winner.trophies.size(), 0, "men ingen pokal:")


## Turneringssiden viser hvem som har kommet til kampen, og når walkoveren kommer.
func test_waiting_match_shows_who_is_here_and_walkover_time() -> void:
	var id := _create()
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var m: Dictionary = _t(id).rounds[0][0]
	_msg(peers[m.p1], { "t": "join_room", "code": m.room })
	var room: Dictionary = _last(peers[m.p1], "room_state")
	check_eq(int(room.tournament.walkover_in), 120, "venterommet viser tiden til walkover:")
	_msg(2, { "t": "get_tournament", "id": id })
	var pm: Dictionary = _last(2, "tournament_state").tournament.rounds[0][0]
	check_eq(pm.here, [true, false], "hvem som er her:")
	check_eq(int(pm.walkover_at), unix + 120)


## Turneringschatten: for dem som har siden oppe eller er i en kamp i turneringen.
func test_tournament_chat() -> void:
	var id := _create()
	_user(2, "Bobo")
	_user(3, "Cyra")
	_user(4, "Dino")
	_msg(2, { "t": "view_tournament", "id": id })
	_msg(3, { "t": "view_tournament", "id": id })
	_msg(2, { "t": "tournament_chat", "id": id, "text": "Lykke til alle!" })
	check_eq(_last(3, "tournament_chat_msg").messages[0].text, "Lykke til alle!", "de som har siden oppe:")
	check(_last(4, "tournament_chat_msg").is_empty(), "andre får den ikke")
	_msg(4, { "t": "tournament_chat", "id": id, "text": "" })
	var history: Dictionary = _last(4, "tournament_chat_msg")
	check(history.history, "tom tekst gir historikken")
	check_eq(history.messages[0].from, "Bobo")


func test_calendar_file() -> void:
	var id := _create()
	var page := lobby.web_page("kalender/%d.ics" % id, "fourinspace.com")
	check_eq(page.get("type", ""), "text/calendar; charset=utf-8")
	var body := str(page.get("body", ""))
	check(body.begins_with("BEGIN:VCALENDAR"), body.substr(0, 40))
	check(body.contains("SUMMARY:Turnering: Høstcup"), "navnet er med")
	check(body.contains("https://fourinspace.com/?turnering=%d" % id), "lenken til siden er med")
	check(body.contains("DTSTART:" + Time.get_datetime_string_from_unix_time(unix + 60).replace("-", "").replace(":", "") + "Z"))
	check(lobby.web_page("kalender/999.ics", "x").is_empty(), "ukjent turnering")
	check(lobby.web_page("index.html", "x").is_empty(), "vanlige filer serveres som før")


## Nedtelling før hvert parti: trekk avvises og klokken står til den er ferdig.
func test_countdown_before_every_game() -> void:
	Lobby.countdown_ms = 3000
	_user(2, "Bobo")
	_user(3, "Cyra")
	_msg(2, { "t": "create_room", "options": { "must_block": false, "no_gift": false, "time_base_s": 60 }, "private": true })
	var code: String = _last(2, "room_state").code
	_msg(3, { "t": "join_room", "code": code })
	_msg(2, { "t": "ready", "ready": true })
	_msg(3, { "t": "ready", "ready": true })
	Lobby.countdown_ms = 0
	var start := _last(2, "game_start")
	check_eq(int(start.countdown), 3000, "nedtellingen er med i meldingen:")
	var first := 2 if int(start.you) == int(start.first) else 3
	_msg(first, { "t": "move", "x": 0, "y": 0, "ply": 0 })
	check_eq(_last(first, "move_rejected").text, "Vent til nedtellingen er ferdig.")
	var room = lobby.rooms[code]
	now += 2000
	check_eq(room.clock.time_left(room.state.first_player, now), 60_000, "klokken står under nedtellingen:")
	now += 1500
	_msg(first, { "t": "move", "x": 0, "y": 0, "ply": 0 })
	check(not _last(first, "move_made").is_empty(), "etter nedtellingen kan man spille")
	check_eq(room.clock.time_left(room.state.first_player, now), 59_500, "bare 0,5 s er brukt:")


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


## «Klar» i pausen mellom rundene: når begge i neste kamp er klare, starter den med en gang.
func test_ready_skips_the_break_between_rounds() -> void:
	var id := _create()
	var peers := {}
	for i in 4:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var t := _t(id)
	for m in t.rounds[0]:
		_play_match(m, peers)
	var final: Dictionary = t.rounds[1][0]
	check_eq(final.status, "scheduled", "pause før finalen:")
	_msg(peers[final.p1], { "t": "tournament_ready", "id": id })
	check_eq(final.status, "scheduled", "én klar er ikke nok:")
	check_eq(_last(peers[final.p2], "tournament_notice").args[0], lobby.accounts.username_of(final.p1),
		"den andre får beskjed:")
	_msg(peers[final.p2], { "t": "get_tournament", "id": id })
	check_eq(_last(peers[final.p2], "tournament_state").tournament.rounds[1][0].ready, [true, false])
	_msg(peers[final.p2], { "t": "tournament_ready", "id": id })
	lobby.tick(now)
	check_eq(final.status, "waiting", "begge klare: kampen starter uten å vente ut pausen:")
	_msg(peers[final.p1], { "t": "tournament_ready", "id": id })
	check_eq(_last(peers[final.p1], "error").code, "tournament", "ingen kamp å bli klar for nå")


## Påmeldte får turneringschatten selv uten siden oppe, og alle får den mens turneringen pågår.
func test_tournament_chat_reaches_participants() -> void:
	var id := _create()
	_user(2, "Bobo")
	_user(3, "Cyra")
	_user(4, "Dino")
	_msg(2, { "t": "tournament_join", "id": id })
	_msg(3, { "t": "tournament_join", "id": id })
	_msg(3, { "t": "tournament_chat", "id": id, "text": "Gleder meg!" })
	check_eq(_last(2, "tournament_chat_msg").messages[0].text, "Gleder meg!", "påmeldt:")
	check(_last(4, "tournament_chat_msg").is_empty(), "ikke påmeldt og turneringen har ikke startet")
	_advance(61)
	now += 2000
	_msg(2, { "t": "tournament_chat", "id": id, "text": "Lykke til!" })
	check_eq(_last(4, "tournament_chat_msg").messages[0].text, "Lykke til!", "alle mens den pågår:")


## Alle mot alle med høyst 2 runder (admin kan endre det før start): hver spiller spiller 2 partier.
func test_round_robin_with_limited_rounds() -> void:
	var id := _create("round_robin", { "max_rounds": 3 })
	check_eq(int(_t(id).max_rounds), 3)
	_msg(1, { "t": "tournament_update", "id": id, "data": { "max_rounds": 2 } })
	check_eq(int(_t(id).max_rounds), 2, "admin endret antall runder:")
	var peers := {}
	for i in 6:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var t := _t(id)
	check_eq(t.rounds.size(), 2, "bare 2 runder (ikke 5):")
	for r in 2:
		if r > 0:
			_advance(31)
		for m in t.rounds[r]:
			if m.status == "waiting":
				_play_match(m, peers)
	check_eq(t.status, "finished", "ferdig etter 2 runder:")
	var games := {}
	for r in t.rounds:
		for m in r:
			for p in [m.p1, m.p2]:
				games[p] = int(games.get(p, 0)) + 1
	check(games.values().all(func(n: int) -> bool: return n == 2), "alle spilte 2 partier: %s" % str(games))
	_msg(2, { "t": "list_tournaments" })
	check_eq(int(_last(2, "tournament_list").tournaments[0].max_rounds), 2, "listen viser grensen:")


## Runde 17: partiene lagres på kampene, så finalen (og de andre kampene) kan ses i reprise.
func test_final_can_be_replayed() -> void:
	var id := _create()
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var t := _t(id)
	var final: Dictionary = t.rounds[0][0]
	_play_match(final, peers)
	check_eq(t.status, "finished")
	check_eq((final.games as Array).size(), 1, "partiet er lagret på kampen")
	var game_id := int(final.games[0])
	check_eq(str(lobby.store.get_game(game_id).tournament), str(final.id))
	_msg(2, { "t": "get_tournament", "id": id })
	var pub: Dictionary = _last(2, "tournament_state").tournament
	check_eq(int(pub.final_game), game_id, "«Se finalen»")
	check_eq(int(pub.rounds[0][0].games[0]), game_id, "reprise av kampen")
	_msg(2, { "t": "get_game", "id": game_id })
	check_eq(int(_last(2, "game_record").game.id), game_id)
	# Turneringer fra før runde 17 (uten partiene på kampene) finner dem i partiloggen ved oppstart
	final.games = []
	var again := Tournaments.new(lobby.store, lobby.accounts)
	check_eq(int(Tournaments.final_game(again.get_t(id))), game_id)


## Runde 17: admin kan endre turneringen. Før start alt, mens den pågår navn, pauser, møtefrist og pokal.
func test_admin_can_edit_before_and_during() -> void:
	var id := _create()
	_msg(1, { "t": "tournament_update", "id": id, "data": { "name": "Vintercup", "format": "round_robin", "max_players": 8 } })
	check_eq(_t(id).name, "Vintercup")
	check_eq(_t(id).format, "round_robin")
	check_eq(_t(id).max_players, 8)
	for i in 3:
		_user(i + 2, "Spiller%d" % i)
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	check_eq(_t(id).status, "running")
	var start := int(_t(id).start_time)
	_msg(1, { "t": "tournament_update", "id": id, "data": { "name": "Vintercup 2", "round_gap_s": 300, "show_up_s": 600,
		"format": "knockout", "max_players": 4, "start_time": unix + 9999 } })
	check(_last(1, "error").is_empty() or _last(1, "error").code != "tournament", "endringen godtas")
	check_eq(_t(id).name, "Vintercup 2")
	check_eq(_t(id).round_gap_s, 300)
	check_eq(_t(id).show_up_s, 600)
	check_eq(_t(id).format, "round_robin", "formatet ligger fast etter start")
	check_eq(_t(id).max_players, 8)
	check_eq(int(_t(id).start_time), start, "starttiden ligger fast")


## Runde 17: rangert turnering gir XP etter plassering, og vinneren får premien og Mester-skinnet.
func test_tournament_xp_and_prize() -> void:
	var id := _create("knockout", { "prize": "skin:blackhole" })
	check_eq(str(_t(id).prize), "skin:blackhole")
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var final: Dictionary = _t(id).rounds[0][0]
	var xp_before := {}
	for uid in peers:
		xp_before[uid] = int(lobby.store.users[uid].xp)
	_play_match(final, peers)
	var winner: Dictionary = lobby.store.users[int(final.p1)]
	var loser: Dictionary = lobby.store.users[int(final.p2)]
	check_eq(Tournaments.new(lobby.store, lobby.accounts).placements(_t(id)), { int(final.p1): "winner", int(final.p2): "final" })
	check("skin:blackhole" in winner.unlocks, "premien")
	var progress := Progression.progress_of(winner)
	check(Progression.is_unlocked("skin:champion", progress), "første turneringsseier låser opp Mester")
	check(int(loser.xp) - int(xp_before[int(final.p2)]) >= Progression.TOURNAMENT_XP.final, "finalisten får XP")
	var notice := _last(peers[int(final.p1)], "notice")
	check(str(notice.text).contains("XP"), str(notice))
	check(str(notice.text).contains("Sort hull"), "premien står i beskjeden: " + str(notice.text))
