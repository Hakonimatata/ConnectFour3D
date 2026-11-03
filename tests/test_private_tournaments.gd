extends TestCase
## Tester for private turneringer (runde 18): alle med konto kan lage dem, koden, gjestekontoer med bare
## kallenavn, arrangørens knapper, innsjekken før start og oppryddingen av gamle gjestekontoer.
## Peer 1 = admin «Ada», peer 2 = «Arran» (vanlig bruker, arrangør av turneringen hen lager).

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


func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _hello(peer: int, session := "") -> void:
	_msg(peer, { "t": "hello", "name": "Gjest", "skin": "ocean", "version": Protocol.VERSION, "session": session,
		"avatar": "" })


func _user(peer: int, name: String) -> void:
	_hello(peer)
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })


## «Arran» (en vanlig bruker) lager en privat turnering. Gir turneringen.
func _private_tournament(extra := {}) -> Dictionary:
	_user(1, "Ada")
	lobby.accounts.set_admin("Ada", true)
	_user(2, "Arran")
	var data := { "name": "Fredagskveld", "format": "knockout", "options": { "must_block": false, "no_gift": false } }
	data.merge(extra, true)
	_msg(2, { "t": "tournament_create", "data": data })
	return lobby.tournaments.get_t(int(_last(2, "tournament_state").tournament.id))


## En gjest blir med via koden med bare et kallenavn. Gir svaret (økten) fra serveren.
func _guest_joins(peer: int, code: String, name: String) -> Dictionary:
	_hello(peer)
	_msg(peer, { "t": "tournament_code", "code": code, "join": true, "name": name })
	return _last(peer, "session")


func test_everyone_creates_private_tournaments() -> void:
	var t := _private_tournament({ "ranked": true, "prize": "skin:lava", "private": false })
	check(t.private, "vanlige brukere lager alltid private turneringer")
	_user(3, "Vanlig")
	check(not t.ranked and t.prize == "", "uranket og uten premie")
	check_eq(t.status, "open", "åpen med en gang")
	check_eq(str(t.code).length(), 5)
	check_eq(_last(2, "tournament_state").tournament.code, t.code, "arrangøren får koden")
	check(bool(_last(2, "tournament_state").admin), "og kan styre den")
	_msg(3, { "t": "list_tournaments" })
	check(_last(3, "tournament_list").tournaments.is_empty(), "andre ser den ikke i listen")
	_msg(3, { "t": "get_tournament", "id": t.id })
	check_eq(_last(3, "error").code, "no_tournament", "eller med id-en")
	_msg(3, { "t": "tournament_code", "code": str(t.code).to_lower() })
	check_eq(int(_last(3, "tournament_state").tournament.id), int(t.id), "men med koden")
	check(not _last(3, "tournament_state").tournament.has("code"), "uten selve koden (bare arrangøren)")
	check(not bool(_last(3, "tournament_state").admin))
	_msg(1, { "t": "list_tournaments" })
	check_eq(_last(1, "tournament_list").tournaments.size(), 1, "admin ser alle")
	check(bool(_last(1, "tournament_list").create), "admin kan lage turneringer")
	# Høyst to som ikke er ferdige
	_msg(2, { "t": "tournament_create", "data": { "name": "To" } })
	_msg(2, { "t": "tournament_create", "data": { "name": "Tre" } })
	check_eq(_last(2, "error").key, "Du kan ha høyst %d turneringer som ikke er ferdige.")
	_guest_joins(10, t.code, "Gjesten")
	_msg(10, { "t": "tournament_create", "data": { "name": "Gjestecup" } })
	check_eq(_last(10, "error").code, "guest", "gjester kan ikke lage turneringer")


