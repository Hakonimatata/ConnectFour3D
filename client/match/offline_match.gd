class_name OfflineMatch
extends MatchController
## Parti uten nett: to spillere på samme enhet, eller mot boten.
## Trening (runde 17, bare mot boten): uten klokke, og du kan angre trekk (undo). Spillskjermen viser
## stillingsmåleren, beste trekk og en vurdering av hvert trekk; mens den vurderer trekket ditt, venter
## boten (gate), så vurderingen rekker å bli ferdig.

const THINK_SLICE_USEC := 12_000   ## så lenge boten får tenke per bilde, så spillet ikke fryser

var bot: Bot = null
var bot_seat := 2
var training := false
## Boten legger først når denne gir true (treningen: når stillingen etter trekket ditt er vurdert)
var gate: Callable = func() -> bool: return true
var _rng := RandomNumberGenerator.new()
var _bot_game := -1        ## partiet boten tenker på (-1 = tenker ikke)
var _bot_ready_ms := 0     ## boten legger tidligst nå (kunstig tenketid og nedtellingen)


## Uten profil: lokalt to-spiller. Med profil: mot bot (boten er spiller 2). Med p_training: trening.
func _init(p_options: GameOptions, bot_profile: BotProfile = null, p_training := false) -> void:
	training = p_training and bot_profile != null
	if training:
		p_options = GameOptions.from_dict(p_options.to_dict())
		p_options.time_base_s = 0   # angring og klokke passer ikke sammen
		p_options.time_increment_s = 0
	options = p_options
	_rng.randomize()
	players[1] = { "name": Settings.display_name(), "avatar": Settings.avatar, "local": true, "subtitle": "" }
	players[1].merge(Settings.look(), true)
	if bot_profile != null:
		mode = "ai"
		bot = Bot.new(bot_profile)
		players[2] = { "name": tr("Bot"), "local": false, "subtitle": bot_profile.display_name }
		players[2].merge(Skins.look(Skins.DEFAULT_P2), true)
	else:
		mode = "local"
		players[1].name = tr("Spiller 1")
		players[2] = { "name": tr("Spiller 2"), "local": true, "subtitle": "" }
		players[2].merge(Skins.look(Skins.DEFAULT_P2), true)
	resolve_looks()


func my_seat() -> int:
	return 1 if mode == "ai" else 0


func start_game() -> void:
	game_number += 1
	var first := options.first_player(game_number, _rng)
	state = GameState.new(options, first)
	clock = ChessClock.new(options)
	play_at_ms = Time.get_ticks_msec() + countdown_ms
	if clock.enabled:
		clock.start(first, play_at_ms)
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


## Treningen: angrer ditt siste trekk (og botens svar på det). Går også etter at partiet er slutt.
## Gir false hvis det ikke er noe å angre.
func undo() -> bool:
	if not training or state == null:
		return false
	var human := GameState.opponent(bot_seat)
	# Hvor mange trekk tilbake til før ditt siste: botens svar (om det er lagt) og ditt trekk
	var back := 0
	for i in range(state.history.size() - 1, -1, -1):
		back += 1
		if _mover(i) == human:
			break
	if back == 0 or _mover(state.history.size() - back) != human:
		return false
	_bot_game = -1   # boten slutter å tenke på det gamle trekket
	for i in back:
		state.undo()
	undone.emit()
	turn_changed.emit(state.current_player)
	_maybe_let_bot_play()
	return true


## Hvem som la trekk nummer i (de bytter på).
func _mover(i: int) -> int:
	return state.first_player if i % 2 == 0 else GameState.opponent(state.first_player)


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


## Boten begynner å tenke. Den tenker litt hvert bilde (_think_bot), og legger når den er ferdig og
## den kunstige tenketiden og nedtellingen er over.
func _maybe_let_bot_play() -> void:
	if bot == null or state.is_over() or state.current_player != bot_seat:
		return
	_bot_game = game_number
	_bot_ready_ms = Time.get_ticks_msec() + int(bot.profile.think_time_s * 1000.0) + countdown_left_ms()
	bot.begin_move(state)


func _think_bot() -> void:
	if _bot_game < 0:
		return
	if _bot_game != game_number or state.is_over() or state.current_player != bot_seat:
		_bot_game = -1
		return
	if bot.think(THINK_SLICE_USEC) and Time.get_ticks_msec() >= _bot_ready_ms and gate.call():
		_bot_game = -1
		_apply(bot.chosen_move())


func _process(_delta: float) -> void:
	_think_bot()
	if state == null or state.is_over() or not clock.enabled:
		return
	var flagged := clock.flagged(Time.get_ticks_msec())
	if flagged != 0:
		state.end_with_loss(flagged, GameState.EndReason.TIMEOUT)
		_finish()
