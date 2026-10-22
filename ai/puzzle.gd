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
##   { day, options, first, moves (stillingen), player (angriperen), depth }

const MIN_DEPTH := 3
const MAX_DEPTH := 4
const ATTEMPTS := 400


## Lager oppgaven for en dag (f.eks. "2026-10-21"). Gir {} hvis ingen ble funnet (skjer ikke i praksis).
static func generate(day: String, min_depth := MIN_DEPTH, max_depth := MAX_DEPTH) -> Dictionary:
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
## innen oppgavens antall trekk.
static func verify(puzzle: Dictionary, attacker_moves: Array) -> bool:
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


## Hele løsningen fra stillingen: angriperens trekk og forsvarerens svar, til seier.
static func solution(puzzle: Dictionary) -> Array[Vector2i]:
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
