class_name Accounts
extends RefCounted
## Brukerkontoer: registrering, innlogging, økter, profil, statistikk og Elo.
## Dataene ligger i Store (users.json m.fl.). Se Plan.md, seksjon 13.3 og 13.4.

const START_ELO := 1200
const ELO_K := 32
const SESSION_DAYS := 90
const MAX_FAILURES := 5            ## feilede innlogginger før pause
const FAILURE_WINDOW_S := 600      ## ... innenfor 10 minutter
const MAX_FRIENDS := 200
const USERNAME_RE :="^[A-Za-z0-9_æøåÆØÅ-]{3,16}$"
const GUEST_DAYS := 14             ## gjestekontoer som ikke er brukt så lenge, slettes
const GUEST_PER_HOUR := 200        ## nye gjestekontoer i timen, totalt (ikke per IP: mange deler nett)
const GUEST_NAME_MAX := 14         ## kallenavnet til en gjest (plass til et tall bak hvis det er tatt)

var store: Store
var iterations := Password.ITERATIONS   ## testene bruker færre runder for fart
var _failures: Dictionary = {}          ## brukernavn (små bokstaver) -> [tidspunkter]
var _guest_times: Array = []            ## når de siste gjestekontoene ble laget (unix-s)
var _username_re := RegEx.create_from_string(USERNAME_RE)
var _crypto := Crypto.new()


func _init(p_store: Store) -> void:
	store = p_store


# ---------------------------------------------------------------- Innlogging

## Gir { user } eller { error } (norsk tekst som klienten oversetter).
func register(username: String, password: String) -> Dictionary:
	username = username.strip_edges()
	if _username_re.search(username) == null:
		return { "error": "Brukernavnet må være 3–16 tegn (bokstaver, tall, - og _)." }
	if password.length() < Password.MIN_LENGTH:
		return { "error": "Passordet må ha minst 8 tegn." }
	if not store.find_user(username).is_empty():
		return { "error": "Brukernavnet er tatt." }
	var u := store.add_user(username, Password.make(password, iterations))
	return { "user": u }


func login(username: String, password: String, now_s: int) -> Dictionary:
	var key := username.strip_edges().to_lower()
	var recent: Array = _failures.get(key, []).filter(func(t: int) -> bool: return now_s - t < FAILURE_WINDOW_S)
	_failures[key] = recent
	if recent.size() >= MAX_FAILURES:
		return { "error": "For mange forsøk. Vent noen minutter og prøv igjen." }
	var u := store.find_user(username)
	if u.is_empty() or not Password.verify(password, u.password):
		recent.append(now_s)
		return { "error": "Feil brukernavn eller passord." }
	_failures.erase(key)
	if u.banned:
		return banned_error(u)
	return { "user": u }


## Bytter brukernavn (det man logger inn med og vises med). Samme krav som ved registrering, og høyst
## ett bytte per Protocol.RENAME_DAYS dager (det første byttet går alltid). Store bokstaver kan rettes
## når som helst. Det gamle navnet huskes (old_names), men er ledig for andre. Gir { user } eller
## { error, args }.
func rename(user_id: int, username: String, now_s: int) -> Dictionary:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty():
		return { "error": "Du må logge inn først.", "args": [] }
	username = username.strip_edges()
	if _username_re.search(username) == null:
		return { "error": "Brukernavnet må være 3–16 tegn (bokstaver, tall, - og _).", "args": [] }
	if username == str(u.username):
		return { "error": "Det er allerede brukernavnet ditt.", "args": [] }
	var other := store.find_user(username)
	if not other.is_empty() and int(other.id) != user_id:
		return { "error": "Brukernavnet er tatt.", "args": [] }
	var only_case := username.to_lower() == str(u.username).to_lower()
	var wait_s := int(u.renamed_at) + Protocol.RENAME_DAYS * 86400 - now_s
	if not only_case and not u.guest and int(u.renamed_at) > 0 and wait_s > 0:   # gjester kan rette kallenavnet fritt
		return { "error": "Du kan bytte brukernavn igjen om %d dager.", "args": [ceili(wait_s / 86400.0)] }
	if not only_case:
		var now_name := str(u.username)
		var old: Array = (u.old_names as Array).filter(func(n: String) -> bool:
			return n.to_lower() != now_name.to_lower() and n.to_lower() != username.to_lower())
		old.append(now_name)
		u.old_names = old.slice(maxi(0, old.size() - 5))
		u.renamed_at = now_s
	u.username = username
	store.save_users()
	return { "user": u }


