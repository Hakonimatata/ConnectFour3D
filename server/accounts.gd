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

var store: Store
var iterations := Password.ITERATIONS   ## testene bruker færre runder for fart
var _failures: Dictionary = {}          ## brukernavn (små bokstaver) -> [tidspunkter]
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


# ---------------------------------------------------------------- Venner

## Venneforespørsel fra en bruker til en annen. Har den andre allerede spurt deg, blir dere venner.
## Gir { state: "requested" | "friends", user } eller { error }.
func friend_request(from_id: int, to_username: String) -> Dictionary:
	var me: Dictionary = store.users.get(from_id, {})
	var other := store.find_user(to_username)
	if me.is_empty() or other.is_empty():
		return { "error": "Fant ikke brukeren %s." }
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


## Utseendet (skin, merke, seiersanimasjon) følger siste enhet brukeren logget inn fra.
func update_profile(user_id: int, skin: String, decal: String, win_fx: String) -> void:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty():
		return
	var profile := { "skin": skin, "decal": decal, "win_fx": win_fx,
		"avatar_removed": bool(u.profile.get("avatar_removed", false)) }
	if u.profile != profile:
		u.profile = profile
		store.save_users()


## Profilbildet hører til kontoen, så det er det samme på alle enheter. "" = fjernet.
func set_avatar(user_id: int, avatar: String) -> void:
	var u: Dictionary = store.users.get(user_id, {})
	if u.is_empty():
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
		if not u.banned and str(u.username).to_lower().contains(q):
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
		"trophies": u.trophies }


# ---------------------------------------------------------------- Statistikk og Elo

## Registrerer et ferdig parti. ids: [_, bruker i sete 1, bruker i sete 2] (0 = gjest).
## result: 1 eller 2 = vinner, 0 = uavgjort. analysis fra GameAnalysis.
## Elo endres bare når begge er innlogget. Gir { 1: { before, after }, 2: ... } for kontoene.
func record_game(ids: Array, result: int, reason: int, analysis: Dictionary, move_count: int) -> Dictionary:
	var changes := {}
	var users := [{}, store.users.get(int(ids[1]), {}), store.users.get(int(ids[2]), {})]
	var rated: bool = not users[1].is_empty() and not users[2].is_empty() and int(ids[1]) != int(ids[2])
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
	var listed: Array = store.users.values().filter(func(u: Dictionary) -> bool: return not u.banned)
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
