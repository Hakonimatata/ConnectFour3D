extends TestCase
## Tester AI-analysen av partier (ai/move_review.gd, runde 15 og 17).

const FREE := { "must_block": false, "no_gift": false }


## Spiller 2 blokkerer ikke tre på rad, og spiller 1 tar ikke seieren etterpå: begge er tabber.
func test_missed_block_and_missed_win_are_blunders() -> void:
	var moves := [[0, 0], [0, 3], [1, 0], [3, 3], [2, 0], [1, 3], [0, 1]]
	var r := MoveReview.new(GameOptions.from_dict(FREE), 1, moves).run()
	check(r.done())
	check_eq(r.results.size(), 7)
	var miss_block: Dictionary = r.results[5]
	check_eq(miss_block.player, 2)
	check_eq(miss_block.grade, "blunder")
	check_eq(miss_block.reason, "missed_block")
	check_eq(miss_block.better, Vector3i(3, 0, 0), "markøren viser blokkeringen:")
	var miss_win: Dictionary = r.results[6]
	check_eq(miss_win.reason, "missed_win")
	check_eq(miss_win.better, Vector3i(3, 0, 0))
	check(MoveReview.describe(miss_win).contains(I18n.t("Tabbe!")), MoveReview.describe(miss_win))
	var sum := r.summary()
	check(int(sum[2].accuracy) < 90, "spiller 2 mister poeng: %d" % int(sum[2].accuracy))
	check_eq(int(sum[2].blunders), 1)
	check_eq(int(sum[1].blunders), 1)


## Å vinne når man kan, eller blokkere når man må, er beste trekk.
func test_winning_and_blocking_are_best() -> void:
	var blocked := MoveReview.new(GameOptions.from_dict(FREE), 1, [[0, 0], [0, 3], [1, 0], [3, 3], [2, 0], [3, 0]]).run()
	check_eq(blocked.results[5].grade, "best", "blokkeringen:")
	var won := MoveReview.new(GameOptions.from_dict(FREE), 1, [[0, 0], [0, 3], [1, 0], [3, 3], [2, 0], [1, 3], [3, 0]]).run()
	check_eq(won.results[6].grade, "best", "vinnertrekket:")
	check_eq(won.results[6].reason, "")
	check_eq(won.eval_text(7)[1], 1, "slutten: spiller 1 har vunnet")
	check_eq(won.evals[7], 100.0)


func test_accuracy_and_win_chance() -> void:
	check_eq(MoveReview.accuracy_for_drop(0.0), 100.0)
	check(MoveReview.accuracy_for_drop(3.0) >= MoveReview.GOOD, "litt dårligere er fortsatt bra")
	check_eq(MoveReview.grade_of(MoveReview.accuracy_for_drop(60.0)), "blunder")
	check_eq(MoveReview.grade_of(MoveReview.accuracy_for_drop(25.0)), "mistake")
	check_eq(MoveReview.win_percent(0), 50.0)
	check(MoveReview.win_percent(300) > 80.0 and MoveReview.win_percent(-300) < 20.0)
	check_eq(MoveReview.win_percent(SearchBot.WIN - 3), 100.0, "tvungen seier")
	check_eq(SearchBot.mate_in(SearchBot.WIN), 1, "vinner med dette trekket")
	check_eq(SearchBot.mate_in(SearchBot.WIN - 2), 2)
	check_eq(SearchBot.mate_in(-(SearchBot.WIN - 1)), -1, "motstanderen vinner med neste trekk")


## Analysen gjøres litt etter litt (step), så den ikke fryser skjermen.
func test_review_runs_in_small_steps() -> void:
	var moves := [[1, 1], [2, 2], [1, 2], [2, 1]]
	var r := MoveReview.new(GameOptions.new(), 1, moves)
	var steps := 0
	while not r.done() and steps < 100_000:
		var t := Time.get_ticks_usec()
		r.step()
		check(Time.get_ticks_usec() - t < 60_000, "ett steg tar litt tid, ikke mye")
		steps += 1
	check(r.done())
	check(steps > moves.size(), "flere steg enn trekk: %d" % steps)
	check(r.progress() == 1.0)
	check_eq(r.evals.size(), moves.size() + 1, "en verdi per stilling (stillingsmåleren)")


