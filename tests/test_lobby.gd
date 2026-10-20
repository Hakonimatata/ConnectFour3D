extends TestCase
## Tester for serverlogikken (server/lobby.gd), uten nettverk.
## To «klienter» er bare peer-id 1 og 2; utgående meldinger samles i _inbox.

var lobby: Lobby
var _inbox := {}      ## peer -> Array[Dictionary]
var _closed: Array[int] = []
var now := 1000


func before_each() -> void:
	lobby = Lobby.new()
	lobby.send = func(peer: int, msg: Dictionary) -> void:
		# Send gjennom JSON slik som på ekte, så tall blir float osv.
		_inbox.get_or_add(peer, []).append(Protocol.decode(Protocol.encode(msg)))
	lobby.close_peer = func(peer: int) -> void: _closed.append(peer)


func after_each() -> void:
	# Bryt referansesyklusen test -> lobby -> lambda -> test
	lobby.send = Callable()
	lobby.close_peer = Callable()


func _msg(peer: int, msg: Dictionary) -> void:
	lobby.on_message(peer, msg, now)


func _hello(peer: int, name: String, token := "") -> void:
	_msg(peer, { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION, "token": token })


## Siste melding av typen t til peer (eller {}).
func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _count(peer: int, t: String) -> int:
	return _inbox.get(peer, []).filter(func(m: Dictionary) -> bool: return m.t == t).size()


## Oppretter et rom med to spillere som er klare. Gir romkoden.
func _start_game(options := {}) -> String:
	_hello(1, "Ada")
	_hello(2, "Bo")
	_msg(1, { "t": "create_room", "options": options, "private": false })
	var code: String = _last(1, "room_state").code
	_msg(2, { "t": "join_room", "code": code.to_lower() })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	return code


func test_hello_and_version_check() -> void:
	_hello(1, "Ada")
	check_eq(_last(1, "welcome").get("resumed"), false)
	_msg(2, { "t": "hello", "name": "Gammel", "version": 0 })
	check_eq(_last(2, "error").get("code"), "version")
	check(2 in _closed, "utdatert klient skal kobles fra")


func test_avatar_is_shared_and_invalid_ones_dropped() -> void:
	var img := Image.create(40, 30, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	var avatar := AvatarData.from_bytes(img.save_png_to_buffer())
	_msg(1, { "t": "hello", "name": "Ada", "skin": "ocean", "decal": "star", "win_fx": "confetti", "avatar": avatar,
		"version": Protocol.VERSION })
	_msg(2, { "t": "hello", "name": "Bo", "skin": "lime", "avatar": Marshalls.raw_to_base64("ikke et bilde".to_utf8_buffer()),
		"version": Protocol.VERSION })
	_msg(1, { "t": "create_room", "options": {}, "private": true })
	_msg(2, { "t": "join_room", "code": _last(1, "room_state").code })
	var players: Array = _last(2, "room_state").players
	check_eq(players[0].avatar, avatar, "Ada sitt bilde deles:")
	check_eq(players[0].decal, "star")
	check_eq(players[0].win_fx, "confetti")
	check_eq(players[1].avatar, "", "ugyldig bilde droppes:")


func test_messages_before_hello_are_rejected() -> void:
	_msg(1, { "t": "create_room" })
	check_eq(_last(1, "error").get("code"), "not_logged_in")


func test_create_list_and_join_room() -> void:
	_hello(1, "Ada")
	_hello(2, "Bo")
	_msg(1, { "t": "create_room", "options": { "size": 5, "must_block": true }, "private": false })
	var room := _last(1, "room_state")
	check_eq(room.code.length(), 5)
	check_eq(room.options.size, 5.0)
	_msg(2, { "t": "list_rooms" })
	var listed: Array = _last(2, "room_list").rooms
	check_eq(listed.size(), 1)
	check_eq(listed[0].host, "Ada")
	_msg(2, { "t": "join_room", "code": room.code })
	check_eq(_last(2, "room_state").you, 2.0)
	check_eq(_last(1, "room_state").players[1].name, "Bo")
	_msg(2, { "t": "list_rooms" })
	check_eq(_last(2, "room_list").rooms.size(), 0, "fullt rom skal ikke listes:")


func test_private_rooms_are_hidden_but_joinable() -> void:
	_hello(1, "Ada")
	_hello(2, "Bo")
	_msg(1, { "t": "create_room", "options": {}, "private": true })
	var code: String = _last(1, "room_state").code
	_msg(2, { "t": "list_rooms" })
	check_eq(_last(2, "room_list").rooms.size(), 0)
	_msg(2, { "t": "join_room", "code": code })
	check_eq(_last(2, "room_state").code, code)


func test_join_unknown_room() -> void:
	_hello(1, "Ada")
	_msg(1, { "t": "join_room", "code": "ZZZZZ" })
	check_eq(_last(1, "error").get("code"), "no_room")


func test_game_starts_when_both_ready() -> void:
	_start_game()
	check_eq(_count(1, "game_start"), 1)
	check_eq(_last(1, "game_start").you, 1.0)
	check_eq(_last(2, "game_start").you, 2.0)


func test_full_game_with_win() -> void:
	_start_game()
	var moves := [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0]]
	for i in moves.size():
		var peer := 1 if i % 2 == 0 else 2
		_msg(peer, { "t": "move", "x": moves[i][0], "y": moves[i][1], "ply": i })
	check_eq(_count(2, "move_made"), 7)
	var over := _last(2, "game_over")
	check_eq(over.get("winner"), 1.0)
	check_eq(over.get("reason"), float(GameState.EndReason.LINE))
	check_eq(over.line.size(), 4)


