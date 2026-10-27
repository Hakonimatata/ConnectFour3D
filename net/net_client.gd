extends Node
## Autoload «Net»: WebSocket-tilkoblingen til serveren.
## Kobler automatisk til igjen ved brudd, og sender token slik at serveren
## kjenner oss igjen og kan sende partiet på nytt.

signal connected(resumed: bool)
signal disconnected
signal message(msg: Dictionary)
signal account_changed          ## innlogget/utlogget (se `user`)
signal avatar_changed           ## profilbildet kom fra kontoen (innlogget på en annen enhet)

enum Status { OFFLINE, CONNECTING, ONLINE }

const PING_INTERVAL_S := 20.0
const CONNECT_TIMEOUT_MS := 5000   ## Gi opp et tilkoblingsforsøk etter så lang tid (Windows kan henge lenge)

var status := Status.OFFLINE
var url := ""
var player_id := 0
var last_error := ""
var user: Dictionary = {}       ## innlogget bruker { username, admin, elo, stats }, eller tom
## Den globale chatten og «online» huskes her, så chatten i menyen er fylt med en gang den vises
## (serveren sender historikken bare rett etter tilkobling).
var global_messages: Array = []
var presence := { "online": 0, "playing": 0, "users": [] }
var last_game: Dictionary = {}  ## siste ferdige parti på serveren
var last_games: Array = []      ## de tre siste partiene, nyeste først (hovedmenyen spiller av ett om gangen)
const GLOBAL_KEEP := 160   ## for alle kanalene til sammen
var friends: Dictionary = { "friends": [], "requests": [], "sent": [] }   ## siste venneliste fra serveren

var _ws: WebSocketPeer
var _token := ""
var _want_connection := false
var _keep_trying := true        ## false = bare en titt (menyen): gi opp hvis serveren ikke svarer
var _retry_in := 0.0
var _retry_delay := 1.0
var _ping_in := PING_INTERVAL_S
var _socket_open := false
var _connect_started_ms := 0


func connect_to_server(p_url: String = "", keep_trying := true) -> void:
	url = p_url if p_url != "" else Settings.resolved_server_url()
	_want_connection = true
	_keep_trying = keep_trying
	_retry_delay = 1.0
	_open()


## Sørger for at vi er (eller blir) tilkoblet riktig server, og prøver igjen ved brudd.
## Brukes av lobbyen og turneringssidene, også når menyen allerede har en «titt»-tilkobling.
func ensure_connected() -> void:
	var wanted := Settings.resolved_server_url()
	if status != Status.OFFLINE and url == wanted:
		_keep_trying = true
		_want_connection = true
		return
	if status != Status.OFFLINE:
		close()
	connect_to_server(wanted)


func close() -> void:
	_want_connection = false
	_token = ""
	if _ws:
		_ws.close()
	_ws = null
	_socket_open = false
	_set_user(null)   # økten huskes i Settings og brukes neste gang vi kobler til
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
	_connect_started_ms = Time.get_ticks_msec()
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
				send({ "t": Protocol.HELLO, "name": Settings.display_name(), "skin": Settings.skin_id,
					"decal": Settings.decal_id, "win_fx": Settings.win_fx_id, "decal_color": Settings.decal_color_id,
					"away": Settings.kit_away,
					"avatar": Settings.avatar,
					"version": Protocol.VERSION, "token": _token, "session": Settings.session_token })
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
		WebSocketPeer.STATE_CONNECTING:
			if Time.get_ticks_msec() - _connect_started_ms > CONNECT_TIMEOUT_MS:
				last_error = tr("Fikk ikke kontakt med %s") % url
				_ws.close()
				_on_closed()


