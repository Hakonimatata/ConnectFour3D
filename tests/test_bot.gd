extends TestCase
## Tester for boten (ai/).


## Søket får kortere tid enn i spillet, så testene går fort (det er fortsatt mye sterkere enn før).
func _bot(level := BotProfile.Level.HARD, seed := 42, search_ms := 80) -> Bot:
	var profile := BotProfile.create(level)
	if profile.search_ms > 0:
		profile.search_ms = search_ms
	var b := Bot.new(profile)
	b.rng.seed = seed
	return b


func _setup(state: GameState, pieces: Array) -> void:
	for p in pieces:
		state.place(Vector2i(p[0], p[1]), p[2])
		state.history.append(Vector2i(p[0], p[1]))


func _no_rules() -> GameOptions:
	return GameOptions.from_dict({ "must_block": false, "no_gift": false })


func test_takes_immediate_win() -> void:
	var s := GameState.new(_no_rules())
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 2]])
	check_eq(_bot().choose_move(s), Vector2i(3, 0))


func test_blocks_immediate_win() -> void:
	var s := GameState.new(_no_rules())
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 2], [2, 0]])
	check_eq(_bot().choose_move(s), Vector2i(3, 0))


func test_finds_forced_win_from_old_notebook() -> void:
	# Stillingen fra «Bug Test» i den gamle notebooken. Boten (P2) skal spille (1, 2).
	var s := GameState.new(_no_rules())
	_setup(s, [
		[0, 0, 1], [0, 3, 1], [0, 3, 2], [0, 3, 2],
		[1, 1, 1], [1, 3, 1],
		[2, 0, 2], [2, 0, 1], [2, 0, 1],
		[2, 1, 2], [2, 1, 2], [2, 1, 2], [2, 1, 1],
		[3, 0, 2], [3, 0, 2], [3, 0, 2], [3, 0, 1],
		[0, 0, 1],
	])
	s.current_player = 2
	var bot := _bot()
	var t := Time.get_ticks_msec()
	check_eq(bot.choose_move(s), Vector2i(1, 2), "tvungen seier:")
	print("        (brukte %d ms)" % (Time.get_ticks_msec() - t))


func test_bot_leaves_board_unchanged() -> void:
	var s := GameState.new(_no_rules())
	play_all(s, [[0, 0], [1, 1], [2, 2], [1, 2]])
	var cells := s.cells.duplicate()
	var counts := s.counts.duplicate()
	_bot().choose_move(s)
	check_eq(s.cells, cells)
	check_eq(s.counts, counts)


func test_all_levels_only_play_legal_moves_with_rules() -> void:
	var o := GameOptions.new()
	o.must_block = true
	o.no_gift = true
	for level in [BotProfile.Level.EASY, BotProfile.Level.MEDIUM, BotProfile.Level.HARD, BotProfile.Level.EXPERT]:
		var s := GameState.new(o)
		var a := _bot(level, 1)
		var b := _bot(level, 2)
		while not s.is_over():
			var bot := a if s.current_player == 1 else b
			var m := bot.choose_move(s)
			if s.check_move(m) != GameState.MoveError.OK:
				check(false, "nivå %d spilte ulovlig %s" % [level, str(m)])
				return
			s.play(m)


func test_hard_beats_easy() -> void:
	var hard_wins := 0
	var games := 6
	var slowest := 0
	for g in games:
		var s := GameState.new(GameOptions.new(), 1 + g % 2)
		var hard := _bot(BotProfile.Level.HARD, g)
		var easy := _bot(BotProfile.Level.EASY, 100 + g)
		while not s.is_over():
			var t := Time.get_ticks_msec()
			var m := (hard if s.current_player == 1 else easy).choose_move(s)
			if s.current_player == 1:
				slowest = maxi(slowest, Time.get_ticks_msec() - t)
			s.play(m)
		if s.winner() == 1:
			hard_wins += 1
	print("        Vanskelig vant %d av %d, tregeste trekk %d ms" % [hard_wins, games, slowest])
	check(hard_wins >= games - 1, "Vanskelig skal nesten alltid slå Lett")


