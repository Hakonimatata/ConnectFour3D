extends SceneTree
## Stresstest av en turnering: en admin og N boter kobler seg til en server over WebSocket,
## registrerer seg, melder seg på en utslagsturnering og spiller den ferdig. Til slutt skrives en
## rapport med svartider (trekk sendt -> trekket bekreftet av serveren) og antall partier og meldinger.
##
## Bruk en EGEN server (andre porter og egen datamappe), så den som er på nett ikke påvirkes:
##   godot --headless --path . -- --server --port 9080 --web build/web --web-port 9000 --data build/stresstest
##   godot --headless --path . --script res://tools/stress_tournament.gd -- --url ws://127.0.0.1:9080 --data build/stresstest
## Valg: --players 32, --signup 90 (sekunder til start), --delay 0.35 (sekunder per trekk), --report fil.json,
## --level easy (alle botene lette: de tenker under 1 ms, så svartiden måler serveren og ikke botene;
## standard er en blanding, og en vanskelig bot kan tenke i 0,2 s og holde igjen de andre i samme prosess)
## Mens den kjører, kan du se på i nettleseren: http://localhost:9000/?turnering=<id>

const NAMES := ["Ada", "Bob", "Cyan", "Duck", "Eira", "Frode", "Gro", "Havard", "Ina", "Jonas", "Kari", "Lars",
	"Mona", "Nils", "Oda", "Petter", "Ragnhild", "Sindre", "Tiril", "Ulrik", "Vilde", "Wenche", "Yngve", "Zara",
	"Aksel", "Brage", "Cecilie", "Dag", "Elin", "Fride", "Gaute", "Hedda", "Iver", "Jorun", "Kasper", "Liv"]
const PASSWORD := "stresstest123"
const ADMIN_NAME := "StressAdmin"


class Client:
	var name := ""
	var ws := WebSocketPeer.new()
	var open := false
	var user_id := 0
	var state: GameState
	var seat := 0
	var bot: Bot
	var move_at := -1.0      ## sekunder (klokke) for neste trekk, -1 = ikke vår tur
	var sent_ms := 0         ## når forrige trekk ble sendt (for svartid)
	var join_at := -1.0      ## når boten skal melde seg på
	var joined := false

	func send(msg: Dictionary) -> void:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(Protocol.encode(msg))


var url := "ws://127.0.0.1:9080"
var data_dir := "build/stresstest"
var player_count := 32
var signup_s := 90
var move_delay := 0.35
var report_path := ""
var all_easy := false

var admin: Client
var bots: Array[Client] = []
var tournament_id := 0
var start_unix := 0
var clock := 0.0
var latencies: Array[int] = []
var games_started := 0
var games_over := 0
var moves := 0
var rejected := 0
var msgs_in := 0
var errors: Array[String] = []
var _poll_in := 0.0
var _admin_ready := false
var _created := false
var _done_at := -1.0
var _final: Dictionary = {}
var _round_seen := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--url": url = args[i + 1]
			"--data": data_dir = args[i + 1]
			"--players": player_count = int(args[i + 1])
			"--signup": signup_s = int(args[i + 1])
			"--delay": move_delay = float(args[i + 1])
			"--report": report_path = args[i + 1]
			"--level": all_easy = args[i + 1] == "easy"
	admin = _client(ADMIN_NAME)
	for i in player_count:
		var c := _client(NAMES[i % NAMES.size()] + ("" if i < NAMES.size() else str(i)))
		var level: BotProfile.Level = BotProfile.Level.EASY if all_easy \
			else [BotProfile.Level.EASY, BotProfile.Level.MEDIUM, BotProfile.Level.HARD][i % 3]
		# Den gamle vanskelige boten (uten søk): søket tenker i 0,7 s per trekk og ville holdt igjen de
		# andre botene i samme prosess, og det er serveren som skal måles
		c.bot = Bot.new(BotProfile.legacy_hard() if level == BotProfile.Level.HARD else BotProfile.create(level))
		bots.append(c)
	_log("Kobler %d boter og en admin til %s" % [player_count, url])


