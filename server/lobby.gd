class_name Lobby
extends RefCounted
## All serverlogikk: spillere, rom, partier, klokker, chat, kontoer og turneringer.
## Global chat og hendelser ligger i Social, dagens oppgave i Puzzles.
## Vet ingenting om nettverk. ServerMain gir meldinger inn (on_message) og
## sender det Lobby legger ut via `send`. Tiden (now_ms) gis utenfra.
## Derfor kan hele serveren testes uten sockets (se tests/test_lobby.gd).

const RECONNECT_GRACE_MS := 60_000
const CHAT_INTERVAL_MS := 350
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"   # uten I og O
const CODE_LENGTH := 5
const PRESENCE_INTERVAL_MS := 1000
const MAX_PRESENCE_USERS := 100   ## så mange navn sendes i «hvem er online»
const LAST_GAMES := 3              ## så mange av de siste partiene hovedmenyen får (spilles av etter tur)
const STREAK_MILESTONES := [5, 10, 15, 20, 30, 50]
const FORCED_WIN_EVENT := 3       ## seier med minst så mange tvungne trekk på rad blir en hendelse


class Player:
	var id: int
	var name: String
	var skin: String
	var decal := "none"
	var win_fx := "classic"
	var decal_color := "auto"
	var away := false              ## valgt drakt (bortedrakt)
	var avatar := ""               ## base64-JPEG, sjekket med AvatarData.is_valid
	var look_pending := false      ## utseendet ble endret uten nett: enhetens utseende vinner ved innlogging
	var token: String
	var peer := 0                  ## 0 = frakoblet
	var room_code := ""
	var disconnected_at := -1
	var last_chat_ms := -100_000
	var user_id := 0               ## 0 = gjest (ikke innlogget)
	var guest_name := ""           ## kallenavnet fra hello (brukes igjen etter utlogging)
	var watching := ""             ## romkoden spilleren ser på som tilskuer
	var last_global_ms := -100_000
	var viewing_tournament := 0    ## turneringen spilleren har oppe (får endringer med en gang)


class Room:
	var code: String
	var private := false
	var options := GameOptions.new()
	var seats: Array[int] = [0, 0, 0]          ## indeks 1 og 2 = spiller-id (0 = ledig)
	var ready: Array[bool] = [false, false, false]
	var rematch: Array[bool] = [false, false, false]
	var state: GameState = null
	var clock := ChessClock.new()
	var number := 0
	# Turneringskamp: bare de to påmeldte kan bli med, og reglene er låst.
	var match_id := ""
	var tournament_id := 0
	var tournament_name := ""
	var reserved: Array[int] = [0, 0, 0]       ## bruker-id per sete
	var replay_at := -1                         ## omspill etter uavgjort (ms)
	var match_done := false                     ## turneringskampen er avgjort (rommet kan ryddes)
	var spectators: Array[int] = []             ## spiller-id-er som ser på (bare turneringskamper)

	func in_game() -> bool:
		return state != null and not state.is_over()

	func seat_of(player_id: int) -> int:
		return seats.find(player_id) if player_id != 0 else -1

	func is_empty() -> bool:
		return seats[1] == 0 and seats[2] == 0


var send: Callable = func(_peer: int, _msg: Dictionary) -> void: pass
var close_peer: Callable = func(_peer: int) -> void: pass
var players: Dictionary = {}   ## spiller-id -> Player
var rooms: Dictionary = {}     ## kode -> Room
var _peers: Dictionary = {}    ## peer-id -> spiller-id
var _next_id := 1
var rng := RandomNumberGenerator.new()
var store := Store.new()            ## minne-lagring til use_store() kalles (testene bruker denne)
var accounts := Accounts.new(store)
var tournaments := Tournaments.new(store, accounts)
var social := Social.new(store)
var puzzles := Puzzles.new(store, accounts)
## Veggklokke i unix-sekunder (kan byttes ut i tester).
var clock_s: Callable = func() -> int: return int(Time.get_unix_time_from_system())
var _last_ms := 0
var _presence_dirty := true
var _presence_sent_ms := -100_000
var _tournaments_changed := {}   ## turnering-id -> true: sendes til dem som har siden oppe i neste tick


func _init() -> void:
	rng.randomize()
	_hook_tournaments()


## Bytter til varig lagring (ServerMain gjør dette med datamappen).
func use_store(p_store: Store) -> void:
	store = p_store
	accounts = Accounts.new(store)
	tournaments = Tournaments.new(store, accounts)
	social = Social.new(store)
	puzzles = Puzzles.new(store, accounts)
	_hook_tournaments()


func _hook_tournaments() -> void:
	social.broadcast = _broadcast_all
	tournaments.announce = _announce
	tournaments.open_room = _open_tournament_room
	tournaments.presence = _room_presence
	tournaments.notify = _notify_user
	tournaments.close_room = _close_room
	tournaments.changed = func(id: int) -> void: _tournaments_changed[id] = true


# ---------------------------------------------------------------- Tilkobling

func on_disconnect(peer: int, now: int) -> void:
	if not _peers.has(peer):
		return
	var p: Player = players[_peers[peer]]
	_peers.erase(peer)
	p.peer = 0
	p.disconnected_at = now
	_presence_dirty = true
	_unwatch(p)
	var room := _room_of(p)
	if room:
		_notice_room(room, "%s mistet forbindelsen…", [p.name], p.id)
		_broadcast_room_state(room)


