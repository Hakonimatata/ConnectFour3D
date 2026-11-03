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
	# Innsjekken (runde 18) har egne tester. Her regnes alle påmeldte som til stede ved start.
	lobby.tournaments.here = func(_t: Dictionary, _uid: int) -> bool: return true


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


## Alle med konto kan lage turneringer (runde 18), men bare private. Uten konto: logg inn først.
func test_everyone_creates_private_and_login_required() -> void:
	_user(2, "Bobo")
	_msg(2, { "t": "tournament_create", "data": { "name": "Bobos cup", "private": false, "ranked": true } })
	check(bool(_last(2, "tournament_state").tournament.private), "vanlige brukere lager private turneringer")
	check(bool(_last(2, "tournament_state").admin), "og styrer sin egen")
	_msg(3, { "t": "hello", "name": "Gjest", "skin": "ocean", "version": Protocol.VERSION })
	_msg(3, { "t": "tournament_create", "data": { "name": "Uten konto" } })
	check_eq(_last(3, "error").code, "login_required")
	var id := _create()
	_msg(3, { "t": "tournament_join", "id": id })
	check_eq(_last(3, "error").code, "login_required")
	_msg(2, { "t": "list_tournaments" })
	check_eq(_last(2, "tournament_list").tournaments.size(), 2, "sin egne private og den offentlige:")
	check_eq(_last(2, "tournament_list").admin, false)
	check(bool(_last(2, "tournament_list").create), "får «Ny turnering»")


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


## Uavgjort i utslag spilles om. Blir også tredje parti uavgjort, går den som ikke startet det, videre
## (ikke den med høyest Elo).
func test_knockout_draw_is_replayed() -> void:
	var id := _create()
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var m: Dictionary = _t(id).rounds[0][0]
	lobby.store.users[m.p2].elo = 2000   # Elo skal ikke avgjøre
	check_eq(lobby.tournaments.report(m.id, 0, true, unix), "replay")
	check_eq(m.status != "done", true)
	check_eq(lobby.tournaments.report(m.id, 0, true, unix), "replay_last", "før siste omspill sies det fra:")
	check_eq(lobby.tournaments.report(m.id, 0, true, unix, m.p1), "", "etter tre uavgjorte avgjøres det:")
	check_eq(m.status, "done")
	check_eq(m.reason, "draws")
	check_eq(m.winner, m.p1, "den som ikke startet tredje parti, går videre:")
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
	check_eq(table[0].points2, 6, "to seire og fri runde = 3 poeng (lagret som 6 halve):")
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
	check_eq(t.pairing, "swiss", "færre runder enn alle mot alle: sveitsisk")
	check_eq(t.rounds.size(), 1, "neste runde settes opp når denne er ferdig:")
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


## Runde 18: alle som møter opp til start, får XP med en gang (i tillegg til XP etter plassering).
func test_show_up_xp() -> void:
	var id := _create("knockout")
	var peers := _join(id, 2)
	_advance(61)
	check_eq(_t(id).status, "running")
	for uid in peers:
		check_eq(int(lobby.store.users[uid].xp), Progression.SHOW_UP_XP)
		var told: Array = _inbox.get(peers[uid], []).filter(func(m: Dictionary) -> bool:
			return m.t == "notice" and str(m.text).contains("møte opp"))
		check_eq(told.size(), 1, "får beskjed")
		check_eq(int(_last(peers[uid], "stats").user.xp), Progression.SHOW_UP_XP, "og den nye progresjonen")


# ---------------------------------------------------------------- Runde 18: alle mot alle uten Elo

## n spillere melder seg på. Gir bruker-id -> peer.
func _join(id: int, n: int) -> Dictionary:
	var peers := {}
	for i in n:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	return peers


## Avgjør alle kampene i runden som pågår (pick(m) gir vinneren, eller 0 for uavgjort), og går videre.
func _decide_round(t: Dictionary, pick: Callable) -> void:
	for m in (t.rounds[int(t.current_round)] as Array).duplicate():
		if m.status != "done" and int(m.p2) != 0:
			var w: int = pick.call(m)
			lobby.tournaments.report(m.id, w, w == 0, unix)
	if t.status == "running":
		_advance(31)


static func _key(m: Dictionary) -> Array:
	return [mini(int(m.p1), int(m.p2)), maxi(int(m.p1), int(m.p2))]


