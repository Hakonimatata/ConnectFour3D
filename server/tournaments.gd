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
var rng := RandomNumberGenerator.new()


func _init(p_store: Store, p_accounts: Accounts) -> void:
	store = p_store
	accounts = p_accounts
	rng.randomize()
	for t in store.tournaments:
		normalize(t)


## JSON gir desimaltall. Gjør tall om til heltall igjen etter innlesing fra fil.
static func normalize(t: Dictionary) -> void:
	for k in ["id", "current_round", "winner", "created_by", "created_at", "max_players", "start_time",
			"signup_deadline", "round_gap_s", "show_up_s"]:
		t[k] = int(t.get(k, 0))
	t.players = (t.get("players", []) as Array).map(func(v: Variant) -> int: return int(v))
	for round in t.get("rounds", []):
		for m in round:
			for k in ["round", "p1", "p2", "start_at", "waiting_since", "winner", "draws"]:
				m[k] = int(m.get(k, 0))


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
	store.save_tournaments()
	return t


## Endrer navn, regler og tider. Bare før turneringen har startet.
func update(id: int, data: Dictionary, now: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if not t.status in ["draft", "open"]:
		return "Turneringen har allerede startet."
	_apply(t, data, now)
	store.save_tournaments()
	return ""


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
	t.start_time = maxi(int(d.get("start_time", t.get("start_time", now + 600))), now)
	t.signup_deadline = mini(int(d.get("signup_deadline", t.get("signup_deadline", t.start_time))), t.start_time)
	t.round_gap_s = clampi(int(d.get("round_gap_s", t.get("round_gap_s", 120))), 0, 3600)
	t.show_up_s = clampi(int(d.get("show_up_s", t.get("show_up_s", 300))), 30, 1800)


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
	store.save_tournaments()
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
	store.save_tournaments()
	return ""


func leave(id: int, uid: int) -> String:
	var t := get_t(id)
	if t.is_empty():
		return "Fant ikke turneringen."
	if t.status != "open":
		return "Du kan ikke melde deg av etter start."
	t.players.erase(uid)
	store.save_tournaments()
	return ""


# ---------------------------------------------------------------- Tid

func tick(now: int) -> void:
	for t in store.tournaments.duplicate():
		if t.status == "open" and now >= int(t.start_time):
			_start(t, now)
			store.save_tournaments()
		if t.status == "running":
			if _tick_round(t, now):
				store.save_tournaments()


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
		"start_at": 0, "waiting_since": 0, "room": "", "winner": 0, "reason": "", "draws": 0 }


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
		store.save_tournaments()


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
				store.save_tournaments()
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
	store.save_tournaments()
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
			_finish(t, int(table[0].id) if not table.is_empty() else 0)
		return
	var winners: Array = t.rounds[round_i].map(func(m: Dictionary) -> int: return int(m.winner))
	if winners.size() == 1:
		_finish(t, winners[0])
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


func _finish(t: Dictionary, winner: int) -> void:
	t.status = "finished"
	t.winner = winner
	if winner != 0 and store.users.has(winner):
		store.users[winner].stats.tournaments_won += 1
		store.save_users()
		_notify_all(t, "«%s» er ferdig. Vinner: %s!", [t.name, accounts.username_of(winner)])
	else:
		_notify_all(t, "«%s» er ferdig.", [t.name])


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
		"players": t.players.size(), "max_players": t.max_players, "options": t.options,
		"winner": accounts.username_of(t.winner) if int(t.winner) != 0 else "" }


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
			return { "id": m.id, "p1": m.p1, "p2": m.p2, "p1_name": _name_or_dash(m.p1), "p2_name": _name_or_dash(m.p2),
				"status": m.status, "start_at": m.start_at, "room": m.room, "winner": m.winner, "reason": m.reason }
		)
	)
	if t.format == "round_robin" and t.status in ["running", "finished"]:
		out.standings = standings(t)
	return out


func _name_or_dash(uid: int) -> String:
	return accounts.username_of(uid) if uid != 0 else "—"


# ---------------------------------------------------------------- Hjelpere

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
