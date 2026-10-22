extends TestCase
## Tester for dagens oppgave (ai/puzzle.gd) og trekk-for-trekk-analysen til repriser.

const DAYS := ["2026-10-21", "2026-10-23", "2027-01-01"]


func test_puzzle_is_the_same_all_day_and_has_a_forced_win() -> void:
	var a := Puzzle.generate("2026-10-21")
	var b := Puzzle.generate("2026-10-21")
	check(not a.is_empty(), "fant en oppgave")
	check_eq(a.moves, b.moves, "samme dag gir samme oppgave:")
	check(Puzzle.generate("2026-10-22").moves != a.moves, "ny dag, ny oppgave")
	var s := Puzzle.start_state(a)
	check_eq(s.current_player, int(a.player))
	check(int(a.depth) >= Puzzle.MIN_DEPTH, "minst tre trekk")
	check(Puzzle.can_win(s, int(a.depth)), "tvungen seier finnes")
	check(not Puzzle.can_win(s, int(a.depth) - 1), "ingen raskere seier")
	check(s.winning_columns(GameState.opponent(s.current_player)).is_empty(), "forsvareren truer ikke selv")


func test_solution_is_accepted_and_others_are_not() -> void:
	for day in DAYS:
		var p := Puzzle.generate(day)
		var sol := Puzzle.solution(p)
		var mine := []
		for i in range(0, sol.size(), 2):
			mine.append([sol[i].x, sol[i].y])
		check_eq(mine.size(), int(p.depth), "%s: løsningen bruker akkurat dybden:" % day)
		check(Puzzle.verify(p, mine), "%s: løsningen godtas" % day)
		check(not Puzzle.verify(p, mine.slice(0, mine.size() - 1)), "%s: halv løsning godtas ikke" % day)
		check(not Puzzle.verify(p, [[9, 9]]), "ugyldig trekk")
		check(not Puzzle.verify(p, ["tull"]), "søppel")
		# Etter JSON (tall blir desimaltall) skal alt virke likt
		var from_json: Dictionary = JSON.parse_string(JSON.stringify(p))
		check(Puzzle.verify(from_json, mine), "%s: virker etter JSON" % day)


func test_defender_is_deterministic() -> void:
	var p := Puzzle.generate("2026-10-21")
	var s := Puzzle.start_state(p)
	s.play(Puzzle.best_move(s, int(p.depth)), false)
	var a := Puzzle.defend(s, int(p.depth) - 1)
	var b := Puzzle.defend(s, int(p.depth) - 1)
	check_eq(a, b)
	check(a in s.legal_moves(), "forsvaret er et lovlig trekk")


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
