extends TestCase
## Tester for runde 9 på serveren: tilskuere på turneringskamper, global chat og «online»,
## hendelser, merker låst av Elo, partiliste til repriser og dagens oppgave via lobbyen.

const NO_RULES := { "must_block": false, "no_gift": false }

var lobby: Lobby
var _inbox := {}
var now := 1000
var unix := 1_800_000_000


func before_each() -> void:
	lobby = Lobby.new()
	lobby.accounts.iterations = 10
	lobby.send = func(peer: int, msg: Dictionary) -> void:
		_inbox.get_or_add(peer, []).append(Protocol.decode(Protocol.encode(msg)))
	lobby.clock_s = func() -> int: return unix


func after_each() -> void:
	lobby.send = Callable()
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


func _count(peer: int, t: String) -> int:
	return _inbox.get(peer, []).filter(func(m: Dictionary) -> bool: return m.t == t).size()


func _register(peer: int, name: String) -> int:
	_hello(peer, name)
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })
	return int(_last(peer, "session").user.id)


## Begge i et rom, klare, og sete 1 vinner langs x.
func _play_game(p1: int, p2: int) -> void:
	_msg(p1, { "t": "create_room", "options": NO_RULES, "private": true })
	_msg(p2, { "t": "join_room", "code": _last(p1, "room_state").code })
	_msg(p1, { "t": "ready", "ready": true })
	_msg(p2, { "t": "ready", "ready": true })
	var first := int(_last(p1, "game_start").first)
	var a := [[0, 0], [1, 0], [2, 0], [3, 0]]
	var b := [[0, 1], [1, 1], [2, 1]]
	var seats := [p1, p2] if first == 1 else [p2, p1]
	for i in 4:
		_msg(seats[0], { "t": "move", "x": a[i][0], "y": a[i][1], "ply": i * 2 })
		if i < 3:
			_msg(seats[1], { "t": "move", "x": b[i][0], "y": b[i][1], "ply": i * 2 + 1 })


# ---------------------------------------------------------------- Tilskuere

func test_spectator_watches_a_tournament_match() -> void:
	_hello(1, "Ada")
	_hello(2, "Bob")
	_hello(3, "Cy")
	lobby.players[1].user_id = 101
	lobby.players[2].user_id = 102
	var code: String = lobby._open_tournament_room({ "id": 7, "name": "Cup", "options": NO_RULES },
		{ "id": "7-0-0", "p1": 101, "p2": 102 })
	_msg(3, { "t": "watch", "code": code })
	check_eq(_last(3, "room_state").you, 0.0, "tilskueren har ikke sete:")
	_msg(1, { "t": "join_room", "code": code })
	_msg(2, { "t": "join_room", "code": code })
	check_eq(_last(3, "game_start").you, 0.0, "tilskueren får partiet:")
	check_eq(_last(1, "room_state").spectators, 1.0, "spillerne ser antallet:")
	var first := int(_last(1, "game_start").first)
	_msg(first, { "t": "move", "x": 1, "y": 1, "ply": 0 })
	check_eq(_last(3, "move_made").ply, 0.0, "tilskueren ser trekket:")
	_msg(3, { "t": "move", "x": 2, "y": 2, "ply": 1 })
	check_eq(_count(1, "move_made"), 1, "tilskueren kan ikke spille")
	_msg(3, { "t": "chat", "text": "Heia!" })
	check_eq(_last(1, "chat").from, "Cy")
	check_eq(_last(1, "chat").seat, 0.0)
	_msg(3, { "t": "leave_room" })
	check_eq(_last(1, "spectators").count, 0.0)
	check(lobby.rooms[code].in_game(), "partiet fortsetter")


func test_any_running_game_can_be_watched_from_the_live_list() -> void:
	_hello(1, "Ada")
	_hello(2, "Bob")
	_hello(3, "Cy")
	_msg(1, { "t": "create_room", "options": NO_RULES, "private": true })
	var code: String = _last(1, "room_state").code
	_msg(3, { "t": "watch", "code": code })
	check_eq(_last(3, "error").code, "not_watchable", "kan ikke se på før partiet starter:")
	_msg(2, { "t": "join_room", "code": code })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	_msg(3, { "t": "list_rooms" })
	var live: Array = _last(3, "room_list").live
	check_eq(live.size(), 1, "partiet står i listen:")
	check_eq(live[0].code, code)
	check_eq(live[0].players[0].name, "Ada")
	_msg(3, { "t": "watch", "code": code })
	check_eq(_last(3, "game_sync").you, 0.0, "tilskueren får partiet:")
	check_eq(_last(1, "spectators").count, 1.0)
	var first := int(_last(1, "game_start").first)
	_msg(first, { "t": "move", "x": 0, "y": 0, "ply": 0 })
	check_eq(_last(3, "move_made").ply, 0.0, "tilskueren ser trekket:")
	_msg(3, { "t": "list_rooms" })
	check_eq(_last(3, "room_list").live[0].spectators, 1.0)
	_msg(2, { "t": "watch", "code": "ZZZZZ" })
	check_eq(_last(2, "error").code, "no_room")


