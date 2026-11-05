extends TestCase
## Tester for dagens oppgave (ai/puzzle.gd) og trekk-for-trekk-analysen til repriser.

const DAYS := ["2026-10-21", "2026-10-23", "2027-01-01"]


## Første dag fra og med from som får typen kind (runde 17: typen bytter dag for dag).
static func _day_of_kind(kind: String, from := "2026-10-21") -> String:
	var unix := int(Time.get_unix_time_from_datetime_string(from + "T12:00:00"))
	while Puzzle.kind_for(Time.get_date_string_from_unix_time(unix)) != kind:
		unix += 86400
	return Time.get_date_string_from_unix_time(unix)


func test_puzzle_is_the_same_all_day_and_has_a_forced_win() -> void:
	var day := _day_of_kind("forced")
	var a := Puzzle.generate(day)
	var b := Puzzle.generate(day)
	check(not a.is_empty(), "fant en oppgave")
	check_eq(a.moves, b.moves, "samme dag gir samme oppgave:")
	var next_day := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_datetime_string(day + "T12:00:00")) + 86400)
	check(Puzzle.generate(_day_of_kind("forced", next_day)).moves != a.moves, "ny dag, ny oppgave")
	var s := Puzzle.start_state(a)
	check_eq(s.current_player, int(a.player))
	check(int(a.depth) >= Puzzle.MIN_DEPTH, "minst tre trekk")
	check(Puzzle.can_win(s, int(a.depth)), "tvungen seier finnes")
	check(not Puzzle.can_win(s, int(a.depth) - 1), "ingen raskere seier")
	check(s.winning_columns(GameState.opponent(s.current_player)).is_empty(), "forsvareren truer ikke selv")


func test_solution_is_accepted_and_others_are_not() -> void:
	for day in DAYS:
		var p := Puzzle.generate(day)
		var mine := _attacker_moves(p)
		if str(p.get("kind", "forced")) == "forced":
			check_eq(mine.size(), int(p.depth), "%s: løsningen bruker akkurat dybden:" % day)
		check(Puzzle.verify(p, mine), "%s: løsningen godtas" % day)
		check(not Puzzle.verify(p, mine.slice(0, mine.size() - 1)), "%s: halv løsning godtas ikke" % day)
		check(not Puzzle.verify(p, [[9, 9]]), "ugyldig trekk")
		check(not Puzzle.verify(p, ["tull"]), "søppel")
		# Etter JSON (tall blir desimaltall) skal alt virke likt
		var from_json: Dictionary = JSON.parse_string(JSON.stringify(p))
		check(Puzzle.verify(from_json, mine), "%s: virker etter JSON" % day)


func test_defender_is_deterministic() -> void:
	var p := Puzzle.generate(_day_of_kind("forced"))
	var s := Puzzle.start_state(p)
	# Et stille trekk først, så motstanderen kan velge fritt
	var quiet := Vector2i(-1, -1)
	for c in s.legal_moves():
		if not Puzzle._creates_threat(s, c, s.current_player):
			quiet = c
			break
	s.play(quiet, false)
	var a := Puzzle.reply(p, s, [quiet])
	var b := Puzzle.reply(JSON.parse_string(JSON.stringify(p)), s, [[quiet.x, quiet.y]])
	check_eq(a, b, "samme svar (også etter JSON):")
	check(a in s.legal_moves(), "forsvaret er et lovlig trekk")


