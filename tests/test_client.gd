extends TestCase
## Røyktest av klienten: går gjennom skjermene og spiller partier via UI-et,
## slik at skriptfeil i meny, HUD, effekter og online-flyt blir oppdaget.

const PORT := 18766

var app: ClientRoot
var server: ServerMain
var _saved_url := ""


func before_each() -> void:
	_saved_url = Settings.server_url
	app = ClientRoot.new()
	root.add_child(app)


func after_each() -> void:
	Net.close()
	Settings.server_url = _saved_url
	app.queue_free()
	if server:
		server.queue_free()
	Engine.time_scale = 1.0
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _screen() -> Control:
	return app._screen


func test_menu_setup_and_settings_screens() -> void:
	await _frames(3)
	check(_screen() is MainMenu, "starter i hovedmenyen")
	await tree.create_timer(1.0).timeout   # la demo-botene spille litt
	for mode in ["ai", "local", "online"]:
		app.show_setup(mode)
		await _frames(2)
		check(_screen() is SetupScreen)
	app.show_settings()
	await _frames(2)
	check(_screen() is SettingsScreen)
	app.show_menu()
	await _frames(2)
	check(_screen() is MainMenu)


func test_ai_game_to_the_end() -> void:
	var o := GameOptions.new()
	o.must_block = true
	o.time_base_s = 60
	var profile := BotProfile.create(BotProfile.Level.MEDIUM)
	profile.think_time_s = 0.01
	var m := OfflineMatch.new(o, profile)
	app.start_match(m)
	await _frames(2)
	check(_screen() is GameScreen)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var guard := 0
	while not m.state.is_over() and guard < 400:
		guard += 1
		if m.is_local_turn():
			var moves := m.state.legal_moves()
			# Gå via brettet slik et museklikk ville gjort
			app.board.column_tapped.emit(moves[rng.randi() % moves.size()], false)
		await _frames(1)
	check(m.state.is_over(), "partiet ble ikke ferdig")
	var game_screen: GameScreen = _screen()
	check(await wait_until(func() -> bool: return game_screen._result_overlay.visible, 6.0), "resultat vises ikke")
	# Spill igjen
	game_screen._rematch_button.pressed.emit()
	await _frames(2)
	check(not m.state.is_over(), "nytt parti startet ikke")
	check_eq(m.game_number, 2)


func test_settings_avatar_pick_and_clear() -> void:
	app.show_settings()
	await _frames(2)
	var screen := _screen() as SettingsScreen
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.GREEN)
	var before := Settings.avatar
	screen._on_avatar_picked(img.save_png_to_buffer())
	check(Settings.avatar != "", "bildet skal lagres")
	check(screen._avatar_view.texture != null, "bildet skal vises")
	screen._clear_avatar()
	check_eq(Settings.avatar, "")
	Settings.avatar = before


func test_every_win_animation_runs() -> void:
	var m := OfflineMatch.new(GameOptions.new())
	app.start_match(m)
	await _frames(2)
	for mv in [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 3], [3, 0]]:
		m.submit_move(Vector2i(mv[0], mv[1]))
	await _frames(2)
	for fx in Skins.WIN_FX:
		WinFx.play(app.board, app.camera, m.state.winning_line, Color.ORANGE, fx.id)
		await tree.create_timer(0.7, true, false, true).timeout
	Engine.time_scale = 1.0
	check(true)


func test_language_switch_and_chat_presets() -> void:
	var old_lang := Settings.language
	var old_presets := Settings.chat_presets.duplicate()
	app.show_settings()
	await _frames(2)
	(_screen() as SettingsScreen)._set_language("en")
	await _frames(2)
	check(_screen() is SettingsScreen, "innstillingene vises igjen")
	check_eq(tr("Lagre"), "Save")
	check_eq(Settings.chat_messages()[0], "Good luck!", "standardmeldinger følger språket:")
	var screen := _screen() as SettingsScreen
	screen._preset_edits[0].text = "Hei hei"
	screen._store_fields()
	check_eq(Settings.chat_messages()[0], "Hei hei")
	var chat := ChatPanel.new()
	root.add_child(chat)
	await _frames(1)
	var found := false
	for b in chat.find_children("*", "Button", true, false):
		if (b as Button).text == "Hei hei":
			found = true
	check(found, "chatten viser egne hurtigmeldinger")
	chat.queue_free()
	Settings.chat_presets.assign(old_presets)
	Settings.language = old_lang
	I18n.apply(old_lang)


