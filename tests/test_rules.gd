extends TestCase
## Tester for regelmotoren (core/). Hver test tilsvarer en regel i Plan.md, seksjon 2.


func _options(size := 4, must_block := false, no_gift := false) -> GameOptions:
	var o := GameOptions.new()
	o.size = size
	o.must_block = must_block
	o.no_gift = no_gift
	return o


## Setter brikker direkte uten turregler. pieces: [[x, y, spiller], ...] i rekkefølge.
func _setup(state: GameState, pieces: Array) -> void:
	for p in pieces:
		state.place(Vector2i(p[0], p[1]), p[2])
		state.history.append(Vector2i(p[0], p[1]))


func test_number_of_lines() -> void:
	check_eq(Lines.get_for(4, 4).count(), 76, "4×4×4:")
	check_eq(Lines.get_for(5, 4).count(), 302, "5×5×5:")


func test_every_line_has_distinct_cells_in_a_row() -> void:
	var lines := Lines.get_for(5, 4)
	for line in lines.cells:
		var a := lines.pos_of(line[0])
		var d := lines.pos_of(line[1]) - a
		check(d != Vector3i.ZERO, "null-retning")
		for k in 4:
			check_eq(lines.pos_of(line[k]), a + d * k, "linje ikke rett:")


func test_gravity_stacks_pieces() -> void:
	var s := GameState.new(_options())
	check_eq(s.play(Vector2i(1, 2)).pos, Vector3i(1, 2, 0))
	check_eq(s.play(Vector2i(1, 2)).pos, Vector3i(1, 2, 1))
	check_eq(s.get_cell(Vector3i(1, 2, 0)), 1)
	check_eq(s.get_cell(Vector3i(1, 2, 1)), 2)


func test_full_column_is_rejected() -> void:
	var s := GameState.new(_options())
	play_all(s, [[0, 0], [0, 0], [0, 0], [0, 0]])
	check_eq(s.check_move(Vector2i(0, 0)), GameState.MoveError.COLUMN_FULL)
	check_eq(s.check_move(Vector2i(4, 0)), GameState.MoveError.OUT_OF_BOUNDS)
	check(not Vector2i(0, 0) in s.legal_moves())


func test_turns_alternate() -> void:
	var s := GameState.new(_options(), 2)
	check_eq(s.current_player, 2)
	s.play(Vector2i(0, 0))
	check_eq(s.current_player, 1)


func test_win_horizontal() -> void:
	var s := GameState.new(_options())
	# P1 langs x på y=0, P2 langs x på y=1
	play_all(s, [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]])
	var r := s.play(Vector2i(3, 0))
	check(r.won, "skulle vunnet")
	check_eq(s.result, GameState.Result.P1_WON)
	check_eq(s.winning_line.size(), 4)
	check_eq(s.legal_moves().size(), 0, "ingen trekk etter seier:")


func test_win_vertical() -> void:
	var s := GameState.new(_options())
	play_all(s, [[0, 0], [1, 1], [0, 0], [1, 1], [0, 0], [2, 2]])
	check(s.play(Vector2i(0, 0)).won)


func test_win_space_diagonal() -> void:
	var s := GameState.new(_options())
	# P1 skal ha (0,0,0) (1,1,1) (2,2,2) (3,3,3)
	_setup(s, [
		[0, 0, 1],
		[1, 1, 2], [1, 1, 1],
		[2, 2, 2], [2, 2, 2], [2, 2, 1],
		[3, 3, 2], [3, 3, 2], [3, 3, 1],
	])
	check(s.wins_by(Vector2i(3, 3), 1), "P1 skal vinne på (3,3)")
	s.current_player = 1
	check(s.play(Vector2i(3, 3)).won)


func test_all_13_directions_win() -> void:
	# Legg fire brikker langs hver retning i 4×4×4 og sjekk at siste gir seier.
	var lines := Lines.get_for(4, 4)
	for d in Lines.DIRECTIONS:
		var found := false
		for line in lines.cells:
			if lines.pos_of(line[1]) - lines.pos_of(line[0]) != d:
				continue
			found = true
			var s := GameState.new(_options())
			# Fyll opp under hver celle med spiller 2, deretter spiller 1 i cellen.
			for k in 4:
				var p := lines.pos_of(line[k])
				var col := Vector2i(p.x, p.y)
				while s.column_height(col) < p.z:
					s.place(col, 2)
				if k < 3:
					s.place(col, 1)
			var last := lines.pos_of(line[3])
			check(s.wins_by(Vector2i(last.x, last.y), 1), "retning %s ga ikke seier" % str(d))
			break
		check(found, "fant ingen linje for retning %s" % str(d))


