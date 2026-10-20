class_name OfflineMatch
extends MatchController
## Parti uten nett: to spillere på samme enhet, eller mot boten.

var bot: Bot = null
var bot_seat := 2
var _rng := RandomNumberGenerator.new()


## Uten profil: lokalt to-spiller. Med profil: mot bot (boten er spiller 2).
func _init(p_options: GameOptions, bot_profile: BotProfile = null) -> void:
	options = p_options
	_rng.randomize()
	var own_skin: String = Settings.skin_id
	players[1] = { "name": Settings.player_name, "skin": own_skin, "local": true, "subtitle": "" }
	if bot_profile != null:
		mode = "ai"
		bot = Bot.new(bot_profile)
		players[2] = { "name": "Bot", "skin": Skins.contrast_for(own_skin, Skins.DEFAULT_P2),
			"local": false, "subtitle": bot_profile.display_name }
	else:
		mode = "local"
		players[1].name = "Spiller 1"
		players[2] = { "name": "Spiller 2", "skin": Skins.contrast_for(own_skin, Skins.DEFAULT_P2),
			"local": true, "subtitle": "" }


func my_seat() -> int:
	return 1 if mode == "ai" else 0


func start_game() -> void:
	game_number += 1
	var first := options.first_player(game_number, _rng)
	state = GameState.new(options, first)
	clock = ChessClock.new(options)
	if clock.enabled:
		clock.start(first, Time.get_ticks_msec())
	started.emit()
	turn_changed.emit(first)
	_maybe_let_bot_play()


func submit_move(col: Vector2i) -> void:
	if is_local_turn():
		_apply(col)


func resign() -> void:
	if state == null or state.is_over():
		return
	var loser := 1 if mode == "ai" else state.current_player
	state.end_with_loss(loser, GameState.EndReason.RESIGN)
	_finish()


func request_rematch() -> void:
	start_game()


func _apply(col: Vector2i) -> void:
	var err := state.check_move(col)
	if err != GameState.MoveError.OK:
		var hints: Array = []
		if err == GameState.MoveError.MUST_BLOCK:
			hints.assign(state.threat_positions(state.current_player))
		move_rejected.emit(GameState.error_text(err), hints)
		return
	var player := state.current_player
	var r := state.play(col)
	if clock.enabled:
		if state.is_over():
			clock.stop(Time.get_ticks_msec())
		else:
			clock.switch(Time.get_ticks_msec())
	move_applied.emit(col, r.pos, player)
	if state.is_over():
		_finish()
		return
	turn_changed.emit(state.current_player)
	_maybe_let_bot_play()


func _finish() -> void:
	clock.stop(Time.get_ticks_msec())
	finished.emit(state.result, state.end_reason, state.winning_line)


func _maybe_let_bot_play() -> void:
	if bot == null or state.is_over() or state.current_player != bot_seat:
		return
	var game := game_number
	await get_tree().create_timer(bot.profile.think_time_s).timeout
	if game != game_number or state.is_over() or state.current_player != bot_seat:
		return
	_apply(bot.choose_move(state))


func _process(_delta: float) -> void:
	if state == null or state.is_over() or not clock.enabled:
		return
	var flagged := clock.flagged(Time.get_ticks_msec())
	if flagged != 0:
		state.end_with_loss(flagged, GameState.EndReason.TIMEOUT)
		_finish()
