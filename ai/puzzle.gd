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
##
## Runde 19: to av tre oppgaver var et vanlig firepårad i én høyde, og mange «Vinn på N trekk» endte
## med samme triks (tre trekk i samme kolonne). Nå må oppgavene gå i flere plan (is_3d), se shape.
## Da tar det mye lenger tid å finne en «Tving frem seier» (opptil 8 s), så også de ligger nå ferdige i
## DailyBank. generate lager dem fortsatt fra en nøkkel som ikke er en dato (verktøyene bruker det).
##
## Runde 19 (forts.): oppgaven spilles ut som et parti. Et feil trekk stopper deg ikke: motstanderen
## svarer (reply), vinner selv hvis den kan, og du ser hvordan det går. Alle seire innen move_limit
## godtas, også andre løsninger og seire på flere trekk enn den raskeste (depth).

const MIN_DEPTH := 3
const MAX_DEPTH := 4
const ATTEMPTS := 400
const KINDS := ["forced", "win", "defend"]
const EXTRA_MOVES := 3     ## så mange egne trekk mer enn den raskeste seieren du får bruke
const QUIET_SIGHT := 3     ## hvor mange trekk frem motstanderen ser seire med stille trekk (eksakt søk, dyrt)
const THREAT_SIGHT := 6    ## … og seire med bare trusler (billig)
const COUNTER_SIGHT := 4   ## hvor langt frem motstanderen ser sin egen tvungne seier med trusler
const THREAT_STEPS := 800   ## steg trusselsøket får i et svar (fast antall, så svaret blir det samme overalt)

static var _exact: SearchBot    ## eksakt søk til oppgavene med stille trekk (lages første gang)
static var _steps := -1        ## steg igjen i trusselsøket (known_win), -1 = ubegrenset


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
## En dato tar oppgaven av dagens type fra DailyBank (hver brukes én gang per runde gjennom banken).
## Andre nøkler (eller en bank uten typen) lager en «Tving frem seier» som går i flere plan (is_3d):
## en stilling som bare har en flat løsning, spilles videre.
static func generate(day: String, min_depth := MIN_DEPTH, max_depth := MAX_DEPTH) -> Dictionary:
	var kind := kind_for(day)
	if _day_number(day) >= 0:
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
				var p := { "day": day, "options": options.to_dict(), "first": s.first_player, "moves": moves,
					"player": s.current_player, "depth": d }
				if is_3d(p):
					return p
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
	if _steps == 0:
		return Vector2i(-1, -1)   # known_win har brukt opp stegene: ingen seier funnet
	if _steps > 0:
		_steps -= 1
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


## Hvor mange egne trekk du får bruke på oppgaven (defend: ett, svaret).
static func move_limit(puzzle: Dictionary) -> int:
	if str(puzzle.get("kind", "forced")) == "defend":
		return 1
	return int(puzzle.get("depth", MIN_DEPTH)) + EXTRA_MOVES


## Motstanderens svar i oppgaven. s: stillingen etter angriperens siste trekk; attacker_moves: alle
## angriperens trekk så langt. Deterministisk, så serveren kan spille det samme som klienten.
## win: følger du løsningen (line), svarer motstanderen som i den. Ellers respond.
static func reply(puzzle: Dictionary, s: GameState, attacker_moves: Array) -> Vector2i:
	var i := attacker_moves.size()
	if str(puzzle.get("kind", "forced")) == "win":
		var line: Array = puzzle.get("line", [])
		var on_line := 2 * i - 1 < line.size()
		for j in i:
			on_line = on_line and _vec(attacker_moves[j]) == _vec(line[2 * j])
		if on_line:
			return _vec(line[2 * i - 1])
	return respond(s, move_limit(puzzle) - i)