## Sveitsisk (færre runder enn alle mot alle): like mange poeng møtes, ingen møtes to ganger, og hvem som
## starter, fordeles jevnt.
func test_swiss_pairs_by_points_without_rematches() -> void:
	var id := _create("round_robin", { "max_rounds": 3 })
	_join(id, 8)
	_advance(61)
	var t := _t(id)
	check_eq(t.pairing, "swiss")
	for r in 3:
		if r > 0:
			var points := {}
			for row in lobby.tournaments.standings(t):
				points[int(row.id)] = int(row.points2)
			for m in t.rounds[r]:
				check_eq(points[m.p1], points[m.p2], "runde %d: like mange poeng møtes:" % (r + 1))
		_decide_round(t, func(m: Dictionary) -> int: return mini(m.p1, m.p2))   # lavest id vinner
	check_eq(t.status, "finished")
	check_eq(t.rounds.size(), 3)
	var met := {}
	var starts := {}
	for round in t.rounds:
		for m in round:
			check(not met.has(_key(m)), "ingen møtes to ganger: %s" % str(_key(m)))
			met[_key(m)] = true
			# Den som har startet færrest kamper før runden, starter (likt: hvem som helst)
			check(int(starts.get(m.p1, 0)) <= int(starts.get(m.p2, 0)), "den som har startet minst, starter")
		for m in round:
			starts[m.p1] = int(starts.get(m.p1, 0)) + 1
	check_eq(t.winner, (t.players as Array).min(), "den som vant alt:")


## Likt antall poeng avgjøres av innbyrdes oppgjør, ikke Elo. Fri runde gir 1 poeng.
func test_round_robin_ties_without_elo() -> void:
	var id := _create("round_robin")
	_join(id, 4)
	var ids: Array = _t(id).players.duplicate()
	ids.sort()
	var a: int = ids[0]
	var b: int = ids[1]
	var c: int = ids[2]
	var d: int = ids[3]
	for uid in [b, c]:
		lobby.store.users[uid].elo = 2400   # høy Elo skal ikke hjelpe
	# a slår b og d, taper for c. b slår c og d. d slår c. Da har a og b 2 poeng, og a slo b; d og c 1, og d slo c.
	var beats := { [a, b]: a, [a, c]: c, [a, d]: a, [b, c]: b, [b, d]: b, [c, d]: d }
	_advance(61)
	var t := _t(id)
	check_eq(t.pairing, "all")
	for r in 3:
		_decide_round(t, func(m: Dictionary) -> int: return int(beats[_key(m)]))
	check_eq(t.status, "finished")
	var table := lobby.tournaments.standings(t)
	check_eq(table.map(func(row: Dictionary) -> int: return int(row.id)), [a, b, d, c], "innbyrdes avgjør begge likhetene:")
	check_eq(t.winner, a)
	var odd := _create("round_robin", { "name": "Oddetall" })
	for i in 3:
		_msg(i + 2, { "t": "tournament_join", "id": odd })
	_advance(61)
	var t2 := _t(odd)
	_decide_round(t2, func(_m: Dictionary) -> int: return 0)   # uavgjort
	var bye := int(t2.rounds[0].filter(func(m: Dictionary) -> bool: return m.reason == "bye")[0].winner)
	var rows := lobby.tournaments.standings(t2)
	check_eq(int(rows.filter(func(r: Dictionary) -> bool: return int(r.id) == bye)[0].points2), 2, "fri runde gir 1 poeng:")


## Står det helt likt øverst etter siste runde, spilles omkamp om seieren (her: tre som slo hverandre
## i ring, så alt er likt).
func test_round_robin_playoff_when_fully_tied() -> void:
	var id := _create("round_robin")
	var peers := _join(id, 3)
	var ids: Array = _t(id).players.duplicate()
	ids.sort()
	var beats := { [ids[0], ids[1]]: ids[0], [ids[1], ids[2]]: ids[1], [ids[0], ids[2]]: ids[2] }
	_advance(61)
	var t := _t(id)
	for r in 3:
		_decide_round(t, func(m: Dictionary) -> int: return int(beats[_key(m)]))
	check_eq(t.status, "running", "ikke ferdig: omkamp")
	check_eq((t.playoff as Array).size(), 3, "alle tre står likt:")
	check((t.rounds[-1] as Array).all(func(m: Dictionary) -> bool: return m.playoff), "omkamprunden er merket")
	for i in 2:   # første omkamprunde (én kamp og fri runde), så finalen
		var round: Array = t.rounds[int(t.current_round)]
		for m in round:
			if m.status == "scheduled":
				_advance(31)
			if m.status == "waiting":
				_play_match(m, peers)
	check_eq(t.status, "finished", "ferdig etter omkampen")
	var table := lobby.tournaments.standings(t)
	check_eq(int(table[0].id), t.winner, "vinneren av omkampen står øverst:")
	check(Tournaments.final_game(t) > 0, "«Se finalen» viser omkampen")
	_msg(2, { "t": "get_tournament", "id": id })
	check(_last(2, "tournament_state").tournament.rounds[-1][0].playoff, "klienten ser at det er omkamp")