func test_rejects_wrong_turn_illegal_and_duplicate_moves() -> void:
	_start_game({ "must_block": true })
	_msg(2, { "t": "move", "x": 0, "y": 0, "ply": 0 })
	check_eq(_last(2, "move_rejected").text, "Det er ikke din tur.")
	_msg(1, { "t": "move", "x": 9, "y": 9, "ply": 0 })
	check_eq(_last(1, "move_rejected").text, GameState.error_text(GameState.MoveError.OUT_OF_BOUNDS))
	_msg(1, { "t": "move", "x": 0, "y": 0, "ply": 0 })
	_msg(1, { "t": "move", "x": 0, "y": 0, "ply": 0 })   # duplisert
	check_eq(_count(1, "move_made"), 1)
	# Må blokkere: P1 får tre på rad, P2 må blokkere (3, 0).
	_msg(2, { "t": "move", "x": 0, "y": 3, "ply": 1 })
	_msg(1, { "t": "move", "x": 1, "y": 0, "ply": 2 })
	_msg(2, { "t": "move", "x": 1, "y": 3, "ply": 3 })
	_msg(1, { "t": "move", "x": 2, "y": 0, "ply": 4 })
	_msg(2, { "t": "move", "x": 2, "y": 2, "ply": 5 })
	var rejected := _last(2, "move_rejected")
	check_eq(rejected.text, GameState.error_text(GameState.MoveError.MUST_BLOCK))
	check_eq(rejected.hints, [[3.0, 0.0, 0.0]])


func test_timeout_loses() -> void:
	_start_game({ "time_base_s": 60 })
	now += 61_000
	lobby.tick(now)
	var over := _last(1, "game_over")
	check_eq(over.get("reason"), float(GameState.EndReason.TIMEOUT))
	check_eq(over.get("winner"), 2.0, "P1 hadde tur og gikk tom for tid:")


func test_resign_and_rematch() -> void:
	_start_game({ "starter": "alternate" })
	_msg(1, { "t": "resign" })
	check_eq(_last(2, "game_over").get("winner"), 2.0)
	_msg(1, { "t": "rematch" })
	check_eq(_last(2, "notice").text, "Ada vil spille igjen!")
	check_eq(_last(2, "notice").key, "%s vil spille igjen!", "meldingen har nøkkel for oversettelse:")
	check_eq(_last(2, "notice").args, ["Ada"])
	_msg(2, { "t": "rematch" })
	check_eq(_count(1, "game_start"), 2)
	check_eq(_last(1, "game_start").first, 2.0, "annenhver: parti 2 startes av P2:")


func test_chat_is_trimmed_and_rate_limited() -> void:
	_start_game()
	_msg(1, { "t": "chat", "text": "  hei " + "x".repeat(500) })
	var chat := _last(2, "chat")
	check_eq(chat.from, "Ada")
	check_eq(chat.text.length(), Protocol.MAX_CHAT)
	_msg(1, { "t": "chat", "text": "spam" })
	check_eq(_count(2, "chat"), 1, "for rask chat skal ignoreres:")
	now += 1000
	_msg(1, { "t": "chat", "text": "ok" })
	check_eq(_count(2, "chat"), 2)


func test_reconnect_with_token_gets_sync() -> void:
	_start_game()
	_msg(1, { "t": "move", "x": 1, "y": 1, "ply": 0 })
	var token: String = _last(1, "welcome").token
	lobby.on_disconnect(1, now)
	check_eq(_last(2, "notice").text, "Ada mistet forbindelsen…")
	now += 5000
	_hello(3, "Ada", token)   # ny tilkobling (peer 3), samme spiller
	check_eq(_last(3, "welcome").resumed, true)
	var sync := _last(3, "game_sync")
	check_eq(sync.moves, [[1.0, 1.0]])
	check_eq(sync.you, 1.0)
	_msg(2, { "t": "move", "x": 2, "y": 2, "ply": 1 })
	check_eq(_count(3, "move_made"), 1, "den nye tilkoblingen får trekkene:")


func test_disconnect_too_long_forfeits() -> void:
	_start_game()
	lobby.on_disconnect(2, now)
	now += Lobby.RECONNECT_GRACE_MS + 1
	lobby.tick(now)
	var over := _last(1, "game_over")
	check_eq(over.get("reason"), float(GameState.EndReason.DISCONNECT))
	check_eq(over.get("winner"), 1.0)


func test_leaving_makes_other_player_host_and_empty_room_closes() -> void:
	var code := _start_game()
	_msg(1, { "t": "leave_room" })
	check_eq(_last(2, "game_over").get("winner"), 2.0)
	var room := _last(2, "room_state")
	check_eq(room.you, 1.0, "Bo blir vert:")
	_msg(2, { "t": "leave_room" })
	check(not lobby.rooms.has(code), "tomt rom skal slettes")


func test_garbage_input_does_not_crash() -> void:
	_hello(1, "Ada")
	for m in [{ "t": "move" }, { "t": "move", "x": "a", "y": null }, { "t": "join_room", "code": 5 },
			{ "t": "create_room", "options": "tull" }, { "t": "ready" }, { "t": "chat" }, { "t": "x" }]:
		_msg(1, m)
	check_eq(Protocol.decode("ikke json"), {})
	check_eq(Protocol.decode("[1, 2]"), {})
	check_eq(Protocol.decode("{\"t\": 5}"), {})