## Motstanderen har tur, og du har left trekk igjen. Den
##   1. vinner med en gang hvis det går;
##   2. har den selv en tvungen seier med trusler, spiller den den (da får du aldri et fritt trekk);
##   3. ellers spiller den trekket som stopper seieren din (står flere likt: det som bygger mest på egne
##      linjer og stenger dine, _move_value), eller som utsetter den lengst (slik known_win ser den; står
##      flere likt: det første, slik løsningene i bankene er laget).
## Rekkefølgen er fast (legal_moves), så svaret er alltid det samme for samme stilling.
## Trekkene prøves etter _move_value, så det første som stopper deg er svaret, og et trekk som ikke
## stopper deg, søkes bare helt hvis det kan utsette seieren lenger enn det beste så langt (sparer tid).
static func respond(s: GameState, left: int) -> Vector2i:
	var me := s.current_player
	var legal := s.legal_moves()
	if legal.is_empty():
		return Vector2i(-1, -1)
	for col in legal:
		if s.wins_by(col, me):
			return col
	if legal.size() == 1:
		return legal[0]
	var own := win_depth(s, COUNTER_SIGHT)
	if own > 0:
		return best_move(s, own)
	var values := legal.map(func(c: Vector2i) -> int: return _move_value(s, c, me))
	var order := range(legal.size())
	order.sort_custom(func(a: int, b: int) -> bool: return values[a] > values[b] or (values[a] == values[b] and a < b))
	var best_i := -1
	var longest := 0
	_steps = THREAT_STEPS   # alle trusselsøkene i svaret deler på stegene
	for i in order:
		s.play(legal[i], false)
		var d := 0
		if not s.is_over():
			var need := longest if i > best_i else longest - 1   # så lenge holder det beste så langt
			d = -1 if need > 0 and known_win(s, need) > 0 else known_win(s, left)
		s.undo()
		if d == 0:
			best_i = i
			break
		if d > longest or (d == longest and i < best_i):
			longest = d
			best_i = i
	_steps = -1
	return legal[best_i]


## Korteste seier spilleren som har tur kan tvinge frem innen left egne trekk, slik motstanderen i
## oppgaven ser det: med stille trekk inntil QUIET_SIGHT trekk frem, og med bare trusler inntil
## THREAT_SIGHT. 0 = ingen funnet.
static func known_win(s: GameState, left: int) -> int:
	if left <= 0 or s.is_over():
		return 0
	var q := quiet_win_depth(s, mini(left, QUIET_SIGHT))
	if q > 0:
		return q
	# Trusselsøket kan vokse mye i stillinger med mange trusler, så det får THREAT_STEPS steg (i respond:
	# til sammen for alle svarene). Er de brukt opp, er ingen seier funnet.
	var own_steps := _steps < 0
	if own_steps:
		_steps = THREAT_STEPS
	var found := 0
	for n in range(QUIET_SIGHT + 1, mini(left, THREAT_SIGHT) + 1):
		if can_win(s, n):
			found = n
			break
	if own_steps:
		_steps = -1
	return found


## Hvor nyttig et trekk er i seg selv: linjer gjennom plassen der egne brikker kan bli fire på rad (jo
## flere egne, jo mer), og linjer det stenger for motstanderen (jo flere av hans, jo mer).
static func _move_value(s: GameState, col: Vector2i, me: int) -> int:
	var own := me * s.n_lines
	var opp := GameState.opponent(me) * s.n_lines
	var v := 0
	for li in s.lines.cell_lines[s.lines.index_of(s.landing_pos(col))]:
		var a := int(s.counts[own + li])
		var b := int(s.counts[opp + li])
		if b == 0:
			v += 1 << (2 * a)
		if a == 0:
			v += (1 << (2 * b)) - 1
	return v


## Sjekker en løsning (angriperens trekk) ved å spille den mot motstanderen (reply). Gir true ved
## seier innen move_limit egne trekk. defend: ett trekk, answer.
static func verify(puzzle: Dictionary, attacker_moves: Array) -> bool:
	if str(puzzle.get("kind", "forced")) == "defend":
		return attacker_moves.size() == 1 and _vec(attacker_moves[0]) == _vec(puzzle.get("answer", []))
	var s := start_state(puzzle)
	if s.current_player != int(puzzle.get("player", 0)) or attacker_moves.size() > move_limit(puzzle):
		return false
	var played := []
	for m in attacker_moves:
		var col := _vec(m)
		if s.is_over() or s.check_move(col) != GameState.MoveError.OK:
			return false
		played.append(col)
		if s.play(col).won:
			return true
		if s.is_over():
			return false
		s.play(reply(puzzle, s, played), false)
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
	var played := []
	while left > 0 and not s.is_over():
		var col := best_move(s, left)
		if col == Vector2i(-1, -1):
			break
		out.append(col)
		played.append(col)
		s.play(col, false)
		left -= 1
		if s.is_over():
			break
		var answer := reply(puzzle, s, played)
		out.append(answer)
		s.play(answer, false)
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