func test_local_game_touch_needs_two_taps_and_5x5() -> void:
	var o := GameOptions.new()
	o.size = 5
	var m := OfflineMatch.new(o)
	app.start_match(m)
	await _frames(2)
	app.board.column_tapped.emit(Vector2i(4, 4), true)
	await _frames(1)
	check_eq(m.state.history.size(), 0, "første trykk på touch skal bare vise brikken")
	app.board.column_tapped.emit(Vector2i(4, 4), true)
	await _frames(1)
	check_eq(m.state.history.size(), 1, "andre trykk legger brikken")
	check_eq(m.state.get_cell(Vector3i(4, 4, 0)), 1)
	m.resign()
	await _frames(1)
	check_eq(m.state.winner(), 1, "spiller 2 hadde tur og ga opp")
	# Etter partiet skal «Meny» vise resultatet, ikke pausemenyen med «Gi opp».
	var gs: GameScreen = _screen()
	gs._open_menu()
	check(gs._result_overlay.visible, "resultatet vises")
	check(not gs._menu_overlay.visible, "pausemenyen (med Gi opp) vises ikke")


func test_online_lobby_room_and_game() -> void:
	server = ServerMain.new()
	server.port = PORT
	root.add_child(server)
	Settings.server_url = "ws://127.0.0.1:%d" % PORT

	app.show_online()
	check(await wait_until(func() -> bool: return Net.is_online()), "lobbyen koblet ikke til")
	# Opprett rom slik brukeren gjør: Lobby -> «Opprett rom» -> oppsett -> «Opprett rom».
	(_screen() as LobbyScreen)._on_create()
	await _frames(2)
	check(_screen() is SetupScreen, "skal vise oppsett")
	(_screen() as SetupScreen)._on_start()
	check(await wait_until(func() -> bool: return _screen() is RoomScreen), "kom ikke til venterommet")
	var code: String = (_screen() as RoomScreen)._room.code
	# «Endre regler» -> oppsett -> «Lagre» skal gi tilbake til samme rom.
	(_screen() as RoomScreen)._edit_options()
	await _frames(2)
	var setup := _screen() as SetupScreen
	setup.options.must_block = true
	setup._on_start()
	check(await wait_until(func() -> bool:
		return _screen() is RoomScreen and (_screen() as RoomScreen)._room.get("options", {}).get("must_block", false)
	), "reglene ble ikke lagret i rommet")

	# En motstander kobler til direkte
	var b := WebSocketPeer.new()
	b.connect_to_url(Settings.server_url)
	var poll_b := func() -> bool:
		b.poll()
		while b.get_available_packet_count() > 0:
			b.get_packet()
		return b.get_ready_state() == WebSocketPeer.STATE_OPEN
	check(await wait_until(poll_b), "motstander koblet ikke til")
	b.send_text(Protocol.encode({ "t": "hello", "name": "Bo", "skin": "lime", "version": Protocol.VERSION }))
	b.send_text(Protocol.encode({ "t": "join_room", "code": code }))
	b.send_text(Protocol.encode({ "t": "ready", "ready": true }))
	await wait_until(func() -> bool:
		poll_b.call()
		return false
	, 0.3)
	(_screen() as RoomScreen)._toggle_ready()
	check(await wait_until(func() -> bool:
		poll_b.call()
		return _screen() is GameScreen
	), "partiet startet ikke")
	var m: OnlineMatch = app.current_match
	check_eq(m.players[2].name, "Bo")
	if m.is_local_turn():
		app.board.column_tapped.emit(Vector2i(1, 1), false)
		check(await wait_until(func() -> bool:
			poll_b.call()
			return m.state.history.size() == 1
		), "trekket kom ikke tilbake fra serveren")
	b.close()
