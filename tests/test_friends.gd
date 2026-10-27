extends TestCase
## Tester for runde 14 på serveren: venner (forespørsel, godta, online-status, invitasjon),
## kanaler i den globale chatten og at turneringssiden får endringer med en gang.

var lobby: Lobby
var _inbox := {}
var now := 1000
var unix := 1_800_000_000


func before_each() -> void:
	lobby = Lobby.new()
	lobby.accounts.iterations = 10
	lobby.send = func(peer: int, msg: Dictionary) -> void:
		_inbox.get_or_add(peer, []).append(Protocol.decode(Protocol.encode(msg)))
	lobby.clock_s = func() -> int: return unix


func after_each() -> void:
	lobby.send = Callable()
	lobby.clock_s = Callable()


func _msg(peer: int, msg: Dictionary) -> void:
	lobby.on_message(peer, msg, now)


func _hello(peer: int, name: String) -> void:
	_msg(peer, { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION })


func _register(peer: int, name: String) -> void:
	_hello(peer, name)
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })


func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _friend(peer: int, action: String, username := "") -> void:
	_msg(peer, { "t": "friend", "action": action, "username": username })


func _tick() -> void:
	now += 1100
	lobby.tick(now)


# ---------------------------------------------------------------- Venner

func test_request_accept_and_online_status() -> void:
	_register(1, "Ada")
	_register(2, "Bob")
	_friend(1, "request", "bob")
	check_eq(_last(2, "friend_notice").kind, "request", "Bob får beskjed:")
	check_eq(_last(2, "friend_notice").from, "Ada")
	check_eq(_last(2, "friends").requests[0].username, "Ada", "forespørselen i Bobs liste:")
	check((_last(1, "friends").friends as Array).is_empty(), "ikke venner før Bob godtar")
	_friend(2, "accept", "Ada")
	check_eq(_last(1, "friend_notice").kind, "accepted")
	var ada_list: Array = _last(1, "friends").friends
	check_eq(ada_list.size(), 1)
	check_eq(ada_list[0].username, "Bob")
	check(ada_list[0].online, "Bob er online")
	check((_last(2, "friends").requests as Array).is_empty(), "forespørselen er borte")
	# Bob går: Ada får oppdatert liste (offline)
	lobby.on_disconnect(2, now)
	_tick()
	check(not _last(1, "friends").friends[0].online, "Bob er offline")
	# Bob kommer tilbake og logger inn med økten
	_inbox.clear()
	_hello(3, "Bob igjen")
	_msg(3, { "t": "login", "username": "Bob", "password": "hemmelig123" })
	_tick()
	check(_last(1, "friends").friends[0].online, "Bob er online igjen")


func test_mutual_request_becomes_friends_and_remove() -> void:
	_register(1, "Ada")
	_register(2, "Bob")
	_friend(1, "request", "Bob")
	_friend(2, "request", "Ada")   # Ada har allerede spurt: dere blir venner med en gang
	check_eq((_last(2, "friends").friends as Array).size(), 1)
	check_eq(lobby.store.find_user("Ada").friends, [int(lobby.store.find_user("Bob").id)])
	_friend(1, "remove", "Bob")
	check((lobby.store.find_user("Bob").friends as Array).is_empty(), "fjernet begge veier")
	check((_last(2, "friends").friends as Array).is_empty(), "Bob får oppdatert liste")


func test_friend_errors_and_login_required() -> void:
	_hello(9, "Gjest")
	_friend(9, "list")
	check_eq(_last(9, "error").code, "login_required")
	_register(1, "Ada")
	_friend(1, "request", "Ada")
	check_eq(_last(1, "error").text, "Du kan ikke legge til deg selv.")
	_friend(1, "request", "Ingen")
	check_eq(_last(1, "error").text, "Fant ikke brukeren Ingen.")


