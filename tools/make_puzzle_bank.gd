extends SceneTree
## Lager oppgavebanken (ai/puzzle_bank.gd): ferdige oppgaver i fire vanskelighetsgrader, så
## «Flere oppgaver» lastes med en gang og virker uten nett. Kjør på nytt for å lage nye:
##   godot --headless --path . -s res://tools/make_puzzle_bank.gd
## Måler også hvor lang tid motstanderens svar tar, og hopper over oppgaver der det tar mer enn
## MAX_REPLY_MS her (i nettleseren tar det flere ganger så lang tid), så de vanskelige ikke henger.
##
## Runde 19: alle oppgavene går i flere plan (Puzzle.generate), og høyst MAX_SAME av hvert nivå har
## vinnerlinjen i samme retning. Oppgaver som allerede ligger i banken og passer, beholdes med samme id
## (så fremgangen på enheten stemmer). Nye får id-er etter den høyeste som har vært brukt.

const PER_LEVEL := 20
const MAX_SAME := 8
const MAX_REPLY_MS := 120
const LEVELS := [3, 4, 5, 6]
const OUT := "res://ai/puzzle_bank.gd"
const SEED := "bank19"


func _init() -> void:
	var lines: Array[String] = []
	var worst_ms := 0
	for depth in LEVELS:
		var old := PuzzleBank.PUZZLES.filter(func(p: Dictionary) -> bool: return int(p.depth) == depth)
		var next_id: int = 1 + old.reduce(func(m: int, p: Dictionary) -> int: return maxi(m, int(str(p.id).get_slice("-", 1))), 0)
		var kept := old.filter(func(p: Dictionary) -> bool: return Puzzle.is_3d(p))
		var same := {}
		for p: Dictionary in kept:
			var k := str(Puzzle.shape(p).final)
			same[k] = int(same.get(k, 0)) + 1
		var fresh := []
		var seed_i := 0
		while kept.size() + fresh.size() < PER_LEVEL:
			var p := Puzzle.generate("%s-%d-%d" % [SEED, depth, seed_i], depth, depth)
			seed_i += 1
			if p.is_empty():
				continue
			var k := str(Puzzle.shape(p).final)
			if int(same.get(k, 0)) >= MAX_SAME:
				continue
			var ms := Puzzle.slowest_reply_ms(p)
			if ms > MAX_REPLY_MS:
				continue
			same[k] = int(same.get(k, 0)) + 1
			worst_ms = maxi(worst_ms, ms)
			p.erase("day")
			p.id = "%d-%02d" % [depth, next_id]
			next_id += 1
			fresh.append(p)
			print("%s %s (%d trekk i stillingen)" % [p.id, k, p.moves.size()])
		print("Nivå %d: beholdt %d, nye %d, retninger %s" % [depth, kept.size(), fresh.size(), str(same)])
		for p in kept + fresh:
			lines.append("\t" + JSON.stringify(p) + ",")
	var code := "class_name PuzzleBank\nextends RefCounted\n## Ferdige oppgaver til «Flere oppgaver», laget av tools/make_puzzle_bank.gd. Ikke rediger for hånd.\n"
	code += "## Hver oppgave: { id, depth, options, first, moves, player } (som Puzzle.generate).\n\n"
	code += "const LEVELS := %s\n\nconst PUZZLES := [\n%s\n]\n" % [str(LEVELS), "\n".join(lines)]
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("Skrev %d oppgaver til %s. Tregeste svar fra motstanderen: %d ms" % [lines.size(), OUT, worst_ms])
	quit()