# ---------------------------------------------------------------- Global chat og online

func test_last_game_is_sent_to_everyone_and_on_hello() -> void:
	_register(1, "Ada")
	_register(2, "Bob")
	_hello(3, "Cy")
	check(_last(3, "last_game").is_empty(), "ingen partier ennå")
	_play_game(1, 2)
	var g: Dictionary = _last(3, "last_game").game
	check_eq((g.moves as Array).size(), 7, "alle får det siste partiet:")
	check_eq(g.players[0].name, "Ada")
	check(not g.has("analysis"), "uten analysen (mindre melding)")
	_hello(4, "Di")
	check_eq(_last(4, "last_game").game.reason, float(GameState.EndReason.LINE), "nye får det etter hello:")
	check_eq((_last(4, "last_game").games as Array).size(), 1, "listen over de siste har bare dette ennå:")
	# Flere partier: de tre siste, nyeste først (menyen spiller av ett av dem om gangen)
	for i in 4:
		lobby.store.games.append({ "id": 100 + i, "moves": [], "players": [], "analysis": {} })
	var msg := lobby.last_game_message()
	check_eq((msg.games as Array).map(func(g: Dictionary) -> int: return g.id), [103, 102, 101], "de tre siste:")
	check_eq(msg.game.id, 103, "game er fortsatt det nyeste")
	check(not msg.games[1].has("analysis"), "uten analysen")


func test_global_chat_presence_and_history() -> void:
	_hello(1, "Ada")
	check(_last(1, "global_history").has("messages"), "historikk etter hello")
	check_eq(_last(1, "presence").online, 1.0)
	_hello(2, "Bob")
	lobby.tick(now + 2000)
	check_eq(_last(1, "presence").online, 2.0, "alle får vite at noen kom:")
	var users: Array = _last(1, "presence").users
	check_eq(users.map(func(u: Dictionary) -> String: return u.name), ["Ada", "Bob"], "og hvem, sortert på navn:")
	check(not users[0].playing, "ingen er i et parti ennå")
	_msg(1, { "t": "global_chat", "text": "  Hei alle  " })
	var m := _last(2, "global_msg")
	check_eq(m.text, "Hei alle")
	check_eq(m.from, "Ada")
	check_eq(m.kind, "chat")
	_msg(1, { "t": "global_chat", "text": "spam" })
	check_eq(_count(2, "global_msg"), 1, "for raske meldinger stoppes:")
	_hello(3, "Cy")
	check_eq((_last(3, "global_history").messages as Array).size(), 1, "nye ser det som er skrevet:")
	lobby.on_disconnect(2, now)
	lobby.tick(now + 4000)
	check_eq(_last(1, "presence").online, 2.0)


func test_events_for_new_account_and_new_rank() -> void:
	var a := _register(1, "Ada")
	check_eq(_last(1, "global_msg").key, "Velkommen, %s!")
	var b := _register(2, "Bob")
	lobby.store.users[a].elo = 1245
	lobby.store.users[b].elo = 1245
	_play_game(1, 2)
	var winner_name := "Ada" if lobby.store.users[a].stats.wins == 1 else "Bob"
	var events: Array = _inbox[1].filter(func(x: Dictionary) -> bool:
		return x.t == "global_msg" and x.get("key") == "%s rykket opp til %s!")
	check_eq(events.size(), 1, "én hendelse for nytt nivå:")
	check_eq(events[0].args, [winner_name, "Gull"])


# ---------------------------------------------------------------- Merker låst av Elo

