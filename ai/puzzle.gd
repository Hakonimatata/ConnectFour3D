class_name Puzzle
extends RefCounted
## Dagens oppgave: en stilling der spilleren som har tur kan tvinge frem seier med
## N egne trekk (N ≥ 3), men ikke raskere. Laget fra datoen, så alle får samme oppgave.
##
## Løseren ser bare på «tvingende» trekk for angriperen (trekk som vinner eller lager en
## trussel), og alle lovlige svar for forsvareren. Det er akkurat det spillet kaller
## tvungne trekk, og det holder søket lite.
##
## Forsvareren i oppgaven er deterministisk (defend), så serveren kan sjekke en løsning
## ved å spille den på nytt, og klienten kan spille oppgaven uten nett.
##
## En oppgave er en Dictionary:
##   { day, options, first, moves (stillingen), player (angriperen), depth, kind? }
##
## Runde 17: dagens oppgave har tre typer (kind), etter tur dag for dag:
##   forced  «Tving frem seier»: hvert trekk må lage en trussel (som over). Lages fra datoen.
##   win     «Vinn på N trekk»: stille trekk er lov, og det finnes ingen tvungen seier med bare trusler.
##           Løsningen er entydig: line = angriperens og forsvarerens trekk etter tur (forsvareren
##           holder ut lengst mulig). Ved siste trekk godtas alle vinnertrekk.
##   defend  «Finn beste trekk»: motstanderen truer med å tvinge frem seier på depth trekk, og bare ett
##           trekk (answer) redder deg.
## win og defend er tunge å lage (eksakt søk med stille trekk), så de lages på forhånd av
## tools/make_daily_bank.gd og ligger i DailyBank. Serveren sjekker bare løsningen mot dem.

const MIN_DEPTH := 3
const MAX_DEPTH := 4
const ATTEMPTS := 400
const KINDS := ["forced", "win", "defend"]

static var _exact: SearchBot    ## eksakt søk til oppgavene med stille trekk (lages første gang)


## Typen oppgave en dag får (forced, win, defend etter tur). Andre nøkler enn datoer gir forced.
static func kind_for(day: String) -> String:
	var days := _day_number(day)
	return KINDS[days % KINDS.size()] if days >= 0 else "forced"


static func _day_number(day: String) -> int:
	var parts := day.split("-")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return -1
	return int(Time.get_unix_time_from_datetime_string(day + "T12:00:00")) / 86400


## Lager oppgaven for en dag (f.eks. "2026-10-21"). Gir {} hvis ingen ble funnet (skjer ikke i praksis).
## Dager med win eller defend tar en oppgave fra DailyBank (hver brukes én gang per runde gjennom banken).
static func generate(day: String, min_depth := MIN_DEPTH, max_depth := MAX_DEPTH) -> Dictionary:
	var kind := kind_for(day)
	if kind != "forced":
		var bank := DailyBank.PUZZLES.filter(func(p: Dictionary) -> bool: return p.get("kind") == kind)
		if not bank.is_empty():
			var p: Dictionary = (bank[(_day_number(day) / KINDS.size()) % bank.size()] as Dictionary).duplicate(true)
			p.day = day
			return p
	var rng := RandomNumberGenerator.new()
	rng.seed = day.hash()
	var options := GameOptions.new()
	for attempt in ATTEMPTS:
		var s := GameState.new(options, 1 + rng.randi() % 2)
		var plies := rng.randi_range(8, 26)
		for ply in plies:
			if s.is_over():
				break
			var legal := s.legal_moves()
			var me := s.current_player
			var wins := legal.filter(func(c: Vector2i) -> bool: return s.wins_by(c, me))
			if not wins.is_empty():
				break   # en stilling med vinnertrekk er for lett: prøv en ny
			s.play(legal[rng.randi() % legal.size()], false)
			if ply < 6 or s.is_over():
				continue
			if not s.winning_columns(GameState.opponent(s.current_player)).is_empty():
				continue   # forsvareren truer selv: uryddig oppgave
			var d := win_depth(s, max_depth)
			if d >= min_depth:
				var moves := []
				for m in s.history:
					moves.append([m.x, m.y])
				return { "day": day, "options": options.to_dict(), "first": s.first_player, "moves": moves,
					"player": s.current_player, "depth": d }
	return {}