## Et feil trekk stopper ikke oppgaven: en seier på flere trekk enn den raskeste godtas, men ikke over
## grensen (Puzzle.move_limit).
func test_slower_win_is_accepted() -> void:
	var found := []
	for p in PuzzleBank.PUZZLES.filter(func(q: Dictionary) -> bool: return int(q.depth) == 3).slice(0, 12):
		var sol := Puzzle.solution(p)
		var start := Puzzle.start_state(p)
		for c in start.legal_moves():
			if c == sol[0]:
				continue
			var s := Puzzle.start_state(p)
			var played: Array = [c]
			s.play(c, false)
			s.play(Puzzle.reply(p, s, played), false)
			if s.is_over() or Puzzle.known_win(s, Puzzle.move_limit(p) - 1) == 0:
				continue
			if _win_on(p, s, played) and played.size() > int(p.depth):
				found = [p, played]
				break
		if not found.is_empty():
			break
	check(not found.is_empty(), "fant en oppgave der et annet første trekk også vinner, men senere")
	if found.is_empty():
		return
	var moves: Array = found[1]
	check(Puzzle.verify(found[0], moves), "%s: seieren på %d trekk godtas" % [found[0].id, moves.size()])
	var too_many := moves.duplicate()
	while too_many.size() <= Puzzle.move_limit(found[0]):
		too_many.push_front(moves[0])
	check(not Puzzle.verify(found[0], too_many), "flere trekk enn grensen godtas ikke")


## Gir et trekk motstanderen et fritt trekk, og den har en tvungen seier selv, spiller den den.
func test_opponent_punishes_a_free_move() -> void:
	var punished := 0
	for p in PuzzleBank.PUZZLES.slice(0, 20):
		var start := Puzzle.start_state(p)
		var me := start.current_player
		for c in start.legal_moves():
			var s := Puzzle.start_state(p)
			s.play(c, false)
			if s.is_over() or Puzzle.win_depth(s, Puzzle.COUNTER_SIGHT) == 0:
				continue
			var r := Puzzle.reply(p, s, [c])
			check(s.wins_by(r, s.current_player) or Puzzle._creates_threat(s, r, s.current_player),
				"%s: motstanderen angriper etter %s" % [p.id, c])
			# … og vinner, uansett hvordan du blokkerer
			var played: Array = [c]
			s.play(r, false)
			while not s.is_over() and played.size() < 12:
				var block: Vector2i = s.legal_moves()[0]
				played.append(block)
				s.play(block, false)
				if not s.is_over():
					s.play(Puzzle.reply(p, s, played), false)
			check_eq(s.winner(), GameState.opponent(me), "%s: motstanderen vinner:" % p.id)
			punished += 1
			break
	check(punished > 0, "fant et trekk som gir motstanderen en tvungen seier")


## Spiller videre (raskeste vinnertrekk) mot motstanderen i oppgaven. true ved seier innen grensen.
static func _win_on(p: Dictionary, s: GameState, played: Array) -> bool:
	while played.size() < Puzzle.move_limit(p):
		var col := Puzzle.quiet_winning_move(s, mini(Puzzle.move_limit(p) - played.size(), 4))
		if col.x < 0:
			return false
		played.append(col)
		if s.play(col, false).won:
			return true
		s.play(Puzzle.reply(p, s, played), false)
		if s.is_over():
			return false
	return false


func test_timeline_marks_the_same_moves_as_the_analysis() -> void:
	var rng := RandomNumberGenerator.new()
	for game in 6:
		rng.seed = 100 + game
		var options := GameOptions.from_dict({ "must_block": false, "no_gift": false })
		var s := GameState.new(options, 1)
		var moves := []
		while not s.is_over():
			var legal := s.legal_moves()
			var col: Vector2i = legal[rng.randi() % legal.size()]
			s.play(col)
			moves.append([col.x, col.y])
		var analysis := GameAnalysis.analyze(options, 1, moves)
		var line := GameAnalysis.timeline(options, 1, moves)
		check_eq(line.size(), moves.size(), "ett element per trekk:")
		for player in [1, 2]:
			var forced := line.filter(func(e: Dictionary) -> bool: return e.player == player and e.forced).size()
			var doubles := line.filter(func(e: Dictionary) -> bool: return e.player == player and e.double).size()
			check_eq(forced, int(analysis[player].forced), "tvungne trekk for spiller %d:" % player)
			check_eq(doubles, int(analysis[player].double_threats), "doble trusler for spiller %d:" % player)
		for e in line:
			if e.forced:
				check(not (e.threats as Array).is_empty(), "et tvunget trekk har en plass som må blokkeres")
		check_eq(bool(line[-1].won), s.end_reason == GameState.EndReason.LINE, "siste trekk vant:")


