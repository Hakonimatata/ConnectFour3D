class_name WebFileServer
extends RefCounted
## En liten HTTP-server som serverer web-klienten (build/web), for testing og
## spill uten annet oppsett. På en ekte server brukes Caddy i stedet (se deploy/).
## Støtter bare GET av filer i én mappe, og sender store filer litt etter litt.
## WebSocket-forespørsler på /ws sendes videre til spillserveren, så web-siden og
## spillet deler én port. Det gjør det enkelt å bruke localhost-videresending
## (USB) eller en HTTPS-tunnel, som nettleseren krever for Godot-spill.
## Med et sertifikat (TLSOptions) kjører den HTTPS direkte, f.eks. med
## local-ip.sh-sertifikatet slik at telefoner på wifi kan koble til (se ServerMain).

const MAX_REQUEST := 8192
const CHUNK := 256 * 1024
const MAX_PER_POLL := 16 * 1024 * 1024
const TIMEOUT_MS := 30_000

## Filtyper som komprimeres (gzip) når nettleseren støtter det. index.wasm krymper ~4×.
const GZIP_TYPES := ["wasm", "js", "html", "pck", "json", "css", "svg", "txt"]

const TYPES := {
	"html": "text/html; charset=utf-8", "js": "application/javascript", "wasm": "application/wasm",
	"pck": "application/octet-stream", "png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon",
	"json": "application/json", "css": "text/css", "txt": "text/plain; charset=utf-8",
}

var root := ""
var port := 0
var ws_port := 0              ## Spillserverens port (0 = ingen videresending av /ws)
var tls: TLSOptions = null    ## Satt = HTTPS
## Sider som lages underveis (f.eks. kalenderfiler): dynamic(sti, vert) -> { type, body } eller {}.
var dynamic: Callable
var _gzip_cache: Dictionary = {}   ## full sti -> { mtime, data } (komprimert innhold i minnet)
var _tcp := TCPServer.new()
var _clients: Array[Dictionary] = []


## Gir OK eller en feilkode. dir kan være res://, user:// eller en vanlig sti.
func start(dir: String, p_port: int, p_ws_port := 0, p_tls: TLSOptions = null) -> Error:
	ws_port = p_ws_port
	tls = p_tls
	root = dir.simplify_path()
	if not root.begins_with("res://") and not root.begins_with("user://") and root.is_relative_path():
		root = ProjectSettings.globalize_path("res://").path_join(dir).simplify_path()
	if not FileAccess.file_exists(root.path_join("index.html")):
		push_warning("Fant ikke %s – eksporter web-klienten først." % root.path_join("index.html"))
	port = p_port
	# Komprimer de store filene med en gang, så første besøkende slipper å vente.
	for name in ["index.wasm", "index.js", "index.pck"]:
		if FileAccess.file_exists(root.path_join(name)):
			_gzipped(root.path_join(name))
	return _tcp.listen(port, "*")


func stop() -> void:
	_tcp.stop()
	_clients.clear()


func poll() -> void:
	var now := Time.get_ticks_msec()
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		conn.set_no_delay(true)
		var stream: StreamPeer = conn
		if tls != null:
			var secure := StreamPeerTLS.new()
			if secure.accept_stream(conn, tls) != OK:
				conn.disconnect_from_host()
				continue
			stream = secure
		_clients.append({ "tcp": stream, "request": PackedByteArray(), "file": null, "pending": PackedByteArray(),
			"since": now, "upstream": null, "to_up": PackedByteArray(), "to_client": PackedByteArray(),
			"mem": PackedByteArray(), "mem_pos": 0 })

	var keep: Array[Dictionary] = []
	for c in _clients:
		# Videresendte WebSocket-forbindelser kan vare hele partiet, så de har ingen tidsgrense.
		if _serve(c) and (c.upstream != null or now - c.since < TIMEOUT_MS):
			keep.append(c)
		else:
			_close(c.tcp)
			if c.upstream != null:
				_close(c.upstream)
	_clients = keep


## Gir false når forbindelsen er ferdig og kan lukkes.
func _serve(c: Dictionary) -> bool:
	var tcp: StreamPeer = c.tcp
	var state := _state(tcp)
	if state < 0:
		return false
	if state == 0:
		return true   # TLS-håndtrykk pågår
	if c.upstream != null:
		return _pipe(c)

	if c.file == null and c.pending.is_empty() and c.mem.is_empty():
		# Les forespørselen til vi har hele headeren.
		var available := tcp.get_available_bytes()
		if available > 0:
			var r := tcp.get_partial_data(mini(available, MAX_REQUEST))
			if r[0] == OK:
				c.request.append_array(r[1])
		var text: String = c.request.get_string_from_ascii()
		if not text.contains("\r\n\r\n"):
			return c.request.size() < MAX_REQUEST
		_respond(c, text)
		if c.upstream != null:
			return true
		if c.file == null and c.pending.is_empty() and c.mem.is_empty():
			return false

	# Send så mye som nettverket tar imot nå.
	var sent_total := 0
	while sent_total < MAX_PER_POLL:
		if c.pending.is_empty():
			if not c.mem.is_empty():
				# Komprimert innhold fra minnet
				var mem: PackedByteArray = c.mem
				var pos: int = c.mem_pos
				if pos >= mem.size():
					return false
				c.pending = mem.slice(pos, pos + CHUNK)
				c.mem_pos = pos + CHUNK
			else:
				var f: FileAccess = c.file
				if f == null or f.eof_reached() or f.get_position() >= f.get_length():
					return false
				c.pending = f.get_buffer(CHUNK)
				if c.pending.is_empty():
					return false
		var res := tcp.put_partial_data(c.pending)
		if res[0] != OK:
			return false
		var sent: int = res[1]
		sent_total += sent
		c.pending = c.pending.slice(sent)
		if not c.pending.is_empty():
			break   # nettverket er fullt, prøv igjen neste gang
	return true