## Stillingen i oppgaven, klar til å spilles.
static func start_state(puzzle: Dictionary) -> GameState:
	return GameState.from_moves(GameOptions.from_dict(puzzle.get("options", {})), int(puzzle.get("first", 1)),
		puzzle.get("moves", []))


## Færrest egne trekk spilleren som har tur trenger for å tvinge frem seier (høyst max_n), eller 0.
static func win_depth(s: GameState, max_n: int) -> int:
	for n in range(1, max_n + 1):
		if can_win(s, n):
			return n
	return 0


## Kan spilleren som har tur tvinge frem seier med høyst n egne trekk?
static func can_win(s: GameState, n: int) -> bool:
	return best_move(s, n) != Vector2i(-1, -1)


## Et trekk som holder på en tvungen seier med høyst n egne trekk, eller (-1, -1).
static func best_move(s: GameState, n: int) -> Vector2i:
	var me := s.current_player
	var legal := s.legal_moves()
	for col in legal:
		if s.wins_by(col, me):
			return col
	if n <= 1:
		return Vector2i(-1, -1)
	for col in legal:
		if not _creates_threat(s, col, me):
			continue
		s.play(col, false)
		var ok := _defender_loses(s, n - 1)
		s.undo()
		if ok:
			return col
	return Vector2i(-1, -1)


## Forsvarerens svar: unngå tapet hvis det går, ellers utsett det så lenge som mulig.
## Rekkefølgen er fast (legal_moves), så svaret er alltid det samme for samme stilling.
static func defend(s: GameState, max_n: int) -> Vector2i:
	var me := s.current_player
	var legal := s.legal_moves()
	var best := legal[0] if not legal.is_empty() else Vector2i(-1, -1)
	var best_score := -1
	for col in legal:
		if s.wins_by(col, me):
			return col
		s.play(col, false)
		var score := 100   # angriperen kan ikke lenger tvinge frem seier
		if not s.is_over():
			var d := win_depth(s, max_n)
			if d > 0:
				score = d
		s.undo()
		if score > best_score:
			best_score = score
			best = col
	return best


## Sjekker en løsning (angriperens trekk) ved å spille den mot forsvareren. Gir true ved seier
## innen oppgavens antall trekk. win: trekkene må følge line (siste trekk: et hvilket som helst
## vinnertrekk). defend: ett trekk, answer.
static func verify(puzzle: Dictionary, attacker_moves: Array) -> bool:
	match str(puzzle.get("kind", "forced")):
		"win":
			return _verify_line(puzzle, attacker_moves)
		"defend":
			return attacker_moves.size() == 1 and _vec(attacker_moves[0]) == _vec(puzzle.get("answer", []))
	var s := start_state(puzzle)
	var depth := int(puzzle.get("depth", MIN_DEPTH))
	if s.current_player != int(puzzle.get("player", 0)):
		return false
	for i in attacker_moves.size():
		if i >= depth:
			return false
		var m = attacker_moves[i]
		if not (m is Array and m.size() == 2):
			return false
		var col := Vector2i(int(m[0]), int(m[1]))
		if s.check_move(col) != GameState.MoveError.OK:
			return false
		var r := s.play(col)
		if r.won:
			return true
		if s.is_over():
			return false
		s.play(defend(s, depth - i - 1), false)
		if s.is_over():
			return false
	return false


static func _verify_line(puzzle: Dictionary, attacker_moves: Array) -> bool:
	var s := start_state(puzzle)
	var line: Array = puzzle.get("line", [])
	if s.current_player != int(puzzle.get("player", 0)):
		return false
	for i in attacker_moves.size():
		var col := _vec(attacker_moves[i])
		if 2 * i >= line.size() or s.check_move(col) != GameState.MoveError.OK:
			return false
		if s.play(col).won:
			return true
		if col != _vec(line[2 * i]) or s.is_over() or 2 * i + 1 >= line.size():
			return false
		s.play(_vec(line[2 * i + 1]), false)
	return false


## [x, y] eller Vector2i som Vector2i ((-1, -1) hvis ugyldig).
static func _vec(m: Variant) -> Vector2i:
	if m is Vector2i:
		return m
	if m is Array and m.size() == 2:
		return Vector2i(int(m[0]), int(m[1]))
	return Vector2i(-1, -1)