func on_message(peer: int, msg: Dictionary, now: int) -> void:
	var t: String = msg.get("t", "")
	if t == Protocol.HELLO:
		_hello(peer, msg, now)
		return
	if not _peers.has(peer):
		_error(peer, "not_logged_in", "Send hello først.")
		return
	var p: Player = players[_peers[peer]]
	_last_ms = now
	match t:
		Protocol.PING: send.call(peer, { "t": Protocol.PONG })
		Protocol.REGISTER, Protocol.LOGIN: _auth(p, t, msg, now)
		Protocol.SET_LOOK: _set_look(p, msg)
		Protocol.LOGOUT: _logout(p, msg)
		Protocol.GET_STATS: _stats(p, str(msg.get("username", "")))
		Protocol.GET_LEADERBOARD: send.call(peer, { "t": Protocol.LEADERBOARD, "boards": accounts.leaderboard() })
		Protocol.LIST_TOURNAMENTS: _list_tournaments(p)
		Protocol.GET_TOURNAMENT, Protocol.VIEW_TOURNAMENT:
			# Siden er oppe: send den nå, og senere endringer med en gang (id 0 = siden er lukket)
			p.viewing_tournament = int(msg.get("id", 0))
			if p.viewing_tournament != 0:
				_send_tournament(p, p.viewing_tournament)
		Protocol.FRIEND: _friend(p, msg)
		Protocol.USER_SEARCH: _search(p, str(msg.get("query", "")))
		Protocol.TOURNAMENT_JOIN, Protocol.TOURNAMENT_LEAVE, Protocol.TOURNAMENT_CREATE, \
		Protocol.TOURNAMENT_UPDATE, Protocol.TOURNAMENT_ACTION:
			_tournament_request(p, t, msg)
		Protocol.LIST_ROOMS: _list_rooms(p)
		Protocol.CREATE_ROOM: _create_room(p, msg, now)
		Protocol.JOIN_ROOM: _join_room(p, str(msg.get("code", "")), now)
		Protocol.LEAVE_ROOM:
			if p.watching != "":
				_unwatch(p)
			else:
				_leave_room(p, now)
		Protocol.WATCH: _watch(p, str(msg.get("code", "")), now)
		Protocol.GLOBAL_CHAT: _global_chat(p, str(msg.get("text", "")), now, str(msg.get("channel", "")))
		Protocol.GET_PUZZLE: send.call(peer, puzzles.info_message(p.user_id, clock_s.call()))
		Protocol.PUZZLE_SOLVE: _puzzle_solve(p, msg)
		Protocol.LIST_GAMES: _list_games(p, str(msg.get("username", "")))
		Protocol.GET_GAME: _send_game(p, int(msg.get("id", 0)))
		Protocol.ADMIN: _admin(p, msg)
		Protocol.SET_OPTIONS: _set_options(p, msg)
		Protocol.READY: _set_ready(p, bool(msg.get("ready", true)), now)
		Protocol.MOVE: _move(p, msg, now)
		Protocol.CHAT: _chat(p, str(msg.get("text", "")), now)
		Protocol.RESIGN: _resign(p, now)
		Protocol.REMATCH: _rematch(p, now)
		_: _error(peer, "unknown", "Ukjent melding: %s", [t])


## Kalles jevnlig: tid ute, spillere som ikke kom tilbake, omspill og turneringer.
func tick(now: int) -> void:
	_last_ms = now
	tournaments.tick(clock_s.call())
	for room: Room in rooms.values():
		if room.replay_at >= 0 and now >= room.replay_at:
			room.replay_at = -1
			_start_game(room, now)
		if room.in_game() and room.clock.enabled:
			var flagged := room.clock.flagged(now)
			if flagged != 0:
				room.state.end_with_loss(flagged, GameState.EndReason.TIMEOUT)
				_game_over(room, now)
	for p: Player in players.values():
		if p.peer == 0 and p.disconnected_at >= 0 and now - p.disconnected_at > RECONNECT_GRACE_MS:
			_leave_room(p, now)
			players.erase(p.id)
	if _presence_dirty and now - _presence_sent_ms >= PRESENCE_INTERVAL_MS:
		_presence_dirty = false
		_presence_sent_ms = now
		_broadcast_all(presence_message())
		_push_friends()
	if not _tournaments_changed.is_empty():
		var ids := _tournaments_changed.keys()
		_tournaments_changed.clear()
		for p: Player in players.values():
			if p.peer != 0 and p.viewing_tournament in ids:
				if tournaments.get_t(p.viewing_tournament).is_empty():
					p.viewing_tournament = 0   # slettet
				else:
					_send_tournament(p, p.viewing_tournament)


# ---------------------------------------------------------------- Meldinger

func _hello(peer: int, msg: Dictionary, now: int) -> void:
	if int(msg.get("version", 0)) != Protocol.VERSION:
		_error(peer, "version", "Klienten er utdatert. Last inn siden på nytt.")
		close_peer.call(peer)
		return
	var token := str(msg.get("token", ""))
	var p: Player = null
	for existing: Player in players.values():
		if token != "" and existing.token == token:
			p = existing
	var resumed := p != null
	if p == null:
		p = Player.new()
		p.id = _next_id
		_next_id += 1
		p.token = "%d-%08x%08x" % [p.id, rng.randi(), rng.randi()]
		players[p.id] = p
	elif p.peer != 0:
		_peers.erase(p.peer)   # gammel tilkobling erstattes
		close_peer.call(p.peer)
	p.guest_name = Protocol.clean_name(msg.get("name", "Spiller"))
	p.name = p.guest_name
	p.skin = str(msg.get("skin", "ocean")).substr(0, 24)
	p.decal = str(msg.get("decal", "none")).substr(0, 24)
	p.win_fx = str(msg.get("win_fx", "classic")).substr(0, 24)
	p.decal_color = str(msg.get("decal_color", "auto")).substr(0, 24)
	p.away = bool(msg.get("away", false))
	p.look_pending = bool(msg.get("look_pending", false))
	var avatar = msg.get("avatar", "")
	p.avatar = avatar if AvatarData.is_valid(avatar) else ""
	p.peer = peer
	p.disconnected_at = -1
	_peers[peer] = p.id
	# Husket innlogging (økt-nøkkel fra forrige gang). Utestengte kommer inn som gjest.
	var user := accounts.user_for_session(str(msg.get("session", "")), clock_s.call())
	if user.is_empty() and p.user_id != 0 and resumed:
		user = store.users.get(p.user_id, {})
	if not user.is_empty() and user.banned:
		accounts.end_sessions_of(int(user.id))
		var err := Accounts.banned_error(user)
		send.call(peer, { "t": Protocol.NOTICE, "key": err.error, "args": err.args, "text": _fill(err.error, err.args) })
		user = {}
		p.user_id = 0
	if not user.is_empty():
		_sign_in(p, user)
	send.call(peer, { "t": Protocol.WELCOME, "player_id": p.id, "token": p.token, "resumed": resumed,
		"user": accounts.public_info(user) if not user.is_empty() else null,
		"avatar": p.avatar if not user.is_empty() else null, "look": _look_of(p) if not user.is_empty() else null })
	send.call(peer, social.history_message())
	send.call(peer, presence_message())
	if not store.games.is_empty():
		send.call(peer, last_game_message())
	_presence_dirty = true

	var room := _room_of(p)
	if room:
		_broadcast_room_state(room)
		if room.state != null:
			_send_sync(room, p, now)
		_notice_room(room, "%s er tilbake.", [p.name], p.id)