func test_invite_friend_to_room_and_watch_when_playing() -> void:
	_register(1, "Ada")
	_register(2, "Bob")
	_friend(1, "request", "Bob")
	_friend(2, "accept", "Ada")
	_friend(1, "invite", "Bob")
	check_eq(_last(1, "error").text, "Lag et rom først, så kan du invitere.")
	_msg(1, { "t": "create_room", "options": {}, "private": true })
	var code: String = _last(1, "room_state").code
	_friend(1, "invite", "Bob")
	var inv := _last(2, "friend_notice")
	check_eq(inv.kind, "invite")
	check_eq(inv.code, code, "invitasjonen har romkoden:")
	check(str(inv.text).begins_with("Ada inviterer deg til et parti"), str(inv.text))
	check_eq(_last(1, "notice").key, "Invitasjonen er sendt til %s.")
	# Bob blir med, og de spiller: listen sier at Ada spiller, med rommet (for å se på)
	_msg(2, { "t": "join_room", "code": code })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	_tick()
	var bob_view: Dictionary = _last(2, "friends").friends[0]
	check(bob_view.playing, "spiller nå")
	check_eq(bob_view.room, code)
	_register(3, "Cyan")
	_friend(1, "invite", "Cyan")
	check_eq(_last(1, "error").text, "Cyan er ikke vennen din.")


# ---------------------------------------------------------------- Kanaler

func test_global_chat_channels_and_feedback() -> void:
	_hello(1, "Ada")
	_hello(2, "Bob")
	_msg(1, { "t": "global_chat", "text": "Hei!", "channel": "velkommen" })
	check_eq(_last(2, "global_msg").channel, "velkommen")
	now += 2000
	_msg(1, { "t": "global_chat", "text": "Tull", "channel": "finnes-ikke" })
	check_eq(_last(2, "global_msg").channel, "generelt", "ukjent kanal blir generelt:")
	now += 2000
	_msg(1, { "t": "global_chat", "text": "Mer lyd, takk", "channel": "tilbakemelding" })
	check_eq(_last(2, "global_msg").channel, "tilbakemelding")
	_register(3, "Nyen")
	check_eq(_last(3, "global_msg").channel, "velkommen", "nye kontoer ønskes velkommen i velkommen-kanalen:")
	check_eq(_last(1, "global_history").channels, Social.CHANNELS)
	# Hver kanal holder sine siste meldinger, uten å skyve ut de andre kanalene
	for i in Social.MAX_HISTORY + 5:
		lobby.social.chat("Spam", -1, "x%d" % i, unix, "generelt")
	var welcome := lobby.store.global_chat.filter(func(m: Dictionary) -> bool: return m.channel == "velkommen")
	check_eq(welcome.size(), 2, "velkommen-kanalen er urørt:")
	var general := lobby.store.global_chat.filter(func(m: Dictionary) -> bool: return m.channel == "generelt")
	check_eq(general.size(), Social.MAX_HISTORY)


# ---------------------------------------------------------------- Turneringssiden

func test_tournament_page_gets_changes_pushed() -> void:
	_register(1, "Ada")
	lobby.accounts.set_admin("Ada", true)
	_register(2, "Bob")
	_msg(1, { "t": "tournament_create", "data": { "name": "Cup", "start_time": unix + 600 } })
	var id := int(_last(1, "tournament_state").tournament.id)
	_msg(1, { "t": "tournament_action", "id": id, "action": "publish" })
	_msg(2, { "t": "view_tournament", "id": id })
	check_eq(_last(2, "tournament_state").tournament.players, 0.0)
	_register(3, "Cyan")
	_msg(3, { "t": "tournament_join", "id": id })
	_tick()
	check_eq(_last(2, "tournament_state").tournament.players, 1.0, "Bob ser påmeldingen uten å spørre:")
	_msg(2, { "t": "view_tournament", "id": 0 })   # siden lukket
	_inbox.erase(2)
	_msg(1, { "t": "tournament_join", "id": id })
	_tick()
	check(_last(2, "tournament_state").is_empty(), "ingen flere når siden er lukket")


# ---------------------------------------------------------------- Søk, profilbilde og siste partier