## Hele løsningen fra stillingen: angriperens trekk og forsvarerens svar, til seier.
## defend: bare trekket som redder deg.
static func solution(puzzle: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match str(puzzle.get("kind", "forced")):
		"win":
			for m in puzzle.get("line", []):
				out.append(_vec(m))
			return out
		"defend":
			out.append(_vec(puzzle.get("answer", [])))
			return out
	return _forced_solution(puzzle)


static func _forced_solution(puzzle: Dictionary) -> Array[Vector2i]:
	var s := start_state(puzzle)
	var left := int(puzzle.get("depth", MIN_DEPTH))
	var out: Array[Vector2i] = []
	while left > 0 and not s.is_over():
		var col := best_move(s, left)
		if col == Vector2i(-1, -1):
			break
		out.append(col)
		s.play(col, false)
		left -= 1
		if s.is_over():
			break
		var reply := defend(s, left)
		out.append(reply)
		s.play(reply, false)
	return out


## Lager trekket minst én vinnerplass spilleren kan nå med en gang?
static func _creates_threat(s: GameState, col: Vector2i, me: int) -> bool:
	s.place(col, me)
	var found := false
	for c in s.open_columns():
		if s.wins_by(c, me):
			found = true
			break
	s.unplace(col)
	return found


## Forsvareren har tur. Taper alle svarene innen n angrepstrekk?
static func _defender_loses(s: GameState, n: int) -> bool:
	if s.is_over():
		return false
	var defender := s.current_player
	var legal := s.legal_moves()
	for col in legal:
		if s.wins_by(col, defender):
			return false
	for col in legal:
		s.play(col, false)
		var lost := not s.is_over() and can_win(s, n)
		s.undo()
		if not lost:
			return false
	return true


# ---------------------------------------------------------------- Stille trekk (runde 17)

## Korteste seier (antall egne trekk) for spilleren som har tur, når alle trekk er lov (også stille
## trekk), innen max_n trekk. 0 = ingen. Eksakt søk, så det er den korteste som finnes.
static func quiet_win_depth(s: GameState, max_n: int) -> int:
	if s.is_over() or max_n <= 0:
		return 0
	var me := s.current_player
	for c in s.legal_moves():
		if s.wins_by(c, me):
			return 1
	if max_n == 1:
		return 0
	var m := _exact_mate(s, 2 * max_n - 2)
	return m if m > 0 and m <= max_n else 0


## Taper spilleren som har tur uansett innen max_k av motstanderens trekk? Gir antallet, ellers 0.
static func quiet_loss_depth(s: GameState, max_k: int) -> int:
	if s.is_over() or max_k <= 0:
		return 0
	var m := _exact_mate(s, 2 * max_k - 1)
	return -m if m < 0 and -m <= max_k else 0


## Trekket som vinner raskest for spilleren som har tur (innen max_n trekk), eller (-1, -1).
static func quiet_winning_move(s: GameState, max_n: int) -> Vector2i:
	return _quiet_win(s, max_n)[1]


## [antall trekk til seieren (0 = ingen), første trekk].
static func _quiet_win(s: GameState, max_n: int) -> Array:
	var d := quiet_win_depth(s, max_n)
	if d == 0:
		return [0, Vector2i(-1, -1)]
	if d == 1:
		for c in s.legal_moves():
			if s.wins_by(c, s.current_player):
				return [1, c]
	return [d, _exact.result()]


static func _exact_mate(s: GameState, plies: int) -> int:
	if _exact == null:
		_exact = SearchBot.new()
		_exact.exact = true
	_exact.begin_analysis(s, plies, 3_600_000)
	while not _exact.think(1_000_000):
		pass
	return SearchBot.mate_in(_exact.score())


## «Vinn på N trekk» fra en tilfeldig stilling (seed): seier på nøyaktig n trekk med stille trekk, ingen
## tvungen seier med bare trusler, og entydig løsning. Gir {} hvis stillingen ikke passer.
static func make_win(seed_key: String, n: int) -> Dictionary:
	var s := _random_position(seed_key)
	if s == null or win_depth(s, n) > 0 or quiet_win_depth(s, n) != n:
		return {}
	var line := _unique_line(s, n)
	if line.is_empty():
		return {}
	var out := _record(s, "win", n)
	out.line = line.map(func(c: Vector2i) -> Array: return [c.x, c.y])
	out.cross = _crosses_levels(s, line)
	return out


## «Finn beste trekk»: motstanderen kan tvinge frem seier på k trekk etter alle trekk unntatt ett.
## refute: for hvert av de andre trekkene ("x,y"), motstanderens første trekk i seieren (vises når
## du bommer, uten at klienten må søke).
static func make_defend(seed_key: String, k: int) -> Dictionary:
	var s := _random_position(seed_key)
	if s == null:
		return {}
	var legal := s.legal_moves()
	if legal.size() < 5:
		return {}
	var safe := Vector2i(-1, -1)
	var longest := 0
	var refute := {}
	for c in legal:
		s.play(c, false)
		var win := _quiet_win(s, k)
		s.undo()
		var d: int = win[0]
		var w: Vector2i = win[1]
		if w.x < 0:
			if safe.x >= 0:
				return {}   # to trekk redder deg: ikke entydig
			safe = c
		else:
			refute["%d,%d" % [c.x, c.y]] = [w.x, w.y]
		longest = maxi(longest, d)
	if safe.x < 0 or longest < 2:
		return {}
	s.play(safe, false)
	var holds := quiet_win_depth(s, k + 1) == 0   # og trekket holder (med litt margin)
	s.undo()
	if not holds:
		return {}
	var out := _record(s, "defend", longest)
	out.answer = [safe.x, safe.y]
	out.refute = refute
	return out


## En tilfeldig stilling midt i et parti der ingen kan vinne med en gang (spilleren som har tur, er
## den som skal løse oppgaven). null hvis den ble uryddig.
static func _random_position(seed_key: String) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_key.hash()
	var s := GameState.new(GameOptions.new(), 1 + rng.randi() % 2)
	var plies := rng.randi_range(8, 24)
	for ply in plies:
		if s.is_over():
			return null
		var legal := s.legal_moves()
		var me := s.current_player
		if legal.any(func(c: Vector2i) -> bool: return s.wins_by(c, me)):
			return null
		s.play(legal[rng.randi() % legal.size()], false)
	if s.is_over() or not s.winning_columns(s.current_player).is_empty() \
			or not s.winning_columns(GameState.opponent(s.current_player)).is_empty():
		return null
	return s


## Løsningen for «Vinn på N trekk», eller [] hvis den ikke er entydig. Angriperen: eneste trekk som
## holder seieren innen trekkene som er igjen (siste trekk: et vinnertrekk). Forsvareren: svaret som
## holder ut lengst.
static func _unique_line(start: GameState, n: int) -> Array[Vector2i]:
	var s := GameState.from_moves(start.options, start.first_player, start.history)
	var line: Array[Vector2i] = []
	var left := n
	while left > 0:
		var me := s.current_player
		var keep := Vector2i(-1, -1)
		for c in s.legal_moves():
			if s.wins_by(c, me):
				keep = c
				break
		if keep.x < 0:
			if left == 1:
				return []
			for c in s.legal_moves():
				s.play(c, false)
				var ok := quiet_loss_depth(s, left - 1) > 0
				s.undo()
				if ok:
					if keep.x >= 0:
						return []   # to trekk vinner: ikke entydig
					keep = c
		if keep.x < 0:
			return []
		line.append(keep)
		if s.play(keep, false).won:
			return line
		var reply := Vector2i(-1, -1)
		var hold := 0
		for r in s.legal_moves():
			s.play(r, false)
			var d := quiet_win_depth(s, left - 1)
			s.undo()
			if d == 0:
				return []   # forsvareren slipper unna (skal ikke skje)
			if d > hold:
				hold = d
				reply = r
		line.append(reply)
		s.play(reply, false)
		left = hold
	return []


## Går vinnerlinjen på kryss og tvers (gjennom flere høyder, men ikke rett opp)?
static func _crosses_levels(start: GameState, line: Array[Vector2i]) -> bool:
	var s := GameState.from_moves(start.options, start.first_player, start.history)
	for c in line:
		s.play(c, false)
	var zs := {}
	var cols := {}
	for p in s.winning_line:
		zs[p.z] = true
		cols[Vector2i(p.x, p.y)] = true
	return zs.size() > 1 and cols.size() > 1


static func _record(s: GameState, kind: String, depth: int) -> Dictionary:
	var moves := []
	for m in s.history:
		moves.append([m.x, m.y])
	return { "kind": kind, "options": s.options.to_dict(), "first": s.first_player, "moves": moves,
		"player": s.current_player, "depth": depth }