func _list_rooms(p: Player) -> void:
	var list := []
	for room: Room in rooms.values():
		if room.private or room.seats[2] != 0 or room.seats[1] == 0:
			continue
		var host: Player = players[room.seats[1]]
		var user: Dictionary = store.users.get(host.user_id, {}) if host.user_id != 0 else {}
		list.append({ "code": room.code, "host": host.name, "options": room.options.to_dict(),
			"description": room.options.describe(), "host_elo": user.get("elo") if not user.is_empty() else null })
	send.call(p.peer, { "t": Protocol.ROOM_LIST, "rooms": list, "live": live_games() })


## Partier som spilles nå (alle kan se på): spillerne, antall trekk og tilskuere.
func live_games() -> Array:
	var out := []
	for room: Room in rooms.values():
		if not room.in_game():
			continue
		var names := []
		for info in _players_info(room):
			if info is Dictionary:
				names.append({ "name": info.name, "elo": info.elo, "skin": info.skin })
		out.append({ "code": room.code, "players": names, "moves": room.state.history.size(),
			"spectators": room.spectators.size(), "tournament": room.tournament_name if room.match_id != "" else "",
			"size": room.options.size })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.spectators > b.spectators)
	return out


func _create_room(p: Player, msg: Dictionary, now: int) -> void:
	_leave_room(p, now)
	var room := Room.new()
	room.code = _new_code()
	room.private = bool(msg.get("private", false))
	var opts = msg.get("options", {})
	room.options = GameOptions.from_dict(opts if opts is Dictionary else {})
	room.seats[1] = p.id
	rooms[room.code] = room
	p.room_code = room.code
	_broadcast_room_state(room)


func _join_room(p: Player, code: String, now: int) -> void:
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		_error(p.peer, "no_room", "Fant ikke rommet %s.", [code])
		return
	var room: Room = rooms[code]
	if room.seat_of(p.id) > 0:
		_broadcast_room_state(room)
		return
	var seat := 1 if room.seats[1] == 0 else 2
	if room.match_id != "":
		# Turneringskamp: bare de to påmeldte, i hvert sitt faste sete.
		seat = room.reserved.find(p.user_id) if p.user_id != 0 else -1
		if seat < 1:
			_error(p.peer, "not_your_match", "Denne kampen er bare for de to spillerne i turneringen.")
			return
		if room.seats[seat] != 0 and room.seats[seat] != p.id:
			var old: Player = players.get(room.seats[seat])
			if old:
				old.room_code = ""
			room.seats[seat] = 0
	elif room.seats[1] != 0 and room.seats[2] != 0:
		_error(p.peer, "room_full", "Rommet er fullt.")
		return
	_leave_room(p, now)
	room.seats[seat] = p.id
	p.room_code = room.code
	_notice_room(room, "%s ble med.", [p.name], p.id)
	_broadcast_room_state(room)
	if room.match_id != "" and room.seats[1] != 0 and room.seats[2] != 0 and room.state == null:
		tournaments.on_match_started(room.match_id)
		_start_game(room, now)


func _leave_room(p: Player, now: int) -> void:
	var room := _room_of(p)
	p.room_code = ""
	if room == null:
		return
	var seat := room.seat_of(p.id)
	if room.in_game():
		room.state.end_with_loss(seat, GameState.EndReason.DISCONNECT)
		_game_over(room, now)
	room.seats[seat] = 0
	room.ready.fill(false)
	room.rematch.fill(false)
	if room.is_empty() and (room.match_id == "" or room.match_done):
		_drop_spectators(room, "Kampen er ferdig.")
		rooms.erase(room.code)
		return
	if room.match_id != "":
		# Turneringsrom: setene er faste. Rommet lever til turneringen er ferdig med kampen.
		_broadcast_room_state(room)
		return
	# Den som er igjen blir vert (sete 1).
	if room.seats[1] == 0:
		room.seats[1] = room.seats[2]
		room.seats[2] = 0
	room.state = null
	_notice_room(room, "%s forlot rommet.", [p.name], p.id)
	_broadcast_room_state(room)


func _set_options(p: Player, msg: Dictionary) -> void:
	var room := _room_of(p)
	if room == null or room.seat_of(p.id) != 1 or room.in_game() or room.match_id != "":
		return
	var opts = msg.get("options", {})
	room.options = GameOptions.from_dict(opts if opts is Dictionary else {})
	room.ready.fill(false)
	room.rematch.fill(false)
	if room.state != null:
		# Mellom partier: gi motstanderen beskjed om de nye reglene
		_notice_room(room, "%s endret reglene: %s", [p.name, room.options.describe()], p.id)
	_broadcast_room_state(room)


func _set_ready(p: Player, value: bool, now: int) -> void:
	var room := _room_of(p)
	if room == null or room.in_game() or room.match_id != "":
		return
	room.ready[room.seat_of(p.id)] = value
	if value and room.state != null and not _both_want_to_play(room):
		_notice_room(room, "%s vil spille igjen!", [p.name], p.id)   # etter et parti
	if _both_want_to_play(room):
		if room.state == null:
			room.number = 0
		_start_game(room, now)
	else:
		_broadcast_room_state(room)


func _move(p: Player, msg: Dictionary, now: int) -> void:
	var room := _room_of(p)
	if room == null or not room.in_game():
		return
	var s := room.state
	var seat := room.seat_of(p.id)
	if seat != s.current_player:
		_reject(p, "Det er ikke din tur.", [])
		return
	if int(msg.get("ply", -1)) != s.history.size():
		return   # gammel eller duplisert melding
	var col := Vector2i(int(msg.get("x", -1)), int(msg.get("y", -1)))
	var err := s.check_move(col)
	if err != GameState.MoveError.OK:
		var hints: Array = []
		if err == GameState.MoveError.MUST_BLOCK:
			hints = Protocol.positions_to_json(s.threat_positions(seat))
		_reject(p, GameState.error_text(err), hints)
		return
	s.play(col)
	if room.clock.enabled:
		if s.is_over():
			room.clock.stop(now)
		else:
			room.clock.switch(now)
	_send_room(room, { "t": Protocol.MOVE_MADE, "x": col.x, "y": col.y, "player": seat, "ply": s.history.size() - 1,
		"clocks": _clocks(room, now), "running": room.clock.running_player })
	if s.is_over():
		_game_over(room, now)