func _client(name: String) -> Client:
	var c := Client.new()
	c.name = name
	c.ws.inbound_buffer_size = 1 << 20
	c.ws.connect_to_url(url)
	return c


func _process(delta: float) -> bool:
	clock += delta
	for c: Client in [admin] + bots:
		_poll(c)
	# Botene melder seg på litt etter litt (så det ser naturlig ut)
	for c in bots:
		if not c.joined and c.join_at >= 0.0 and clock >= c.join_at and tournament_id != 0:
			c.joined = true   # registrer (eller logg inn), så meldes boten på når økten er klar
			c.send({ "t": Protocol.REGISTER, "username": c.name, "password": PASSWORD })
		if c.move_at >= 0.0 and clock >= c.move_at:
			_play(c)
	# Admin følger med på turneringen
	_poll_in -= delta
	if tournament_id != 0 and _poll_in <= 0.0:
		_poll_in = 2.0
		admin.send({ "t": Protocol.GET_TOURNAMENT, "id": tournament_id })
	if _done_at >= 0.0 and clock >= _done_at:
		_report()
		return true
	if clock > 1800.0:
		errors.append("Tidsavbrudd etter 30 minutter")
		_report()
		return true
	return false


func _poll(c: Client) -> void:
	c.ws.poll()
	var st := c.ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not c.open:
		c.open = true
		c.send({ "t": Protocol.HELLO, "name": c.name, "skin": Skins.ALL[randi() % Skins.ALL.size()].id,
			"version": Protocol.VERSION })
	while c.ws.get_available_packet_count() > 0:
		var msg := Protocol.decode(c.ws.get_packet().get_string_from_utf8())
		if not msg.is_empty():
			msgs_in += 1
			_on_message(c, msg)


func _on_message(c: Client, msg: Dictionary) -> void:
	match msg.t:
		Protocol.WELCOME:
			# Botene registrerer seg først når turneringen er laget (join_at). Ellers skriver serveren
			# users.json for hver ny bruker, og admin-flagget vi setter i filen kan bli overskrevet.
			if c == admin:
				c.send({ "t": Protocol.REGISTER, "username": c.name, "password": PASSWORD })
		Protocol.AUTH_ERROR:
			# Finnes fra en tidligere kjøring: logg inn i stedet
			c.send({ "t": Protocol.LOGIN, "username": c.name, "password": PASSWORD })
		Protocol.SESSION:
			c.user_id = int(msg.user.id)
			if c == admin:
				_make_admin()
			elif tournament_id != 0:
				c.send({ "t": Protocol.TOURNAMENT_JOIN, "id": tournament_id })
		Protocol.TOURNAMENT_STATE:
			if c == admin:
				_on_tournament(msg.tournament)
		Protocol.TOURNAMENT_NOTICE:
			if str(msg.get("room", "")) != "":
				c.send({ "t": Protocol.JOIN_ROOM, "code": msg.room })
		Protocol.GAME_START, Protocol.GAME_SYNC:
			c.state = GameState.new(GameOptions.from_dict(msg.options), int(msg.get("first", 1)))
			c.seat = int(msg.you)
			for m in msg.get("moves", []):
				c.state.play(Vector2i(int(m[0]), int(m[1])), false)
			if c.seat == 1 and msg.t == Protocol.GAME_START:
				games_started += 1
			_schedule(c)
		Protocol.MOVE_MADE:
			if c.state == null:
				return
			c.state.play(Vector2i(int(msg.x), int(msg.y)), false)
			if int(msg.player) == c.seat and c.sent_ms > 0:
				latencies.append(Time.get_ticks_msec() - c.sent_ms)
				c.sent_ms = 0
				moves += 1
			_schedule(c)
		Protocol.MOVE_REJECTED:
			rejected += 1
			c.move_at = clock + 0.05
		Protocol.GAME_OVER:
			c.move_at = -1.0
			if c.seat == 1:
				games_over += 1
		Protocol.ERROR:
			if errors.size() < 20:
				errors.append("%s: %s" % [c.name, str(msg.get("text", ""))])
			if c == admin and not _created and str(msg.get("code", "")) == "admin_only":
				_admin_ready = false   # users.json er ikke lest inn ennå: prøv igjen
				_retry_create.call_deferred()


