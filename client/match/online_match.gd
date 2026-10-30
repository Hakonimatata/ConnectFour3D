class_name OnlineMatch
extends MatchController
## Parti via serveren. Serveren bestemmer: et trekk vises først når serveren
## har godkjent det (move_made). Lokalt sjekker vi trekket først for rask tilbakemelding.

## En tilskuer reagerte (se Protocol.REACTIONS).
signal reaction_received(kind: String)
## Meldinger i turneringschatten. history = hele loggen (erstatter det som vises).
signal tournament_chat_received(messages: Array, history: bool)

var _seat := 0
var _start_msg: Dictionary
var tournament: Dictionary = {}     ## { id, name, ranked } hvis dette er en turneringskamp
var last_elo: Dictionary = {}       ## Elo før/etter for mitt sete etter partiet (tom = ikke rangert)
var last_xp: Dictionary = {}        ## XP etter partiet for mitt sete { gained, xp, level, level_before, unlocked } (tom = ingen)
var spectators := 0                 ## antall tilskuere (bare turneringskamper)
var room_code := ""
var keep_room := false              ## true = bli i rommet når skjermen byttes (f.eks. endre regler mellom partier)
var _raw_players: Array = []
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


## Rommet slik venterommet trenger det (serveren sender oppdatert status straks etterpå).
func room_snapshot() -> Dictionary:
	var ps := []
	for info in _raw_players:
		if info is Dictionary:
			var copy: Dictionary = info.duplicate()
			copy.ready = false
			ps.append(copy)
	return { "code": room_code, "you": _seat, "options": options.to_dict(), "players": ps, "tournament": null,
		"in_game": false, "description": options.describe() }


## Ser vi på som tilskuer (ikke spiller)?
func is_spectator() -> bool:
	return _seat == 0


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
	info.emit(tr("Venter på motstanderen…"))


func send_chat(text: String) -> void:
	Net.send({ "t": Protocol.CHAT, "text": text })


func send_reaction(kind: String) -> void:
	Net.send({ "t": Protocol.REACT, "kind": kind })


## Tom tekst = be om historikken.
func send_tournament_chat(text: String) -> void:
	if not tournament.is_empty():
		Net.send({ "t": Protocol.TOURNAMENT_CHAT, "id": int(tournament.id), "text": text })


func leave() -> void:
	if keep_room:
		return
	Net.send({ "t": Protocol.LEAVE_ROOM })
	if not is_spectator() and tournament.is_empty():   # fra en turneringskamp går vi tilbake til turneringssiden
		Net.close()


# ---------------------------------------------------------------- Fra serveren

func _apply_start(msg: Dictionary) -> void:
	options = GameOptions.from_dict(msg.get("options", {}))
	_seat = int(msg.get("you", 1))
	spectators = int(msg.get("spectators", 0))
	room_code = str(msg.get("code", room_code))
	_raw_players = msg.get("players", [])
	tournament = msg.get("tournament") if msg.get("tournament") is Dictionary else {}
	last_elo = {}
	last_xp = {}
	game_number = int(msg.get("number", 1))
	_read_players(msg.get("players", []))
	var moves: Array = msg.get("moves", [])
	state = GameState.from_moves(options, int(msg.get("first", 1)), moves)
	clock = ChessClock.new(options)
	var clocks: Array = msg.get("clocks", [0, 0])
	var running := int(msg.get("running", state.current_player))
	play_at_ms = Time.get_ticks_msec() + int(msg.get("countdown", 0))
	if clock.enabled:
		clock.sync(int(clocks[0]), int(clocks[1]), running, maxi(play_at_ms, Time.get_ticks_msec()))
	_waiting_for_server = false
	started.emit()
	if bool(msg.get("over", false)):
		_finish_from(msg)
	else:
		turn_changed.emit(state.current_player)


func _read_players(list: Array) -> void:
	for info in list:
		if not info is Dictionary:
			continue
		var seat := int(info.seat)
		var sub := "" if bool(info.get("connected", true)) else tr("frakoblet")
		var elo := int(info.elo) if info.get("elo") != null else -1
		if elo >= 0 and sub == "":
			sub = EloBadge.describe(elo)
		players[seat] = { "name": str(info.name), "avatar": str(info.get("avatar", "")),
			"local": seat == _seat, "subtitle": sub, "elo": elo }
		players[seat].merge(Skins.look(str(info.get("skin", "")), str(info.get("decal", "none")),
			str(info.get("win_fx", "classic")), bool(info.get("away", false)), str(info.get("decal_color", "auto"))), true)
	# Begge klientene regner likt: verten (sete 1) har hjemmedrakt, gjesten bortedrakt ved lik skin.
	resolve_looks()
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
		Protocol.REACTION:
			reaction_received.emit(str(msg.get("kind", "")))
		Protocol.TOURNAMENT_CHAT_MSG:
			if not tournament.is_empty() and int(msg.get("id", 0)) == int(tournament.id):
				tournament_chat_received.emit(msg.get("messages", []), bool(msg.get("history", false)))
		Protocol.ROOM_STATE:
			spectators = int(msg.get("spectators", spectators))
			if state != null:
				_read_players(msg.get("players", []))
		Protocol.SPECTATORS:
			spectators = int(msg.get("count", 0))
			players_changed.emit()
		Protocol.NOTICE, Protocol.ERROR:
			info.emit(I18n.server_text(msg))


func _finish_from(msg: Dictionary) -> void:
	var result := int(msg.get("result", 0))
	var reason := int(msg.get("reason", 0))
	if not state.is_over():
		var winner := int(msg.get("winner", 0))
		state.end_with_loss(GameState.opponent(winner) if winner != 0 else 1, reason)
	var clocks: Array = msg.get("clocks", [0, 0])
	if clock.enabled:
		clock.sync(int(clocks[0]), int(clocks[1]), 0, Time.get_ticks_msec())
	var elo = msg.get("elo", {})
	if elo is Dictionary and elo.has(str(_seat)):
		last_elo = elo[str(_seat)]
	var xp = msg.get("xp", {})
	if xp is Dictionary and xp.get(str(_seat)) is Dictionary:
		last_xp = xp[str(_seat)]
	var line := Protocol.positions_from_json(msg.get("line", []))
	finished.emit(result, reason, line)


func _on_disconnected() -> void:
	info.emit(tr("Mistet forbindelsen. Kobler til igjen…"))


func _on_connected(resumed: bool) -> void:
	if not resumed and state != null and not state.is_over():
		info.emit(tr("Partiet ble avbrutt (serveren startet på nytt)."))
		state.end_with_loss(_seat, GameState.EndReason.DISCONNECT)
		finished.emit(state.result, state.end_reason, [])