func _chat(p: Player, text: String, now: int) -> void:
	var room := _room_of(p) if p.watching == "" else rooms.get(p.watching) as Room
	text = text.strip_edges().substr(0, Protocol.MAX_CHAT)
	if room == null or text == "" or now - p.last_chat_ms < CHAT_INTERVAL_MS:
		return
	p.last_chat_ms = now
	_send_room(room, { "t": Protocol.CHAT_MSG, "from": p.name, "seat": maxi(0, room.seat_of(p.id)), "text": text })


func _resign(p: Player, now: int) -> void:
	var room := _room_of(p)
	if room == null or not room.in_game():
		return
	room.state.end_with_loss(room.seat_of(p.id), GameState.EndReason.RESIGN)
	_game_over(room, now)


func _rematch(p: Player, now: int) -> void:
	var room := _room_of(p)
	if room == null or room.state == null or room.in_game() or room.seats[1] == 0 or room.seats[2] == 0:
		return
	if room.match_id != "":
		return   # turneringskamper spilles bare én gang (omspill ved uavgjort skjer automatisk)
	var seat := room.seat_of(p.id)
	room.rematch[seat] = true
	if _both_want_to_play(room):
		_start_game(room, now)
	else:
		_notice_room(room, "%s vil spille igjen!", [p.name], p.id)


# ---------------------------------------------------------------- Parti

func _start_game(room: Room, now: int) -> void:
	room.number += 1
	var first := room.options.first_player(room.number, rng)
	room.state = GameState.new(room.options, first)
	room.clock = ChessClock.new(room.options)
	if room.clock.enabled:
		room.clock.start(first, now)
	room.ready.fill(false)
	room.rematch.fill(false)
	for seat in [1, 2]:
		var p: Player = players[room.seats[seat]]
		if p.peer != 0:
			var msg := _start_message(room, seat, now)
			msg["t"] = Protocol.GAME_START
			send.call(p.peer, msg)
	for id in room.spectators:
		var msg := _start_message(room, 0, now)
		msg["t"] = Protocol.GAME_START
		send.call(players[id].peer, msg)
	_presence_dirty = true


## Begge sitter i rommet og vil spille («Klar!» i venterommet eller «Spill igjen» etter et parti).
func _both_want_to_play(room: Room) -> bool:
	if room.seats[1] == 0 or room.seats[2] == 0:
		return false
	return (room.ready[1] or room.rematch[1]) and (room.ready[2] or room.rematch[2])


func _send_sync(room: Room, p: Player, now: int) -> void:
	var msg := _start_message(room, maxi(0, room.seat_of(p.id)), now)
	msg["t"] = Protocol.GAME_SYNC
	var moves := []
	for m in room.state.history:
		moves.append([m.x, m.y])
	msg["moves"] = moves
	msg["running"] = room.clock.running_player
	msg["over"] = room.state.is_over()
	msg["result"] = room.state.result
	msg["reason"] = room.state.end_reason
	msg["line"] = Protocol.positions_to_json(room.state.winning_line)
	send.call(p.peer, msg)


func _start_message(room: Room, seat: int, now: int) -> Dictionary:
	return {
		"options": room.options.to_dict(), "first": room.state.first_player, "you": seat,
		"players": _players_info(room), "clocks": _clocks(room, now), "number": room.number,
		"tournament": { "id": room.tournament_id, "name": room.tournament_name } if room.match_id != "" else null,
		"spectators": room.spectators.size(), "code": room.code,
	}


func _game_over(room: Room, now: int) -> void:
	room.clock.stop(now)
	var s := room.state
	var ids := [0, _user_in_seat(room, 1), _user_in_seat(room, 2)]
	var moves := []
	for m in s.history:
		moves.append([m.x, m.y])
	var analysis := GameAnalysis.analyze(room.options, s.first_player, moves)
	var elo := accounts.record_game(ids, s.winner(), s.end_reason, analysis, s.history.size())
	_publish_achievements(ids, s, analysis, elo)
	_presence_dirty = true
	store.append_game({
		"time": Time.get_datetime_string_from_unix_time(clock_s.call(), true), "options": room.options.to_dict(),
		"players": [_seat_record(room, 1), _seat_record(room, 2)], "first": s.first_player, "moves": moves,
		"result": s.result, "reason": s.end_reason, "analysis": { "1": analysis[1], "2": analysis[2] },
		"elo": elo, "tournament": room.match_id,
	})
	_broadcast_all(last_game_message())   # hovedmenyen hos alle viser det siste partiet
	var elo_json := {}
	for seat in elo:
		elo_json[str(seat)] = elo[seat]
	_send_room(room, { "t": Protocol.GAME_OVER, "result": s.result, "reason": s.end_reason, "winner": s.winner(),
		"line": Protocol.positions_to_json(s.winning_line), "clocks": _clocks(room, now), "elo": elo_json,
		"analysis": { "1": analysis[1], "2": analysis[2] } })
	if room.match_id != "":
		var draw := s.result == GameState.Result.DRAW
		var winner_uid: int = 0 if draw else ids[s.winner()]
		if tournaments.report(room.match_id, winner_uid, draw, clock_s.call()) == "replay":
			_notice_room(room, "Uavgjort! Kampen spilles om om litt.", [], 0)
			room.replay_at = now + 4000
		else:
			room.match_done = true


func _clocks(room: Room, now: int) -> Array:
	return [room.clock.time_left(1, now), room.clock.time_left(2, now)]


func _reject(p: Player, text: String, hints: Array) -> void:
	send.call(p.peer, { "t": Protocol.MOVE_REJECTED, "text": text, "hints": hints })


# ---------------------------------------------------------------- Hjelpere

func _room_of(p: Player) -> Room:
	return rooms.get(p.room_code) if p.room_code != "" else null


func _players_info(room: Room) -> Array:
	var out := []
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id == 0 or not players.has(id):
			out.append(null)
			continue
		var p: Player = players[id]
		var user: Dictionary = store.users.get(p.user_id, {}) if p.user_id != 0 else {}
		out.append({ "seat": seat, "name": p.name, "skin": p.skin, "decal": _decal_for(p), "win_fx": p.win_fx,
			"decal_color": p.decal_color, "away": p.away, "avatar": p.avatar,
			"ready": room.ready[seat], "connected": p.peer != 0, "account": p.user_id != 0,
			"elo": user.get("elo") if not user.is_empty() else null })
	return out


