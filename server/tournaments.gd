class_name Tournaments
extends RefCounted
## Turneringer: utslag («knockout») eller alle-mot-alle («round_robin»).
## Ren logikk med tiden (unix-sekunder) gitt utenfra, så alt kan testes uten nettverk.
## Lobbyen kobles på via callbacks: åpne et rom for en kamp, se hvem som er i rommet,
## varsle en bruker og lukke et rom. Se Plan.md, seksjon 13.5.
##
## Gangen i en turnering:
##   utkast -> åpen for påmelding -> (innsjekk) -> (ved starttid) pågår -> ferdig   (eller avlyst)
## Innsjekk (runde 18): de siste CHECKIN_S sekundene før start får deltakerne beskjed, og klienten åpner
## turneringssiden med nedtelling og chat. Den som har hatt siden oppe (here), er sjekket inn. Bare de er
## med når oppsettet trekkes; de andre er ute før start (missed), så ingen vinner på walkover mot folk
## som aldri kom. Faller man ut underveis, kan man komme tilbake (lobbyen kaster en inn i kampen igjen).
## Hver kamp får et privat rom, og begge spillerne varsles. Møter ikke begge innen show_up_s, vinner den
## som kom (walkover). Hvem som starter, fordeles jevnt (p1 starter første parti, så byttes det).
##
## Utslag: seedet etter Elo. Uavgjort spilles om; blir også tredje parti uavgjort, går den som ikke
## startet det, videre (avtalt før partiet, som «Armageddon» i sjakk).
##
## Alle mot alle avgjøres ikke av Elo (runde 18):
## - Første runde trekkes tilfeldig. Uten grense på antall runder møter alle alle (sirkelmetoden).
##   Med grense (max_rounds, færre runder enn alle møter alle) er det sveitsisk system: hver runde
##   settes opp etter tabellen, så like mange poeng møtes, og ingen møtes to ganger. Med 16 spillere tar
##   alle 15 runder ca. 2 timer, så grensen trengs.
## - Seier 1 poeng, uavgjort ½, fri runde 1. Likt: innbyrdes oppgjør, Buchholz, Sonneborn-Berger, flest
##   seire (se standings). Er det fortsatt helt likt om førsteplassen, spilles omkamp (utslag mellom dem).
## - Står to uten motstander (motstanderen møtte ikke), spiller de mot hverandre i stedet for å vinne på
##   walkover (se _pair_lonely).
##
## Private turneringer (runde 18, «private»): alle med konto kan lage dem (den som lager, er arrangøren).
## De vises bare for dem som er med, arrangøren og admin, og man blir med med koden (code, lenken ?t=KODE).
## De er alltid urangerte, uten premie, og starter når arrangøren trykker «Start nå» (ikke på et
## klokkeslett): da begynner innsjekken, og er alle der, starter den med en gang. Alle turneringer har en
## kode (storskjermen bruker den). names: kallenavnet til hver deltaker da hen meldte seg på, så navnene
## står igjen når en gjestekonto er slettet. chat = false: bare arrangøren skriver i chatten.
## Hver turnering har sin egen pokal (Trophy). Admin kan velge den i skjemaet, ellers lages en
## tilfeldig. Vinneren får pokalen med turneringens navn på profilen sin.
## Uranket turnering («ranked» = false): partiene endrer ikke Elo, og turneringen vises ikke i
## hovedmenyen, kunngjøres ikke i chatten og hedres ikke (ingen hall of fame, ingen turneringsseier
## i statistikken). Pokal er et eget valg («with_trophy»).

const FORMATS := ["knockout", "round_robin"]
const MAX_REPLAYS := 3
const CHECKIN_S := 120   ## innsjekken før start (se _begin_checkin)

var store: Store
var accounts: Accounts
## open_room(t, m) -> romkode. presence(kode) -> bruker-id-er i rommet.
## notify(bruker-id, melding). close_room(kode, nøkkel, args).
var open_room: Callable = func(_t: Dictionary, _m: Dictionary) -> String: return ""
var presence: Callable = func(_code: String) -> Array: return []
var notify: Callable = func(_uid: int, _msg: Dictionary) -> void: pass
var close_room: Callable = func(_code: String, _key: String, _args: Array) -> void: pass
## announce(nøkkel, args): publiseres i den globale chatten (start og vinner).
var announce: Callable = func(_key: String, _args: Array) -> void: pass
## here(t, bruker-id): har deltakeren turneringssiden oppe nå (innsjekken)? Uten lobby (testene): alle.
var here: Callable = func(_t: Dictionary, _uid: int) -> bool: return true
## changed(id): turneringen er endret (lobbyen sender den nye utgaven til dem som har siden oppe).
var changed: Callable = func(_id: int) -> void: pass
var rng := RandomNumberGenerator.new()


func _init(p_store: Store, p_accounts: Accounts) -> void:
	store = p_store
	accounts = p_accounts
	rng.randomize()
	for t in store.tournaments:
		normalize(t)
		if str(t.code) == "":
			t.code = _new_code()   # turneringer fra før kodene fantes
	_link_old_games()


## Turneringer fra før runde 17 har ikke partiene på kampene: finn dem i partiloggen (der hvert parti
## har kamp-id-en), så finalen og de andre kampene kan ses i reprise.
func _link_old_games() -> void:
	var by_match := {}
	for g in store.games:
		var mid := str(g.get("tournament", ""))
		if mid != "":
			by_match.get_or_add(mid, []).append(int(g.id))
	if by_match.is_empty():
		return
	for t in store.tournaments:
		for round in t.rounds:
			for m in round:
				if (m.games as Array).is_empty() and by_match.has(m.id):
					m.games = by_match[m.id]


## JSON gir desimaltall. Gjør tall om til heltall igjen etter innlesing fra fil.
static func normalize(t: Dictionary) -> void:
	for k in ["id", "current_round", "winner", "created_by", "created_at", "max_players", "max_rounds", "start_time",
			"signup_deadline", "round_gap_s", "show_up_s", "finished_at", "checkin_at"]:
		t[k] = int(t.get(k, 0))
	t.ranked = bool(t.get("ranked", true))
	t.with_trophy = bool(t.get("with_trophy", true))
	t.prize = str(t.get("prize", ""))
	t.private = bool(t.get("private", false))
	t.code = str(t.get("code", ""))
	t.chat = bool(t.get("chat", true))
	t.names = t.get("names", {}) if t.get("names") is Dictionary else {}
	# Turneringer fra før pokalene fantes, får en fast pokal ut fra id-en.
	t.trophy = Trophy.normalize(t.trophy) if t.get("trophy") is Dictionary else Trophy.generate(int(t.id) * 7919)
	t.players = _ints(t.get("players", []))
	t.checked_in = _ints(t.get("checked_in", []))   # møtt til innsjekken (checkin_at > 0 mens den pågår)
	t.missed = _ints(t.get("missed", []))           # var påmeldt, men møtte ikke til start
	t.pairing = str(t.get("pairing", "all"))   # alle mot alle: "all" (alle møter alle) eller "swiss"
	t.playoff = _ints(t.get("playoff", []))    # med i omkampen
	for round in t.get("rounds", []):
		for m in round:
			for k in ["round", "p1", "p2", "start_at", "waiting_since", "winner", "draws", "lonely", "absent"]:
				m[k] = int(m.get(k, 0))
			m.extra = bool(m.get("extra", false))
			m.playoff = bool(m.get("playoff", false))
			m.ready = _ints(m.get("ready", []))
			m.games = _ints(m.get("games", []))


