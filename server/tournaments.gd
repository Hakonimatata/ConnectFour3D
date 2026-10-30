class_name Tournaments
extends RefCounted
## Turneringer: utslag («knockout») eller alle-mot-alle («round_robin»).
## Ren logikk med tiden (unix-sekunder) gitt utenfra, så alt kan testes uten nettverk.
## Lobbyen kobles på via callbacks: åpne et rom for en kamp, se hvem som er i rommet,
## varsle en bruker og lukke et rom. Se Plan.md, seksjon 13.5.
##
## Gangen i en turnering:
##   utkast -> åpen for påmelding -> (ved starttid) pågår -> ferdig   (eller avlyst)
## Ved starttid trekkes oppsettet (sortert etter Elo). Hver kamp får et privat rom, og begge
## spillerne varsles. Møter ikke begge innen show_up_s, vinner den som kom (walkover).
## Uavgjort i utslag spilles om (inntil 3 ganger). I alle-mot-alle gir uavgjort ½ poeng.
## Alle mot alle kan begrenses til max_rounds runder (admin velger; 0 = alle). Da spiller hver spiller
## så mange partier (én færre ved fri runde), og flest poeng vinner. Med 16 spillere tar alle 15 runder
## ca. 2 timer, så det trengs.
## Hver turnering har sin egen pokal (Trophy). Admin kan velge den i skjemaet, ellers lages en
## tilfeldig. Vinneren får pokalen med turneringens navn på profilen sin.
## Uranket turnering («ranked» = false): partiene endrer ikke Elo, og turneringen vises ikke i
## hovedmenyen, kunngjøres ikke i chatten og hedres ikke (ingen hall of fame, ingen turneringsseier
## i statistikken). Pokal er et eget valg («with_trophy»).

const FORMATS := ["knockout", "round_robin"]
const MAX_REPLAYS := 3

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
## changed(id): turneringen er endret (lobbyen sender den nye utgaven til dem som har siden oppe).
var changed: Callable = func(_id: int) -> void: pass
var rng := RandomNumberGenerator.new()


func _init(p_store: Store, p_accounts: Accounts) -> void:
	store = p_store
	accounts = p_accounts
	rng.randomize()
	for t in store.tournaments:
		normalize(t)
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
			"signup_deadline", "round_gap_s", "show_up_s", "finished_at"]:
		t[k] = int(t.get(k, 0))
	t.ranked = bool(t.get("ranked", true))
	t.with_trophy = bool(t.get("with_trophy", true))
	t.prize = str(t.get("prize", ""))
	# Turneringer fra før pokalene fantes, får en fast pokal ut fra id-en.
	t.trophy = Trophy.normalize(t.trophy) if t.get("trophy") is Dictionary else Trophy.generate(int(t.id) * 7919)
	t.players = (t.get("players", []) as Array).map(func(v: Variant) -> int: return int(v))
	for round in t.get("rounds", []):
		for m in round:
			for k in ["round", "p1", "p2", "start_at", "waiting_since", "winner", "draws"]:
				m[k] = int(m.get(k, 0))
			m.ready = (m.get("ready", []) as Array).map(func(v: Variant) -> int: return int(v))
			m.games = (m.get("games", []) as Array).map(func(v: Variant) -> int: return int(v))


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
		"winner": 0, "created_by": user_id, "created_at": now,
	}
	store.next_tournament_id += 1
	_apply(t, data, now)
	store.tournaments.append(t)
	_save(t)
	return t