func _broadcast_room_state(room: Room) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id == 0 or players[id].peer == 0:
			continue
		send.call(players[id].peer, {
			"t": Protocol.ROOM_STATE, "code": room.code, "private": room.private, "options": room.options.to_dict(),
			"description": room.options.describe(), "you": seat, "in_game": room.in_game(), "players": _players_info(room),
			"tournament": { "id": room.tournament_id, "name": room.tournament_name } if room.match_id != "" else null,
			"spectators": room.spectators.size(),
		})
	for id in room.spectators:
		send.call(players[id].peer, {
			"t": Protocol.ROOM_STATE, "code": room.code, "private": room.private, "options": room.options.to_dict(),
			"description": room.options.describe(), "you": 0, "in_game": room.in_game(), "players": _players_info(room),
			"tournament": { "id": room.tournament_id, "name": room.tournament_name } if room.match_id != "" else null,
			"spectators": room.spectators.size(),
		})


func _send_room(room: Room, msg: Dictionary) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and players[id].peer != 0:
			send.call(players[id].peer, msg)
	for id in room.spectators:
		send.call(players[id].peer, msg)


## key er en norsk tekst med %s for args. Klienten oversetter key, og «text» er ferdig utfylt.
func _notice_room(room: Room, key: String, args: Array, except_id: int) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and id != except_id and players[id].peer != 0:
			send.call(players[id].peer, { "t": Protocol.NOTICE, "text": key % args, "key": key, "args": args })


func _error(peer: int, code: String, key: String, args: Array = []) -> void:
	send.call(peer, { "t": Protocol.ERROR, "code": code, "text": _fill(key, args), "key": key, "args": args })


## Fyller inn args i en tekst med %s (bare hvis det finnes args).
static func _fill(key: String, args: Array) -> String:
	return key % args if not args.is_empty() else key


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[rng.randi() % CODE_LETTERS.length()]
		if not rooms.has(code):
			return code
	return ""


# ---------------------------------------------------------------- Kontoer

func _auth(p: Player, t: String, msg: Dictionary, now: int) -> void:
	var username := str(msg.get("username", ""))
	var password := str(msg.get("password", ""))
	var res := accounts.register(username, password) if t == Protocol.REGISTER \
		else accounts.login(username, password, clock_s.call())
	if res.has("error"):
		var args: Array = res.get("args", [])
		send.call(p.peer, { "t": Protocol.AUTH_ERROR, "key": res.error, "args": args, "text": _fill(res.error, args) })
		return
	_sign_in(p, res.user, t == Protocol.REGISTER)
	if t == Protocol.REGISTER:
		social.event("Velkommen, %s!", [str(res.user.username)], clock_s.call(), "velkommen")
	var token := accounts.create_session(res.user.id, clock_s.call())
	send.call(p.peer, { "t": Protocol.SESSION, "token": token, "user": accounts.public_info(res.user), "avatar": p.avatar,
		"look": _look_of(p) })
	var room := _room_of(p)
	if room:
		_broadcast_room_state(room)


## Utseendet og profilbildet hører til kontoen: ved innlogging får enheten kontoens utseende.
## En ny konto tar utseendet enheten har valgt.
func _sign_in(p: Player, user: Dictionary, new_account := false) -> void:
	p.user_id = int(user.id)
	p.name = str(user.username)
	_presence_dirty = true   # nytt navn i «hvem er online»
	if new_account or p.look_pending:
		p.look_pending = false
		accounts.update_profile(p.user_id, _look_of(p))
	else:
		var look: Dictionary = user.profile
		p.skin = look.skin
		p.decal = look.decal
		p.win_fx = look.win_fx
		p.decal_color = look.decal_color
		p.away = look.away
	p.avatar = accounts.avatar_on_sign_in(p.user_id, p.avatar)   # samme bilde på alle enheter


## Utseendet slik klienten lagrer det (sendes ved innlogging, så enheten får kontoens utseende).
func _look_of(p: Player) -> Dictionary:
	return { "skin": p.skin, "decal": p.decal, "win_fx": p.win_fx, "decal_color": p.decal_color, "away": p.away }


## Byttet utseende (skin, merke, seiersanimasjon). Rommet får beskjed, så motstanderen ser det før start.
func _set_look(p: Player, msg: Dictionary) -> void:
	p.skin = str(msg.get("skin", p.skin)).substr(0, 24)
	p.decal = str(msg.get("decal", p.decal)).substr(0, 24)
	p.win_fx = str(msg.get("win_fx", p.win_fx)).substr(0, 24)
	p.decal_color = str(msg.get("decal_color", p.decal_color)).substr(0, 24)
	p.away = bool(msg.get("away", p.away))
	if msg.has("avatar"):   # nytt eller fjernet profilbilde
		var avatar = msg.avatar
		if avatar == "" or AvatarData.is_valid(avatar):
			p.avatar = avatar
			if p.user_id != 0:
				accounts.set_avatar(p.user_id, p.avatar)
	if p.user_id != 0:
		accounts.update_profile(p.user_id, _look_of(p))
	var room := _room_of(p)
	if room and not room.in_game():
		_broadcast_room_state(room)


func _logout(p: Player, msg: Dictionary) -> void:
	accounts.end_session(str(msg.get("session", "")))
	p.user_id = 0
	p.name = p.guest_name
	_presence_dirty = true
	send.call(p.peer, { "t": Protocol.LOGGED_OUT })


func _stats(p: Player, username: String) -> void:
	var u: Dictionary = store.find_user(username) if username != "" else store.users.get(p.user_id, {})
	var info := accounts.public_info(u)
	if not u.is_empty():
		info.avatar = store.avatars.get(int(u.id), "")
	send.call(p.peer, { "t": Protocol.STATS, "user": info if not u.is_empty() else null })


## Søk etter spillere på navn (venner-skjermen): treff mens man skriver.
func _search(p: Player, query: String) -> void:
	var users := []
	for u: Dictionary in accounts.search(query.substr(0, Protocol.MAX_NAME)):
		if int(u.id) != p.user_id:
			users.append({ "username": u.username, "elo": u.elo, "online": _is_online(int(u.id)) })
	send.call(p.peer, { "t": Protocol.USERS, "query": query, "users": users })


func _user_in_seat(room: Room, seat: int) -> int:
	var id := room.seats[seat]
	return players[id].user_id if id != 0 and players.has(id) else 0


func _seat_record(room: Room, seat: int) -> Dictionary:
	var id := room.seats[seat]
	if id == 0 or not players.has(id):
		return {}
	var p: Player = players[id]
	return { "name": p.name, "user": p.user_id, "skin": p.skin, "decal": _decal_for(p), "decal_color": p.decal_color,
		"away": p.away,
		"elo": _elo_of(p) }