## Mange på samme nett blir med med bare kallenavn. Like navn får et tall bak.
func test_guests_join_with_a_nickname() -> void:
	var t := _private_tournament()
	for i in 6:
		var s := _guest_joins(10 + i, t.code, "Kari N" if i < 2 else "Gjest%d" % i)
		check(not s.is_empty() and str(s.token) != "", "gjest %d fikk en økt" % i)
		check(bool(s.user.guest))
	check_eq(t.players.size(), 6, "alle seks er med")
	check_eq(lobby.accounts.username_of(t.players[0]), "Kari_N", "mellomrom blir _:")
	check_eq(lobby.accounts.username_of(t.players[1]), "Kari_N2", "likt navn får et tall bak:")
	_hello(20)
	_msg(20, { "t": "tournament_code", "code": t.code, "join": true, "name": "x" })
	check_eq(_last(20, "error").code, "guest", "for kort kallenavn")
	_hello(21)
	_msg(21, { "t": "tournament_code", "code": "ZZZZZ", "join": true, "name": "Bob" })
	check_eq(_last(21, "error").code, "no_tournament")
	# Gjesten kommer tilbake med økten (f.eks. lastet siden på nytt)
	var token := str(_guest_joins(22, t.code, "Tilbake").token)
	_hello(23, token)
	check_eq(_last(23, "welcome").user.username, "Tilbake", "samme gjest etter omlasting:")
	check(not lobby.store.find_user("Tilbake").password.has("hash"), "gjester har ikke passord")
	_msg(24, { "t": "hello", "name": "x", "skin": "ocean", "version": Protocol.VERSION })
	_msg(24, { "t": "login", "username": "Tilbake", "password": "" })
	check(not _last(24, "auth_error").is_empty(), "og kan ikke logge inn med passord")


## Gjester har bare kallenavn: ikke bilde, venner, XP, global chat eller vanlige rom.
func test_guests_are_limited_to_the_tournament() -> void:
	var t := _private_tournament()
	_guest_joins(10, t.code, "Gjesten")
	_msg(10, { "t": "global_chat", "text": "Hei alle", "channel": "generelt" })
	check_eq(_last(10, "error").code, "guest", "ikke den globale chatten")
	_msg(10, { "t": "create_room", "options": {} })
	check_eq(_last(10, "error").code, "guest", "ikke egne rom")
	_msg(10, { "t": "friend", "action": "request", "username": "Ada" })
	check_eq(_last(10, "error").code, "friend", "ikke venner")
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var avatar := AvatarData.from_bytes(img.save_png_to_buffer())
	check(AvatarData.is_valid(avatar))
	_msg(10, { "t": "set_look", "avatar": avatar })
	check(not lobby.store.avatars.has(int(t.players[0])), "ikke bilde")
	check_eq(lobby.players[lobby._peers[10]].avatar, "", "heller ikke for andre i rommet")
	_msg(10, { "t": "tournament_chat", "id": t.id, "text": "Lykke til!" })
	check_eq(_last(10, "tournament_chat_msg").messages[0].text, "Lykke til!", "turneringschatten går")
	_msg(3, { "t": "hello", "name": "Utenfor", "skin": "ocean", "version": Protocol.VERSION })
	now += 2000
	_msg(10, { "t": "tournament_chat", "id": t.id, "text": "Bare oss" })
	check(_last(3, "tournament_chat_msg").is_empty(), "andre får ikke chatten i en privat turnering")
	_msg(2, { "t": "tournament_update", "id": t.id, "data": { "chat": false } })
	now += 2000
	_msg(10, { "t": "tournament_chat", "id": t.id, "text": "Hallo?" })
	check_eq(_last(10, "error").code, "chat_off", "arrangøren slo av chatten")
	_msg(2, { "t": "tournament_chat", "id": t.id, "text": "Vi starter snart" })
	check_eq(_last(10, "tournament_chat_msg").messages[0].text, "Vi starter snart", "arrangøren kan fortsatt skrive")
	_msg(10, { "t": "list_tournaments" })
	check_eq(_last(10, "tournament_list").tournaments.size(), 1, "gjesten ser turneringen sin")


## Arrangøren starter når hen vil, kan fjerne deltakere og rette kallenavn, men bare i egne turneringer.
func test_organizer_controls() -> void:
	var t := _private_tournament()
	_advance(7200)
	check_eq(t.status, "open", "starter ikke av seg selv")
	_guest_joins(10, t.code, "Feilnavn")
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "start" })
	check_eq(_last(2, "error").key, "Det trengs minst to deltakere.", "ikke avlyst med én:")
	check_eq(t.status, "open")
	var uid: int = t.players[0]
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "rename", "user": uid, "name": "Riktig navn" })
	check_eq(lobby.accounts.username_of(uid), "Riktig_navn", "arrangøren rettet kallenavnet:")
	check_eq(_last(10, "renamed").user.username, "Riktig_navn", "gjesten får det nye navnet")
	_user(3, "Vanlig")
	_msg(3, { "t": "tournament_code", "code": t.code, "join": true })
	_msg(3, { "t": "tournament_action", "id": t.id, "action": "kick", "user": uid })
	check_eq(_last(3, "error").code, "admin_only", "andre kan ikke styre")
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "rename", "user": lobby.store.find_user("Vanlig").id, "name": "Hei" })
	check_eq(_last(2, "error").code, "tournament", "bare gjesters navn kan endres")
	_guest_joins(11, t.code, "Bort")
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "kick", "user": lobby.store.find_user("Bort").id })
	check_eq(t.players.size(), 2, "fjernet")
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "start" })
	check_eq(t.status, "running", "arrangøren startet")
	_msg(1, { "t": "tournament_action", "id": t.id, "action": "cancel" })
	check_eq(t.status, "cancelled", "admin kan styre alle")


