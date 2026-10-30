extends SceneTree
## Boter mot boter: seiersprosent (som starter og ikke), partilengde og tenketid per trekk.
## Brukes til å måle om en ny AI faktisk er bedre (og rask nok) før den tas i bruk (se Fremgang, runde 16):
##   godot --headless --path . -s res://tools/ai_arena.gd -- 4 20 vanskelig gammel
##   godot --headless --path . -s res://tools/ai_arena.gd -- 5 10 ekspert vanskelig free
## Argumenter: brettstørrelse, partier per farge, bot A, bot B, og «free» for å slå av «må blokkere»
## og «ikke gi bort seier». Botene: lett, middels, gammel (vanskelig før runde 16), vanskelig, ekspert,
## søk:<ms> (søket med egen tenketid) eller dybde:<n> (fast dybde, uavhengig av hvor rask maskinen er).
## Vekter i evalueringen kan endres etter et komma: dybde:4,parity_w=0,threat_w=100 (se SearchBot).
## Hver bot starter halvparten av partiene. Samme frø gir samme partier (unntatt søk med tidsgrense).


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var size := int(args[0]) if args.size() > 0 else 4
	var games := int(args[1]) if args.size() > 1 else 10
	var a := args[2] if args.size() > 2 else "vanskelig"
	var b := args[3] if args.size() > 3 else "gammel"
	var rules := not (args.size() > 4 and args[4] == "free")
	var score := { a: 0.0, b: 0.0 }
	for starter in [a, b]:
		var other: String = b if starter == a else a
		var wins := { 0: 0, 1: 0, 2: 0 }
		var times := { starter: [], other: [] }
		var moves := 0
		for g in games:
			var r := _play(size, starter, other, g + 1, rules)
			wins[r.winner] += 1
			times[starter].append_array(r.times[1])
			times[other].append_array(r.times[2])
			moves += int(r.moves)
		score[starter] += wins[1] + wins[0] * 0.5
		score[other] += wins[2] + wins[0] * 0.5
		print("%d×%d×%d %s  %s (starter) mot %s: %d–%d, uavgjort %d · %.0f trekk per parti · tenketid %s: %s · %s: %s" % [
			size, size, size, "med regler" if rules else "fritt", starter, other, wins[1], wins[2], wins[0],
			float(moves) / games, starter, _times(times[starter]), other, _times(times[other])])
	print("Sammenlagt: %s %.1f – %s %.1f (%.0f %% til %s)" % [a, score[a], b, score[b], 100.0 * score[a] / (2 * games), a])
	quit()


static func _times(list: Array) -> String:
	if list.is_empty():
		return "-"
	list.sort()
	var total := 0
	for t in list:
		total += int(t)
	return "snitt %d ms, maks %d ms" % [total / list.size() / 1000, int(list[-1]) / 1000]


static func profile(spec: String) -> BotProfile:
	var parts := spec.split(",")
	var p := _base_profile(parts[0])
	for i in range(1, parts.size()):
		var kv := parts[i].split("=")
		if kv.size() == 2:
			p.search_tweaks[kv[0]] = int(kv[1])
	return p


static func _base_profile(name: String) -> BotProfile:
	if name.begins_with("dybde:"):
		var d := BotProfile.create(BotProfile.Level.HARD).with_search(600_000)
		d.search_depth = int(name.get_slice(":", 1))
		return d
	match name:
		"lett": return BotProfile.create(BotProfile.Level.EASY)
		"middels": return BotProfile.create(BotProfile.Level.MEDIUM)
		"gammel": return BotProfile.legacy_hard()
		"ekspert": return BotProfile.create(BotProfile.Level.EXPERT)
	if name.begins_with("søk:") or name.begins_with("sok:"):
		return BotProfile.create(BotProfile.Level.HARD).with_search(int(name.get_slice(":", 1)))
	return BotProfile.create(BotProfile.Level.HARD)


func _play(size: int, p1: String, p2: String, seed: int, rules: bool) -> Dictionary:
	var o := GameOptions.from_dict({ "size": size, "must_block": rules, "no_gift": rules })
	var s := GameState.new(o, 1)
	var bots := { 1: Bot.new(profile(p1)), 2: Bot.new(profile(p2)) }
	bots[1].rng.seed = seed
	bots[2].rng.seed = seed * 7 + 1
	var times := { 1: [], 2: [] }
	while not s.is_over():
		var t0 := Time.get_ticks_usec()
		var col: Vector2i = bots[s.current_player].choose_move(s)
		times[s.current_player].append(Time.get_ticks_usec() - t0)
		if not s.play(col).ok:
			push_error("Ulovlig trekk fra %s: %s" % [p1 if s.current_player == 1 else p2, col])
			break
	return { "winner": s.winner(), "moves": s.history.size(), "times": times }