# ---------------------------------------------------------------- Turneringer

func _list_tournaments(p: Player) -> void:
	var list := store.tournaments.map(func(t: Dictionary) -> Dictionary:
		var s := tournaments.summary(t)
		s.joined = p.user_id != 0 and p.user_id in t.players   # så menyen kan si «Du er påmeldt»
		return s
	)
	var admin := accounts.is_admin(p.user_id)
	if not admin:
		list = list.filter(func(t: Dictionary) -> bool: return t.status != "draft")
	send.call(p.peer, { "t": Protocol.TOURNAMENT_LIST, "tournaments": list, "admin": admin })


func _send_tournament(p: Player, id: int) -> void:
	var t := tournaments.get_t(id)
	if t.is_empty() or (t.status == "draft" and not accounts.is_admin(p.user_id)):
		_error(p.peer, "no_tournament", "Fant ikke turneringen.")
		return
	send.call(p.peer, { "t": Protocol.TOURNAMENT_STATE, "tournament": tournaments.public(t),
		"admin": accounts.is_admin(p.user_id), "you": p.user_id })


func _tournament_request(p: Player, t: String, msg: Dictionary) -> void:
	if p.user_id == 0:
		_error(p.peer, "login_required", "Du må logge inn først.")
		return
	var id := int(msg.get("id", 0))
	var err := ""
	var now: int = clock_s.call()
	match t:
		Protocol.TOURNAMENT_JOIN: err = tournaments.join(id, p.user_id, now)
		Protocol.TOURNAMENT_LEAVE: err = tournaments.leave(id, p.user_id)
		_:
			if not accounts.is_admin(p.user_id):
				_error(p.peer, "admin_only", "Bare admin kan gjøre dette.")
				return
			var data = msg.get("data", {})
			if t == Protocol.TOURNAMENT_CREATE:
				id = int(tournaments.create(p.user_id, data if data is Dictionary else {}, now).id)
			elif t == Protocol.TOURNAMENT_UPDATE:
				err = tournaments.update(id, data if data is Dictionary else {}, now)
			else:
				err = tournaments.action(id, str(msg.get("action", "")), now)
				if err == "" and str(msg.get("action", "")) == "delete":
					_list_tournaments(p)
					return
	if err != "":
		_error(p.peer, "tournament", err)
		return
	_send_tournament(p, id)


## Callback fra Tournaments: lager et privat, låst rom for en kamp.
func _open_tournament_room(t: Dictionary, m: Dictionary) -> String:
	var room := Room.new()
	room.code = _new_code()
	room.private = true
	room.options = GameOptions.from_dict(t.options)
	room.match_id = m.id
	room.tournament_id = int(t.id)
	room.tournament_name = str(t.name)
	room.reserved = [0, int(m.p1), int(m.p2)]
	rooms[room.code] = room
	return room.code


func _room_presence(code: String) -> Array:
	var room: Room = rooms.get(code)
	if room == null:
		return []
	var out := []
	for seat in [1, 2]:
		var uid := _user_in_seat(room, seat)
		if uid != 0 and players[room.seats[seat]].peer != 0:
			out.append(uid)
	return out


func _notify_user(uid: int, msg: Dictionary) -> void:
	for p: Player in players.values():
		if p.user_id == uid and p.peer != 0:
			send.call(p.peer, msg)


func _close_room(code: String, key: String, args: Array) -> void:
	var room: Room = rooms.get(code)
	if room == null:
		return
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and players.has(id):
			var p: Player = players[id]
			p.room_code = ""
			if p.peer != 0:
				send.call(p.peer, { "t": Protocol.ROOM_CLOSED, "key": key, "args": args, "text": key % args if not args.is_empty() else key })
	_drop_spectators(room, key, args)
	rooms.erase(code)


# ---------------------------------------------------------------- Admin

## Admin-handlinger: utestenge/oppheve, kunngjøre og gi en pokal. Svarer alltid med admin_result
## (med listen over utestengte, så admin-siden er oppdatert).
func _admin(p: Player, msg: Dictionary) -> void:
	if not accounts.is_admin(p.user_id):
		_error(p.peer, "admin_only", "Bare admin kan gjøre dette.")
		return
	var action := str(msg.get("action", ""))
	var username := str(msg.get("username", "")).strip_edges()
	var now_s: int = clock_s.call()
	var key := ""
	var args := []
	var ok := true
	match action:
		"ban":
			key = accounts.ban(username, str(msg.get("reason", "")))
			ok = key == ""
			if ok:
				var u := store.find_user(username)
				_remove_from_open_tournaments(int(u.id))
				_kick_banned(int(u.id))
				key = "%s er utestengt."
				username = str(u.username)
		"unban":
			key = accounts.unban(username)
			ok = key == ""
			if ok:
				key = "%s kan logge inn igjen."
				username = str(store.find_user(username).username)
		"announce":
			var text := str(msg.get("text", "")).strip_edges().substr(0, Protocol.MAX_ANNOUNCEMENT)
			ok = text != ""
			if ok:
				social.announce(p.name, text, now_s)
				key = "Kunngjøringen er sendt."
			else:
				key = "Skriv en kunngjøring først."
		"award":
			var u := store.find_user(username)
			ok = not u.is_empty()
			if ok:
				var entry := Trophy.entry(str(msg.get("name", "")), msg.get("design", Trophy.generate(rng.randi())), 0,
					Time.get_date_string_from_unix_time(now_s))
				accounts.award_trophy(int(u.id), entry)
				social.event("%s fikk pokalen «%s»!", [str(u.username), entry.name], now_s)
				key = "%s fikk pokalen «%s»."
				args = [str(u.username), entry.name]
			else:
				key = "Fant ikke brukeren %s."
		"banned_list":
			pass
		_:
			ok = false
			key = "Ukjent handling."
	if args.is_empty() and key.contains("%s"):
		args = [username]
	send.call(p.peer, { "t": Protocol.ADMIN_RESULT, "action": action, "ok": ok, "key": key, "args": args,
		"text": _fill(key, args), "banned": accounts.banned_list() })


## Kaster ut en utestengt bruker som er online: logges ut, får beskjed og kobles fra.
func _kick_banned(uid: int) -> void:
	var err := Accounts.banned_error(store.users.get(uid, {}))
	for p: Player in players.values():
		if p.user_id != uid:
			continue
		p.user_id = 0
		p.name = p.guest_name
		_presence_dirty = true
		if p.peer != 0:
			var peer := p.peer
			_error(peer, "banned", err.error, err.args)
			close_peer.call(peer)


