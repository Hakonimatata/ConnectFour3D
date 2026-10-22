extends SceneTree
## Lager oppgavebanken (ai/puzzle_bank.gd): ferdige oppgaver i fire vanskelighetsgrader, så
## «Flere oppgaver» lastes med en gang og virker uten nett. Kjør på nytt for å lage nye:
##   godot --headless --path . -s res://tools/make_puzzle_bank.gd
## Måler også hvor lang tid motstanderens svar tar, så de vanskelige oppgavene ikke henger.

const PER_LEVEL := 15
const LEVELS := [3, 4, 5, 6]
const OUT := "res://ai/puzzle_bank.gd"


func _init() -> void:
	var lines: Array[String] = []
	var worst_ms := 0
	for depth in LEVELS:
		var found := 0
		var seed_i := 0
		while found < PER_LEVEL:
			var p := Puzzle.generate("bank-%d-%d" % [depth, seed_i], depth, depth)
			seed_i += 1
			if p.is_empty():
				continue
			worst_ms = maxi(worst_ms, _solve_ms(p))
			found += 1
			p.erase("day")
			p.id = "%d-%02d" % [depth, found]
			lines.append("\t" + JSON.stringify(p) + ",")
			print("%s (%d trekk i stillingen)" % [p.id, p.moves.size()])
	var code := "class_name PuzzleBank\nextends RefCounted\n## Ferdige oppgaver til «Flere oppgaver», laget av tools/make_puzzle_bank.gd. Ikke rediger for hånd.\n"
	code += "## Hver oppgave: { id, depth, options, first, moves, player } (som Puzzle.generate).\n\n"
	code += "const LEVELS := %s\n\nconst PUZZLES := [\n%s\n]\n" % [str(LEVELS), "\n".join(lines)]
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("Skrev %d oppgaver til %s. Tregeste svar fra motstanderen: %d ms" % [lines.size(), OUT, worst_ms])
	quit()


## Spiller løsningen som en spiller ville gjort, og gir det tregeste steget (svar + sjekk) i ms.
func _solve_ms(p: Dictionary) -> int:
	var s := Puzzle.start_state(p)
	var left := int(p.depth)
	var worst := 0
	while left > 0:
		var col := Puzzle.best_move(s, left)
		if s.play(col).won:
			break
		left -= 1
		var t := Time.get_ticks_msec()
		s.play(Puzzle.defend(s, left), false)
		Puzzle.win_depth(s, left)
		worst = maxi(worst, Time.get_ticks_msec() - t)
	return worst