static func _ints(v: Variant) -> Array:
	return (v as Array).map(func(x: Variant) -> int: return int(x)) if v is Array else []


func get_t(id: int) -> Dictionary:
	for t in store.tournaments:
		if int(t.id) == id:
			return t
	return {}


# ---------------------------------------------------------------- Admin

## Lager en turnering (som utkast). data kommer fra admin-skjemaet i klienten.
func create(user_id: int, data: Dictionary, now: int) -> Dictionary:
	var t := {
		"id": store.next_tournament_id, "status": "draft", "players": [], "rounds": [], "current_round": -1,
		"winner": 0, "created_by": user_id, "created_at": now, "names": {}, "pairing": "all", "playoff": [],
		"checkin_at": 0, "checked_in": [], "missed": [],
	}
	store.next_tournament_id += 1
	_apply(t, data, now)
	t.code = _new_code()
	if t.private:
		t.status = "open"   # starter når arrangøren vil: ingen grunn til å vente som utkast
	store.tournaments.append(t)
	_save(t)
	return t


## En kode som ingen annen turnering har (5 bokstaver, uten I og O, som rommene).
func _new_code() -> String:
	while true:
		var code := ""
		for i in 5:
			code += Lobby.CODE_LETTERS[rng.randi() % Lobby.CODE_LETTERS.length()]
		if find_by_code(code).is_empty():
			return code
	return ""