func _remove_from_open_tournaments(uid: int) -> void:
	for t in store.tournaments:
		if t.status == "open" and uid in t.players:
			t.players.erase(uid)
			store.save_tournaments()


## Kalles når users.json er lastet inn på nytt (f.eks. "banned": true satt for hånd).
func on_users_reloaded() -> void:
	for p: Player in players.values():
		if p.user_id != 0 and accounts.is_banned(p.user_id):
			_remove_from_open_tournaments(p.user_id)
			_kick_banned(p.user_id)


# ---------------------------------------------------------------- Venner

## Venner krever konto. Etter hver handling får spilleren den oppdaterte vennelisten.
func _friend(p: Player, msg: Dictionary) -> void:
	if p.user_id == 0:
		_error(p.peer, "login_required", "Du må logge inn først.")
		return
	var username := str(msg.get("username", "")).strip_edges()
	match str(msg.get("action", "list")):
		"request":
			var res := accounts.friend_request(p.user_id, username)
			if res.has("error"):
				_error(p.peer, "friend", res.error, [username] if str(res.error).contains("%s") else [])
				return
			var other: Dictionary = res.user
			if res.state == "friends":
				_friend_notice(int(other.id), "accepted", p.name, "%s og du er nå venner.", [p.name])
				_send_friends(int(other.id))
			else:
				_friend_notice(int(other.id), "request", p.name, "%s vil bli venn med deg.", [p.name])
				_send_friends(int(other.id))
		"accept":
			var other := accounts.friend_accept(p.user_id, username)
			if not other.is_empty():
				_friend_notice(int(other.id), "accepted", p.name, "%s og du er nå venner.", [p.name])
				_send_friends(int(other.id))
		"decline":
			accounts.friend_decline(p.user_id, username)
		"remove":
			var other := store.find_user(username)
			accounts.friend_remove(p.user_id, username)
			if not other.is_empty():
				_send_friends(int(other.id))
		"invite":
			_invite(p, username)
	_send_friends(p.user_id)


## Inviterer en venn som er online til rommet du venter i.
func _invite(p: Player, username: String) -> void:
	var other := store.find_user(username)
	var room := _room_of(p)
	if other.is_empty() or not int(other.id) in store.users[p.user_id].friends:
		_error(p.peer, "friend", "%s er ikke vennen din.", [username])
	elif room == null or room.match_id != "":
		_error(p.peer, "friend", "Lag et rom først, så kan du invitere.")
	elif room.seats[1] != 0 and room.seats[2] != 0:
		_error(p.peer, "friend", "Rommet er fullt.")
	elif not _is_online(int(other.id)):
		_error(p.peer, "friend", "%s er ikke online.", [str(other.username)])
	else:
		_friend_notice(int(other.id), "invite", p.name, "%s inviterer deg til et parti (%s).",
			[p.name, room.options.describe()], room.code)
		send.call(p.peer, { "t": Protocol.NOTICE, "key": "Invitasjonen er sendt til %s.", "args": [str(other.username)],
			"text": "Invitasjonen er sendt til %s." % str(other.username) })


func _friend_notice(uid: int, kind: String, from: String, key: String, args: Array, code := "") -> void:
	_notify_user(uid, { "t": Protocol.FRIEND_NOTICE, "kind": kind, "from": from, "code": code, "key": key,
		"args": args, "text": _fill(key, args) })


## Vennelisten til en bruker: venner (online først, med om de spiller og hvor) og forespørsler.
func friends_message(uid: int) -> Dictionary:
	var u: Dictionary = store.users.get(uid, {})
	var online := {}   # bruker-id -> Player som er koblet til
	for p: Player in players.values():
		if p.user_id != 0 and p.peer != 0:
			online[p.user_id] = p
	var list := []
	for fid in u.get("friends", []):
		var f: Dictionary = store.users.get(int(fid), {})
		if f.is_empty():
			continue
		var p: Player = online.get(int(fid))
		var room: Room = _room_of(p) if p else null
		var playing := room != null and room.in_game()
		list.append({ "username": f.username, "elo": f.elo, "online": p != null, "playing": playing,
			"room": room.code if playing else "" })
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.online != b.online:
			return a.online
		return a.username.naturalnocasecmp_to(b.username) < 0
	)
	var requests := []
	for rid in u.get("friend_requests", []):
		var r: Dictionary = store.users.get(int(rid), {})
		if not r.is_empty():
			requests.append({ "username": r.username, "elo": r.elo })
	var sent := []   # forespørsler du har sendt og som venter på svar
	for other: Dictionary in store.users.values():
		if uid in other.friend_requests:
			sent.append(other.username)
	return { "t": Protocol.FRIENDS, "friends": list, "requests": requests, "sent": sent }


func _send_friends(uid: int) -> void:
	if _is_online(uid):
		_notify_user(uid, friends_message(uid))


## Når noen kommer eller går (eller starter et parti), får de som har venner en oppdatert liste.
func _push_friends() -> void:
	var sent := {}
	for p: Player in players.values():
		if p.user_id == 0 or p.peer == 0 or sent.has(p.user_id):
			continue
		sent[p.user_id] = true
		var u: Dictionary = store.users.get(p.user_id, {})
		if not (u.get("friends", []) as Array).is_empty() or not (u.get("friend_requests", []) as Array).is_empty():
			_notify_user(p.user_id, friends_message(p.user_id))


func _is_online(uid: int) -> bool:
	for p: Player in players.values():
		if p.user_id == uid and p.peer != 0:
			return true
	return false


# ---------------------------------------------------------------- Tilskuere

## Se på en turneringskamp. Tilskuere får det samme som spillerne (trekk, chat, resultat), med «you» = 0.
func _watch(p: Player, code: String, now: int) -> void:
	code = code.strip_edges().to_upper()
	var room: Room = rooms.get(code)
	if room == null:
		_error(p.peer, "no_room", "Fant ikke rommet %s.", [code])
		return
	if room.match_id == "" and room.state == null:
		_error(p.peer, "not_watchable", "Partiet har ikke startet ennå.")
		return
	if p.room_code != "":
		_error(p.peer, "in_room", "Forlat rommet du er i først.")
		return
	_unwatch(p)
	p.watching = code
	room.spectators.append(p.id)
	_broadcast_room_state(room)
	if room.state != null:
		_send_sync(room, p, now)
	_send_room(room, { "t": Protocol.SPECTATORS, "count": room.spectators.size() })