## Storskjermen trenger ikke konto: koden gir turneringen.
func test_display_needs_no_account() -> void:
	var t := _private_tournament()
	_hello(30)
	_msg(30, { "t": "tournament_code", "code": t.code })
	check_eq(int(_last(30, "tournament_state").tournament.id), int(t.id))
	_msg(30, { "t": "get_tournament", "id": t.id })
	check_eq(int(_last(30, "tournament_state").tournament.id), int(t.id), "senere oppdateringer med id-en går")


## Gjestekontoer som ikke er brukt på 14 dager, slettes, men ikke mens turneringen pågår, og navnet
## står igjen i turneringen.
func test_old_guest_accounts_are_removed() -> void:
	var t := _private_tournament()
	_guest_joins(10, t.code, "Gammel")
	_guest_joins(11, t.code, "Ny")
	var old_id := int(lobby.store.find_user("Gammel").id)
	_advance((Accounts.GUEST_DAYS + 1) * 86400)
	check(lobby.store.users.has(old_id), "beholdes mens turneringen ikke er ferdig")
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "cancel" })
	_advance(3601)
	check(not lobby.store.users.has(old_id), "slettet etter 14 dager")
	_msg(2, { "t": "get_tournament", "id": t.id })
	var names: Array = _last(2, "tournament_state").tournament.player_list.map(func(p: Dictionary) -> String: return p.username)
	check("Gammel" in names, "navnet står igjen: %s" % str(names))

## «Start nå» begynner innsjekken: de som har turneringssiden oppe, er med. Den som mangler, får beskjed
## (klienten åpner siden). Er alle der, starter en privat turnering med en gang.
func test_start_checks_in_who_is_here() -> void:
	var t := _private_tournament()
	_guest_joins(10, t.code, "Kari")
	_guest_joins(11, t.code, "Ola")
	_user(3, "Vanlig")
	_msg(3, { "t": "tournament_code", "code": t.code, "join": true })
	_msg(3, { "t": "view_tournament", "id": 0 })   # gikk fra siden
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "start" })
	check_eq(t.status, "open", "venter på den som ikke er her")
	var starts := int(t.start_time)
	_msg(2, { "t": "tournament_update", "id": t.id, "data": { "description": "Pizza etterpå!", "start_time": unix + 86400 } })
	check(int(t.checkin_at) > 0 and int(t.start_time) == starts, "å endre turneringen avbryter ikke innsjekken")
	var state: Dictionary = _last(2, "tournament_state").tournament
	check(bool(state.checkin), "innsjekken er i gang")
	check_eq(state.player_list.filter(func(p: Dictionary) -> bool: return bool(p.here)).size(), 2, "to er her")
	var notice := _last(3, "tournament_notice")
	check(bool(notice.get("open", false)) and int(notice.get("tournament", 0)) == int(t.id), "den som mangler, får beskjed")
	check(_last(10, "tournament_notice").is_empty(), "de som er her, får ingen beskjed")
	_advance(30)
	check_eq(t.status, "open")
	_msg(3, { "t": "view_tournament", "id": t.id })   # kom tilbake til siden
	_advance(1)
	check_eq(t.status, "running", "alle er her: starter med en gang")
	check_eq(t.players.size(), 3)
	check(t.missed.is_empty())


