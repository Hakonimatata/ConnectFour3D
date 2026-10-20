extends TestCase
## Ende-til-ende: ekte WebSocket-server, en «rå» testklient (A) og spillets egen
## nettverksklient Net + OnlineMatch (B). Spiller et helt parti med chat.

const PORT := 18765


class RawClient:
	var ws := WebSocketPeer.new()
	var inbox: Array[Dictionary] = []

	func open(url: String) -> void:
		ws.connect_to_url(url)

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
var a := RawClient.new()


func after_each() -> void:
	Net.close()
	if server:
		server.queue_free()
	await tree.process_frame


func _poll_until(cond: Callable, timeout_s := 5.0) -> bool:
	return await wait_until(func() -> bool:
		a.poll()
		return cond.call()
	, timeout_s)


func test_full_online_game() -> void:
	server = ServerMain.new()
	server.port = PORT
	root.add_child(server)
	var url := "ws://127.0.0.1:%d" % PORT

	# A: kobler til, oppretter rom
	a.open(url)
	check(await _poll_until(func() -> bool: return a.ws.get_ready_state() == WebSocketPeer.STATE_OPEN), "A koblet ikke til")
	a.send({ "t": "hello", "name": "Ada", "skin": "gold", "version": Protocol.VERSION })
	a.send({ "t": "create_room", "options": {}, "private": true })
	check(await _poll_until(func() -> bool: return not a.last("room_state").is_empty()), "fikk ikke romstatus")
	var code: String = a.last("room_state").code

	# B: spillets egen klient
	var b_msgs: Array[Dictionary] = []
	var collect := func(m: Dictionary) -> void: b_msgs.append(m)
	Net.message.connect(collect)
	Net.connect_to_server(url)
	check(await _poll_until(func() -> bool: return Net.is_online()), "Net koblet ikke til")
	Net.send({ "t": "join_room", "code": code })
	a.send({ "t": "ready", "ready": true })
	Net.send({ "t": "ready", "ready": true })
	check(await _poll_until(func() -> bool:
		return b_msgs.any(func(m: Dictionary) -> bool: return m.t == Protocol.GAME_START)
	), "partiet startet ikke")
	var start: Dictionary = b_msgs.filter(func(m: Dictionary) -> bool: return m.t == Protocol.GAME_START)[0]
	Net.message.disconnect(collect)

	var m := OnlineMatch.new(start)
	root.add_child(m)
	var applied := []
	var result := {}
	var chats := []
	m.move_applied.connect(func(col: Vector2i, _pos: Vector3i, player: int) -> void: applied.append([col, player]))
	m.finished.connect(func(r: int, reason: int, line: Array) -> void: result.merge({ "r": r, "reason": reason, "line": line }))
	m.chat_received.connect(func(from: String, text: String) -> void: chats.append([from, text]))
	m.start_game()
	check_eq(m.my_seat(), 2)
	check_eq(m.players[1].name, "Ada")

	# A (P1) bygger fire langs x på y=0, B (P2) legger på y=1.
	var a_moves := [[0, 0], [1, 0], [2, 0], [3, 0]]
	var b_moves := [[0, 1], [1, 1], [2, 1]]
	for i in 4:
		a.send({ "t": "move", "x": a_moves[i][0], "y": a_moves[i][1], "ply": i * 2 })
		check(await _poll_until(func() -> bool: return applied.size() == i * 2 + 1), "B så ikke A sitt trekk %d" % i)
		if i < 3:
			check(m.is_local_turn(), "B skal ha tur")
			m.submit_move(Vector2i(b_moves[i][0], b_moves[i][1]))
			check(not m.is_local_turn(), "venter på server etter trekk")
			check(await _poll_until(func() -> bool: return applied.size() == i * 2 + 2), "B sitt trekk %d kom ikke tilbake" % i)

	check(await _poll_until(func() -> bool: return not result.is_empty()), "fikk ikke game_over")
	check_eq(result.get("r"), GameState.Result.P1_WON)
	check_eq(result.get("line", []).size(), 4)
	check_eq(m.state.winner(), 1)

	m.send_chat("GG!")
	check(await _poll_until(func() -> bool: return not a.last("chat").is_empty()), "A fikk ikke chat")
	check_eq(a.last("chat").text, "GG!")
	a.send({ "t": "chat", "text": "takk" })
	# Serveren sender også egne meldinger tilbake, så chatten viser alt likt.
	check(await _poll_until(func() -> bool: return chats.size() == 2), "B fikk ikke chat")
	check_eq(chats[0][1], "GG!")
	check_eq(chats[1], ["Ada", "takk"])

	m.queue_free()
	a.ws.close()