## Sveitsisk: to som står uten motstander, spiller mot hverandre i stedet for å vinne på walkover. Den som
## ikke kom, taper; poengene kommer fra den nye kampen.
func test_swiss_players_without_opponent_play_each_other() -> void:
	var id := _create("round_robin", { "max_rounds": 2 })
	var peers := _join(id, 6)
	_advance(61)
	var t := _t(id)
	var first: Array = t.rounds[0]
	var m1: Dictionary = first[0]
	var m2: Dictionary = first[1]
	_msg(peers[m1.p1], { "t": "join_room", "code": m1.room })   # bare p1 kommer i de to første kampene
	_msg(peers[m2.p1], { "t": "join_room", "code": m2.room })
	_play_match(first[2], peers)
	_advance(121)   # møtefristen
	check_eq(m1.reason, "forfeit", "ikke walkover:")
	check_eq(m2.reason, "forfeit")
	check_eq(m1.winner, 0, "ingen vinner den kampen:")
	check_eq(first.size(), 4, "en ny kamp i runden:")
	var extra: Dictionary = first[3]
	check(extra.extra and extra.status == "waiting", "den nye kampen er i gang")
	check_eq(_key(extra), [mini(m1.p1, m2.p1), maxi(m1.p1, m2.p1)], "de to som kom:")
	check_eq(_last(peers[m1.p1], "tournament_notice").room, extra.room, "spilleren kastes inn i den nye kampen")
	_play_match(extra, peers)
	var rows := {}
	for row in lobby.tournaments.standings(t):
		rows[int(row.id)] = row
	check_eq(int(rows[extra.p1].points2), 2, "seier i den nye kampen:")
	check_eq(int(rows[extra.p2].points2), 0, "tap i den nye kampen:")
	check_eq(int(rows[m1.p2].points2), 0, "den som ikke kom:")
	check_eq(int(rows[m1.p2].losses), 1)
	check_eq(int(t.current_round), 1, "neste runde etter den nye kampen")


## Alle møter alle: de to uten motstander spiller kampen de skulle hatt mot hverandre senere, nå, og vinner
## walkoveren. Blir bare én stående uten motstander, er det walkover som før.
func test_round_robin_players_without_opponent_play_their_later_match() -> void:
	var id := _create("round_robin")
	var peers := _join(id, 4)
	_advance(61)
	var t := _t(id)
	var first: Array = t.rounds[0]
	var m1: Dictionary = first[0]
	var m2: Dictionary = first[1]
	_msg(peers[m1.p1], { "t": "join_room", "code": m1.room })
	_msg(peers[m2.p1], { "t": "join_room", "code": m2.room })
	_advance(121)
	check_eq(m1.reason, "walkover")
	check_eq(m1.winner, m1.p1)
	check_eq(first.size(), 3, "kampen fra en senere runde er flyttet hit:")
	var pulled: Dictionary = first[2]
	check(pulled.extra and pulled.status == "waiting")
	var later := 0
	for r in range(1, t.rounds.size()):
		for m in t.rounds[r]:
			if _key(m) == _key(pulled):
				later += 1
	check_eq(later, 0, "og er borte fra den senere runden:")
	_play_match(pulled, peers)
	check_eq(int(t.current_round), 1, "neste runde")
	# Neste runde: én kamp der bare én kommer, og ingen andre uten motstander: walkover
	_advance(31)
	var second: Array = t.rounds[1]
	var lone: Dictionary = second[0]
	_msg(peers[lone.p1], { "t": "join_room", "code": lone.room })
	for m in second.slice(1):
		if m.status == "waiting":
			_play_match(m, peers)
	_advance(121)
	check_eq(lone.reason, "walkover", "ingen å spille mot: walkover")


