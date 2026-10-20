extends TestCase
## Tester for boten (ai/).


func _bot(level := BotProfile.Level.HARD, seed := 42) -> Bot:
	var b := Bot.new(BotProfile.create(level))
	b.rng.seed = seed
	return b


func _setup(state: GameState, pieces: Array) -> void:
	for p in pieces:
		state.place(Vector2i(p[0], p[1]), p[2])
		state.history.append(Vector2i(p[0], p[1]))


func test_takes_immediate_win() -> void:
	var s := GameState.new()
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 2]])
	check_eq(_bot().choose_move(s), Vector2i(3, 0))


func test_blocks_immediate_win() -> void:
	var s := GameState.new()
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 2], [2, 0]])
	check_eq(_bot().choose_move(s), Vector2i(3, 0))


func test_finds_forced_win_from_old_notebook() -> void:
	# Stillingen fra «Bug Test» i den gamle notebooken. Boten (P2) skal spille (1, 2).
	var s := GameState.new()
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
	var s := GameState.new()
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
	for level in [BotProfile.Level.EASY, BotProfile.Level.MEDIUM, BotProfile.Level.HARD]:
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