## Feilmeldingen en utestengt bruker får (med grunnen hvis admin skrev en).
static func banned_error(u: Dictionary) -> Dictionary:
	if str(u.get("ban_reason", "")) != "":
		return { "error": "Kontoen din er utestengt. Grunn: %s", "args": [str(u.ban_reason)] }
	return { "error": "Kontoen din er utestengt.", "args": [] }


## Lager en ny økt og gir nøkkelen (bare en hash lagres på serveren).
func create_session(user_id: int, now_s: int) -> String:
	var token := _crypto.generate_random_bytes(24).hex_encode()
	store.sessions[_hash(token)] = { "user": user_id, "created": now_s }
	store.save_sessions()
	return token


func user_for_session(token: String, now_s: int) -> Dictionary:
	if token == "":
		return {}
	var s: Dictionary = store.sessions.get(_hash(token), {})
	if s.is_empty() or now_s - int(s.created) > SESSION_DAYS * 86400:
		return {}
	return store.users.get(int(s.user), {})


func end_session(token: String) -> void:
	if store.sessions.erase(_hash(token)):
		store.save_sessions()


func set_admin(username: String, on: bool) -> bool:
	var u := store.find_user(username)
	if u.is_empty():
		return false
	u.admin = on
	store.save_users()
	return true


func is_admin(user_id: int) -> bool:
	return user_id != 0 and bool(store.users.get(user_id, {}).get("admin", false))


## Alle med konto (ikke gjester) kan lage private turneringer og styre sine egne. Admin lager også offentlige.
func can_create_tournament(user_id: int) -> bool:
	var u: Dictionary = store.users.get(user_id, {})
	return not u.is_empty() and not bool(u.guest)


func is_guest(user_id: int) -> bool:
	return bool(store.users.get(user_id, {}).get("guest", false))


## Gjestekonto til en privat turnering: bare et kallenavn, uten passord. Er navnet tatt, får det et tall
## bak («Ada2»). Gjestekontoer kan ikke logge inn med passord, får ikke bilde, venner eller XP, kommer
## ikke på topplister, og slettes når de ikke har vært brukt på GUEST_DAYS dager (remove_stale_guests).
## Gir { user } eller { error }.
func create_guest(nickname: String, now_s: int) -> Dictionary:
	var base := nickname.strip_edges().replace(" ", "_")
	if base.length() > GUEST_NAME_MAX or _username_re.search(base) == null:
		return { "error": "Kallenavnet må være 3–14 tegn (bokstaver, tall, - og _)." }
	_guest_times = _guest_times.filter(func(t: int) -> bool: return now_s - t < 3600)
	if _guest_times.size() >= GUEST_PER_HOUR:
		return { "error": "For mange nye gjester akkurat nå. Prøv igjen om litt." }
	_guest_times.append(now_s)
	var name := base
	var n := 2
	while not store.find_user(name).is_empty():
		name = "%s%d" % [base, n]
		n += 1
	var u := store.add_user(name, {})
	u.guest = true
	u.last_seen = now_s
	store.save_users()
	return { "user": u }


## Sletter gjestekontoer som ikke har vært brukt på GUEST_DAYS dager, unntatt dem i keep (id -> true:
## med i en turnering som ikke er ferdig). Gir antallet.
func remove_stale_guests(now_s: int, keep: Dictionary) -> int:
	var gone := []
	for u: Dictionary in store.users.values():
		if u.guest and now_s - int(u.last_seen) > GUEST_DAYS * 86400 and not keep.has(int(u.id)):
			gone.append(int(u.id))
	for id in gone:
		store.users.erase(id)
		end_sessions_of(id)
	if not gone.is_empty():
		store.save_users()
	return gone.size()