func _schedule(c: Client) -> void:
	if c.state != null and not c.state.is_over() and c.state.current_player == c.seat:
		c.move_at = clock + move_delay * randf_range(0.6, 1.4)
	else:
		c.move_at = -1.0


func _play(c: Client) -> void:
	c.move_at = -1.0
	if c.state == null or c.state.is_over() or c.state.current_player != c.seat:
		return
	var col := c.bot.choose_move(c.state)
	c.sent_ms = Time.get_ticks_msec()
	c.send({ "t": Protocol.MOVE, "x": col.x, "y": col.y, "ply": c.state.history.size() })


## Gjør admin-boten til admin: sett "admin": true i users.json (serveren leser den inn på nytt).
func _make_admin() -> void:
	var path := ProjectSettings.globalize_path("res://" + data_dir).path_join("users.json") \
		if not data_dir.is_absolute_path() else data_dir.path_join("users.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		errors.append("Fant ikke %s" % path)
		return
	for u in data.users:
		if u.username == ADMIN_NAME:
			u.admin = true
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_log("Admin satt i users.json. Venter på at serveren leser den inn …")
	_retry_create.call_deferred()


func _retry_create() -> void:
	await create_timer(2.5).timeout
	if _created:
		return
	start_unix = int(Time.get_unix_time_from_system()) + signup_s
	admin.send({ "t": Protocol.TOURNAMENT_CREATE, "data": { "name": "Stresstest %d" % player_count, "format": "knockout",
		"max_players": player_count, "start_time": start_unix, "signup_deadline": start_unix, "round_gap_s": 8,
		"show_up_s": 30, "description": "Automatisk test med %d boter." % player_count } })


func _on_tournament(t: Dictionary) -> void:
	if tournament_id == 0:
		_created = true
		tournament_id = int(t.id)
		admin.send({ "t": Protocol.TOURNAMENT_ACTION, "id": tournament_id, "action": "publish" })
		_log("Turnering %d laget. Start om %d s. Se på: http://localhost:9000/?turnering=%d" % [tournament_id, signup_s, tournament_id])
		var spread := maxf(5.0, signup_s * 0.6)
		for i in bots.size():
			bots[i].join_at = clock + 2.0 + spread * float(i) / bots.size()
		return
	if t.status == "running" and int(t.current_round) != _round_seen:
		_round_seen = int(t.current_round)
		_log("Runde %d av turneringen har startet (%d partier ferdig så langt)" % [_round_seen + 1, games_over])
	if t.status in ["finished", "cancelled"] and _done_at < 0.0:
		_final = t
		_log("Turneringen er %s. Vinner: %s" % [t.status, str(t.get("winner", "—"))])
		_done_at = clock + 3.0


func _report() -> void:
	var sorted := latencies.duplicate()
	sorted.sort()
	var pct := func(p: float) -> int: return sorted[mini(sorted.size() - 1, int(sorted.size() * p))] if not sorted.is_empty() else 0
	var report := {
		"players": player_count, "tournament": tournament_id, "status": _final.get("status", "ukjent"),
		"winner": _final.get("winner", ""), "rounds": (_final.get("rounds", []) as Array).size(),
		"games_started": games_started, "games_over": games_over, "moves": moves, "moves_rejected": rejected,
		"messages_received": msgs_in, "duration_s": snappedf(clock, 0.1),
		"latency_ms": { "p50": pct.call(0.5), "p95": pct.call(0.95), "p99": pct.call(0.99),
			"max": sorted[-1] if not sorted.is_empty() else 0 },
		"errors": errors,
	}
	print(JSON.stringify(report, "  "))
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
	for c: Client in [admin] + bots:
		c.ws.close()


func _log(text: String) -> void:
	print("[%5.1f s] %s" % [clock, text])
