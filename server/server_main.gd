class_name ServerMain
extends Node
## Spillserveren: tar imot WebSocket-tilkoblinger og sender meldinger til Lobby.
## Startes med:  godot --headless -- --server [--port 8080]
## Porten kan også settes med miljøvariabelen PORT.

const DEFAULT_PORT := 8080
const HANDSHAKE_TIMEOUT_MS := 10_000
const IDLE_TIMEOUT_MS := 90_000      ## Klienten sender ping hvert 20. sekund

var port := 0                 ## 0 = les fra --port / PORT / standard
var lobby := Lobby.new()
var _tcp := TCPServer.new()
var _peers: Dictionary = {}   ## peer-id -> { ws, open, since, last_seen }
var _next_peer := 1
var _tick_accum := 0.0


func _ready() -> void:
	if port == 0:
		port = _read_port()
	lobby.send = _send
	lobby.close_peer = _close
	var err := _tcp.listen(port, "*")
	if err != OK:
		push_error("Kunne ikke lytte på port %d (feil %d)" % [port, err])
		get_tree().quit(1)
		return
	print("Server kjører på port %d (protokoll v%d)" % [port, Protocol.VERSION])


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 16 * 1024
		ws.outbound_buffer_size = 64 * 1024
		ws.accept_stream(_tcp.take_connection())
		_peers[_next_peer] = { "ws": ws, "open": false, "since": now, "last_seen": now }
		_next_peer += 1

	for id: int in _peers.keys():
		var peer: Dictionary = _peers[id]
		var ws: WebSocketPeer = peer.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				peer.open = true
				while ws.get_available_packet_count() > 0:
					var packet := ws.get_packet()
					peer.last_seen = now
					var msg := Protocol.decode(packet.get_string_from_utf8())
					if msg.is_empty():
						_send(id, { "t": Protocol.ERROR, "code": "bad_message", "text": "Ugyldig melding." })
					else:
						lobby.on_message(id, msg, now)
				if now - peer.last_seen > IDLE_TIMEOUT_MS:
					ws.close()
			WebSocketPeer.STATE_CONNECTING:
				if now - peer.since > HANDSHAKE_TIMEOUT_MS:
					_peers.erase(id)
			WebSocketPeer.STATE_CLOSED:
				if peer.open:
					lobby.on_disconnect(id, now)
				_peers.erase(id)

	_tick_accum += delta
	if _tick_accum >= 0.2:
		_tick_accum = 0.0
		lobby.tick(now)


func _send(peer_id: int, msg: Dictionary) -> void:
	if _peers.has(peer_id):
		var ws: WebSocketPeer = _peers[peer_id].ws
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(Protocol.encode(msg))


func _close(peer_id: int) -> void:
	if _peers.has(peer_id):
		_peers[peer_id].ws.close()


func _read_port() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--port")
	if i >= 0 and i + 1 < args.size():
		return int(args[i + 1])
	var env := OS.get_environment("PORT")
	if env.is_valid_int():
		return int(env)
	return DEFAULT_PORT


func _exit_tree() -> void:
	_tcp.stop()
