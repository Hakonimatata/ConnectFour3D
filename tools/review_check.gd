extends SceneTree
## Måler AI-analysen (ai/move_review.gd): boter spiller mot hverandre, og analysen gir hver av dem en
## treffsikkerhet. En god analyse gir Ekspert høy treffsikkerhet og Lett lav (se Fremgang, runde 17):
##   godot --headless --path . -s res://tools/review_check.gd -- 4 4 ekspert lett
## Argumenter: brettstørrelse, antall partier, bot A (starter), bot B (som i tools/ai_arena.gd).
## Skriver også hvor lang tid analysen tok og hvor store verdiene var (til SCALE i MoveReview).


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size := int(args[0]) if args.size() > 0 else 4
	var games := int(args[1]) if args.size() > 1 else 4
	var a := args[2] if args.size() > 2 else "ekspert"
	var b := args[3] if args.size() > 3 else "lett"
	var arena := load("res://tools/ai_arena.gd")
	var acc := { 1: [], 2: [] }
	var grades := {}
	var values := []
	var total_us := 0
	var total_moves := 0
	for g in games:
		var o := GameOptions.new()
		o.size = size
		var s := GameState.new(o, 1)
		var bots := { 1: Bot.new(arena.profile(a)), 2: Bot.new(arena.profile(b)) }
		bots[1].rng.seed = g * 7 + 1
		bots[2].rng.seed = g * 7 + 2
		while not s.is_over():
			s.play(bots[s.current_player].choose_move(s))
		var t0 := Time.get_ticks_usec()
		var r := MoveReview.new(o, 1, s.history).run()
		var us := Time.get_ticks_usec() - t0
		total_us += us
		total_moves += s.history.size()
		var sum := r.summary()
		for p in [1, 2]:
			acc[p].append(int(sum[p].accuracy))
		for res in r.results:
			var key := "%d:%s" % [res.player, res.grade]
			grades[key] = int(grades.get(key, 0)) + 1
		for sc in r._scores:
			if absi(sc) < SearchBot.MATE:
				values.append(absi(sc))
		print("Parti %d: %d trekk, vinner %d · treffsikkerhet %s %d %%, %s %d %% · analyse %.1f s" % [
			g + 1, s.history.size(), s.winner(), a, int(sum[1].accuracy), b, int(sum[2].accuracy), us / 1e6])
	values.sort()
	var pct := func(q: float) -> int: return int(values[int(q * (values.size() - 1))]) if not values.is_empty() else 0
	print("Snitt: %s %s, %s %s · %.0f ms per trekk" % [a, str(acc[1]), b, str(acc[2]), total_us / 1000.0 / maxi(1, total_moves)])
	print("Karakterer: %s" % str(grades))
	print("|verdi| (ikke tvunget): median %d, 75 %% %d, 90 %% %d, maks %d" % [pct.call(0.5), pct.call(0.75), pct.call(0.9),
		pct.call(1.0)])
	quit()
