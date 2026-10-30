extends TestCase
## Tester XP, nivåer og opplåsing (core/progression.gd og serveren, runde 17).

const LONG_GAME := [[0, 0], [3, 3], [1, 0], [3, 2], [0, 3], [2, 3], [1, 2], [2, 2], [2, 0], [1, 3], [3, 0]]   ## 11 trekk, spiller 1 vinner
const SHORT_GAME := [[0, 0], [3, 3], [1, 0], [3, 2], [2, 0], [2, 3], [3, 0]]   ## 7 trekk

var lobby: Lobby
var _inbox := {}
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
	lobby.on_message(peer, msg, 1000)


func _last(peer: int, t: String) -> Dictionary:
	var list: Array = _inbox.get(peer, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].t == t:
			return list[i]
	return {}


func _user(peer: int, name: String) -> Dictionary:
	_msg(peer, { "t": "hello", "name": name, "skin": "ocean", "version": Protocol.VERSION })
	_msg(peer, { "t": "register", "username": name, "password": "hemmelig123" })
	return lobby.store.find_user(name)


## Ada (peer 1, starter) og Bobo (peer 2) spiller et parti med trekkene. Gir game_over til Ada.
func _play(moves: Array) -> Dictionary:
	_msg(1, { "t": "create_room", "options": { "must_block": false, "no_gift": false }, "private": true })
	_msg(2, { "t": "join_room", "code": _last(1, "room_state").code })
	_msg(1, { "t": "ready", "ready": true })
	_msg(2, { "t": "ready", "ready": true })
	for i in moves.size():
		_msg(1 if i % 2 == 0 else 2, { "t": "move", "x": moves[i][0], "y": moves[i][1], "ply": i })
	var over := _last(1, "game_over")
	_msg(1, { "t": "leave_room" })
	_msg(2, { "t": "leave_room" })
	return over


func test_levels_and_rewards() -> void:
	check_eq(Progression.level_for(0), 1)
	check_eq(Progression.level_for(99), 1)
	check_eq(Progression.level_for(100), 2)
	check_eq(Progression.xp_for_level(10), 2700)
	check_eq(Progression.level_for(2700), 10)
	check(Progression.game_xp(1.0, 1200, 1600) > Progression.game_xp(1.0, 1200, 1200), "mer for å slå en sterkere")
	check(Progression.game_xp(1.0, 1200, 800) >= 20, "litt for å slå en svakere")
	check_eq(Progression.game_xp(0.5, 1200, 1200), 15)
	check_eq(Progression.game_xp(0.0, 1200, 1200), 8)
	check_eq(Progression.puzzle_xp(1), 25)
	check_eq(Progression.puzzle_xp(5), 45, "rekken gir mer")
	check_eq(Progression.puzzle_xp(100), 75, "men høyst +50")


func test_unlocks_by_level_achievement_and_prize() -> void:
	var guest := {}
	check(Progression.is_unlocked("skin:ocean", guest), "standard er åpen")
	check(not Progression.is_unlocked("skin:lava", guest), "lava krever nivå")
	check(Progression.is_unlocked("skin:lava", { "xp": Progression.xp_for_level(10) }))
	check(not Progression.is_unlocked("skin:champion", { "xp": 1_000_000 }), "turneringsskin krever turneringsseier")
	check(Progression.is_unlocked("skin:champion", { "tournaments_won": 1 }))
	check(Progression.is_unlocked("skin:dawn", { "best_puzzle_streak": 7 }))
	check(Progression.is_unlocked("skin:blackhole", { "unlocks": ["skin:blackhole"] }), "premie")
	var look := Progression.allowed_look({ "skin": "lava", "win_fx": "chaos" }, guest)
	check_eq(look.skin, Skins.DEFAULT_P1)
	check_eq(look.win_fx, "classic")
	check_eq(Progression.newly_unlocked({ "xp": 0 }, { "xp": Progression.xp_for_level(3) }), ["skin:gold", "skin:ceramic", "fx:fireworks"] as Array[String])
	for item in Progression.UNLOCKS:
		check(item in Progression.items(), "%s finnes" % item)


## Kontoer fra før XP får XP fra statistikken og beholder det de bruker.
func test_existing_accounts_get_xp_and_keep_their_look() -> void:
	var u := Store.normalize_user({ "id": 7, "username": "Gammel", "stats": { "wins": 10, "losses": 5, "puzzles_solved": 2 },
		"profile": { "skin": "blackhole", "win_fx": "fireworks" } })
	check_eq(int(u.xp), 10 * 30 + 5 * 8 + 2 * 25)
	check("skin:blackhole" in u.unlocks, "beholder skinen")
	check(not "fx:fireworks" in u.unlocks, "fyrverkeri er allerede låst opp av nivået")
	var again := Store.normalize_user(u)
	check_eq(again.xp, u.xp, "regnes ikke på nytt")


## Partier mellom to kontoer gir XP. For korte partier, og for mange mot samme motstander samme dag, gir ikke.
func test_games_give_xp_with_limits() -> void:
	var ada := _user(1, "Ada")
	var bo := _user(2, "Bobo")
	var over := _play(LONG_GAME)
	check_eq(int(over.winner), 1)
	var gained := int(over.xp["1"].gained)
	check(gained >= 30, "seier mot like god: %d" % gained)
	check_eq(int(over.xp["2"].gained), 8, "tap")
	check_eq(int(ada.xp), gained)
	check_eq(int(_last(1, "stats").user.xp), gained, "klienten får den nye progresjonen")
	var short := _play(SHORT_GAME)
	check(not short.xp.has("1"), "for kort parti gir ingenting")
	_play(LONG_GAME)
	_play(LONG_GAME)
	var fourth := _play(LONG_GAME)
	check_eq(int(fourth.xp["1"].gained), 0, "fjerde parti mot samme motstander samme dag")
	unix += 86400
	var next_day := _play(LONG_GAME)
	check(int(next_day.xp["1"].gained) > 0, "ny dag")
	check_eq(int(bo.xp_day.opponents[str(ada.id)]), 1)


## Dagens oppgave gir XP, mer for hver dag på rad. 7 dager på rad låser opp en egen skin.
func test_daily_puzzle_xp_and_streak_unlock() -> void:
	var ada := _user(1, "Ada")
	ada.stats.puzzle_streak = 6
	ada.stats.best_puzzle_streak = 6
	ada.last_puzzle = Puzzles.day_of(unix - 86400)
	var p := lobby.puzzles.today(unix).puzzle as Dictionary
	_msg(1, { "t": "puzzle_solve", "day": p.day, "moves": _solution(p), "attempts": 1 })
	var r := _last(1, "puzzle_result")
	check(bool(r.ok), str(r))
	check_eq(int(r.xp.gained), Progression.puzzle_xp(7))
	check("skin:dawn" in r.xp.unlocked, "7 dager på rad låser opp Morgengry")


## Angriperens trekk i løsningen.
func _solution(p: Dictionary) -> Array:
	var sol := Puzzle.solution(p)
	if str(p.get("kind", "forced")) == "defend":
		return [[sol[0].x, sol[0].y]]
	var out := []
	for i in range(0, sol.size(), 2):
		out.append([sol[i].x, sol[i].y])
	return out
