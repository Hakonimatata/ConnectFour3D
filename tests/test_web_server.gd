extends TestCase
## Tester den lille HTTP-serveren som serverer web-klienten pÃ¥ lokalnettet.

const PORT := 18770
const DIR := "user://test_web"

var server: WebFileServer


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + "/index.html", FileAccess.WRITE)
	f.store_string("<h1>Hei</h1>")
	f.close()
	var big := PackedByteArray()
	big.resize(700_000)
	for i in big.size():
		big[i] = i % 251
	f = FileAccess.open(DIR + "/game.wasm", FileAccess.WRITE)
	f.store_buffer(big)
	f.close()
	server = WebFileServer.new()
	check_eq(server.start(DIR, PORT), OK, "start:")


func after_each() -> void:
	server.stop()


## Sender en GET og gir { head, body } nÃ¥r serveren har lukket forbindelsen.
func _http_get(path: String, extra_headers := "") -> Dictionary:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", PORT)
	var sent := false
	var data := PackedByteArray()
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		server.poll()
		tcp.poll()
		var status := tcp.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED and not sent:
			tcp.put_data(("GET %s HTTP/1.1\r\nHost: x\r\n%s\r\n" % [path, extra_headers]).to_utf8_buffer())
			sent = true
		var n := tcp.get_available_bytes() if status == StreamPeerTCP.STATUS_CONNECTED else 0
		if n > 0:
			data.append_array(tcp.get_partial_data(n)[1])
		elif sent and status != StreamPeerTCP.STATUS_CONNECTED:
			break
		await tree.process_frame
	var text := data.get_string_from_ascii()
	var split := text.find("\r\n\r\n")
	if split < 0:
		return { "head": text, "body": PackedByteArray() }
	return { "head": text.substr(0, split), "body": data.slice(split + 4) }


func test_serves_index_for_root() -> void:
	var r: Dictionary = await _http_get("/")
	check(r.head.begins_with("HTTP/1.1 200"), "status: " + r.head.get_slice("\r\n", 0))
	check(r.head.contains("text/html"), "content-type")
	check_eq(r.body.get_string_from_utf8(), "<h1>Hei</h1>")


func test_serves_big_file_completely() -> void:
	var r: Dictionary = await _http_get("/game.wasm?v=1")
	check(r.head.contains("application/wasm"), "wasm-type")
	check_eq(r.body.size(), 700_000, "stÃ¸rrelse:")
	check_eq(r.body[699_999], 699_999 % 251)


func test_missing_and_escaping_paths() -> void:
	var r: Dictionary = await _http_get("/finnes-ikke.js")
	check(r.head.begins_with("HTTP/1.1 404"), "404: " + r.head.get_slice("\r\n", 0))
	r = await _http_get("/../project.godot")
	check(not r.head.begins_with("HTTP/1.1 200"), "skal ikke slippe ut av mappen")


func test_lan_addresses_are_private_ipv4() -> void:
	for ip in WebFileServer.lan_addresses():
		check(ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("172."), ip)


func test_websocket_on_ws_path_reaches_game_server() -> void:
	server.stop()   # bruk ServerMain sin egen web-del i stedet
	var game := ServerMain.new()
	game.port = 18771
	game.web_dir = DIR
	game.web_port = 18772
	root.add_child(game)
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:18772/ws")
	var welcome := {}
	var sent := false
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end and welcome.is_empty():
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not sent:
				ws.send_text(Protocol.encode({ "t": "hello", "name": "Proxy", "skin": "ocean", "version": Protocol.VERSION }))
				sent = true
			while ws.get_available_packet_count() > 0:
				var msg := Protocol.decode(ws.get_packet().get_string_from_utf8())
				if msg.get("t") == Protocol.WELCOME:
					welcome = msg
		await tree.process_frame
	check(not welcome.is_empty(), "fikk ikke welcome gjennom /ws på web-porten")
	# Vanlige filer virker fortsatt på samme port
	ws.close()
	game.queue_free()
	await tree.process_frame


func test_https_with_certificate() -> void:
	server.stop()
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, "CN=localhost,O=Test,C=NO")
	var secure_server := WebFileServer.new()
	check_eq(secure_server.start(DIR, 18773, 0, TLSOptions.server(key, cert)), OK, "start:")
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", 18773)
	var tls: StreamPeerTLS = null
	var data := PackedByteArray()
	var sent := false
	var end := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < end:
		secure_server.poll()
		if tls == null:
			tcp.poll()
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				tls = StreamPeerTLS.new()
				tls.connect_to_stream(tcp, "localhost", TLSOptions.client_unsafe())
		else:
			tls.poll()
			var st := tls.get_status()
			if st == StreamPeerTLS.STATUS_CONNECTED:
				if not sent:
					tls.put_data("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".to_utf8_buffer())
					sent = true
				var n := tls.get_available_bytes()
				if n > 0:
					data.append_array(tls.get_partial_data(n)[1])
			elif st != StreamPeerTLS.STATUS_HANDSHAKING:
				break
			if data.get_string_from_utf8().contains("<h1>Hei</h1>"):
				break
		await tree.process_frame
	var text := data.get_string_from_utf8()
	check(text.begins_with("HTTP/1.1 200"), "HTTPS-svar: " + text.get_slice("\r\n", 0))
	check(text.contains("<h1>Hei</h1>"), "innhold over HTTPS")
	if tls:
		tls.disconnect_from_stream()
	secure_server.stop()


func test_gzip_when_browser_accepts_it() -> void:
	var r: Dictionary = await _http_get("/game.wasm", "Accept-Encoding: gzip, deflate, br\r\n")
	check(r.head.contains("Content-Encoding: gzip"), "skal være komprimert: " + r.head)
	var body: PackedByteArray = r.body
	check(body.size() < 700_000, "komprimert skal være mindre, var %d" % body.size())
	check(body.size() > 2 and body[0] == 0x1f and body[1] == 0x8b, "skal være gzip-format")
	var raw := body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	check_eq(raw.size(), 700_000, "utpakket størrelse:")
	check_eq(raw[699_999], 699_999 % 251)
	# Uten Accept-Encoding: ukomprimert
	var plain: Dictionary = await _http_get("/game.wasm")
	check(not plain.head.contains("Content-Encoding"), "uten gzip-støtte skal svaret være ukomprimert")