func test_decals_are_checked_against_elo() -> void:
	_hello(1, "Gjest", { "decal": "crown" })
	_msg(1, { "t": "create_room", "options": {}, "private": true })
	check_eq(_last(1, "room_state").players[0].decal, "none", "gjester får ikke låste merker:")
	_msg(1, { "t": "set_look", "decal": "star" })
	check_eq(_last(1, "room_state").players[0].decal, "star", "åpne merker går fint:")
	var uid := _register(2, "Bob")
	_msg(2, { "t": "create_room", "options": {}, "private": true })
	_msg(2, { "t": "set_look", "decal": "diamond" })
	check_eq(_last(2, "room_state").players[0].decal, "diamond", "sølv (1200) låser opp diamant:")
	_msg(2, { "t": "set_look", "decal": "crown" })
	check_eq(_last(2, "room_state").players[0].decal, "none", "krone krever diamant-nivå:")
	lobby.store.users[uid].elo = 1600
	_msg(2, { "t": "set_look", "decal": "crown" })
	check_eq(_last(2, "room_state").players[0].decal, "crown")
	check(EloTiers.decal_unlocked("laurel", 1900) and not EloTiers.decal_unlocked("laurel", 1800))


# ---------------------------------------------------------------- Repriser

func test_games_are_listed_and_can_be_fetched() -> void:
	_register(1, "Ada")
	_register(2, "Bob")
	_play_game(1, 2)
	_msg(1, { "t": "list_games" })
	var games: Array = _last(1, "game_list").games
	check_eq(games.size(), 1)
	check_eq(games[0].moves, 7.0)
	check_eq(games[0].players, ["Ada", "Bob"])
	_msg(2, { "t": "list_games", "username": "Ada" })
	check_eq((_last(2, "game_list").games as Array).size(), 1, "andres partier kan også vises:")
	_msg(1, { "t": "get_game", "id": int(games[0].id) })
	var g: Dictionary = _last(1, "game_record").game
	check_eq((g.moves as Array).size(), 7)
	check_eq(g.players[0].skin, "ocean", "utseendet lagres for reprisen:")
	_msg(1, { "t": "get_game", "id": 99 })
	check_eq(_last(1, "error").code, "no_game")


# ---------------------------------------------------------------- Dagens oppgave

func test_daily_puzzle_solve_streak_and_leaderboard() -> void:
	var uid := _register(1, "Ada")
	_msg(1, { "t": "get_puzzle" })
	var info := _last(1, "puzzle")
	var puzzle: Dictionary = info.puzzle
	check(int(puzzle.depth) >= 3, "oppgaven har dybde")
	check_eq(info.solved, false)
	var sol := Puzzle.solution(puzzle)
	var mine := []
	for i in range(0, sol.size(), 2):
		mine.append([sol[i].x, sol[i].y])
	_msg(1, { "t": "puzzle_solve", "day": puzzle.day, "moves": [mine[0]], "attempts": 1 })
	check_eq(_last(1, "puzzle_result").ok, false, "halv løsning godtas ikke:")
	_msg(1, { "t": "puzzle_solve", "day": puzzle.day, "moves": mine, "attempts": 2 })
	var res := _last(1, "puzzle_result")
	check_eq(res.ok, true)
	check_eq(res.rank, 1.0)
	check_eq(_last(1, "puzzle").solved, true)
	check_eq(_last(1, "global_msg").key, "%s løste dagens oppgave (nr. %d i dag).")
	check_eq(lobby.store.users[uid].stats.puzzles_solved, 1)
	_msg(1, { "t": "puzzle_solve", "day": puzzle.day, "moves": mine, "attempts": 1 })
	check_eq(lobby.store.users[uid].stats.puzzles_solved, 1, "teller bare én gang per dag:")
	_msg(1, { "t": "get_leaderboard" })
	check_eq(_last(1, "leaderboard").boards.puzzles[0].username, "Ada")

	# Neste dag: rekken øker
	unix += 86400
	_msg(1, { "t": "get_puzzle" })
	var next: Dictionary = _last(1, "puzzle").puzzle
	check(next.day != puzzle.day, "ny dag, ny oppgave")
	var sol2 := Puzzle.solution(next)
	var mine2 := []
	for i in range(0, sol2.size(), 2):
		mine2.append([sol2[i].x, sol2[i].y])
	_msg(1, { "t": "puzzle_solve", "day": next.day, "moves": mine2, "attempts": 1 })
	check_eq(lobby.store.users[uid].stats.puzzle_streak, 2, "to dager på rad:")
	_msg(1, { "t": "puzzle_solve", "day": puzzle.day, "moves": mine, "attempts": 1 })
	check_eq(_last(1, "puzzle_result").ok, false, "gårsdagens oppgave godtas ikke i dag:")