## Endrer turneringen (admin). Før start kan alt endres. Mens den pågår: navn, beskrivelse, pause
## mellom rundene, møtefrist og pokalen (format, deltakere, tider og regler ligger fast, siden
## oppsettet er trukket). Etter at den er ferdig: navn og beskrivelse.
func update(id: int, data: Dictionary, now: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status in ["draft", "open"]:
		_apply(t, data, now)
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
	_apply_prize(t, d)
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
			if not t.status in ["draft", "open"]:
				return "Turneringen har allerede startet."
			t.start_time = now
			t.signup_deadline = mini(int(t.signup_deadline), now)
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
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status != "open":
		return "Påmeldingen er ikke åpen."
	if now >= int(t.signup_deadline):
		return "Påmeldingsfristen er ute."
	if uid in t.players:
		return ""
	if t.players.size() >= int(t.max_players):
		return "Turneringen er full."
	t.players.append(uid)
	_save(t)
	return ""


func leave(id: int, uid: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status != "open":
		return "Du kan ikke melde deg av etter start."
	t.players.erase(uid)
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
		if t.status == "open" and now >= int(t.start_time):
			_start(t, now)
			_save(t)
		if t.status == "running":
			if _tick_round(t, now):
				_save(t)


func _start(t: Dictionary, now: int) -> void:
	if t.players.size() < 2:
		t.status = "cancelled"
		_notify_all(t, "Turneringen «%s» ble avlyst (for få deltakere).", [t.name])
		return
	t.status = "running"
	var seeds: Array = t.players.duplicate()
	seeds.shuffle()
	seeds.sort_custom(func(a: int, b: int) -> bool: return _elo(a) > _elo(b))
	t.rounds = []
	if t.format == "round_robin":
		var rounds := _round_robin(seeds)
		if int(t.max_rounds) > 0 and rounds.size() > int(t.max_rounds):
			rounds = rounds.slice(0, int(t.max_rounds))   # admin har begrenset antall runder
		for r in rounds.size():
			var matches := []
			for i in rounds[r].size():
				matches.append(_match(t, r, i, rounds[r][i][0], rounds[r][i][1]))
			t.rounds.append(matches)
	else:
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


func _match(t: Dictionary, round_i: int, i: int, p1: int, p2: int) -> Dictionary:
	return { "id": "t%d-r%d-m%d" % [t.id, round_i, i], "round": round_i, "p1": p1, "p2": p2, "status": "pending",
		"start_at": 0, "waiting_since": 0, "room": "", "winner": 0, "reason": "", "draws": 0, "ready": [], "games": [] }


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
			m.room = open_room.call(t, m)
			m.status = "waiting"
			m.waiting_since = now
			changed = true
			for uid in [m.p1, m.p2]:
				notify.call(uid, { "t": Protocol.TOURNAMENT_NOTICE, "key": "Kampen din i «%s» starter nå!",
					"args": [t.name], "tournament": t.id, "room": m.room })
		elif m.status == "waiting" and now >= int(m.waiting_since) + int(t.show_up_s):
			var here: Array = presence.call(m.room)
			var p1_here: bool = m.p1 in here
			var p2_here: bool = m.p2 in here
			if p1_here and p2_here:
				continue
			var winner: int = m.p1 if p1_here else (m.p2 if p2_here else 0)
			close_room.call(m.room, "Motstanderen møtte ikke. Du vinner på walkover." if winner != 0 \
				else "Ingen av spillerne møtte.", [])
			_finish_match(t, m, winner, "walkover" if winner != 0 else "no_show")
			changed = true
	if t.status == "running" and _round_done(t, round_i):
		_next_round(t, now)
		changed = true
	return changed


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


## Lobbyen melder resultatet av et parti i en turneringskamp.
## winner_uid = 0 og draw = true for uavgjort. Gir "replay" hvis kampen skal spilles om.
func report(match_id: String, winner_uid: int, draw: bool, now: int) -> String:
	var found := _find_match(match_id)
	if found.is_empty():
		return ""
	var t: Dictionary = found.t
	var m: Dictionary = found.m
	if m.status == "done":
		return ""
	if draw:
		m.draws += 1
		if t.format == "knockout":
			if m.draws < MAX_REPLAYS:
				_save(t)
				return "replay"
			# Etter flere uavgjorte går den med høyest Elo videre.
			winner_uid = m.p1 if _elo(m.p1) >= _elo(m.p2) else m.p2
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
		if round_i + 1 < t.rounds.size():
			t.current_round = round_i + 1
			_schedule_round(t, round_i + 1, start_at)
			if _round_done(t, round_i + 1):
				_next_round(t, now)
		else:
			var table := standings(t)
			_finish(t, int(table[0].id) if not table.is_empty() else 0, now)
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
		var unlocked := ", ".join((r.unlocked as Array).map(func(item: String) -> String: return Progression.item_name(item)))
		var key := "Du fikk %d XP for «%s». Låst opp: %s!" if unlocked != "" else "Du fikk %d XP for «%s»."
		var args: Array = [int(r.gained), t.name, unlocked] if unlocked != "" else [int(r.gained), t.name]
		notify.call(int(uid), { "t": Protocol.NOTICE, "key": key, "args": args, "text": key % args })
		notify.call(int(uid), { "t": Protocol.STATS, "user": accounts.public_info(u) })
	store.save_users()


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


## Tabell for alle-mot-alle: seier 1 poeng, uavgjort ½ (lagret som 2 og 1 for å unngå desimaler).
func standings(t: Dictionary) -> Array:
	var rows := {}
	for uid in t.players:
		rows[uid] = { "id": uid, "username": accounts.username_of(uid), "elo": _elo(uid), "points2": 0, "wins": 0,
			"draws": 0, "losses": 0 }
	for round in t.rounds:
		for m in round:
			if m.status != "done" or m.reason == "bye" or m.p1 == 0 or m.p2 == 0:
				continue
			if m.winner == 0:
				if m.reason == "draw":
					for uid in [m.p1, m.p2]:
						rows[uid].points2 += 1
						rows[uid].draws += 1
				continue
			var loser: int = m.p2 if m.winner == m.p1 else m.p1
			rows[m.winner].points2 += 2
			rows[m.winner].wins += 1
			rows[loser].losses += 1
	var out := rows.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.points2 != b.points2:
			return a.points2 > b.points2
		if a.wins != b.wins:
			return a.wins > b.wins
		return _elo(a.id) > _elo(b.id)
	)
	return out


# ---------------------------------------------------------------- Til klienten

## Kort versjon til listen.
func summary(t: Dictionary) -> Dictionary:
	return { "id": t.id, "name": t.name, "format": t.format, "status": t.status, "start_time": t.start_time,
		"players": t.players.size(), "max_players": t.max_players, "max_rounds": int(t.get("max_rounds", 0)),
		"options": t.options,
		"winner": accounts.username_of(t.winner) if int(t.winner) != 0 else "", "trophy": t.trophy,
		"finished_at": int(t.get("finished_at", 0)), "ranked": t.ranked, "with_trophy": t.with_trophy,
		"final_game": final_game(t), "prize": str(t.get("prize", "")) }


## Det siste partiet i finalen (utslag, når turneringen er ferdig), til «Se finalen». 0 = ingen.
static func final_game(t: Dictionary) -> int:
	if t.status != "finished" or t.format != "knockout" or (t.rounds as Array).is_empty():
		return 0
	var last: Array = t.rounds[-1]
	if last.size() != 1 or (last[0].get("games", []) as Array).is_empty():
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
		return { "id": uid, "username": accounts.username_of(uid), "elo": _elo(uid) }
	)
	out.rounds = t.rounds.map(func(r: Array) -> Array:
		return r.map(func(m: Dictionary) -> Dictionary:
			var pm := { "id": m.id, "p1": m.p1, "p2": m.p2, "p1_name": _name_or_dash(m.p1), "p2_name": _name_or_dash(m.p2),
				"status": m.status, "start_at": m.start_at, "room": m.room, "winner": m.winner, "reason": m.reason,
				"games": m.get("games", []) }
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


func _name_or_dash(uid: int) -> String:
	return accounts.username_of(uid) if uid != 0 else "—"


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