func _respond(c: Dictionary, request: String) -> void:
	var request_line := request.get_slice("\r\n", 0)
	var parts := request_line.split(" ")
	# WebSocket til /ws: send hele forespørselen videre til spillserveren og koble sammen.
	if ws_port > 0 and parts.size() >= 2 and parts[1].begins_with("/ws") \
			and request.to_lower().contains("upgrade: websocket"):
		var up := StreamPeerTCP.new()
		if up.connect_to_host("127.0.0.1", ws_port) != OK:
			c.pending = _header(502, "text/plain", 0)
			return
		up.set_no_delay(true)
		c.upstream = up
		c.to_up = c.request.duplicate()
		return
	if parts.size() < 2 or parts[0] != "GET":
		c.pending = _header(405, "text/plain", 0)
		return
	var path := parts[1].get_slice("?", 0).uri_decode()
	if path == "/" or path.ends_with("/"):
		path += "index.html"
	var clean := path.simplify_path().trim_prefix("/")
	if clean.contains("..") or clean.begins_with("/"):
		c.pending = _header(403, "text/plain", 0)
		return
	if dynamic.is_valid():
		var page: Dictionary = dynamic.call(clean, _host(request))
		if not page.is_empty():
			var bytes: PackedByteArray = str(page.body).to_utf8_buffer()
			c.pending = _header(200, str(page.type), bytes.size()) + bytes
			return
	var full := root.path_join(clean)
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		var body := ("Fant ikke " + clean).to_utf8_buffer()
		c.pending = _header(404, "text/plain; charset=utf-8", body.size()) + body
		return
	var ext := clean.get_extension().to_lower()
	var type: String = TYPES.get(ext, "application/octet-stream")
	if ext in GZIP_TYPES and _accepts_gzip(request):
		var data := _gzipped(full)
		if not data.is_empty():
			c.pending = _header(200, type, data.size(), "Content-Encoding: gzip" + "\r\n" + "Vary: Accept-Encoding" + "\r\n")
			c.mem = data
			return
	c.pending = _header(200, type, f.get_length())
	c.file = f


static func _host(request: String) -> String:
	for line in request.split("
"):
		if line.to_lower().begins_with("host:"):
			return line.substr(5).strip_edges()
	return ""


static func _accepts_gzip(request: String) -> bool:
	for line in request.split("\r\n"):
		if line.to_lower().begins_with("accept-encoding:"):
			return line.to_lower().contains("gzip")
	return false


## Komprimert innhold for en fil (gzip), hentet fra minnet hvis filen ikke er endret.
func _gzipped(full: String) -> PackedByteArray:
	var mtime := FileAccess.get_modified_time(full)
	var cached: Dictionary = _gzip_cache.get(full, {})
	if cached.get("mtime", -1) == mtime:
		return cached.data
	var raw := FileAccess.get_file_as_bytes(full)
	if raw.is_empty():
		return PackedByteArray()
	var data := raw.compress(FileAccess.COMPRESSION_GZIP)
	_gzip_cache[full] = { "mtime": mtime, "data": data }
	return data


func _header(code: int, type: String, length: int, extra := "") -> PackedByteArray:
	var reason := { 200: "OK", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 502: "Bad Gateway" }
	var h := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n%sCache-Control: no-cache\r\nConnection: close\r\n\r\n" \
		% [code, reason.get(code, ""), type, length, extra]
	return h.to_utf8_buffer()


## Kobler en WebSocket-klient og spillserveren sammen: kopierer bytes begge veier.
func _pipe(c: Dictionary) -> bool:
	var tcp: StreamPeer = c.tcp
	var up: StreamPeerTCP = c.upstream
	var state := _state(up)
	if state == 0:
		return true
	if state < 0:
		return false
	var n := tcp.get_available_bytes()
	if n > 0:
		c.to_up.append_array(tcp.get_partial_data(n)[1])
	if not c.to_up.is_empty():
		var r := up.put_partial_data(c.to_up)
		if r[0] != OK:
			return false
		c.to_up = c.to_up.slice(r[1])
	var m := up.get_available_bytes()
	if m > 0:
		c.to_client.append_array(up.get_partial_data(m)[1])
	if not c.to_client.is_empty():
		var r2 := tcp.put_partial_data(c.to_client)
		if r2[0] != OK:
			return false
		c.to_client = c.to_client.slice(r2[1])
	return true


## 1 = klar, 0 = venter (kobler til / TLS-håndtrykk), -1 = lukket eller feil. Poller strømmen.
static func _state(s: StreamPeer) -> int:
	if s is StreamPeerTLS:
		var secure := s as StreamPeerTLS
		secure.poll()
		match secure.get_status():
			StreamPeerTLS.STATUS_HANDSHAKING: return 0
			StreamPeerTLS.STATUS_CONNECTED: return 1
		return -1
	var tcp := s as StreamPeerTCP
	tcp.poll()
	match tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTING: return 0
		StreamPeerTCP.STATUS_CONNECTED: return 1
	return -1


static func _close(s: StreamPeer) -> void:
	if s is StreamPeerTLS:
		(s as StreamPeerTLS).disconnect_from_stream()
	elif s is StreamPeerTCP:
		(s as StreamPeerTCP).disconnect_from_host()


## Lokale IPv4-adresser (192.168.x.x, 10.x.x.x, 172.16–31.x.x) – nyttig å skrive ut.
static func lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3:
			continue
		var p := ip.split(".")
		var a := int(p[0])
		var b := int(p[1])
		if a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31):
			out.append(ip)
	return out
