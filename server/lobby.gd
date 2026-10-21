class_name Lobby
extends RefCounted
## All serverlogikk: spillere, rom, partier, klokker, chat, kontoer og turneringer.
## Vet ingenting om nettverk. ServerMain gir meldinger inn (on_message) og
## sender det Lobby legger ut via `send`. Tiden (now_ms) gis utenfra.
## Derfor kan hele serveren testes uten sockets (se tests/test_lobby.gd).

const RECONNECT_GRACE_MS := 60_000
const CHAT_INTERVAL_MS := 350
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"   # uten I og O
const CODE_LENGTH := 5


class Player:
	var id: int
	var name: String
	var skin: String
	var decal := "none"
	var win_fx := "classic"
	var decal_color := "auto"
	var avatar := ""               ## base64-JPEG, sjekket med AvatarData.is_valid
	var token: String
	var peer := 0                  ## 0 = frakoblet
	var room_code := ""
	var disconnected_at := -1
	var last_chat_ms := -100_000
	var user_id := 0               ## 0 = gjest (ikke innlogget)
	var guest_name := ""           ## kallenavnet fra hello (brukes igjen etter utlogging)


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
## Veggklokke i unix-sekunder (kan byttes ut i tester).
var clock_s: Callable = func() -> int: return int(Time.get_unix_time_from_system())
var _last_ms := 0


func _init() -> void:
	rng.randomize()
	_hook_tournaments()


## Bytter til varig lagring (ServerMain gjør dette med datamappen).
func use_store(p_store: Store) -> void:
	store = p_store
	accounts = Accounts.new(store)
	tournaments = Tournaments.new(store, accounts)
	_hook_tournaments()


func _hook_tournaments() -> void:
	tournaments.open_room = _open_tournament_room
	tournaments.presence = _room_presence
	tournaments.notify = _notify_user
	tournaments.close_room = _close_room


# ---------------------------------------------------------------- Tilkobling

func on_disconnect(peer: int, now: int) -> void:
	if not _peers.has(peer):
		return
	var p: Player = players[_peers[peer]]
	_peers.erase(peer)
	p.peer = 0
	p.disconnected_at = now
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
		Protocol.GET_TOURNAMENT: _send_tournament(p, int(msg.get("id", 0)))
		Protocol.TOURNAMENT_JOIN, Protocol.TOURNAMENT_LEAVE, Protocol.TOURNAMENT_CREATE, \
		Protocol.TOURNAMENT_UPDATE, Protocol.TOURNAMENT_ACTION:
			_tournament_request(p, t, msg)
		Protocol.LIST_ROOMS: _list_rooms(p)
		Protocol.CREATE_ROOM: _create_room(p, msg, now)
		Protocol.JOIN_ROOM: _join_room(p, str(msg.get("code", "")), now)
		Protocol.LEAVE_ROOM: _leave_room(p, now)
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
	var avatar = msg.get("avatar", "")
	p.avatar = avatar if AvatarData.is_valid(avatar) else ""
	p.peer = peer
	p.disconnected_at = -1
	_peers[peer] = p.id
	# Husket innlogging (økt-nøkkel fra forrige gang)
	var user := accounts.user_for_session(str(msg.get("session", "")), clock_s.call())
	if not user.is_empty():
		_sign_in(p, user)
	elif p.user_id != 0 and resumed:
		user = store.users.get(p.user_id, {})
		if not user.is_empty():
			_sign_in(p, user)
	send.call(peer, { "t": Protocol.WELCOME, "player_id": p.id, "token": p.token, "resumed": resumed,
		"user": accounts.public_info(user) if not user.is_empty() else null })

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
	send.call(p.peer, { "t": Protocol.ROOM_LIST, "rooms": list })


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
	_broadcast_room_state(room)


func _set_ready(p: Player, value: bool, now: int) -> void:
	var room := _room_of(p)
	if room == null or room.in_game() or room.match_id != "":
		return
	room.ready[room.seat_of(p.id)] = value
	if room.seats[1] != 0 and room.seats[2] != 0 and room.ready[1] and room.ready[2]:
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
	var room := _room_of(p)
	text = text.strip_edges().substr(0, Protocol.MAX_CHAT)
	if room == null or text == "" or now - p.last_chat_ms < CHAT_INTERVAL_MS:
		return
	p.last_chat_ms = now
	_send_room(room, { "t": Protocol.CHAT_MSG, "from": p.name, "seat": room.seat_of(p.id), "text": text })


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
	if room.rematch[1] and room.rematch[2]:
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