# ---------------------------------------------------------------- Venner

## Venneforespørsel fra en bruker til en annen. Har den andre allerede spurt deg, blir dere venner.
## Gir { state: "requested" | "friends", user } eller { error }.
func friend_request(from_id: int, to_username: String) -> Dictionary:
	var me: Dictionary = store.users.get(from_id, {})
	var other := store.find_user(to_username)
	if me.is_empty() or other.is_empty():
		return { "error": "Fant ikke brukeren %s." }
	if me.guest or other.guest:
		return { "error": "Gjester kan ikke ha venner." }
	if int(other.id) == from_id:
		return { "error": "Du kan ikke legge til deg selv." }
	if int(other.id) in me.friends:
		return { "error": "Dere er allerede venner." }
	if me.friends.size() >= MAX_FRIENDS or other.friends.size() >= MAX_FRIENDS:
		return { "error": "Vennelisten er full." }
	if int(other.id) in me.friend_requests:
		_make_friends(me, other)
		return { "state": "friends", "user": other }
	if not from_id in other.friend_requests:
		other.friend_requests.append(from_id)
		store.save_users()
	return { "state": "requested", "user": other }


## Godtar en forespørsel fra username. Gir den andre brukeren, eller {} hvis det ikke fantes en forespørsel.
func friend_accept(user_id: int, username: String) -> Dictionary:
	var me: Dictionary = store.users.get(user_id, {})
	var other := store.find_user(username)
	if me.is_empty() or other.is_empty() or not int(other.id) in me.friend_requests:
		return {}
	_make_friends(me, other)
	return other


func friend_decline(user_id: int, username: String) -> void:
	var me: Dictionary = store.users.get(user_id, {})
	var other := store.find_user(username)
	if not me.is_empty() and not other.is_empty() and me.friend_requests.has(int(other.id)):
		me.friend_requests.erase(int(other.id))
		store.save_users()


func friend_remove(user_id: int, username: String) -> void:
	var me: Dictionary = store.users.get(user_id, {})
	var other := store.find_user(username)
	if me.is_empty() or other.is_empty():
		return
	me.friends.erase(int(other.id))
	other.friends.erase(user_id)
	store.save_users()


func _make_friends(a: Dictionary, b: Dictionary) -> void:
	for pair in [[a, b], [b, a]]:
		var x: Dictionary = pair[0]
		var y: Dictionary = pair[1]
		x.friend_requests.erase(int(y.id))
		if not int(y.id) in x.friends:
			x.friends.append(int(y.id))
	store.save_users()


# ---------------------------------------------------------------- Admin: utestenging og pokaler

## Utestenger en bruker: kan ikke logge inn, og alle øktene slettes. Gir "" eller en feilmelding.
func ban(username: String, reason: String) -> String:
	var u := store.find_user(username)
	if u.is_empty():
		return "Fant ikke brukeren %s."
	if u.admin:
		return "Du kan ikke utestenge en admin."
	u.banned = true
	u.ban_reason = reason.strip_edges().substr(0, 200)
	store.save_users()
	end_sessions_of(int(u.id))
	return ""


func unban(username: String) -> String:
	var u := store.find_user(username)
	if u.is_empty():
		return "Fant ikke brukeren %s."
	u.banned = false
	u.ban_reason = ""
	store.save_users()
	return ""


func is_banned(user_id: int) -> bool:
	return bool(store.users.get(user_id, {}).get("banned", false))


## Utestengte brukere til admin-siden: [{ username, reason }].
func banned_list() -> Array:
	var out := []
	for u in store.users.values():
		if u.banned:
			out.append({ "username": u.username, "reason": u.ban_reason })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.username.naturalnocasecmp_to(b.username) < 0)
	return out


func end_sessions_of(user_id: int) -> void:
	var changed := false
	for k in store.sessions.keys():
		if int(store.sessions[k].user) == user_id:
			store.sessions.erase(k)
			changed = true
	if changed:
		store.save_sessions()


