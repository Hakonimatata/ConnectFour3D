extends Node
## Autoload «Net»: WebSocket-tilkoblingen til serveren.
## Kobler automatisk til igjen ved brudd, og sender token slik at serveren
## kjenner oss igjen og kan sende partiet på nytt.

signal connected(resumed: bool)
signal disconnected
signal message(msg: Dictionary)

enum Status { OFFLINE, CONNECTING, ONLINE }

const PING_INTERVAL_S := 20.0

var status := Status.OFFLINE
var url := ""
var player_id := 0
var last_error := ""

var _ws: WebSocketPeer
var _token := ""
var _want_connection := false
var _retry_in := 0.0
var _retry_delay := 1.0
var _ping_in := PING_INTERVAL_S
var _socket_open := false


func connect_to_server(p_url: String = "") -> void:
	url = p_url if p_url != "" else Settings.resolved_server_url()
	_want_connection = true
	_retry_delay = 1.0
	_open()


func close() -> void:
	_want_connection = false
	_token = ""
	if _ws:
		_ws.close()
	_ws = null
	_socket_open = false
	if status != Status.OFFLINE:
		status = Status.OFFLINE
		disconnected.emit()


func send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(Protocol.encode(msg))


func is_online() -> bool:
	return status == Status.ONLINE


func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 256 * 1024   # romstatus kan inneholde profilbilder
	_ws.outbound_buffer_size = 64 * 1024
	_socket_open = false
	status = Status.CONNECTING
	var err := _ws.connect_to_url(url)
	if err != OK:
		last_error = tr("Ugyldig serveradresse: %s") % url
		_on_closed()


func _process(delta: float) -> void:
	if _ws == null:
		if _want_connection:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_open()
		return

	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _socket_open:
				_socket_open = true
				send({ "t": Protocol.HELLO, "name": Settings.player_name, "skin": Settings.skin_id,
					"decal": Settings.decal_id, "win_fx": Settings.win_fx_id, "avatar": Settings.avatar,
					"version": Protocol.VERSION, "token": _token })
			while _ws and _ws.get_available_packet_count() > 0:
				var msg := Protocol.decode(_ws.get_packet().get_string_from_utf8())
				if not msg.is_empty():
					_handle(msg)
			_ping_in -= delta
			if _ping_in <= 0.0:
				_ping_in = PING_INTERVAL_S
				send({ "t": Protocol.PING })
		WebSocketPeer.STATE_CLOSED:
			if not _socket_open:
				last_error = tr("Fikk ikke kontakt med %s") % url
			_on_closed()


func _handle(msg: Dictionary) -> void:
	if msg.t == Protocol.WELCOME:
		var resumed := _token != "" and bool(msg.get("resumed", false))
		_token = str(msg.get("token", ""))
		player_id = int(msg.get("player_id", 0))
		status = Status.ONLINE
		_retry_delay = 1.0
		last_error = ""
		connected.emit(resumed)
	elif msg.t == Protocol.ERROR and msg.get("code") == "version":
		last_error = I18n.server_text(msg)
		_want_connection = false
	message.emit(msg)


func _on_closed() -> void:
	var was_online := status == Status.ONLINE
	_ws = null
	_socket_open = false
	status = Status.CONNECTING if _want_connection else Status.OFFLINE
	if was_online:
		disconnected.emit()
	if _want_connection:
		_retry_in = _retry_delay
		_retry_delay = minf(_retry_delay * 2.0, 8.0)