func test_gap_is_not_a_win_on_5x5x5() -> void:
	# Feilen i den gamle Python-koden: x = 0, 1, 3 + trekk på 4 ga «seier».
	var s := GameState.new(_options(5))
	_setup(s, [[0, 0, 1], [1, 0, 1], [3, 0, 1]])
	check(not s.wins_by(Vector2i(4, 0), 1), "hull på x=2 skal ikke gi seier")
	check(s.wins_by(Vector2i(2, 0), 1), "x=2 fullfører 0-1-2-3")


func test_opponent_outside_window_does_not_block_on_5x5x5() -> void:
	var s := GameState.new(_options(5))
	_setup(s, [[0, 0, 2], [1, 0, 1], [2, 0, 1], [3, 0, 1]])
	check(s.wins_by(Vector2i(4, 0), 1), "1-2-3-4 skal vinne selv om x=0 er motstanderens")


## Et ferdig parti uten fire på rad (funnet med et lite søk).
const DRAW_GAME := [[0, 0], [0, 0], [0, 0], [0, 0], [2, 0], [1, 0], [3, 0], [1, 0], [3, 0], [1, 0], [1, 0],
	[2, 0], [2, 0], [2, 0], [0, 1], [3, 0], [3, 0], [0, 1], [3, 1], [0, 1], [3, 1], [0, 1], [3, 1], [1, 1],
	[1, 1], [2, 1], [1, 1], [3, 1], [1, 1], [0, 2], [2, 1], [2, 2], [2, 1], [2, 1], [0, 2], [0, 2], [0, 2],
	[2, 2], [1, 2], [1, 2], [3, 2], [1, 2], [0, 3], [1, 2], [1, 3], [2, 2], [2, 2], [3, 2], [3, 2], [0, 3],
	[3, 2], [0, 3], [2, 3], [0, 3], [2, 3], [1, 3], [1, 3], [3, 3], [2, 3], [2, 3], [3, 3], [3, 3], [1, 3], [3, 3]]


func test_draw_when_board_full() -> void:
	var s := GameState.new(_options())
	play_all(s, DRAW_GAME.slice(0, 63))
	check_eq(s.result, GameState.Result.PLAYING)
	var r := s.play(Vector2i(3, 3))
	check(r.draw, "siste trekk skal gi uavgjort")
	check_eq(s.result, GameState.Result.DRAW)
	check_eq(s.end_reason, GameState.EndReason.BOARD_FULL)
	check_eq(s.winner(), 0)


func test_must_block() -> void:
	var s := GameState.new(_options(4, true))
	# P1 har tre langs x på y=0. P2 har tur og må blokkere (3,0).
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0]])
	check_eq(s.legal_moves(), [Vector2i(3, 0)] as Array[Vector2i])
	check_eq(s.check_move(Vector2i(2, 2)), GameState.MoveError.MUST_BLOCK)
	check_eq(s.threat_positions(2), [Vector3i(3, 0, 0)] as Array[Vector3i])


func test_must_block_allows_own_win() -> void:
	var s := GameState.new(_options(4, true))
	# Begge har tre på rad. P1 har tur: kan både vinne og blokkere, men ikke noe annet.
	_setup(s, [[0, 0, 1], [0, 3, 2], [1, 0, 1], [1, 3, 2], [2, 0, 1], [2, 3, 2]])
	var legal := s.legal_moves()
	check(Vector2i(3, 0) in legal, "vinnertrekk skal være lov")
	check(Vector2i(3, 3) in legal, "blokk skal være lov")
	check_eq(legal.size(), 2)


func test_without_must_block_anything_goes() -> void:
	var s := GameState.new(_options(4, false))
	play_all(s, [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0]])
	check_eq(s.legal_moves().size(), 16)