func _handle(msg: Dictionary) -> void:
	match msg.t:
		Protocol.GLOBAL_HISTORY:
			global_messages = (msg.get("messages", []) as Array).filter(func(m: Variant) -> bool: return m is Dictionary)
		Protocol.GLOBAL_MSG:
			global_messages.append(msg)
			if global_messages.size() > GLOBAL_KEEP:
				global_messages = global_messages.slice(global_messages.size() - GLOBAL_KEEP)
		Protocol.PRESENCE:
			presence = { "online": int(msg.get("online", 0)), "playing": int(msg.get("playing", 0)),
				"users": msg.get("users", []) if msg.get("users") is Array else [] }
		Protocol.LAST_GAME:
			if msg.get("game") is Dictionary:
				last_game = msg.game
			var games: Array = msg.get("games", []) if msg.get("games") is Array else []
			last_games = games.filter(func(g: Variant) -> bool: return g is Dictionary)
			if last_games.is_empty() and not last_game.is_empty():
				last_games = [last_game]
		Protocol.FRIENDS:
			friends = { "friends": msg.get("friends", []), "requests": msg.get("requests", []), "sent": msg.get("sent", []) }
	if msg.t == Protocol.WELCOME:
		var resumed := _token != "" and bool(msg.get("resumed", false))
		_token = str(msg.get("token", ""))
		player_id = int(msg.get("player_id", 0))
		status = Status.ONLINE
		_keep_trying = true   # kom vi først inn, prøver vi igjen ved brudd (også etter en «titt»)
		_retry_delay = 1.0
		last_error = ""
		_adopt_avatar(msg)
		_set_user(msg.get("user"))
		connected.emit(resumed)
	elif msg.t == Protocol.SESSION:
		Settings.session_token = str(msg.get("token", ""))
		Settings.save()
		_adopt_avatar(msg)
		_set_user(msg.get("user"))
	elif msg.t == Protocol.LOGGED_OUT:
		_set_user(null)
	elif msg.t == Protocol.STATS and msg.get("user") is Dictionary and str(msg.user.get("username", "")) == str(user.get("username", "-")):
		_set_user(msg.user)
	elif msg.t == Protocol.ERROR and msg.get("code") == "version":
		last_error = I18n.server_text(msg)
		_want_connection = false
	elif msg.t == Protocol.ERROR and msg.get("code") == "banned":
		# Utestengt av admin: serveren kobler fra. Ikke koble til igjen, og glem innloggingen.
		last_error = I18n.server_text(msg)
		_want_connection = false
		Settings.session_token = ""
		Settings.save()
		_set_user(null)
	message.emit(msg)


## Sender nytt utseende til serveren (f.eks. byttet skin i venterommet).
func send_look() -> void:
	send({ "t": Protocol.SET_LOOK, "skin": Settings.skin_id, "decal": Settings.decal_id,
		"win_fx": Settings.win_fx_id, "decal_color": Settings.decal_color_id, "away": Settings.kit_away })


## Nytt eller fjernet profilbilde. Innlogget lagres det på kontoen, så det følger med til andre enheter.
func send_avatar() -> void:
	send({ "t": Protocol.SET_LOOK, "avatar": Settings.avatar })


## Innlogget er profilbildet kontoens: det samme på alle enheter (serveren sender det ved innlogging).
func _adopt_avatar(msg: Dictionary) -> void:
	var avatar = msg.get("avatar")
	if avatar is String and avatar != Settings.avatar:
		Settings.avatar = avatar
		Settings.save()
		avatar_changed.emit()


func is_logged_in() -> bool:
	return not user.is_empty()


func logout() -> void:
	send({ "t": Protocol.LOGOUT, "session": Settings.session_token })
	Settings.session_token = ""
	Settings.last_username = ""
	Settings.save()
	_set_user(null)


## Passord sendes bare over kryptert forbindelse (wss://) eller til denne maskinen.
func can_send_password() -> bool:
	return url.begins_with("wss://") or url.contains("://localhost") or url.contains("://127.0.0.1")


func _set_user(u: Variant) -> void:
	var new_user: Dictionary = u if u is Dictionary else {}
	if new_user == user:
		return
	user = new_user
	if user.is_empty():
		friends = { "friends": [], "requests": [], "sent": [] }
	if user.has("elo") and (int(user.elo) != Settings.last_elo or str(user.username) != Settings.last_username):
		Settings.last_elo = int(user.elo)
		Settings.last_username = str(user.username)
		Settings.save()
	account_changed.emit()


func _on_closed() -> void:
	var was_online := status == Status.ONLINE
	_ws = null
	_socket_open = false
	if not _keep_trying:
		_want_connection = false    # bare en titt: ikke mas på en server som ikke svarer
	status = Status.CONNECTING if _want_connection else Status.OFFLINE
	if was_online:
		disconnected.emit()
	if _want_connection:
		_retry_in = _retry_delay
		_retry_delay = minf(_retry_delay * 2.0, 8.0)
