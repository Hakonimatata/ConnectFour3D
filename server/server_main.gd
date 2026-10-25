class_name ServerMain
extends Node
## Spillserveren: tar imot WebSocket-tilkoblinger og sender meldinger til Lobby.
## Startes med:  godot --headless -- --server [--port 8080] [--web build/web] [--web-port 8000] [--https]
## Porten kan også settes med miljøvariabelen PORT.
## Med --web serverer den også web-klienten (og sender /ws videre til spillet).
## Med --https i tillegg brukes HTTPS, slik at telefoner på samme wifi kan spille:
##   - uten --cert/--key hentes det gratis sertifikatet til local-ip.sh, og man åpner
##     https://192-168-1-23.local-ip.sh:8000 (PC-ens IP med bindestreker),
##   - med --cert fil.pem --key fil.key brukes egne sertifikater.

const DEFAULT_PORT := 8080
const DEFAULT_WEB_PORT := 8000
const HANDSHAKE_TIMEOUT_MS := 10_000
const IDLE_TIMEOUT_MS := 90_000      ## Klienten sender ping hvert 20. sekund

var port := 0                 ## 0 = les fra --port / PORT / standard
var standalone := false       ## true = selve serverprogrammet (avslutt ved feil). false = inne i tester.
var web_dir := ""             ## Tom = ikke server web-klienten
var web_port := DEFAULT_WEB_PORT
var https := false            ## --https
var cert_path := ""           ## --cert (tom = local-ip.sh)
var key_path := ""            ## --key
var _web: WebFileServer
var store := Store.new()
var data_dir := ""            ## --data <mappe> (standard: data/ i prosjektet, eller user://data i eksport)
var _store_poll := 0.0
var lobby := Lobby.new()
var _tcp := TCPServer.new()
var _peers: Dictionary = {}   ## peer-id -> { ws, open, since, last_seen }
var _next_peer := 1
var _tick_accum := 0.0


func _ready() -> void:
	if port == 0:
		port = _read_port()
	_open_store()
	lobby.send = _send
	lobby.close_peer = _close
	var err := _tcp.listen(port, "*")
	if err != OK:
		push_error("Kunne ikke lytte på port %d (feil %d)" % [port, err])
		if standalone:
			get_tree().quit(1)
		return
	print("Server kjører på port %d (protokoll v%d)" % [port, Protocol.VERSION])
	_read_web_args()
	if web_dir != "":
		_start_web()
	else:
		_print_lan_help()


func _start_web() -> void:
	var options: TLSOptions = null
	if https:
		options = await _load_tls()
		if options == null:
			push_error("Fant ikke HTTPS-sertifikat. Starter web-delen uten HTTPS.")
			https = false
	var web := WebFileServer.new()
	if web.start(web_dir, web_port, port, options) != OK:
		push_error("Kunne ikke starte web-serveren på port %d" % web_port)
		return
	_web = web
	_print_lan_help()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 64 * 1024     # plass til hello med profilbilde
		ws.outbound_buffer_size = 256 * 1024   # romstatus med to profilbilder
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

	if _web:
		_web.poll()
	_store_poll += delta
	if _store_poll >= 1.0:
		_store_poll = 0.0
		if store.poll():
			lobby.on_users_reloaded()

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


func _open_store() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--data")
	if data_dir == "" and i >= 0 and i + 1 < args.size():
		data_dir = args[i + 1]
	if data_dir == "" and OS.get_environment("DATA_DIR") != "":
		data_dir = OS.get_environment("DATA_DIR")
	if data_dir == "":
		data_dir = "user://data" if OS.has_feature("standalone") else ProjectSettings.globalize_path("res://data")
	if data_dir == ":memory:":
		data_dir = ""
	store.open(data_dir)
	lobby.use_store(store)
	print("Brukerdata: %s (%d brukere)" % [ProjectSettings.globalize_path(data_dir) if data_dir != "" else "bare i minnet", store.users.size()])
	var a := args.find("--admin")
	if a >= 0 and a + 1 < args.size():
		if lobby.accounts.set_admin(args[a + 1], true):
			print("%s er admin." % args[a + 1])
		else:
			print("Fant ikke brukeren %s (registrer deg i spillet først)." % args[a + 1])


func _read_web_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--web")
	if i >= 0 and i + 1 < args.size():
		web_dir = args[i + 1]
	var j := args.find("--web-port")
	if j >= 0 and j + 1 < args.size():
		web_port = int(args[j + 1])
	if "--https" in args:
		https = true
	var c := args.find("--cert")
	if c >= 0 and c + 1 < args.size():
		cert_path = args[c + 1]
	var k := args.find("--key")
	if k >= 0 and k + 1 < args.size():
		key_path = args[k + 1]


const LOCAL_IP_CERT := "https://local-ip.sh/server.pem"
const LOCAL_IP_KEY := "https://local-ip.sh/server.key"
const CERT_DIR := "user://certs"
const CERT_MAX_AGE_S := 7 * 24 * 3600


## Laster sertifikat og nøkkel. Uten --cert/--key hentes local-ip.sh sitt sertifikat
## (gyldig for *.local-ip.sh), og det lastes ned på nytt når det er over en uke gammelt.
func _load_tls() -> TLSOptions:
	var cert_file := cert_path
	var key_file := key_path
	if cert_file == "" or key_file == "":
		DirAccess.make_dir_recursive_absolute(CERT_DIR)
		cert_file = CERT_DIR + "/local-ip.sh.pem"
		key_file = CERT_DIR + "/local-ip.sh.key"
		var age := Time.get_unix_time_from_system() - FileAccess.get_modified_time(cert_file)
		if not FileAccess.file_exists(cert_file) or not FileAccess.file_exists(key_file) or age > CERT_MAX_AGE_S:
			print("Henter HTTPS-sertifikat fra local-ip.sh …")
			var ok: bool = await _download(LOCAL_IP_CERT, cert_file)
			if ok:
				ok = await _download(LOCAL_IP_KEY, key_file)
			if not ok:
				print("Klarte ikke å hente sertifikatet (er PC-en på nett?).")
	var cert := X509Certificate.new()
	var key := CryptoKey.new()
	if cert.load(cert_file) != OK or key.load(key_file) != OK:
		return null
	return TLSOptions.server(key, cert)


func _download(url: String, path: String) -> bool:
	var req := HTTPRequest.new()
	req.download_file = path
	req.timeout = 20.0
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200


func _print_lan_help() -> void:
	if _web and https:
		print("HTTPS er på. Åpne spillet i nettleseren (telefon, nettbrett og PC på samme wifi):")
		for ip in WebFileServer.lan_addresses():
			print("  https://%s.local-ip.sh:%d" % [ip.replace(".", "-"), web_port])
		print("(Fungerer ikke adressen, kan det være at ruteren blokkerer local-ip.sh, se README.)")
		return
	if _web:
		print("Web-klient på denne PC-en:  http://localhost:%d" % web_port)
		print("  Telefon via USB:  chrome://inspect -> Port forwarding: %d -> localhost:%d, åpne http://localhost:%d" \
			% [web_port, web_port, web_port])
		print("  Telefoner på wifi: start med --https i tillegg (se README)")
		print("  Venner over internett:  cloudflared tunnel --url http://localhost:%d" % web_port)
	for ip in WebFileServer.lan_addresses():
		print("Desktop-klienter på lokalnettet kan koble til ws://%s:%d" % [ip, port])


func _exit_tree() -> void:
	_tcp.stop()
	if _web:
		_web.stop()