# ---------------------------------------------------------------- Variasjon (runde 19)

## Retningen til en linje fra a til b (to celler etter hverandre i linjen):
##   straight  rett bortover i én høyde     flat   diagonalt i én høyde
##   vertical  rett opp                     slant  diagonalt oppover langs en vegg
##   space     romdiagonal (gjennom høydene og på skrå)
static func line_kind(a: Vector3i, b: Vector3i) -> String:
	var d := b - a
	var axes := int(d.x != 0) + int(d.y != 0) + int(d.z != 0)
	if axes == 3:
		return "space"
	if axes == 1:
		return "vertical" if d.z != 0 else "straight"
	return "flat" if d.z == 0 else "slant"


## Hvordan løsningen ligger på brettet (forced og win; defend gir {}):
##   lines    retningene til truslene angriperen lager underveis, og vinnerlinjen
##   final    vinnerlinjens retning
##   levels   hvor mange høyder angriperens brikker havner i
##   stacked  slutten er tre trekk i samme kolonne (legg under, motstanderen må ta trusselen, vinn oppå)
static func shape(puzzle: Dictionary) -> Dictionary:
	if str(puzzle.get("kind", "forced")) == "defend":
		return {}
	var sol := solution(puzzle)
	var s := start_state(puzzle)
	var me := s.current_player
	var own := me * s.n_lines
	var opp := GameState.opponent(me) * s.n_lines
	var kinds := {}
	var levels := {}
	for i in sol.size():
		var pos: Vector3i = s.play(sol[i], false).pos
		if i % 2 == 1:
			continue
		levels[pos.z] = true
		for li in s.lines.cell_lines[s.lines.index_of(pos)]:
			if s.counts[own + li] >= s.win_length - 1 and s.counts[opp + li] == 0:
				var cells: PackedInt32Array = s.lines.cells[li]
				kinds[line_kind(s.lines.pos_of(cells[0]), s.lines.pos_of(cells[1]))] = true
	var n := sol.size()
	return {
		"lines": kinds.keys(),
		"final": line_kind(s.winning_line[0], s.winning_line[1]) if s.winning_line.size() > 1 else "",
		"levels": levels.size(),
		"stacked": n >= 3 and sol[n - 1] == sol[n - 2] and sol[n - 2] == sol[n - 3],
	}


## Går oppgaven i flere plan? Angriperens brikker havner i minst to høyder, og minst én trussel går
## oppover (rett opp, skrått eller på romdiagonalen). Ikke bare et vanlig firepårad i én høyde.
static func is_3d(puzzle: Dictionary) -> bool:
	var sh := shape(puzzle)
	if sh.is_empty():
		return true
	return int(sh.levels) >= 2 and (sh.lines as Array).any(func(k: String) -> bool: return k in ["vertical", "slant", "space"])


## Spiller løsningen som en spiller ville gjort, og gir det tregeste svaret fra motstanderen (svar og
## sjekk, som i oppgaveskjermen) i ms. Verktøyene hopper over oppgaver der det tar for lang tid.
static func slowest_reply_ms(puzzle: Dictionary) -> int:
	var s := start_state(puzzle)
	var left := int(puzzle.depth)
	var worst := 0
	var played := []
	while left > 0:
		var col := best_move(s, left)
		played.append(col)
		if s.play(col).won:
			break
		left -= 1
		var t := Time.get_ticks_msec()
		s.play(reply(puzzle, s, played), false)
		known_win(s, move_limit(puzzle) - played.size())
		worst = maxi(worst, Time.get_ticks_msec() - t)
	return worst


## Taper spilleren som har tur uansett, mot en tvungen seier med trusler innen n av motstanderens trekk?
## (Oppgaveskjermen: da spilles partiet ut, selv om trekkene dine er brukt opp.)
static func loses_to_threats(s: GameState, n: int) -> bool:
	return _defender_loses(s, n)


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
## Runde 19: løsningen må gå i flere plan (is_3d).
static func make_win(seed_key: String, n: int) -> Dictionary:
	var s := _random_position(seed_key)
	if s == null or win_depth(s, n) > 0 or quiet_win_depth(s, n) != n:
		return {}
	var line := _unique_line(s, n)
	if line.is_empty():
		return {}
	var out := _record(s, "win", n)
	out.line = line.map(func(c: Vector2i) -> Array: return [c.x, c.y])
	if not is_3d(out):
		return {}
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
