class_name Lobby
extends RefCounted
## All serverlogikk: spillere, rom, partier, klokker og chat.
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
	var avatar := ""               ## base64-JPEG, sjekket med AvatarData.is_valid
	var token: String
	var peer := 0                  ## 0 = frakoblet
	var room_code := ""
	var disconnected_at := -1
	var last_chat_ms := -100_000


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


func _init() -> void:
	rng.randomize()


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
		_notice_room(room, "%s mistet forbindelsen…" % p.name, p.id)
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
	match t:
		Protocol.PING: send.call(peer, { "t": Protocol.PONG })
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
		_: _error(peer, "unknown", "Ukjent melding: " + t)


## Kalles jevnlig: tid ute og spillere som ikke kom tilbake.
func tick(now: int) -> void:
	for room: Room in rooms.values():
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
	p.name = Protocol.clean_name(msg.get("name", "Spiller"))
	p.skin = str(msg.get("skin", "ocean")).substr(0, 24)
	var avatar = msg.get("avatar", "")
	p.avatar = avatar if AvatarData.is_valid(avatar) else ""
	p.peer = peer
	p.disconnected_at = -1
	_peers[peer] = p.id
	send.call(peer, { "t": Protocol.WELCOME, "player_id": p.id, "token": p.token, "resumed": resumed })

	var room := _room_of(p)
	if room:
		_broadcast_room_state(room)
		if room.state != null:
			_send_sync(room, p, now)
		_notice_room(room, "%s er tilbake." % p.name, p.id)


func _list_rooms(p: Player) -> void:
	var list := []
	for room: Room in rooms.values():
		if room.private or room.seats[2] != 0 or room.seats[1] == 0:
			continue
		list.append({ "code": room.code, "host": players[room.seats[1]].name, "options": room.options.to_dict(),
			"description": room.options.describe() })
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
		_error(p.peer, "no_room", "Fant ikke rommet %s." % code)
		return
	var room: Room = rooms[code]
	if room.seat_of(p.id) > 0:
		_broadcast_room_state(room)
		return
	if room.seats[1] != 0 and room.seats[2] != 0:
		_error(p.peer, "room_full", "Rommet er fullt.")
		return
	_leave_room(p, now)
	var seat := 1 if room.seats[1] == 0 else 2
	room.seats[seat] = p.id
	p.room_code = room.code
	_notice_room(room, "%s ble med." % p.name, p.id)
	_broadcast_room_state(room)


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
	if room.is_empty():
		rooms.erase(room.code)
		return
	# Den som er igjen blir vert (sete 1).
	if room.seats[1] == 0:
		room.seats[1] = room.seats[2]
		room.seats[2] = 0
	room.state = null
	_notice_room(room, "%s forlot rommet." % p.name, p.id)
	_broadcast_room_state(room)


func _set_options(p: Player, msg: Dictionary) -> void:
	var room := _room_of(p)
	if room == null or room.seat_of(p.id) != 1 or room.in_game():
		return
	var opts = msg.get("options", {})
	room.options = GameOptions.from_dict(opts if opts is Dictionary else {})
	room.ready.fill(false)
	_broadcast_room_state(room)


func _set_ready(p: Player, value: bool, now: int) -> void:
	var room := _room_of(p)
	if room == null or room.in_game():
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
	var seat := room.seat_of(p.id)
	room.rematch[seat] = true
	if room.rematch[1] and room.rematch[2]:
		_start_game(room, now)
	else:
		_notice_room(room, "%s vil spille igjen!" % p.name, p.id)


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
	}


func _game_over(room: Room, now: int) -> void:
	room.clock.stop(now)
	var s := room.state
	_send_room(room, { "t": Protocol.GAME_OVER, "result": s.result, "reason": s.end_reason, "winner": s.winner(),
		"line": Protocol.positions_to_json(s.winning_line), "clocks": _clocks(room, now) })


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
		out.append({ "seat": seat, "name": p.name, "skin": p.skin, "avatar": p.avatar,
			"ready": room.ready[seat], "connected": p.peer != 0 })
	return out


func _broadcast_room_state(room: Room) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id == 0 or players[id].peer == 0:
			continue
		send.call(players[id].peer, {
			"t": Protocol.ROOM_STATE, "code": room.code, "private": room.private, "options": room.options.to_dict(),
			"description": room.options.describe(), "you": seat, "in_game": room.in_game(), "players": _players_info(room),
		})


func _send_room(room: Room, msg: Dictionary) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and players[id].peer != 0:
			send.call(players[id].peer, msg)


func _notice_room(room: Room, text: String, except_id: int) -> void:
	for seat in [1, 2]:
		var id := room.seats[seat]
		if id != 0 and id != except_id and players[id].peer != 0:
			send.call(players[id].peer, { "t": Protocol.NOTICE, "text": text })


func _error(peer: int, code: String, text: String) -> void:
	send.call(peer, { "t": Protocol.ERROR, "code": code, "text": text })


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[rng.randi() % CODE_LETTERS.length()]
		if not rooms.has(code):
			return code
	return ""