## Legger en pokal til på brukeren (vises på profilen). Nyeste først.
func award_trophy(user_id: int, entry: Dictionary) -> bool:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty():
		return false
	u.trophies.push_front(Trophy.normalize_entry(entry))
	if u.trophies.size() > Trophy.MAX_PER_USER:
		u.trophies.resize(Trophy.MAX_PER_USER)
	store.save_users()
	return true


## Utseendet (skin, merke, farge på merket, drakt, seiersanimasjon) hører til kontoen. Det lagres når
## det endres, og enheten får det ved innlogging (se Lobby._sign_in).
func update_profile(user_id: int, look: Dictionary) -> void:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty():
		return
	var profile := { "skin": str(look.skin), "decal": str(look.decal), "win_fx": str(look.win_fx),
		"decal_color": str(look.decal_color), "away": bool(look.away),
		"avatar_removed": bool(u.profile.get("avatar_removed", false)) }
	if u.profile != profile:
		u.profile = profile
		store.save_users()


## Profilbildet hører til kontoen, så det er det samme på alle enheter. "" = fjernet.
func set_avatar(user_id: int, avatar: String) -> void:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty() or u.guest:   # gjester har ikke bilde
		return
	if bool(u.profile.get("avatar_removed", false)) != (avatar == ""):
		u.profile.avatar_removed = avatar == ""
		store.save_users()
	if store.avatars.get(user_id, "") != avatar:
		if avatar == "":
			store.avatars.erase(user_id)
		else:
			store.avatars[user_id] = avatar
		store.save_avatars()


## Bildet etter innlogging. Har kontoen et bilde, vinner det (samme bilde på alle enheter).
## Har den ikke, tas enhetens bilde (første gang), med mindre brukeren har fjernet bildet sitt.
func avatar_on_sign_in(user_id: int, device_avatar: String) -> String:
	if is_guest(user_id):
		return ""
	var stored: String = store.avatars.get(user_id, "")
	if stored != "":
		return stored
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty() or bool(u.profile.get("avatar_removed", false)):
		return ""
	if device_avatar != "":
		set_avatar(user_id, device_avatar)
	return device_avatar


## Brukere med navn som inneholder teksten, de som begynner med den først (søket etter spillere).
func search(query: String, limit := 10) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return []
	var hits := []
	for u: Dictionary in store.users.values():
		if not u.banned and not u.guest and str(u.username).to_lower().contains(q):
			hits.append(u)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := str(a.username).to_lower().begins_with(q)
		var pb := str(b.username).to_lower().begins_with(q)
		if pa != pb:
			return pa
		return str(a.username).naturalnocasecmp_to(str(b.username)) < 0
	)
	return hits.slice(0, limit)


func username_of(user_id: int) -> String:
	return str(store.users.get(user_id, {}).get("username", "?"))


## Det andre spillere og klienten får se om en bruker (aldri passord).
func public_info(u: Dictionary) -> Dictionary:
	if u.is_empty():
		return {}
	return { "id": u.id, "username": u.username, "admin": u.admin, "elo": u.elo, "stats": u.stats,
		"trophies": u.trophies, "xp": int(u.get("xp", 0)), "level": Progression.level_for(int(u.get("xp", 0))),
		"unlocks": u.get("unlocks", []), "guest": bool(u.get("guest", false)) }


# ---------------------------------------------------------------- XP (runde 17, se core/progression.gd)

## Gir brukeren XP. Gir { gained, xp, level, level_before, unlocked: [ting] } (til klienten).
## before: progresjonen før det som skjedde (f.eks. før rekken på dagens oppgave økte), så det som
## ble låst opp av prestasjonen også kommer med.
func add_xp(u: Dictionary, gained: int, before := {}) -> Dictionary:
	if before.is_empty():
		before = Progression.progress_of(u)
	u.xp = int(u.get("xp", 0)) + maxi(0, gained)
	var after := Progression.progress_of(u)
	return { "gained": maxi(0, gained), "xp": u.xp, "level": Progression.level_for(u.xp),
		"level_before": Progression.level_for(int(before.xp)), "unlocked": Progression.newly_unlocked(before, after) }


