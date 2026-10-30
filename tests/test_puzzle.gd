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