## Innsjekken (runde 18): 2 min før start får de påmeldte beskjed (klienten åpner siden). Den som har
## siden oppe, er med; de andre er ute ved start. Begynner innsjekken for sent (serveren var nede), får
## alle hele tiden på seg.
func test_checkin_before_start() -> void:
	lobby.tournaments.here = lobby._views_tournament   # den ekte innsjekken
	var id := _create("knockout", { "start_time": unix + 600, "signup_deadline": unix + 600 })
	var uids := []
	for i in 3:
		_user(i + 2, "Spiller%d" % i)
		uids.append(int(lobby.store.find_user("Spiller%d" % i).id))
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_msg(2, { "t": "view_tournament", "id": id })
	_advance(600 - Tournaments.CHECKIN_S - 5)
	check_eq(_t(id).checkin_at, 0, "ikke ennå")
	_advance(10)
	check(_t(id).checkin_at > 0, "innsjekken er i gang")
	check_eq(_t(id).checked_in, [uids[0]], "den som har siden oppe:")
	check(bool(_last(3, "tournament_notice").get("open", false)), "de andre får beskjed om å åpne siden")
	check(_last(2, "tournament_notice").is_empty())
	_msg(3, { "t": "view_tournament", "id": id })
	_advance(1)
	check_eq(_t(id).checked_in.size(), 2)
	check_eq(_t(id).status, "open", "offentlige turneringer starter på klokkeslettet, ikke før")
	_advance(Tournaments.CHECKIN_S)
	check_eq(_t(id).status, "running")
	check_eq(_t(id).players, [uids[0], uids[1]], "bare de som møtte:")
	check_eq(_t(id).missed, [uids[2]])
	check_eq(_last(4, "notice").key, "Du møtte ikke til start, så du er ikke med i «%s».")
	# Serveren var nede over starttiden: innsjekken begynner nå, og starten flyttes
	var late := _create("knockout", { "name": "Etter omstart", "start_time": unix + 60, "signup_deadline": unix + 60 })
	_msg(3, { "t": "tournament_join", "id": late })
	_msg(4, { "t": "tournament_join", "id": late })
	_advance(300)
	check_eq(_t(late).status, "open", "ikke avlyst fordi ingen rakk å komme")
	check_eq(_t(late).start_time, unix + Tournaments.CHECKIN_S, "alle får hele innsjekken:")
	_msg(3, { "t": "view_tournament", "id": late })
	_msg(4, { "t": "view_tournament", "id": late })
	_advance(Tournaments.CHECKIN_S)
	check_eq(_t(late).status, "running")
	check_eq(_t(late).players.size(), 2)


## Faller man ut underveis, kan man komme tilbake: kobler man til igjen (eller logger inn), kastes man rett
## inn i kampen som venter. «Forlat rommet» for et annet rom (en gammel skjerm som lukkes) gjelder ikke.
func test_dropped_player_comes_back_and_old_leave_is_ignored() -> void:
	var id := _create()
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	var token := str(_last(2, "session").token)
	_advance(61)
	var m: Dictionary = _t(id).rounds[0][0]
	lobby.on_disconnect(2, now)
	_advance(61)   # lenger enn RECONNECT_GRACE_MS: en helt ny tilkobling
	_inbox.erase(2)
	_msg(2, { "t": "hello", "name": "Spiller0", "skin": "ocean", "version": Protocol.VERSION, "session": token })
	check_eq(str(_last(2, "tournament_notice").get("room", "")), str(m.room), "kastes inn i kampen igjen:")
	for uid in peers:
		_msg(peers[uid], { "t": "join_room", "code": m.room })
	var room: Lobby.Room = lobby.rooms[m.room]
	check(room.in_game(), "kampen startet")
	var a: int = peers[m.p1]
	_msg(a, { "t": "leave_room", "code": "QQQQQ" })   # gammelt rom
	check(room.in_game() and room.seat_of(lobby._peers[a]) == 1, "en gammel «forlat rommet» gir ikke tap")
	_msg(a, { "t": "leave_room", "code": m.room })
	check(not room.in_game(), "men å forlate dette rommet gjør det")


## Man kan ikke se på sitt eget parti (samme konto i en annen fane gir stillingsmåleren og «vinner om 3 trekk»).
func test_players_cannot_watch_their_own_game() -> void:
	var id := _create()
	var peers := {}
	for i in 2:
		_user(i + 2, "Spiller%d" % i)
		peers[int(lobby.store.find_user("Spiller%d" % i).id)] = i + 2
		_msg(i + 2, { "t": "tournament_join", "id": id })
	_advance(61)
	var m: Dictionary = _t(id).rounds[0][0]
	var name := lobby.accounts.username_of(int(m.p1))
	_msg(9, { "t": "hello", "name": "Fane 2", "skin": "ocean", "version": Protocol.VERSION })
	_msg(9, { "t": "login", "username": name, "password": "hemmelig123" })
	_msg(9, { "t": "watch", "code": m.room })
	check_eq(_last(9, "error").code, "own_game", "før partiet:")
	for uid in peers:
		_msg(peers[uid], { "t": "join_room", "code": m.room })
	_msg(9, { "t": "watch", "code": m.room })
	check_eq(_last(9, "error").code, "own_game", "og mens det spilles:")
	check(_last(9, "room_state").is_empty())
	_user(8, "Tilskuer")
	_msg(8, { "t": "watch", "code": m.room })
	check_eq(int(_last(8, "room_state").you), 0, "andre kan se på")