## Låser opp en ting (premie i en turnering). Gir true hvis den ikke var låst opp fra før.
func unlock(u: Dictionary, item: String) -> bool:
	if item == "" or Progression.is_unlocked(item, Progression.progress_of(u)):
		return false
	(u.unlocks as Array).append(item)
	return true


## XP etter et parti mellom to kontoer (ids som i record_game). elo = endringene fra record_game (for
## Elo-en før partiet). Se Progression: minst MIN_MOVES trekk, høyst SAME_OPPONENT_DAILY partier mot
## samme motstander per dag, og høyst DAILY_GAME_XP per dag fra partier.
## Gir { sete: add_xp-resultatet } for dem som fikk (eller kunne fått) XP.
func award_game_xp(ids: Array, result: int, move_count: int, elo: Dictionary, now_s: int) -> Dictionary:
	var out := {}
	var users := [{}, store.users.get(int(ids[1]), {}), store.users.get(int(ids[2]), {})]
	if users[1].is_empty() or users[2].is_empty() or int(ids[1]) == int(ids[2]) or move_count < Progression.MIN_MOVES \
			or users[1].guest or users[2].guest:   # gjestekontoer er lette å lage, så ingen XP mot dem
		return out
	for seat in [1, 2]:
		var me: Dictionary = users[seat]
		var opp: Dictionary = users[3 - seat]
		var my_elo := int(elo[seat].before) if elo.has(seat) else int(me.elo)
		var opp_elo := int(elo[3 - seat].before) if elo.has(3 - seat) else int(opp.elo)
		var score := 0.5 if result == 0 else (1.0 if result == seat else 0.0)
		var gained := Progression.game_xp(score, my_elo, opp_elo)
		var d := _xp_day(me, now_s)
		var key := str(opp.id)
		var played := int(d.opponents.get(key, 0))
		d.opponents[key] = played + 1
		if played >= Progression.SAME_OPPONENT_DAILY:
			gained = 0
		gained = mini(gained, maxi(0, Progression.DAILY_GAME_XP - int(d.games)))
		d.games = int(d.games) + gained
		out[seat] = add_xp(me, gained)
	store.save_users()
	return out


## XP for å møte opp til start i en turnering (Progression.SHOW_UP_XP). Ikke til gjester, og fra
## urangerte turneringer (som alle med konto kan lage) høyst UNRANKED_SHOW_UP_DAILY per dag.
## Gir add_xp-resultatet, eller {} hvis hen ikke fikk noe. Den som kaller, lagrer.
func award_show_up_xp(user_id: int, ranked: bool, now_s: int) -> Dictionary:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty() or u.guest:
		return {}
	if not ranked:
		var d := _xp_day(u, now_s)
		if int(d.show_ups) >= Progression.UNRANKED_SHOW_UP_DAILY:
			return {}
		d.show_ups = int(d.show_ups) + 1
	return add_xp(u, Progression.SHOW_UP_XP)


## Dagens XP-tellere på kontoen (xp_day), nullstilt når det har blitt en ny dag.
func _xp_day(u: Dictionary, now_s: int) -> Dictionary:
	var d: Dictionary = u.xp_day
	var day := Puzzles.day_of(now_s)
	if d.day != day:
		d.day = day
		d.games = 0
		d.show_ups = 0
		d.opponents = {}
	return d


# ---------------------------------------------------------------- Statistikk og Elo