func _send_sync(room: Room, p: Player, now: int) -> void:
	var msg := _start_message(room, room.seat_of(p.id), now)
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
	store.append_game({
		"time": Time.get_datetime_string_from_unix_time(clock_s.call(), true), "options": room.options.to_dict(),
		"players": [_seat_record(room, 1), _seat_record(room, 2)], "first": s.first_player, "moves": moves,
		"result": s.result, "reason": s.end_reason, "analysis": { "1": analysis[1], "2": analysis[2] },
		"elo": elo, "tournament": room.match_id,
	})
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
		out.append({ "seat": seat, "name": p.name, "skin": p.skin, "decal": p.decal, "win_fx": p.win_fx,
			"decal_color": p.decal_color, "avatar": p.avatar,
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
		})


func _send_room(room: Room, msg: Dictionary) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and players[id].peer != 0:
			send.call(players[id].peer, msg)


## key er en norsk tekst med %s for args. Klienten oversetter key, og «text» er ferdig utfylt.
func _notice_room(room: Room, key: String, args: Array, except_id: int) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and id != except_id and players[id].peer != 0:
			send.call(players[id].peer, { "t": Protocol.NOTICE, "text": key % args, "key": key, "args": args })


func _error(peer: int, code: String, key: String, args: Array = []) -> void:
	var text := key % args if not args.is_empty() else key
	send.call(peer, { "t": Protocol.ERROR, "code": code, "text": text, "key": key, "args": args })


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
		send.call(p.peer, { "t": Protocol.AUTH_ERROR, "key": res.error, "text": res.error })
		return
	_sign_in(p, res.user)
	var token := accounts.create_session(res.user.id, clock_s.call())
	send.call(p.peer, { "t": Protocol.SESSION, "token": token, "user": accounts.public_info(res.user) })
	var room := _room_of(p)
	if room:
		_broadcast_room_state(room)


func _sign_in(p: Player, user: Dictionary) -> void:
	p.user_id = int(user.id)
	p.name = str(user.username)
	accounts.update_profile(p.user_id, p.skin, p.decal, p.win_fx, p.avatar)


## Byttet utseende (skin, merke, seiersanimasjon). Rommet får beskjed, så motstanderen ser det før start.
func _set_look(p: Player, msg: Dictionary) -> void:
	p.skin = str(msg.get("skin", p.skin)).substr(0, 24)
	p.decal = str(msg.get("decal", p.decal)).substr(0, 24)
	p.win_fx = str(msg.get("win_fx", p.win_fx)).substr(0, 24)
	p.decal_color = str(msg.get("decal_color", p.decal_color)).substr(0, 24)
	if p.user_id != 0:
		accounts.update_profile(p.user_id, p.skin, p.decal, p.win_fx, p.avatar)
	var room := _room_of(p)
	if room and not room.in_game():
		_broadcast_room_state(room)


func _logout(p: Player, msg: Dictionary) -> void:
	accounts.end_session(str(msg.get("session", "")))
	p.user_id = 0
	p.name = p.guest_name
	send.call(p.peer, { "t": Protocol.LOGGED_OUT })


func _stats(p: Player, username: String) -> void:
	var u: Dictionary = store.find_user(username) if username != "" else store.users.get(p.user_id, {})
	send.call(p.peer, { "t": Protocol.STATS, "user": accounts.public_info(u) if not u.is_empty() else null })


func _user_in_seat(room: Room, seat: int) -> int:
	var id := room.seats[seat]
	return players[id].user_id if id != 0 and players.has(id) else 0


func _seat_record(room: Room, seat: int) -> Dictionary:
	var id := room.seats[seat]
	if id == 0 or not players.has(id):
		return {}
	var p: Player = players[id]
	return { "name": p.name, "user": p.user_id }


# ---------------------------------------------------------------- Turneringer

func _list_tournaments(p: Player) -> void:
	var list := store.tournaments.map(func(t: Dictionary) -> Dictionary: return tournaments.summary(t))
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
	rooms.erase(code)