func test_hard_beats_medium_more_often() -> void:
	var hard_wins := 0
	var medium_wins := 0
	for g in 6:
		var s := GameState.new(GameOptions.new(), 1 + g % 2)
		var hard := _bot(BotProfile.Level.HARD, g)
		var medium := _bot(BotProfile.Level.MEDIUM, 200 + g)
		while not s.is_over():
			s.play((hard if s.current_player == 1 else medium).choose_move(s))
		if s.winner() == 1:
			hard_wins += 1
		elif s.winner() == 2:
			medium_wins += 1
	print("        Vanskelig %d – Middels %d" % [hard_wins, medium_wins])
	check(hard_wins > medium_wins, "Vanskelig skal vinne oftere enn Middels")


## Søkets egne tabeller (vinnerplasser og linjer) følger regelmotoren gjennom et helt parti, også på 5×5×5.
func test_search_tables_match_the_rules_engine() -> void:
	for size in [4, 5]:
		var o := GameOptions.from_dict({ "size": size, "must_block": false, "no_gift": false })
		var s := GameState.new(o)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var search := SearchBot.new()
		while not s.is_over():
			search._setup(s)
			for c in s.open_columns():
				var cell := s.lines.index_of(s.landing_pos(c))
				for p in [1, 2]:
					if (search._wins[p * search.n_cells + cell] > 0) != s.is_winning_cell(cell, p):
						check(false, "%d×%d×%d: vinnerplass for %d i %s stemmer ikke" % [size, size, size, p, c])
						return
			# Legg og ta bort et trekk: alt skal bli som før
			var before := [search._counts.duplicate(), search._wins.duplicate(), search._line_score, search._hash]
			var moves := s.open_columns()
			var col: Vector2i = moves[rng.randi() % moves.size()]
			search._place(col.x + size * col.y, s.current_player)
			search._unplace(col.x + size * col.y, s.current_player)
			check_eq([search._counts, search._wins, search._line_score, search._hash], before, "legg + ta bort:")
			s.play(col, false)


## Den nye Vanskelig (søk) slår den gamle Vanskelig, både som starter og ikke.
func test_search_beats_the_old_hard_bot() -> void:
	var new_wins := 0
	var old_wins := 0
	for g in 4:
		var s := GameState.new(GameOptions.new(), 1)
		# Fast dybde (ikke tid), så resultatet ikke avhenger av hvor travel maskinen er
		var new_bot := _bot(BotProfile.Level.HARD, g, 5000)
		new_bot.profile.search_depth = 2
		var old_bot := Bot.new(BotProfile.legacy_hard())
		old_bot.rng.seed = 300 + g
		var new_seat := 1 + g % 2
		while not s.is_over():
			s.play((new_bot if s.current_player == new_seat else old_bot).choose_move(s))
		if s.winner() == new_seat:
			new_wins += 1
		elif s.winner() != 0:
			old_wins += 1
	print("        ny Vanskelig %d – gammel Vanskelig %d" % [new_wins, old_wins])
	check(new_wins >= 3, "den nye skal vinne nesten alle")


## I spillet tenker boten litt om gangen (think) og fryser ikke skjermen.
func test_search_thinks_in_small_slices() -> void:
	var s := GameState.new(GameOptions.new())
	play_all(s, [[1, 1], [2, 2], [1, 2], [2, 1], [0, 0], [3, 3]])
	var bot := _bot(BotProfile.Level.HARD, 1, 300)
	bot.begin_move(s)
	var slices := 0
	var longest := 0
	while true:
		var t := Time.get_ticks_usec()
		var done := bot.think(5000)
		longest = maxi(longest, Time.get_ticks_usec() - t)
		slices += 1
		if done:
			break
	check(slices > 3, "tenkte i flere biter (%d)" % slices)
	check(longest < 60_000, "ingen bit tok lang tid (lengste %d µs)" % longest)
	check_eq(s.check_move(bot.chosen_move()), GameState.MoveError.OK, "lovlig trekk:")
	check_eq(s.history.size(), 6, "stillingen er urørt")


## Søket ser tvungne seire som går dypere enn det taktiske søket alene.
func test_search_wins_quickly_on_5x5x5() -> void:
	var s := GameState.new(GameOptions.from_dict({ "size": 5 }), 1)
	var new_bot := _bot(BotProfile.Level.HARD, 3, 150)
	var old_bot := Bot.new(BotProfile.legacy_hard())
	old_bot.rng.seed = 9
	while not s.is_over():
		s.play((new_bot if s.current_player == 1 else old_bot).choose_move(s))
	check_eq(s.winner(), 1, "søket vinner på 5×5×5:")
	check(s.history.size() < 40, "og det går fort (%d trekk)" % s.history.size())