## Registrerer et ferdig parti. ids: [_, bruker i sete 1, bruker i sete 2] (0 = gjest).
## result: 1 eller 2 = vinner, 0 = uavgjort. analysis fra GameAnalysis.
## Elo endres bare når begge er innlogget (og ikke i en uranket turnering, ranked = false).
## Gir { 1: { before, after }, 2: ... } for kontoene.
func record_game(ids: Array, result: int, reason: int, analysis: Dictionary, move_count: int, ranked := true) -> Dictionary:
	var changes := {}
	var users := [{}, store.users.get(int(ids[1]), {}), store.users.get(int(ids[2]), {})]
	var rated: bool = ranked and not users[1].is_empty() and not users[2].is_empty() and int(ids[1]) != int(ids[2])
	var new_elo := [0, 0, 0]
	if rated:
		var score1 := 0.5 if result == 0 else (1.0 if result == 1 else 0.0)
		var e1 := expected(users[1].elo, users[2].elo)
		new_elo[1] = int(round(users[1].elo + ELO_K * (score1 - e1)))
		new_elo[2] = int(round(users[2].elo + ELO_K * ((1.0 - score1) - (1.0 - e1))))
	for seat in [1, 2]:
		var u: Dictionary = users[seat]
		if u.is_empty():
			continue
		var st: Dictionary = u.stats
		var a: Dictionary = analysis.get(seat, {})
		st.games += 1
		st.forced_moves += int(a.get("forced", 0))
		st.double_threats += int(a.get("double_threats", 0))
		if result == 0:
			st.draws += 1
			st.current_streak = 0
		elif result == seat:
			st.wins += 1
			st.current_streak += 1
			st.best_streak = maxi(st.best_streak, st.current_streak)
			var own_moves := (move_count + 1) / 2
			if st.fastest_win == 0 or own_moves < st.fastest_win:
				st.fastest_win = own_moves
			st.best_forced_win = maxi(st.best_forced_win, int(a.get("winning_streak", 0)))
			match reason:
				GameState.EndReason.LINE: st.wins_line += 1
				GameState.EndReason.TIMEOUT: st.wins_time += 1
				GameState.EndReason.RESIGN: st.wins_resign += 1
				GameState.EndReason.DISCONNECT: st.wins_walkover += 1
		else:
			st.losses += 1
			st.current_streak = 0
			match reason:
				GameState.EndReason.TIMEOUT: st.losses_time += 1
				GameState.EndReason.RESIGN: st.losses_resign += 1
		if rated:
			changes[seat] = { "before": u.elo, "after": new_elo[seat] }
			u.elo = new_elo[seat]
	store.save_users()
	return changes


static func expected(rating: int, opponent: int) -> float:
	return 1.0 / (1.0 + pow(10.0, (opponent - rating) / 400.0))


## Topplister: Elo (minst ett parti), flest seire og lengste tvungne seier. Utestengte vises ikke.
func leaderboard(limit := 20) -> Dictionary:
	var listed: Array = store.users.values().filter(func(u: Dictionary) -> bool: return not u.banned and not u.guest)
	var solvers: Array = listed.filter(func(u: Dictionary) -> bool: return u.stats.puzzles_solved > 0)
	solvers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.stats.puzzles_solved != b.stats.puzzles_solved:
			return a.stats.puzzles_solved > b.stats.puzzles_solved
		return a.stats.best_puzzle_streak > b.stats.best_puzzle_streak
	)
	var all: Array = listed.filter(func(u: Dictionary) -> bool: return u.stats.games > 0)
	var row := func(u: Dictionary) -> Dictionary:
		return { "username": u.username, "elo": u.elo, "games": u.stats.games, "wins": u.stats.wins,
			"losses": u.stats.losses, "draws": u.stats.draws, "best_forced_win": u.stats.best_forced_win,
			"puzzles_solved": u.stats.puzzles_solved, "puzzle_streak": u.stats.puzzle_streak }
	var by_elo := all.duplicate()
	by_elo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.elo > b.elo)
	var by_wins := all.duplicate()
	by_wins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.stats.wins > b.stats.wins)
	var by_forced := all.filter(func(u: Dictionary) -> bool: return u.stats.best_forced_win > 0)
	by_forced.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.stats.best_forced_win > b.stats.best_forced_win
	)
	return {
		"elo": by_elo.slice(0, limit).map(row),
		"wins": by_wins.slice(0, limit).map(row),
		"forced": by_forced.slice(0, limit).map(row),
		"puzzles": solvers.slice(0, limit).map(row),
	}


func _hash(token: String) -> String:
	return token.sha256_text()