func test_search_finds_players_and_sent_requests_are_listed() -> void:
	_register(1, "Ada")
	_register(2, "Adrian")
	_register(3, "Bob")
	_register(4, "Hilda")
	_msg(1, { "t": "user_search", "query": "ad" })
	var hits: Array = _last(1, "users").users
	check_eq(hits.size(), 1, "Ada ser ikke seg selv, bare Adrian:")
	check_eq(hits[0].username, "Adrian")
	check(hits[0].online, "med online-status")
	_msg(3, { "t": "user_search", "query": "A" })
	var names: Array = (_last(3, "users").users as Array).map(func(u: Dictionary) -> String: return u.username)
	check_eq(names, ["Ada", "Adrian", "Hilda"], "store og små bokstaver likt, de som begynner med teksten først:")
	_msg(3, { "t": "user_search", "query": "" })
	check((_last(3, "users").users as Array).is_empty(), "tomt søk gir ingen treff")
	_friend(1, "request", "Bob")
	check_eq(_last(1, "friends").sent, ["Bob"], "Ada ser at forespørselen er sendt:")
	_friend(3, "accept", "Ada")
	check((_last(1, "friends").sent as Array).is_empty(), "borte når Bob har godtatt")


func test_avatar_follows_the_account_to_other_devices() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	var pic := AvatarData.from_bytes(img.save_png_to_buffer())
	check(pic != "", "testbildet er gyldig")
	# Mobilen har bildet og logger inn: kontoen får det
	_msg(1, { "t": "hello", "name": "Ada", "skin": "ocean", "version": Protocol.VERSION, "avatar": pic })
	_msg(1, { "t": "register", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(1, "session").avatar, pic, "kontoen tar enhetens bilde:")
	# PC-en har ikke bildet: får det ved innlogging, og det slettes ikke
	_hello(2, "Ada")
	_msg(2, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(2, "session").avatar, pic, "samme bilde på PC-en:")
	_hello(3, "Gjest")
	_msg(3, { "t": "get_stats", "username": "Ada" })
	check_eq(_last(3, "stats").user.avatar, pic, "andre ser bildet på profilen")
	# Fjernet på PC-en: mobilen (som fortsatt har det lokalt) får det ikke tilbake på kontoen
	_msg(2, { "t": "set_look", "avatar": "" })
	_msg(4, { "t": "hello", "name": "Ada", "skin": "ocean", "version": Protocol.VERSION, "avatar": pic })
	_msg(4, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(4, "session").avatar, "", "fjernet bilde blir borte overalt:")
	# Nytt bilde lagres på kontoen med en gang
	_msg(4, { "t": "set_look", "avatar": pic })
	_hello(5, "Ada")
	_msg(5, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(5, "session").avatar, pic, "nytt bilde følger med:")
	_msg(5, { "t": "set_look", "avatar": "aGVp" })   # gyldig base64, men ikke et bilde
	check_eq(lobby.store.avatars.get(int(_last(5, "session").user.id)), pic, "ugyldig bilde ignoreres")


func test_look_follows_the_account() -> void:
	# Ny konto tar enhetens utseende
	_msg(1, { "t": "hello", "name": "Ada", "skin": "lava", "decal": "star", "win_fx": "fireworks",
		"decal_color": "gold", "away": true, "version": Protocol.VERSION })
	_msg(1, { "t": "register", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(1, "session").look.skin, "lava", "kontoen tar enhetens utseende:")
	# PC-en (standard utseende) logger inn: får kontoens
	_hello(2, "Ada")
	_msg(2, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	var look: Dictionary = _last(2, "session").look
	check_eq([look.skin, look.decal, look.win_fx, look.decal_color, look.away], ["lava", "star", "fireworks", "gold", true],
		"PC-en får kontoens utseende:")
	# Endret på PC-en: lagres på kontoen
	_msg(2, { "t": "set_look", "skin": "glass", "decal": "none", "win_fx": "classic", "decal_color": "auto", "away": false })
	_hello(3, "Ada")
	_msg(3, { "t": "login", "username": "Ada", "password": "hemmelig123" })
	check_eq(_last(3, "session").look.skin, "glass", "endringen følger med:")
	# Endret uten nett (look_pending): enhetens utseende vinner ved innlogging med husket økt
	var token := str(_last(3, "session").token)
	_msg(4, { "t": "hello", "name": "Ada", "skin": "gold", "look_pending": true, "version": Protocol.VERSION, "session": token })
	check_eq(_last(4, "welcome").look.skin, "gold", "enheten vinner når den har endret uten nett:")
	check_eq(lobby.store.find_user("Ada").profile.skin, "gold", "og kontoen er oppdatert")
	# Gjester får ikke noe utseende fra serveren
	_hello(5, "Gjest")
	check(_last(5, "welcome").get("look") == null, "gjest: ingen look")