## Runde 17: analysen bruker søkeboten, så den sterke boten får høy treffsikkerhet og den lette lav.
## Og markøren for det bedre trekket står aldri i kolonnen brikken ble lagt i (feilen der markøren
## sto oppå brikken var trusselmarkøren; det bedre trekket er alltid et annet sted).
func test_strong_bot_scores_higher_than_easy_bot() -> void:
	var strong := BotProfile.create(BotProfile.Level.EXPERT)
	strong.search_ms = 60_000
	strong.search_depth = 4   # fast dybde: samme parti hver gang, uavhengig av maskinen
	var bots := { 1: Bot.new(strong), 2: Bot.new(BotProfile.create(BotProfile.Level.EASY)) }
	bots[1].rng.seed = 11
	bots[2].rng.seed = 12
	var s := GameState.new(GameOptions.new(), 1)
	while not s.is_over():
		s.play(bots[s.current_player].choose_move(s))
	var r := MoveReview.new(s.options, 1, s.history).run()
	var sum := r.summary()
	check(int(sum[1].accuracy) >= 90, "den sterke boten: %d %%" % int(sum[1].accuracy))
	check(int(sum[1].accuracy) > int(sum[2].accuracy) + 10, "den lette boten lavere: %d %%" % int(sum[2].accuracy))
	for res in r.results:
		var better: Vector3i = res.better
		if better.x >= 0:
			check(Vector2i(better.x, better.y) != res.col, "bedre trekk i en annen kolonne")
			check(str(res.reason) != "", "et bedre trekk har et tips")


## Tre på rad er bare verdt noe så lenge den ikke kan blokkeres: analysen sier fra når et trekk bruker
## opp en trussel (motstanderen bare blokkerer), både en ny og en spart en.
func test_spending_a_threat_is_explained() -> void:
	var o := GameOptions.from_dict(FREE)
	var fresh := GameState.from_moves(o, 1, [[0, 0], [0, 3], [1, 0], [3, 3]])
	check_eq(MoveReview.spent_threat(fresh, Vector2i(2, 0), 1), "spent_threat", "ny tre på rad som kan blokkeres straks:")
	check_eq(MoveReview.spent_threat(fresh, Vector2i(2, 2), 1), "", "et stille trekk:")
	# Spiller 1 har tre på rad i andre høyde; den siste plassen (3, 0, 1) kan ikke spilles ennå
	var saved := GameState.from_moves(o, 1, [[1, 0], [0, 0], [0, 0], [2, 0], [2, 0], [3, 3], [1, 0], [3, 2]])
	check_eq(MoveReview.spent_threat(saved, Vector2i(3, 0), 1), "under_own_threat", "rett under egen trussel:")
	check_eq(MoveReview.spent_threat(saved, Vector2i(3, 1), 1), "", "trusselen spares:")
	var info := MoveReview.position_info(saved, Vector2i(3, 1))
	check_eq(info.spends.get(Vector2i(3, 0), ""), "under_own_threat")
	# Et trekk som brukte opp trusselen og mistet vinnersjanse, får det tipset (ikke grunnen til det beste trekket)
	var r := MoveReview.judge(info, Vector2i(3, 0), 1, 150, -150)
	check(r.grade != "best", "trekket var dårligere")
	check_eq(r.reason, "under_own_threat")
	check(MoveReview.describe(r).ends_with(MoveReview.tip("under_own_threat")), MoveReview.describe(r))
	# Var det beste trekket også en trussel, er det den som forklares
	info.why = "threat"
	check_eq(MoveReview.judge(info, Vector2i(3, 0), 1, 150, -150).reason, "threat")


## «Tar plassen motstanderen trenger» bare når motstanderens tre på rad ikke kunne vært blokkert med en
## gang (ellers er det ingen fare).
func test_block_three_only_when_it_could_not_be_blocked() -> void:
	var o := GameOptions.from_dict(FREE)
	var open := GameState.from_moves(o, 1, [[2, 2], [0, 0], [3, 3], [1, 0]])
	check_eq(MoveReview.explain(open, Vector2i(2, 0), 1), "better_spot", "siste plass kan spilles:")
	var hanging := GameState.from_moves(o, 1, [[0, 0], [0, 0], [1, 0], [1, 0], [3, 3], [2, 0]])
	check_eq(MoveReview.explain(hanging, Vector2i(2, 0), 1), "block_three", "siste plass henger:")