func test_puzzle_bank_has_valid_puzzles_on_every_level() -> void:
	var ids := {}
	for puzzle in PuzzleBank.PUZZLES:
		check(not ids.has(puzzle.id), "dobbel id: %s" % puzzle.id)
		ids[puzzle.id] = true
		check(int(puzzle.depth) in PuzzleBank.LEVELS)
	for level in PuzzleBank.LEVELS:
		var list := PuzzleBank.PUZZLES.filter(func(p: Dictionary) -> bool: return int(p.depth) == level)
		check(list.size() >= 10, "nok oppgaver på nivå %d" % level)
		# Den første på hvert nivå: løsningen godtas og bruker akkurat så mange trekk
		var first: Dictionary = list[0]
		var sol := Puzzle.solution(first)
		var mine := []
		for i in range(0, sol.size(), 2):
			mine.append([sol[i].x, sol[i].y])
		check_eq(mine.size(), level, "nivå %d:" % level)
		check(Puzzle.verify(first, mine), "løsningen på %s godtas" % first.id)
		if level <= 4:
			check(not Puzzle.can_win(Puzzle.start_state(first), level - 1), "%s har ingen raskere seier" % first.id)


## Runde 17: dagens oppgave bytter mellom tre typer, dag for dag.
func test_daily_kinds_rotate() -> void:
	var kinds := {}
	for d in ["2026-11-01", "2026-11-02", "2026-11-03"]:
		kinds[Puzzle.kind_for(d)] = true
	check_eq(kinds.size(), 3, "tre dager på rad gir tre typer")
	check_eq(Puzzle.kind_for("bank-3-1"), "forced", "andre nøkler enn datoer")
	for d in ["2026-11-01", "2026-11-02", "2026-11-03"]:
		var p := Puzzle.generate(d)
		check(not p.is_empty(), d)
		var has_bank := DailyBank.PUZZLES.any(func(b: Dictionary) -> bool: return b.kind == Puzzle.kind_for(d))
		check_eq(str(p.get("kind", "forced")), Puzzle.kind_for(d) if has_bank else "forced", d)
		check(Puzzle.verify(p, _attacker_moves(p)), "løsningen godtas: %s" % d)


## Runde 19: oppgavene går i flere plan. Før var to av tre et vanlig firepårad i én høyde (som FLAT).
const FLAT := {"depth":3,"first":1,"id":"3-01","moves":[[2,3],[1,3],[0,2],[2,2],[3,1],[1,3],[0,2],[3,3],[2,0],[1,3],[1,3],[1,1],[0,0],[2,2],[0,0],[2,0],[2,1],[3,1]],"options":{"must_block":true,"no_gift":true,"size":4,"starter":"p1","time_base_s":0,"time_increment_s":0,"win_length":4},"player":1}