## De som ikke møter til innsjekken, er ikke med (ingen vinner på walkover mot dem). Arrangøren kan
## starte med dem som er her, men det må være minst to.
func test_no_shows_are_left_out() -> void:
	var t := _private_tournament()
	for i in 3:
		_guest_joins(10 + i, t.code, "Gjest%d" % i)
	_user(3, "Borte")
	_msg(3, { "t": "tournament_code", "code": t.code, "join": true })
	lobby.on_disconnect(3, now)   # mistet nettet
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "start" })
	check_eq(t.status, "open")
	_advance(Tournaments.CHECKIN_S + 1)
	check_eq(t.status, "running", "starter når innsjekken er over")
	var borte := int(lobby.store.find_user("Borte").id)
	check_eq(t.players.size(), 3, "uten den som ikke kom:")
	check_eq(t.missed, [borte])
	for m in t.rounds[0]:
		check(not borte in [int(m.p1), int(m.p2)], "ikke satt opp i en kamp")
	_msg(2, { "t": "get_tournament", "id": t.id })
	check_eq(_last(2, "tournament_state").tournament.missed, ["Borte"], "siden viser hvem som ikke møtte:")
	# Arrangøren starter med dem som er her (uten å vente ut innsjekken)
	var t2 := lobby.tournaments.get_t(int(_create_as(2, "Lørdag").id))
	_guest_joins(20, t2.code, "Rask")
	_guest_joins(21, t2.code, "Kjapp")
	_user(4, "Treig")
	_msg(4, { "t": "tournament_code", "code": t2.code, "join": true })
	_msg(4, { "t": "view_tournament", "id": 0 })
	_msg(2, { "t": "tournament_action", "id": t2.id, "action": "start" })
	check_eq(t2.status, "open")
	_msg(2, { "t": "tournament_action", "id": t2.id, "action": "start" })
	check_eq(t2.status, "running", "andre trykk: start med dem som er her")
	check_eq(t2.players.size(), 2)
	check_eq(_last(4, "notice").key, "Du møtte ikke til start, så du er ikke med i «%s».")
	# Minst to må ha møtt
	var t3 := lobby.tournaments.get_t(int(_create_as(1, "Søndag").id))
	_guest_joins(30, t3.code, "Alene")
	_user(5, "Sover")
	_msg(5, { "t": "tournament_code", "code": t3.code, "join": true })
	_msg(5, { "t": "view_tournament", "id": 0 })
	_msg(1, { "t": "tournament_action", "id": t3.id, "action": "start" })
	_msg(1, { "t": "tournament_action", "id": t3.id, "action": "start" })
	check_eq(_last(1, "error").key, "Det trengs minst to som har møtt opp.")
	check_eq(t3.status, "open")


## Lager en privat turnering som peer lager (allerede innlogget). Gir turneringen slik serveren sendte den.
## Oppmøte-XP også i private turneringer, men ikke til gjester, og bare én urangert turnering per dag
## (alle med konto kan lage dem).
func test_show_up_xp_once_a_day_in_private_tournaments() -> void:
	var t := _private_tournament()
	_guest_joins(10, t.code, "Kari")
	_user(3, "Vanlig")
	_msg(3, { "t": "tournament_code", "code": t.code, "join": true })
	_msg(2, { "t": "tournament_action", "id": t.id, "action": "start" })
	check_eq(t.status, "running", "alle er her")
	var vanlig: Dictionary = lobby.store.find_user("Vanlig")
	check_eq(int(vanlig.xp), Progression.SHOW_UP_XP)
	check(str(_last(3, "notice").text).contains("møte opp"), str(_last(3, "notice")))
	var kari: Dictionary = lobby.store.users[int(t.players.filter(func(uid: int) -> bool: return uid != int(vanlig.id))[0])]
	check(kari.guest and int(kari.xp) == 0, "gjester får ikke XP")
	var t2 := lobby.tournaments.get_t(int(_create_as(2, "Lørdag").id))
	_guest_joins(11, t2.code, "Ola")
	_msg(3, { "t": "tournament_code", "code": t2.code, "join": true })
	_msg(2, { "t": "tournament_action", "id": t2.id, "action": "start" })
	check_eq(t2.status, "running")
	check_eq(int(vanlig.xp), Progression.SHOW_UP_XP, "bare én urangert turnering per dag")
	check(not lobby.accounts.award_show_up_xp(int(vanlig.id), true, unix).is_empty(), "rangerte teller ikke med")
	check(not lobby.accounts.award_show_up_xp(int(vanlig.id), false, unix + 86400).is_empty(), "ny dag")


func _create_as(peer: int, name: String) -> Dictionary:
	_msg(peer, { "t": "tournament_create", "data": { "name": name, "private": true,
		"options": { "must_block": false, "no_gift": false } } })
	return _last(peer, "tournament_state").tournament



func _advance(seconds: int) -> void:
	unix += seconds
	now += seconds * 1000
	lobby.tick(now)