func find_by_code(code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	for t in store.tournaments:
		if code != "" and str(t.get("code", "")) == code:
			return t
	return {}


## Endrer turneringen (admin). Før start kan alt endres. Mens den pågår: navn, beskrivelse, pause
## mellom rundene, møtefrist og pokalen (format, deltakere, tider og regler ligger fast, siden
## oppsettet er trukket). Etter at den er ferdig: navn og beskrivelse.
func update(id: int, data: Dictionary, now: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status in ["draft", "open"]:
		var start := int(t.start_time)
		_apply(t, data, now)
		if int(t.checkin_at) > 0 and t.private:
			t.start_time = start   # under innsjekken: starten er satt av «Start nå», ikke av skjemaet
		elif int(t.checkin_at) > 0 and int(t.start_time) > now + CHECKIN_S:
			t.checkin_at = 0   # starten ble flyttet: innsjekken begynner på nytt når det nærmer seg
			t.checked_in = []
	elif t.status in ["running", "finished"]:
		_apply_live(t, data)
	else:
		return "Turneringen er avlyst."
	_save(t)
	return ""


func _apply_live(t: Dictionary, d: Dictionary) -> void:
	if d.has("name"):
		var name := str(d.name).strip_edges().substr(0, 40)
		t.name = name if name != "" else t.name
	if d.has("description"):
		t.description = str(d.description).strip_edges().substr(0, 300)
	if d.has("chat"):
		t.chat = bool(d.chat)
	if t.status != "running":
		return
	if d.has("round_gap_s"):
		t.round_gap_s = clampi(int(d.round_gap_s), 0, 3600)
	if d.has("show_up_s"):
		t.show_up_s = clampi(int(d.show_up_s), 30, 1800)
	if d.has("with_trophy"):
		t.with_trophy = bool(d.with_trophy)
	if d.get("trophy") is Dictionary:
		t.trophy = Trophy.normalize(d.trophy)
	_apply_prize(t, d)


func _apply(t: Dictionary, d: Dictionary, now: int) -> void:
	t.name = str(d.get("name", t.get("name", "Turnering"))).strip_edges().substr(0, 40)
	if t.name == "":
		t.name = "Turnering"
	t.description = str(d.get("description", t.get("description", ""))).strip_edges().substr(0, 300)
	var fmt := str(d.get("format", t.get("format", "knockout")))
	t.format = fmt if fmt in FORMATS else "knockout"
	var opts = d.get("options", t.get("options", {}))
	var o := GameOptions.from_dict(opts if opts is Dictionary else {})
	o.starter = "alternate"   # rettferdig ved omspill
	t.options = o.to_dict()
	t.max_players = clampi(int(d.get("max_players", t.get("max_players", 16))), 2, 64)
	t.max_rounds = clampi(int(d.get("max_rounds", t.get("max_rounds", 0))), 0, 63)   # alle mot alle: 0 = alle runder
	t.start_time = maxi(int(d.get("start_time", t.get("start_time", now + 600))), now)
	t.signup_deadline = mini(int(d.get("signup_deadline", t.get("signup_deadline", t.start_time))), t.start_time)
	t.round_gap_s = clampi(int(d.get("round_gap_s", t.get("round_gap_s", 120))), 0, 3600)
	t.show_up_s = clampi(int(d.get("show_up_s", t.get("show_up_s", 300))), 30, 1800)
	t.ranked = bool(d.get("ranked", t.get("ranked", true)))
	t.with_trophy = bool(d.get("with_trophy", t.get("with_trophy", true)))
	t.chat = bool(d.get("chat", t.get("chat", true)))
	_apply_prize(t, d)
	if not t.has("private"):   # bestemmes når turneringen lages, og ligger fast
		t.private = bool(d.get("private", false))
	if t.private:
		t.ranked = false
		t.prize = ""
	if d.get("trophy") is Dictionary:
		t.trophy = Trophy.normalize(d.trophy)
	elif not t.get("trophy") is Dictionary:
		t.trophy = Trophy.generate(rng.randi())


## Premien vinneren låser opp (runde 17): en skin eller seiersanimasjon som ellers krever nivå, eller ingen ("").
static func _apply_prize(t: Dictionary, d: Dictionary) -> void:
	var prize := str(d.get("prize", t.get("prize", "")))
	t.prize = prize if Progression.UNLOCKS.has(prize) else ""


## publish | start | cancel | delete
func action(id: int, what: String, now: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	match what:
		"publish":
			if t.status != "draft":
				return "Turneringen er allerede publisert."
			t.status = "open"
		"start":
			# Første trykk: innsjekken begynner (er alle der allerede, starter den med en gang). Under
			# innsjekken: start nå med dem som har kommet.
			if not t.status in ["draft", "open"]:
				return "Turneringen har allerede startet."
			if t.players.size() < 2:
				return "Det trengs minst to deltakere."
			if int(t.checkin_at) == 0:
				t.status = "open"
				t.start_time = now + CHECKIN_S
				t.signup_deadline = mini(int(t.signup_deadline), int(t.start_time))
				_begin_checkin(t, now)
				if _all_here(t):
					_start(t, now)
			elif t.checked_in.size() < 2:
				return "Det trengs minst to som har møtt opp."
			else:
				t.start_time = now
				_start(t, now)
		"cancel":
			if t.status in ["finished", "cancelled"]:
				return "Turneringen er allerede ferdig."
			_close_open_rooms(t)
			t.status = "cancelled"
			_notify_all(t, "Turneringen «%s» ble avlyst.", [t.name])
		"delete":
			_close_open_rooms(t)
			store.tournaments.erase(t)
		_:
			return "Ukjent handling."
	_save(t)
	return ""


# ---------------------------------------------------------------- Spillere

func join(id: int, uid: int, now: int) -> String:
	var t := get_t(id)
	var err := join_error(t, uid, now)
	if err != "" or uid in t.players:
		return err
	t.players.append(uid)
	t.names[str(uid)] = accounts.username_of(uid)
	_save(t)
	return ""


## Hvorfor uid ikke kan melde seg på ("" = kan, eller er allerede med). uid 0: om noen kan.
func join_error(t: Dictionary, uid: int, now: int) -> String:
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status != "open":
		return "Påmeldingen er ikke åpen."
	if not t.private and now >= int(t.signup_deadline):
		return "Påmeldingsfristen er ute."
	if uid != 0 and uid in t.players:
		return ""
	if t.players.size() >= int(t.max_players):
		return "Turneringen er full."
	return ""


## Arrangøren fjerner en deltaker før start.
func kick(id: int, uid: int) -> String:
	var t := get_t(id)
	if t.is_empty() or t.status != "open":
		return "Deltakere kan bare fjernes før start."
	t.players.erase(uid)
	t.checked_in.erase(uid)
	_save(t)
	return ""


## Deltakerne i turneringer som ikke er ferdige (gjestekontoene deres slettes ikke): id -> true.
func active_players() -> Dictionary:
	var out := {}
	for t in store.tournaments:
		if t.status in ["draft", "open", "running"]:
			for uid in t.players:
				out[int(uid)] = true
	return out


func leave(id: int, uid: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status != "open":
		return "Du kan ikke melde deg av etter start."
	t.players.erase(uid)
	t.checked_in.erase(uid)
	_save(t)
	return ""


## «Klar for neste kamp» i pausen mellom rundene. Er begge i kampen klare, starter den med en gang.
## Den andre spilleren får beskjed om at motstanderen er klar.
func ready(id: int, uid: int, now: int) -> String:
	var t := get_t(id)
	if t.is_empty() or t.status != "running":
		return "Turneringen pågår ikke."
	for m in t.rounds[int(t.current_round)]:
		if m.status != "scheduled" or not uid in [m.p1, m.p2]:
			continue
		if not uid in m.ready:
			m.ready.append(uid)
		var other: int = m.p2 if uid == m.p1 else m.p1
		if other in m.ready:
			m.start_at = mini(int(m.start_at), now)   # tick() åpner rommet
		else:
			notify.call(other, { "t": Protocol.TOURNAMENT_NOTICE, "tournament": t.id, "room": "",
				"key": "%s er klar for neste kamp. Trykk «Klar» på turneringssiden for å starte med en gang.",
				"args": [accounts.username_of(uid)],
				"text": "%s er klar for neste kamp. Trykk «Klar» på turneringssiden for å starte med en gang." % accounts.username_of(uid) })
		_save(t)
		return ""
	return "Du har ingen kamp som venter."


# ---------------------------------------------------------------- Tid

func tick(now: int) -> void:
	for t in store.tournaments.duplicate():
		if t.status == "open" and _tick_checkin(t, now):
			_save(t)
		if t.status == "running":
			if _tick_round(t, now):
				_save(t)


## Innsjekken før start. Private turneringer har ingen starttid: der begynner den med «Start nå», og
## starter så snart alle er der. Gir true hvis noe endret seg.
func _tick_checkin(t: Dictionary, now: int) -> bool:
	var changed := false
	if int(t.checkin_at) == 0:
		if t.private or now < int(t.start_time) - CHECKIN_S:
			return false
		_begin_checkin(t, now)
		changed = true
	elif _check_in(t):
		changed = true
	if now >= int(t.start_time) or (t.private and _all_here(t)):
		_start(t, now)
		changed = true
	return changed


## Innsjekken begynner: de som ikke har turneringssiden oppe, får beskjed (klienten åpner den, med
## nedtellingen og chatten). Begynner den sent (f.eks. etter en omstart av serveren), får alle likevel
## hele tiden på seg.
func _begin_checkin(t: Dictionary, now: int) -> void:
	t.checkin_at = now
	t.checked_in = []
	_check_in(t)
	if not _all_here(t):
		t.start_time = maxi(int(t.start_time), now + CHECKIN_S)
	for uid in t.players:
		if not uid in t.checked_in:
			notify.call(uid, { "t": Protocol.TOURNAMENT_NOTICE, "key": "«%s» starter om 2 minutter! Bli med på nedtellingen.",
				"args": [t.name], "tournament": t.id, "room": "", "open": true })


## Sjekker inn deltakerne som har siden oppe nå. Den som har vært innom, er med. Gir true hvis noen kom.
func _check_in(t: Dictionary) -> bool:
	var changed := false
	for uid in t.players:
		if not uid in t.checked_in and here.call(t, uid):
			t.checked_in.append(uid)
			changed = true
	return changed


func _all_here(t: Dictionary) -> bool:
	return t.players.all(func(uid: int) -> bool: return uid in t.checked_in)


## Starttid: bare de som møtte til innsjekken, er med. De andre får beskjed og er ute.
func _start(t: Dictionary, now: int) -> void:
	if int(t.checkin_at) > 0:
		t.missed = t.players.filter(func(uid: int) -> bool: return not uid in t.checked_in)
		t.players = t.players.filter(func(uid: int) -> bool: return uid in t.checked_in)
		for uid in t.missed:
			notify.call(uid, { "t": Protocol.NOTICE, "key": "Du møtte ikke til start, så du er ikke med i «%s».",
				"args": [t.name], "text": "Du møtte ikke til start, så du er ikke med i «%s»." % t.name })
	if t.players.size() < 2:
		t.status = "cancelled"
		_notify_all(t, "Turneringen «%s» ble avlyst (for få deltakere).", [t.name])
		return
	t.status = "running"
	var seeds: Array = t.players.duplicate()
	_shuffle(seeds)
	t.rounds = []
	t.playoff = []
	if t.format == "round_robin":
		# Uten Elo: tilfeldig rekkefølge. Er antall runder begrenset (færre enn alle møter alle), settes
		# hver runde opp etter tabellen (sveitsisk), ellers trekkes alle rundene nå.
		var all := _round_robin(seeds)
		t.pairing = "swiss" if int(t.max_rounds) > 0 and int(t.max_rounds) < all.size() else "all"
		if t.pairing == "all":
			var starts := {}
			for r in all.size():
				t.rounds.append(_matches(t, r, all[r], starts))
		else:
			t.rounds.append(_swiss_round(t, 0, seeds))
	else:
		seeds.sort_custom(func(a: int, b: int) -> bool: return _elo(a) > _elo(b))   # utslag: seedet etter Elo
		var size := 2
		while size < seeds.size():
			size *= 2
		while seeds.size() < size:
			seeds.append(0)   # fri runde («bye»)
		var matches := []
		for i in size / 2:
			matches.append(_match(t, 0, i, seeds[i], seeds[size - 1 - i]))
		t.rounds.append(matches)
	t.current_round = 0
	_schedule_round(t, 0, now)
	_notify_all(t, "Turneringen «%s» har startet!", [t.name])
	if t.ranked:
		announce.call("Turneringen «%s» har startet!", [t.name])
	_award_show_up_xp(t, now)


## Alle med konto som møtte opp, får Progression.SHOW_UP_XP når turneringen starter (urangerte: se
## Accounts.award_show_up_xp).
func _award_show_up_xp(t: Dictionary, now: int) -> void:
	var any := false
	for uid in t.players:
		var r := accounts.award_show_up_xp(int(uid), t.ranked, now)
		if not r.is_empty():
			any = true
			_tell_xp(int(uid), r, "Du fikk %d XP for å møte opp til «%s».", t.name)
	if any:
		store.save_users()


## Alle-mot-alle med «sirkelmetoden»: alle møter alle én gang.
static func _round_robin(players: Array) -> Array:
	var list := players.duplicate()
	if list.size() % 2 == 1:
		list.append(0)
	var n := list.size()
	var rounds := []
	for r in n - 1:
		var pairs := []
		for i in n / 2:
			pairs.append([list[i], list[n - 1 - i]])
		rounds.append(pairs)
		list.insert(1, list.pop_back())   # roter alle unntatt den første
	return rounds


## Neste runde i sveitsisk system: tabellen ovenfra, så like mange poeng møtes, og ingen møtes to ganger.
## Ved oddetall får den lavest plasserte som ikke har hatt fri runde, fri runde (1 poeng). order er
## rekkefølgen å sette opp fra (første runde: tilfeldig; ellers tabellen). Går det ikke uten at noen
## møtes igjen (få spillere og mange runder), tillates det.
func _swiss_round(t: Dictionary, round_i: int, order: Array = []) -> Array:
	var points := {}
	if order.is_empty():
		var table := standings(t)
		order = table.map(func(r: Dictionary) -> int: return int(r.id))
		for r in table:
			points[int(r.id)] = int(r.points2)
	var bye := 0
	if order.size() % 2 == 1:
		var had := {}
		for round in t.rounds:
			for m in round:
				if m.reason == "bye":
					had[int(m.winner)] = true
		bye = int(order[-1])
		for i in range(order.size() - 1, -1, -1):
			if not had.has(int(order[i])):
				bye = int(order[i])
				break
		order = order.filter(func(uid: int) -> bool: return uid != bye)
	var pairs := _pair_up(order, points, _met(t))
	if pairs.is_empty() and not order.is_empty():
		pairs = _pair_up(order, points, {})
	if bye != 0:
		pairs.append([bye, 0])
	return _matches(t, round_i, pairs, _starts(t))


## Setter opp par uten omkamper (met), slik at de som møtes, har så like poeng som mulig (minst sum av
## kvadratet av poengforskjellen; poeng mangler = 0). order er sortert etter tabellen, så det første
## forsøket er nesten alltid godt. Søker videre med tilbakesporing, kutter grener som ikke kan bli bedre,
## og gir det beste den fant innen et fast antall steg. [] hvis det ikke går.
static func _pair_up(order: Array, points: Dictionary, met: Dictionary) -> Array:
	var best := { "cost": 1 << 40, "pairs": [], "steps": 0 }
	_pair_search(order, points, met, [], 0, best)
	return best.pairs


static func _pair_search(rest: Array, points: Dictionary, met: Dictionary, cur: Array, cost: int, best: Dictionary) -> void:
	best.steps += 1
	if best.steps > 50_000 or cost >= best.cost:
		return
	if rest.is_empty():
		best.cost = cost
		best.pairs = cur.duplicate()
		return
	var a: int = rest[0]
	for j in range(1, rest.size()):
		var b: int = rest[j]
		if met.has(_pair_key(a, b)):
			continue
		var d := int(points.get(a, 0)) - int(points.get(b, 0))
		if cost + d * d >= best.cost:
			break   # lenger ned er forskjellen bare større
		var next := rest.slice(1)
		next.remove_at(j - 1)
		cur.append([a, b])
		_pair_search(next, points, met, cur, cost + d * d, best)
		cur.pop_back()
		if best.cost == 0:
			return


## Par som har møtt hverandre (eller skulle, men en av dem møtte ikke): "lav,høy" -> true.
static func _met(t: Dictionary) -> Dictionary:
	var out := {}
	for round in t.rounds:
		for m in round:
			if int(m.p1) != 0 and int(m.p2) != 0:
				out[_pair_key(int(m.p1), int(m.p2))] = true
	return out


static func _pair_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


## Hvor mange kamper hver spiller har startet (vært p1 i) så langt.
static func _starts(t: Dictionary) -> Dictionary:
	var out := {}
	for round in t.rounds:
		for m in round:
			if int(m.p1) != 0 and int(m.p2) != 0:
				out[int(m.p1)] = int(out.get(int(m.p1), 0)) + 1
	return out


## Kampene i en runde fra parene. Den som har startet færrest kamper så langt, starter (p1), så ingen får
## forspranget med å begynne oftere enn de andre. Fri runde (0) står alltid som p2. starts oppdateres.
func _matches(t: Dictionary, round_i: int, pairs: Array, starts: Dictionary) -> Array:
	var out := []
	for pair in pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		if a == 0 or (b != 0 and int(starts.get(b, 0)) < int(starts.get(a, 0))):
			var swap := a
			a = b
			b = swap
		if b != 0:
			starts[a] = int(starts.get(a, 0)) + 1
		out.append(_match(t, round_i, out.size(), a, b))
	return out


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


func _match(t: Dictionary, round_i: int, i: int, p1: int, p2: int) -> Dictionary:
	return { "id": "t%d-r%d-m%d" % [t.id, round_i, i], "round": round_i, "p1": p1, "p2": p2, "status": "pending",
		"start_at": 0, "waiting_since": 0, "room": "", "winner": 0, "reason": "", "draws": 0, "ready": [], "games": [],
		"lonely": 0, "absent": 0, "extra": false, "playoff": false }


func _schedule_round(t: Dictionary, round_i: int, start_at: int) -> void:
	for m in t.rounds[round_i]:
		if m.p1 == 0 or m.p2 == 0:
			# Fri runde: den som har en motstander-plass tom, går videre uten å spille.
			m.status = "done"
			m.winner = m.p1 if m.p2 == 0 else m.p2
			m.reason = "bye"
		else:
			m.status = "scheduled"
			m.start_at = start_at


## Gir true hvis noe endret seg.
func _tick_round(t: Dictionary, now: int) -> bool:
	var changed := false
	var round_i := int(t.current_round)
	for m in t.rounds[round_i]:
		if m.status == "scheduled" and now >= int(m.start_at):
			_open_match(t, m, now)
			changed = true
		elif m.status == "waiting" and int(m.lonely) == 0 and now >= int(m.waiting_since) + int(t.show_up_s):
			var here: Array = presence.call(m.room)
			var p1_here: bool = m.p1 in here
			var p2_here: bool = m.p2 in here
			if p1_here and p2_here:
				continue
			if not p1_here and not p2_here:
				close_room.call(m.room, "Ingen av spillerne møtte.", [])
				_finish_match(t, m, 0, "no_show")
			elif t.format == "round_robin" and not m.extra and not m.playoff:
				m.lonely = m.p1 if p1_here else m.p2   # kanskje står en annen også uten motstander (_pair_lonely)
			else:
				_finish_walkover(t, m, m.p1 if p1_here else m.p2)
			changed = true
	if t.format == "round_robin" and _pair_lonely(t, round_i, now):
		changed = true
	if t.status == "running" and _round_done(t, round_i):
		_next_round(t, now)
		changed = true
	return changed


## Åpner rommet for kampen og kaster begge spillerne inn.
func _open_match(t: Dictionary, m: Dictionary, now: int) -> void:
	m.room = open_room.call(t, m)
	m.status = "waiting"
	m.waiting_since = now
	for uid in [m.p1, m.p2]:
		notify.call(uid, { "t": Protocol.TOURNAMENT_NOTICE, "key": "Kampen din i «%s» starter nå!",
			"args": [t.name], "tournament": t.id, "room": m.room })


func _finish_walkover(t: Dictionary, m: Dictionary, winner: int) -> void:
	close_room.call(m.room, "Motstanderen møtte ikke. Du vinner på walkover.", [])
	m.lonely = 0
	_finish_match(t, m, winner, "walkover")


## Alle mot alle: to som møtte, men står uten motstander (lonely), spiller mot hverandre i stedet for å vinne
## på walkover.
## - Sveitsisk: den nye kampen erstatter walkoverne. Den som ikke kom, taper (forfeit); den som kom, får
##   poeng bare fra den nye kampen. De to kan ikke ha møtt hverandre før.
## - Alle møter alle: de spiller kampen de uansett skulle hatt mot hverandre i en senere runde, nå, og
##   vinner walkoveren (den kampen kommer ikke igjen). Da har de fri i runden kampen var satt opp i.
## Står noen igjen uten motstander, og ingen annen kamp i runden kan gi en, blir det walkover som før.
## Gir true hvis noe endret seg.
func _pair_lonely(t: Dictionary, round_i: int, now: int) -> bool:
	var left: Array = (t.rounds[round_i] as Array).filter(func(m: Dictionary) -> bool:
		return m.status == "waiting" and int(m.lonely) != 0)
	if left.is_empty():
		return false
	var changed := false
	var met := _met(t)
	var i := 0
	while i < left.size():
		var paired := false
		for j in range(i + 1, left.size()):
			var a: int = left[i].lonely
			var b: int = left[j].lonely
			var future := _future_match(t, round_i, a, b) if t.pairing == "all" else {}
			if (t.pairing == "all" and future.is_empty()) or (t.pairing != "all" and met.has(_pair_key(a, b))):
				continue
			_play_lonely(t, round_i, left[i], left[j], future, now)
			left.remove_at(j)
			left.remove_at(i)
			paired = true
			changed = true
			break
		if not paired:
			i += 1
	var more_coming: bool = (t.rounds[round_i] as Array).any(func(m: Dictionary) -> bool:
		return m.status == "scheduled" or (m.status == "waiting" and int(m.lonely) == 0 and not m.extra))
	if not more_coming:
		for m in left:
			_finish_walkover(t, m, int(m.lonely))
			changed = true
	return changed


## Setter de to som står uten motstander i m1 og m2, opp mot hverandre (se _pair_lonely).
func _play_lonely(t: Dictionary, round_i: int, m1: Dictionary, m2: Dictionary, future: Dictionary, now: int) -> void:
	var a: int = m1.lonely
	var b: int = m2.lonely
	for pair in [[m1, b], [m2, a]]:
		var m: Dictionary = pair[0]
		var present: int = m.lonely
		close_room.call(m.room, "Motstanderen møtte ikke. Du spiller mot %s i stedet.", [accounts.username_of(pair[1])])
		m.lonely = 0
		if t.pairing == "all":
			_finish_match(t, m, present, "walkover")
		else:
			m.absent = m.p2 if present == m.p1 else m.p1
			_finish_match(t, m, 0, "forfeit")
	var nm := future
	if nm.is_empty():
		nm = _matches(t, round_i, [[a, b]], _starts(t))[0]
		nm.id = "t%d-r%d-m%d" % [t.id, round_i, (t.rounds[round_i] as Array).size()]
	else:
		(t.rounds[int(nm.round)] as Array).erase(nm)
		nm.round = round_i
	nm.extra = true
	(t.rounds[round_i] as Array).append(nm)
	_open_match(t, nm, now)


## Kampen a og b skal spille mot hverandre i en senere runde (alle møter alle), eller {}.
static func _future_match(t: Dictionary, round_i: int, a: int, b: int) -> Dictionary:
	for r in range(round_i + 1, (t.rounds as Array).size()):
		for m in t.rounds[r]:
			if m.status == "pending" and ((m.p1 == a and m.p2 == b) or (m.p1 == b and m.p2 == a)):
				return m
	return {}


func on_match_started(match_id: String) -> void:
	var found := _find_match(match_id)
	if not found.is_empty():
		found.m.status = "playing"
		_save(found.t)


## Lobbyen har lagret et parti i en turneringskamp (id i partiloggen, til reprisen). Lagres sammen med
## resultatet (report), som kommer rett etter.
func add_game(match_id: String, game_id: int) -> void:
	var found := _find_match(match_id)
	if not found.is_empty():
		(found.m.games as Array).append(game_id)


## Lobbyen melder resultatet av et parti i en turneringskamp. winner_uid = 0 og draw = true for uavgjort;
## second_uid = den som ikke startet partiet. Gir "replay" hvis kampen skal spilles om, og "replay_last"
## før det siste omspillet (da går den som ikke starter, videre ved uavgjort).
func report(match_id: String, winner_uid: int, draw: bool, now: int, second_uid := 0) -> String:
	var found := _find_match(match_id)
	if found.is_empty():
		return ""
	var t: Dictionary = found.t
	var m: Dictionary = found.m
	if m.status == "done":
		return ""
	if draw:
		m.draws += 1
		if t.format == "knockout" or m.playoff:
			if m.draws < MAX_REPLAYS:
				_save(t)
				return "replay_last" if m.draws == MAX_REPLAYS - 1 else "replay"
			# Tredje uavgjorte: den som ikke startet, går videre (sagt fra om før partiet, som «Armageddon»)
			winner_uid = second_uid if second_uid in [m.p1, m.p2] else int(m.p2)
			_finish_match(t, m, winner_uid, "draws")
		else:
			_finish_match(t, m, 0, "draw")
	else:
		_finish_match(t, m, winner_uid, "played")
	if _round_done(t, int(t.current_round)):
		_next_round(t, now)
	_save(t)
	return ""


func _finish_match(t: Dictionary, m: Dictionary, winner: int, reason: String) -> void:
	m.status = "done"
	m.winner = winner
	m.reason = reason


func _round_done(t: Dictionary, round_i: int) -> bool:
	return t.rounds[round_i].all(func(m: Dictionary) -> bool: return m.status == "done")


func _next_round(t: Dictionary, now: int) -> void:
	var round_i := int(t.current_round)
	var start_at := now + int(t.round_gap_s)
	if t.format == "round_robin":
		if (t.playoff as Array).is_empty() and round_i + 1 < regular_rounds(t):
			if t.rounds.size() <= round_i + 1:
				t.rounds.append(_swiss_round(t, round_i + 1))   # sveitsisk: settes opp etter tabellen nå
			t.current_round = round_i + 1
			_schedule_round(t, round_i + 1, start_at)
			if _round_done(t, round_i + 1):
				_next_round(t, now)
		else:
			_end_round_robin(t, now)
		return
	var winners: Array = t.rounds[round_i].map(func(m: Dictionary) -> int: return int(m.winner))
	if winners.size() == 1:
		_finish(t, winners[0], now)
		return
	var matches := []
	for i in winners.size() / 2:
		matches.append(_match(t, round_i + 1, i, winners[i * 2], winners[i * 2 + 1]))
	t.rounds.append(matches)
	t.current_round = round_i + 1
	_schedule_round(t, round_i + 1, start_at)
	for m in matches:
		if m.p1 == 0 and m.p2 == 0:
			m.reason = "no_players"
	if _round_done(t, round_i + 1):
		_next_round(t, now)
	else:
		_notify_all(t, "Neste runde i «%s» starter snart.", [t.name])


## Antall vanlige runder (uten omkamp): sveitsisk har max_rounds, alle møter alle er trukket på forhånd.
static func regular_rounds(t: Dictionary) -> int:
	if str(t.get("pairing", "all")) == "swiss":
		return int(t.max_rounds)
	return (t.rounds as Array).filter(func(r: Array) -> bool: return r.is_empty() or not bool(r[0].get("playoff", false))).size()


## Alle mot alle er ferdig, eller en omkamprunde er ferdig. Står flere helt likt øverst (poeng og alle
## utskillelsene), spilles omkamp om seieren: utslag mellom dem, med uavgjort som i utslag. Ellers vinner
## den øverste i tabellen (eller den som vant omkampen).
func _end_round_robin(t: Dictionary, now: int) -> void:
	var left: Array
	if (t.playoff as Array).is_empty():
		left = _tied_for_first(t)
		_shuffle(left)
	else:
		left = (t.rounds[int(t.current_round)] as Array).map(func(m: Dictionary) -> int: return int(m.winner)) \
			.filter(func(uid: int) -> bool: return uid != 0)
	if left.size() <= 1:
		var table := standings(t)
		_finish(t, int(left[0]) if left.size() == 1 else (int(table[0].id) if not table.is_empty() else 0), now)
		return
	t.playoff = left
	var pairs := []
	for i in range(0, left.size() - 1, 2):
		pairs.append([left[i], left[i + 1]])
	if left.size() % 2 == 1:
		pairs.append([left[-1], 0])   # fri runde i omkampen
	var round_i: int = t.rounds.size()
	var matches := _matches(t, round_i, pairs, _starts(t))
	for m in matches:
		m.playoff = true
	t.rounds.append(matches)
	t.current_round = round_i
	_schedule_round(t, round_i, now + int(t.round_gap_s))
	_notify_all(t, "Helt likt øverst i «%s»: det spilles omkamp om seieren.", [t.name])
	if _round_done(t, round_i):
		_next_round(t, now)


## De som står helt likt øverst i tabellen (poeng og alle utskillelsene, ikke omkampen).
func _tied_for_first(t: Dictionary) -> Array:
	var table := standings(t)
	if table.is_empty():
		return []
	var out := [int(table[0].id)]
	for i in range(1, table.size()):
		if _rank_key(table[i]) != _rank_key(table[0]):
			break
		out.append(int(table[i].id))
	return out


static func _rank_key(r: Dictionary) -> Array:
	return [r.points2, r.h2h, r.buchholz, r.sb2, r.wins]


func _finish(t: Dictionary, winner: int, now: int) -> void:
	t.status = "finished"
	t.winner = winner
	t.finished_at = now
	var before := {}   # vinnerens progresjon før seieren (skin-en som låses opp av første turneringsseier)
	if winner != 0 and store.users.has(winner):
		before = Progression.progress_of(store.users[winner])
		if t.ranked:
			store.users[winner].stats.tournaments_won += 1
			announce.call("%s vant turneringen «%s»!", [accounts.username_of(winner), t.name])
		if t.with_trophy:
			accounts.award_trophy(winner, Trophy.entry(t.name, t.trophy, int(t.id), Time.get_date_string_from_unix_time(now)))
		_notify_all(t, "«%s» er ferdig. Vinner: %s!", [t.name, accounts.username_of(winner)])
	else:
		_notify_all(t, "«%s» er ferdig.", [t.name])
	if t.ranked:
		_award_xp(t, before)


## Rangert turnering ferdig: XP etter plassering (Progression.TOURNAMENT_XP) til alle som spilte, og
## premien (prize) til vinneren. Hver spiller får beskjed og den nye progresjonen (STATS).
func _award_xp(t: Dictionary, winner_before: Dictionary) -> void:
	var places := placements(t)
	for uid in places:
		var u: Dictionary = store.users.get(int(uid), {})
		if u.is_empty():
			continue
		var winner := int(uid) == int(t.winner)
		var prize := winner and accounts.unlock(u, str(t.get("prize", "")))
		var r := accounts.add_xp(u, int(Progression.TOURNAMENT_XP[places[uid]]), winner_before if winner else {})
		if prize:
			r.unlocked.append(str(t.prize))
		_tell_xp(int(uid), r, "Du fikk %d XP for «%s».", t.name)
	store.save_users()


## Beskjed om XP-en (r fra Accounts.add_xp) og den nye progresjonen (STATS) til spilleren. key har %d
## (XP) og %s (turneringen); er noe låst opp, kommer « Låst opp: %s!» etter.
func _tell_xp(uid: int, r: Dictionary, key: String, name: String) -> void:
	var unlocked := ", ".join((r.unlocked as Array).map(func(item: String) -> String: return Progression.item_name(item)))
	var args: Array = [int(r.gained), name]
	if unlocked != "":
		key += " Låst opp: %s!"
		args.append(unlocked)
	notify.call(uid, { "t": Protocol.NOTICE, "key": key, "args": args, "text": key % args })
	notify.call(uid, { "t": Protocol.STATS, "user": accounts.public_info(store.users[uid]) })


## Plasseringen til alle som spilte minst ett parti: winner, final (andreplass), semi (tredje/fjerde)
## eller played. Utslag: etter hvor langt de kom. Alle mot alle: etter tabellen. { bruker-id: plassering }
func placements(t: Dictionary) -> Dictionary:
	var played := {}
	for round in t.rounds:
		for m in round:
			if m.reason in ["played", "draws", "draw"] or not (m.get("games", []) as Array).is_empty():
				played[int(m.p1)] = true
				played[int(m.p2)] = true
	var out := {}
	for uid in played:
		if uid != 0:
			out[uid] = "played"
	if t.format == "round_robin":
		var table := standings(t)
		for i in mini(table.size(), 4):
			var uid := int(table[i].id)
			if out.has(uid):
				out[uid] = "winner" if i == 0 else ("final" if i == 1 else "semi")
		return out
	var n: int = t.rounds.size()
	for r in [n - 2, n - 1]:
		if r < 0:
			continue
		for m in t.rounds[r]:
			var loser := int(m.p1) if int(m.winner) == int(m.p2) else int(m.p2)
			if out.has(loser):
				out[loser] = "final" if r == n - 1 else "semi"
	if out.has(int(t.winner)):
		out[int(t.winner)] = "winner"
	return out


## Tabell for alle mot alle: seier 1 poeng, uavgjort ½, fri runde 1 (lagret som 2, 1 og 2 for å unngå
## desimaler). Likt avgjøres uten Elo, i denne rekkefølgen:
##   h2h       innbyrdes: poengene mot de andre med like mange poeng
##   buchholz  summen av motstandernes poeng (hvor sterke motstandere du har møtt)
##   sb2       Sonneborn-Berger: summen av poengene til dem du slo, og halvparten for uavgjort
##   wins      flest seire
##   playoff   hvor langt man kom i omkampen om seieren (bare når alt over er likt øverst)
## Står noen fortsatt likt lenger ned, deler de plassen (rekkefølgen er da påmeldingen).
## Walkover teller som seier og tap. Møtte man ikke, og den andre spilte mot en annen i stedet (forfeit),
## er det bare et tap for den som ikke møtte. Ingen av dem møtte: tap for begge.
func standings(t: Dictionary) -> Array:
	var rows := {}
	for uid in t.players:
		rows[uid] = { "id": uid, "username": _name(t, uid), "elo": _elo(uid), "points2": 0, "wins": 0,
			"draws": 0, "losses": 0, "h2h": 0, "buchholz": 0, "sb2": 0, "playoff": 0 }
	var games := []   # [a, b, poeng til a, poeng til b] (×2)
	for round in t.rounds:
		for m in round:
			if m.status != "done":
				continue
			var a := int(m.p1)
			var b := int(m.p2)
			if m.playoff:
				if rows.has(int(m.winner)):
					rows[int(m.winner)].playoff += 1   # videre i omkampen (også på fri runde)
				continue
			if m.reason == "bye":
				if rows.has(int(m.winner)):
					rows[int(m.winner)].points2 += 2
				continue
			if not rows.has(a) or not rows.has(b):
				continue
			match str(m.reason):
				"forfeit":
					if rows.has(int(m.absent)):
						rows[int(m.absent)].losses += 1
				"no_show":
					rows[a].losses += 1
					rows[b].losses += 1
				"draw":
					games.append([a, b, 1, 1])
				_:
					if int(m.winner) != 0:
						games.append([a, b, 2 if int(m.winner) == a else 0, 2 if int(m.winner) == b else 0])
	for g in games:
		for side in [[g[0], g[2]], [g[1], g[3]]]:
			var r: Dictionary = rows[side[0]]
			r.points2 += side[1]
			if side[1] == 2:
				r.wins += 1
			elif side[1] == 1:
				r.draws += 1
			else:
				r.losses += 1
	for g in games:
		var ra: Dictionary = rows[g[0]]
		var rb: Dictionary = rows[g[1]]
		ra.buchholz += rb.points2
		rb.buchholz += ra.points2
		ra.sb2 += rb.points2 * g[2]
		rb.sb2 += ra.points2 * g[3]
		if ra.points2 == rb.points2:
			ra.h2h += g[2]
			rb.h2h += g[3]
	var order: Array = t.players
	var out := rows.values()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		for k in ["points2", "h2h", "buchholz", "sb2", "wins", "playoff"]:
			if x[k] != y[k]:
				return x[k] > y[k]
		return order.find(x.id) < order.find(y.id)
	)
	return out


# ---------------------------------------------------------------- Til klienten

## Kort versjon til listen.
func summary(t: Dictionary) -> Dictionary:
	return { "id": t.id, "name": t.name, "format": t.format, "status": t.status, "start_time": t.start_time,
		"players": t.players.size(), "max_players": t.max_players, "max_rounds": int(t.get("max_rounds", 0)),
		"options": t.options,
		"winner": _name(t, int(t.winner)) if int(t.winner) != 0 else "", "trophy": t.trophy,
		"finished_at": int(t.get("finished_at", 0)), "ranked": t.ranked, "with_trophy": t.with_trophy,
		"final_game": final_game(t), "prize": str(t.get("prize", "")), "private": t.private, "chat": t.chat,
		"checkin": t.status == "open" and int(t.checkin_at) > 0 }


## Det siste partiet i finalen (utslag, eller omkampen om seieren i alle mot alle, når turneringen er
## ferdig), til «Se finalen». 0 = ingen.
static func final_game(t: Dictionary) -> int:
	if t.status != "finished" or (t.rounds as Array).is_empty():
		return 0
	var last: Array = t.rounds[-1]
	if last.size() != 1 or (last[0].get("games", []) as Array).is_empty() \
			or not (t.format == "knockout" or bool(last[0].get("playoff", false))):
		return 0
	return int(last[0].games[-1])


## Full versjon til turneringssiden, med navn i stedet for id-er.
func public(t: Dictionary) -> Dictionary:
	var out := summary(t)
	out.description = t.description
	out.signup_deadline = t.signup_deadline
	out.round_gap_s = t.round_gap_s
	out.show_up_s = t.show_up_s
	out.current_round = t.current_round
	out.player_list = t.players.map(func(uid: int) -> Dictionary:
		return { "id": uid, "username": _name(t, uid), "elo": _elo(uid), "guest": accounts.is_guest(uid),
			"here": uid in t.checked_in }
	)
	if not (t.missed as Array).is_empty():
		out.missed = t.missed.map(func(uid: int) -> String: return _name(t, uid))
	out.rounds = t.rounds.map(func(r: Array) -> Array:
		return r.map(func(m: Dictionary) -> Dictionary:
			var pm := { "id": m.id, "p1": m.p1, "p2": m.p2, "p1_name": _name_or_dash(t, m.p1), "p2_name": _name_or_dash(t, m.p2),
				"status": m.status, "start_at": m.start_at, "room": m.room, "winner": m.winner, "reason": m.reason,
				"games": m.get("games", []), "lonely": m.lonely, "playoff": m.playoff, "extra": m.extra }
			if m.reason == "forfeit":
				pm.absent_name = _name_or_dash(t, m.absent)
			if m.status == "scheduled":
				pm.ready = [m.p1 in m.get("ready", []), m.p2 in m.get("ready", [])]
			if m.status == "waiting":
				# Hvem som har kommet, og når den som mangler taper på walkover
				var here: Array = presence.call(m.room)
				pm.here = [m.p1 in here, m.p2 in here]
				pm.walkover_at = int(m.waiting_since) + int(t.show_up_s)
			return pm
		)
	)
	if t.format == "round_robin" and t.status in ["running", "finished"]:
		out.standings = standings(t)
		out.pairing = t.pairing
		out.regular_rounds = regular_rounds(t)
	return out


## Kalenderoppføring (iCalendar) for turneringen. link = turneringssiden.
## Varigheten anslås ut fra antall runder (utslag) med 15 min per runde, minst én time.
static func ics(t: Dictionary, link: String) -> String:
	var start := int(t.start_time)
	var rounds := 1
	while (1 << rounds) < maxi(2, int(t.max_players)):
		rounds += 1
	var end := start + maxi(3600, rounds * 15 * 60)
	var stamp := func(unix: int) -> String:
		return Time.get_datetime_string_from_unix_time(unix).replace("-", "").replace(":", "") + "Z"
	var esc := func(s: String) -> String:
		return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")
	var desc := str(t.get("description", ""))
	desc = (desc + "\n\n" if desc != "" else "") + link
	var lines := [
		"BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Four in Space//Turnering//NO", "CALSCALE:GREGORIAN",
		"METHOD:PUBLISH", "BEGIN:VEVENT",
		"UID:turnering-%d@fourinspace" % int(t.id),
		"DTSTAMP:" + stamp.call(int(t.get("created_at", start))),
		"DTSTART:" + stamp.call(start), "DTEND:" + stamp.call(end),
		"SUMMARY:" + esc.call("Turnering: " + str(t.name)),
		"DESCRIPTION:" + esc.call(desc), "URL:" + link,
		"BEGIN:VALARM", "TRIGGER:-PT15M", "ACTION:DISPLAY", "DESCRIPTION:" + esc.call(str(t.name)), "END:VALARM",
		"END:VEVENT", "END:VCALENDAR",
	]
	return "\r\n".join(lines) + "\r\n"


func _name_or_dash(t: Dictionary, uid: int) -> String:
	return _name(t, uid) if uid != 0 else "—"


## Navnet nå, eller navnet fra påmeldingen hvis kontoen er borte (slettet gjestekonto).
func _name(t: Dictionary, uid: int) -> String:
	return accounts.username_of(uid) if store.users.has(uid) else str(t.get("names", {}).get(str(uid), "?"))


# ---------------------------------------------------------------- Hjelpere

## Lagrer alle turneringene og melder at denne er endret.
func _save(t: Dictionary) -> void:
	store.save_tournaments()
	changed.call(int(t.id))


func _elo(uid: int) -> int:
	return int(store.users.get(uid, {}).get("elo", Accounts.START_ELO))


func _find_match(match_id: String) -> Dictionary:
	for t in store.tournaments:
		for round in t.rounds:
			for m in round:
				if m.id == match_id:
					return { "t": t, "m": m }
	return {}


func _notify_all(t: Dictionary, key: String, args: Array) -> void:
	for uid in t.players:
		notify.call(uid, { "t": Protocol.NOTICE, "key": key, "args": args, "text": key % args })


func _close_open_rooms(t: Dictionary) -> void:
	for round in t.rounds:
		for m in round:
			if m.status in ["waiting", "playing"] and m.room != "":
				close_room.call(m.room, "Turneringen ble avlyst.", [])
				m.status = "done"