func test_puzzles_use_several_planes() -> void:
	check_eq(Puzzle.line_kind(Vector3i(0, 0, 0), Vector3i(1, 1, 1)), "space")
	check_eq(Puzzle.line_kind(Vector3i(0, 3, 0), Vector3i(0, 2, 1)), "slant")
	check_eq(Puzzle.line_kind(Vector3i(1, 1, 0), Vector3i(1, 1, 1)), "vertical")
	check_eq(Puzzle.line_kind(Vector3i(0, 3, 0), Vector3i(1, 2, 0)), "flat")
	check_eq(Puzzle.line_kind(Vector3i(0, 0, 2), Vector3i(0, 1, 2)), "straight")
	var flat := Puzzle.shape(FLAT)
	check_eq(flat.levels, 1, "den gamle oppgaven ligger i én høyde:")
	check(not Puzzle.is_3d(FLAT), "og går ikke i flere plan")
	check(Puzzle.is_3d(Puzzle.generate(_day_of_kind("forced"))), "dagens oppgave går i flere plan")
	for i in range(0, PuzzleBank.PUZZLES.size(), 7):
		check(Puzzle.is_3d(PuzzleBank.PUZZLES[i]), "%s går i flere plan" % PuzzleBank.PUZZLES[i].id)
	var wins := DailyBank.PUZZLES.filter(func(p: Dictionary) -> bool: return p.kind == "win")
	for p in wins:
		check(Puzzle.is_3d(p), "%s går i flere plan" % p.id)
	var stacked := wins.filter(func(p: Dictionary) -> bool: return Puzzle.shape(p).stacked).size()
	check(stacked * 3 <= wins.size() * 2, "høyst to av tre ender med tre trekk i samme kolonne (%d av %d)" % [stacked, wins.size()])
	var forced := DailyBank.PUZZLES.filter(func(p: Dictionary) -> bool: return p.kind == "forced")
	check(forced.size() >= 100, "«Tving frem seier» ligger i banken")
	for i in range(0, forced.size(), 10):
		check(Puzzle.is_3d(forced[i]), "%s går i flere plan" % forced[i].id)


## Det eksakte søket (stille trekk lov) finner de tvungne seirene i oppgavebanken, og aldri lengre.
func test_quiet_search_agrees_with_forced_puzzles() -> void:
	for p in PuzzleBank.PUZZLES.slice(0, 6):
		var s := Puzzle.start_state(p)
		var d := Puzzle.quiet_win_depth(s, int(p.depth))
		check(d > 0 and d <= int(p.depth), "%s: %d" % [p.id, d])


## «Vinn på N trekk» i banken: seier på N trekk med stille trekk, ingen med bare trusler, entydig.
func test_win_puzzles_in_the_bank() -> void:
	var wins := DailyBank.PUZZLES.filter(func(p: Dictionary) -> bool: return p.kind == "win").slice(0, 3)
	for p in wins:
		var s := Puzzle.start_state(p)
		var n := int(p.depth)
		check_eq(Puzzle.quiet_win_depth(s, n), n, "%s: seier på %d" % [p.id, n])
		check_eq(Puzzle.win_depth(s, n), 0, "%s: ikke bare med trusler" % p.id)
		check(Puzzle.verify(p, _attacker_moves(p)), "%s: løsningen" % p.id)
		var first := Puzzle._vec(p.line[0])
		for c in s.legal_moves():
			if c != first:
				check(not Puzzle.verify(p, [[c.x, c.y]]), "%s: feil første trekk godtas ikke" % p.id)
				break


## «Finn beste trekk» i banken: bare svaret redder deg, og alle andre trekk har en vist vei til tap.
func test_defend_puzzles_in_the_bank() -> void:
	var defends := DailyBank.PUZZLES.filter(func(p: Dictionary) -> bool: return p.kind == "defend").slice(0, 3)
	for p in defends:
		var s := Puzzle.start_state(p)
		var answer := Puzzle._vec(p.answer)
		check(Puzzle.verify(p, [p.answer]), "%s: svaret" % p.id)
		for c in s.legal_moves():
			if c == answer:
				continue
			check(not Puzzle.verify(p, [[c.x, c.y]]), "%s: feil trekk" % p.id)
			check((p.refute as Dictionary).has("%d,%d" % [c.x, c.y]), "%s: motstanderens svar på %s" % [p.id, c])
		s.play(answer, false)
		check_eq(Puzzle.quiet_win_depth(s, int(p.depth)), 0, "%s: svaret holder" % p.id)


static func _attacker_moves(p: Dictionary) -> Array:
	var sol := Puzzle.solution(p)
	var out := []
	var step := 1 if str(p.get("kind", "forced")) == "defend" else 2
	for i in range(0, sol.size(), step):
		out.append([sol[i].x, sol[i].y])
	return out