func _unwatch(p: Player) -> void:
	if p.watching == "":
		return
	var room: Room = rooms.get(p.watching)
	p.watching = ""
	if room and room.spectators.has(p.id):
		room.spectators.erase(p.id)
		_send_room(room, { "t": Protocol.SPECTATORS, "count": room.spectators.size() })


func _drop_spectators(room: Room, key: String, args: Array = []) -> void:
	for id in room.spectators:
		var p: Player = players.get(id)
		if p == null:
			continue
		p.watching = ""
		if p.peer != 0:
			send.call(p.peer, { "t": Protocol.ROOM_CLOSED, "key": key, "args": args,
				"text": key % args if not args.is_empty() else key })
	room.spectators.clear()


# ---------------------------------------------------------------- Global chat, online og hendelser

## Det siste ferdige partiet (uten analysen), til hovedmenyen.
## Det siste partiet og de tre siste (nyeste først). Hovedmenyen spiller av ett av dem om gangen.
func last_game_message() -> Dictionary:
	var games := []
	for i in mini(LAST_GAMES, store.games.size()):
		var g: Dictionary = store.games[-1 - i].duplicate()
		g.erase("analysis")
		games.append(g)
	return { "t": Protocol.LAST_GAME, "game": games[0], "games": games }


## Hvor mange som er online og spiller, og hvem (navn, Elo og om de spiller nå), sortert på navn.
func presence_message() -> Dictionary:
	var in_game := {}
	for room: Room in rooms.values():
		if room.in_game():
			for seat in [1, 2]:
				if room.seats[seat] != 0:
					in_game[room.seats[seat]] = true
	var users := []
	for p: Player in players.values():
		if p.peer != 0:
			users.append({ "name": p.name, "elo": _elo_of(p), "playing": in_game.has(p.id) })
	users.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return { "t": Protocol.PRESENCE, "online": users.size(), "playing": in_game.size(),
		"users": users.slice(0, MAX_PRESENCE_USERS) }


func _announce(key: String, args: Array) -> void:
	social.event(key, args, clock_s.call())


func _broadcast_all(msg: Dictionary) -> void:
	for p: Player in players.values():
		if p.peer != 0:
			send.call(p.peer, msg)


func _global_chat(p: Player, text: String, now: int, channel: String) -> void:
	text = text.strip_edges().substr(0, Protocol.MAX_CHAT)
	if text == "" or now - p.last_global_ms < Social.CHAT_INTERVAL_MS:
		return
	p.last_global_ms = now
	social.chat(p.name, _elo_of(p), text, clock_s.call(), channel)


## Hendelser etter et parti: nytt Elo-nivå, seiersrekker og seire med mange tvungne trekk.
func _publish_achievements(ids: Array, s: GameState, analysis: Dictionary, elo: Dictionary) -> void:
	var now_s: int = clock_s.call()
	for seat in [1, 2]:
		var uid: int = ids[seat]
		if uid == 0 or not store.users.has(uid):
			continue
		var name := accounts.username_of(uid)
		if elo.has(seat):
			var before: Dictionary = EloTiers.tier(int(elo[seat].before))
			var after: Dictionary = EloTiers.tier(int(elo[seat].after))
			if int(after.min) > int(before.min):
				social.event("%s rykket opp til %s!", [name, str(after.name)], now_s)
		if s.winner() != seat:
			continue
		var forced := int(analysis.get(seat, {}).get("winning_streak", 0))
		if forced >= FORCED_WIN_EVENT:
			social.event("%s vant med %d tvungne trekk på rad!", [name, forced], now_s)
		var streak := int(store.users[uid].stats.current_streak)
		if streak in STREAK_MILESTONES:
			social.event("%s har vunnet %d partier på rad!", [name, streak], now_s)


## Merket spilleren får bruke: låste merker (for lav Elo, eller gjest) vises som «ingen».
func _decal_for(p: Player) -> String:
	return p.decal if EloTiers.decal_unlocked(p.decal, _elo_of(p)) else "none"


func _elo_of(p: Player) -> int:
	return int(store.users.get(p.user_id, {}).get("elo", -1)) if p.user_id != 0 else -1


# ---------------------------------------------------------------- Dagens oppgave

func _puzzle_solve(p: Player, msg: Dictionary) -> void:
	var moves = msg.get("moves", [])
	var res := puzzles.solve(p.user_id, str(msg.get("day", "")), moves if moves is Array else [],
		int(msg.get("attempts", 1)), clock_s.call())
	if res.has("error"):
		send.call(p.peer, { "t": Protocol.PUZZLE_RESULT, "ok": false, "text": res.error, "key": res.error })
		return
	send.call(p.peer, { "t": Protocol.PUZZLE_RESULT, "ok": true, "rank": res.rank, "first": res.first })
	if res.first:
		social.event("%s løste dagens oppgave (nr. %d i dag).", [p.name, int(res.rank)], clock_s.call())
	send.call(p.peer, puzzles.info_message(p.user_id, clock_s.call()))


# ---------------------------------------------------------------- Repriser

## De siste partiene til en bruker (deg selv hvis username er tomt).
func _list_games(p: Player, username: String) -> void:
	var u: Dictionary = store.find_user(username) if username != "" else store.users.get(p.user_id, {})
	var out := []
	if not u.is_empty():
		for g in store.games_of(int(u.id)):
			var names := []
			var seat := 0
			for i in (g.get("players", []) as Array).size():
				var rec = g.players[i]
				names.append(str(rec.get("name", "?")) if rec is Dictionary else "?")
				if rec is Dictionary and int(rec.get("user", 0)) == int(u.id):
					seat = i + 1
			out.append({ "id": g.id, "time": g.get("time", ""), "players": names, "seat": seat,
				"result": int(g.get("result", 0)), "reason": int(g.get("reason", 0)),
				"moves": (g.get("moves", []) as Array).size(), "tournament": str(g.get("tournament", "")) != "" })
	send.call(p.peer, { "t": Protocol.GAME_LIST, "username": str(u.get("username", "")), "games": out })


func _send_game(p: Player, id: int) -> void:
	var g := store.get_game(id)
	if g.is_empty():
		_error(p.peer, "no_game", "Fant ikke partiet.")
		return
	send.call(p.peer, { "t": Protocol.GAME_RECORD, "game": g })