func test_no_gift() -> void:
	var s := GameState.new(_options(4, false, true))
	# P1 har tre langs x i høyde z=1 på y=0 (over P2-brikker). (3,0,1) er en vinnerplass for P1.
	_setup(s, [[0, 0, 2], [1, 0, 2], [2, 0, 1], [0, 0, 1], [1, 0, 1], [2, 0, 1]])
	s.current_player = 2
	check(s.gives_win_above(Vector2i(3, 0), 2), "å legge på (3,0) gir P1 (3,0,1)")
	check_eq(s.check_move(Vector2i(3, 0)), GameState.MoveError.GIVES_WIN)
	check(not Vector2i(3, 0) in s.legal_moves())
	check_eq(s.legal_moves().size(), 15)


func test_no_gift_top_layer_is_safe() -> void:
	var s := GameState.new(_options(4, false, true))
	check(not s.gives_win_above(Vector2i(0, 0), 1))
	play_all(s, [[0, 0], [0, 0], [0, 0]])
	check(not s.gives_win_above(Vector2i(0, 0), 2), "øverste lag har ikke noe felt over")


func test_rules_never_leave_zero_moves() -> void:
	# «Aldri låst»: med begge regler på finnes det alltid et lovlig trekk før brettet er fullt.
	var rng := RandomNumberGenerator.new()
	for size in [4, 5]:
		for game in 25:
			rng.seed = 1000 * size + game
			var s := GameState.new(_options(size, true, true))
			while not s.is_over():
				var moves := s.legal_moves()
				if moves.is_empty():
					check(false, "ingen lovlige trekk (størrelse %d, parti %d, trekk %d)" % [size, game, s.history.size()])
					return
				for m in moves:
					if s.check_move(m) != GameState.MoveError.OK:
						check(false, "legal_moves og check_move er uenige om %s" % str(m))
						return
				s.play(moves[rng.randi() % moves.size()])


func test_undo_restores_everything() -> void:
	var s := GameState.new(_options())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var snapshots: Array = []
	while not s.is_over():
		snapshots.append([s.cells.duplicate(), s.counts.duplicate(), s.heights.duplicate(), s.current_player])
		var moves := s.legal_moves()
		s.play(moves[rng.randi() % moves.size()])
	while not snapshots.is_empty():
		s.undo()
		var snap: Array = snapshots.pop_back()
		check_eq(s.cells, snap[0], "cells:")
		check_eq(s.counts, snap[1], "counts:")
		check_eq(s.heights, snap[2], "heights:")
		check_eq(s.current_player, snap[3], "tur:")
	check_eq(s.result, GameState.Result.PLAYING)


func test_from_moves_rebuilds_game() -> void:
	var s := GameState.new(_options())
	play_all(s, [[0, 0], [1, 1], [2, 2], [3, 3], [0, 0]])
	var copy := GameState.from_moves(s.options, 1, [[0, 0], [1, 1], [2, 2], [3, 3], [0, 0]])
	check_eq(copy.cells, s.cells)
	check_eq(copy.current_player, s.current_player)


func test_end_with_loss() -> void:
	var s := GameState.new(_options())
	s.end_with_loss(1, GameState.EndReason.TIMEOUT)
	check_eq(s.result, GameState.Result.P2_WON)
	check_eq(s.winner(), 2)
	check_eq(s.check_move(Vector2i(0, 0)), GameState.MoveError.GAME_OVER)


func test_options_from_dict_sanitizes() -> void:
	var o := GameOptions.from_dict({"size": 9, "time_base_s": -5, "starter": "hacker", "must_block": true})
	check_eq(o.size, 4)
	check_eq(o.time_base_s, 0)
	check_eq(o.starter, "p1")
	check_eq(o.must_block, true)
	var round_trip := GameOptions.from_dict(o.to_dict())
	check_eq(round_trip.to_dict(), o.to_dict())


func test_chess_clock() -> void:
	var o := GameOptions.new()
	o.time_base_s = 60
	o.time_increment_s = 2
	var c := ChessClock.new(o)
	c.start(1, 0)
	check_eq(c.time_left(1, 10_000), 50_000)
	check_eq(c.time_left(2, 10_000), 60_000)
	c.switch(10_000)                       # P1 brukte 10 s, får +2
	check_eq(c.time_left(1, 10_000), 52_000)
	check_eq(c.running_player, 2)
	check_eq(c.flagged(69_999), 0)
	check_eq(c.flagged(70_000), 2)        # P2 har brukt 60 s
	check_eq(ChessClock.format_ms(83_000), "1:23")
