class_name OnlineMatch
extends MatchController
## Parti via serveren. Serveren bestemmer: et trekk vises først når serveren
## har godkjent det (move_made). Lokalt sjekker vi trekket først for rask tilbakemelding.

var _seat := 0
var _start_msg: Dictionary
var _waiting_for_server := false


## start_msg er game_start- eller game_sync-meldingen fra serveren.
func _init(start_msg: Dictionary) -> void:
	mode = "online"
	_start_msg = start_msg


func _ready() -> void:
	Net.message.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)
	Net.connected.connect(_on_connected)


func my_seat() -> int:
	return _seat


func supports_chat() -> bool:
	return true


func is_local_turn() -> bool:
	return super() and not _waiting_for_server


func start_game() -> void:
	_apply_start(_start_msg)


func submit_move(col: Vector2i) -> void:
	if not is_local_turn():
		return
	var err := state.check_move(col)
	if err != GameState.MoveError.OK:
		var hints: Array = []
		if err == GameState.MoveError.MUST_BLOCK:
			hints.assign(state.threat_positions(state.current_player))
		move_rejected.emit(GameState.error_text(err), hints)
		return
	_waiting_for_server = true
	Net.send({ "t": Protocol.MOVE, "x": col.x, "y": col.y, "ply": state.history.size() })


func resign() -> void:
	Net.send({ "t": Protocol.RESIGN })


func request_rematch() -> void:
	Net.send({ "t": Protocol.REMATCH })
	info.emit("Venter på motstanderen…")


func send_chat(text: String) -> void:
	Net.send({ "t": Protocol.CHAT, "text": text })


func leave() -> void:
	Net.send({ "t": Protocol.LEAVE_ROOM })
	Net.close()


# ---------------------------------------------------------------- Fra serveren

func _apply_start(msg: Dictionary) -> void:
	options = GameOptions.from_dict(msg.get("options", {}))
	_seat = int(msg.get("you", 1))
	game_number = int(msg.get("number", 1))
	_read_players(msg.get("players", []))
	var moves: Array = msg.get("moves", [])
	state = GameState.from_moves(options, int(msg.get("first", 1)), moves)
	clock = ChessClock.new(options)
	var clocks: Array = msg.get("clocks", [0, 0])
	var running := int(msg.get("running", state.current_player))
	if clock.enabled:
		clock.sync(int(clocks[0]), int(clocks[1]), running, Time.get_ticks_msec())
	_waiting_for_server = false
	started.emit()
	if bool(msg.get("over", false)):
		_finish_from(msg)
	else:
		turn_changed.emit(state.current_player)


func _read_players(list: Array) -> void:
	var own_skin := ""
	for info in list:
		if info is Dictionary and int(info.seat) == _seat:
			own_skin = str(info.skin)
	for info in list:
		if not info is Dictionary:
			continue
		var seat := int(info.seat)
		var skin := str(info.skin)
		if seat != _seat:
			skin = Skins.contrast_for(own_skin, skin if Skins.is_valid(skin) else Skins.DEFAULT_P2)
		elif not Skins.is_valid(skin):
			skin = Skins.DEFAULT_P1
		var sub := "" if bool(info.get("connected", true)) else "frakoblet"
		players[seat] = { "name": str(info.name), "skin": skin, "local": seat == _seat, "subtitle": sub }
	players_changed.emit()


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.GAME_START, Protocol.GAME_SYNC:
			_apply_start(msg)
		Protocol.MOVE_MADE:
			_waiting_for_server = false
			if state == null or int(msg.ply) != state.history.size():
				return
			var col := Vector2i(int(msg.x), int(msg.y))
			var player := state.current_player
			var r := state.play(col, false)
			var clocks: Array = msg.get("clocks", [0, 0])
			if clock.enabled:
				clock.sync(int(clocks[0]), int(clocks[1]), int(msg.get("running", 0)), Time.get_ticks_msec())
			move_applied.emit(col, r.pos, player)
			if not state.is_over():
				turn_changed.emit(state.current_player)
		Protocol.MOVE_REJECTED:
			_waiting_for_server = false
			move_rejected.emit(str(msg.get("text", "")), Protocol.positions_from_json(msg.get("hints", [])))
		Protocol.GAME_OVER:
			_finish_from(msg)
		Protocol.CHAT_MSG:
			chat_received.emit(str(msg.get("from", "")), str(msg.get("text", "")))
		Protocol.ROOM_STATE:
			if state != null:
				_read_players(msg.get("players", []))
		Protocol.NOTICE, Protocol.ERROR:
			info.emit(str(msg.get("text", "")))


func _finish_from(msg: Dictionary) -> void:
	var result := int(msg.get("result", 0))
	var reason := int(msg.get("reason", 0))
	if not state.is_over():
		var winner := int(msg.get("winner", 0))
		state.end_with_loss(GameState.opponent(winner) if winner != 0 else 1, reason)
	var clocks: Array = msg.get("clocks", [0, 0])
	if clock.enabled:
		clock.sync(int(clocks[0]), int(clocks[1]), 0, Time.get_ticks_msec())
	var line := Protocol.positions_from_json(msg.get("line", []))
	finished.emit(result, reason, line)


func _on_disconnected() -> void:
	info.emit("Mistet forbindelsen. Kobler til igjen…")


func _on_connected(resumed: bool) -> void:
	if not resumed and state != null and not state.is_over():
		info.emit("Partiet ble avbrutt (serveren startet på nytt).")
		state.end_with_loss(_seat, GameState.EndReason.DISCONNECT)
		finished.emit(state.result, state.end_reason, [])
