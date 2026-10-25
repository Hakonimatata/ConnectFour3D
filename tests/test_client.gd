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


func test_menu_shows_active_tournaments() -> void:
	await _frames(2)
	var menu := _screen() as MainMenu
	menu.show_tournaments([
		{ "id": 1, "name": "Ferdig cup", "status": "finished", "format": "knockout", "start_time": 0, "players": 4, "max_players": 8 },
		{ "id": 2, "name": "Vårcupen", "status": "open", "format": "knockout", "start_time": 2000000000, "players": 3, "max_players": 16 },
		{ "id": 3, "name": "Fredagsligaen", "status": "running", "format": "round_robin", "start_time": 1000, "players": 6, "max_players": 8 },
	])
	await _frames(1)
	check(menu._tour_box.visible, "aktive turneringer skal vises")
	var buttons := menu._tour_list.get_children().filter(func(c: Node) -> bool: return c is Button and not c.is_queued_for_deletion())
	check_eq(buttons.size(), 2, "ferdige turneringer vises ikke:")
	check((buttons[0] as Button).text.begins_with("Fredagsligaen"), "pågående først")
	menu.show_tournaments([])
	check(not menu._tour_box.visible, "skjules når ingen er aktive")
	# Menyen tar bare en titt på serveren: svarer den ikke, prøver den ikke igjen og igjen
	Net.close()
	Settings.server_url = "ws://127.0.0.1:9"   # ingen server her
	Net.connect_to_server("", false)
	check(await wait_until(func() -> bool: return Net.status == Net.Status.OFFLINE, 8.0),
		"menyen skal gi opp når serveren ikke svarer")


func test_menu_login_button_opens_account_and_back() -> void:
	await _frames(2)
	var menu := _screen() as MainMenu
	check(menu._account_button.visible, "knappen vises ved profilbildet")
	check_eq(menu._account_button.text, "Logg inn", "gjester ser «Logg inn»:")
	menu._on_account_pressed()
	await _frames(2)
	check(_screen() is AccountScreen, "innloggingen åpnes")
	(_screen() as AccountScreen)._on_back()
	await _frames(2)
	check(_screen() is MainMenu, "tilbake går til menyen")


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


func test_touch_drag_scrolls_settings_without_pressing_buttons() -> void:
	var old_size := app.get_window().size
	app.get_window().size = Vector2i(1280, 720)   # hodeløst er vinduet bare 64×64
	await _frames(2)
	app.show_settings()
	await _frames(3)
	var screen := _screen() as SettingsScreen
	var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	var old_skin := Settings.skin_id
	var target: Button = null
	for b in screen.find_children("*", "Button", true, false):
		if (b as Button).icon != null and (b as Button).text == "Lava":
			target = b
	check(target != null, "fant skin-knappen")
	check_eq(target.mouse_filter, Control.MOUSE_FILTER_PASS, "knapper i scroll slipper fingeren videre:")
	var vp := get_window_viewport()
	var to_window := vp.get_final_transform()   # UI-skalaen: fra lerretet til vindusposisjoner
	var start := to_window * target.get_global_rect().get_center()
	_touch(vp, start, true)
	for i in 8:
		_drag(vp, start + Vector2(0, -20.0 * (i + 1)), Vector2(0, -20))
		await _frames(1)
	_touch(vp, start + Vector2(0, -160), false)
	await _frames(2)
	check(scroll.scroll_vertical >= 100, "innholdet fulgte fingeren (scroll = %d)" % scroll.scroll_vertical)
	check_eq(Settings.skin_id, old_skin, "skin ble ikke valgt av et drag:")
	Settings.skin_id = old_skin
	app.get_window().size = old_size


func get_window_viewport() -> Viewport:
	return app.get_viewport()


func _touch(vp: Viewport, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	vp.push_input(e)


func _drag(vp: Viewport, at: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.device = InputEvent.DEVICE_ID_EMULATION
	e.position = at
	e.global_position = at
	e.relative = rel
	e.velocity = rel * 60.0
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e)


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


func test_settings_preview_board_theme_and_fx() -> void:
	var old := [Settings.skin_id, Settings.decal_id, Settings.decal_color_id, Settings.board_theme, Settings.win_fx_id]
	app.show_settings()
	await _frames(2)
	var screen := _screen() as SettingsScreen
	var old_elo := Settings.last_elo
	Settings.last_elo = 1500   # «Lyn» krever platina
	check_eq(app.board._pieces.size(), SettingsScreen.DEMO_LINE.size() + SettingsScreen.DEMO_P2.size(), "demo-stillingen vises:")
	Settings.skin_id = "glass"
	Settings.decal_id = "bolt"
	Settings.decal_color_id = "kit"
	screen._apply_looks()
	var piece: MeshInstance3D = app.board._pieces[Vector3i(0, 0, 0)]
	check_eq((piece.material_override as ShaderMaterial).shader, Skins.shader_for(Skins.Style.GLASS, Skins.decal_index("bolt")))
	var away_piece: MeshInstance3D = app.board._pieces[Vector3i(1, 0, 0)]
	check_eq((away_piece.material_override as ShaderMaterial).get_shader_parameter("color_a"), Skins.get_skin("glass").away.a,
		"spiller 2 vises i bortedrakt:")
	app.board.set_theme("oak")
	check_eq(app.board._board_top_mat.get_shader_parameter("grain"), 1.0)
	for fx in ["supernova", "glitter"]:
		Settings.win_fx_id = fx
		screen.play_fx_preview()
		await tree.create_timer(0.6, true, false, true).timeout
	check(app.camera.view_offset != Vector2.ZERO, "brettet flyttes bort fra kortet")
	Settings.skin_id = old[0]
	Settings.decal_id = old[1]
	Settings.decal_color_id = old[2]
	Settings.board_theme = old[3]
	Settings.win_fx_id = old[4]
	Settings.last_elo = old_elo
	app.show_menu()
	check(await wait_until(func() -> bool: return Engine.time_scale == 1.0, 2.0), "sakte film skal ikke henge igjen")


func test_replay_after_game_and_from_record() -> void:
	var m := OfflineMatch.new(GameOptions.from_dict({ "must_block": false, "no_gift": false }))
	app.start_match(m)
	await _frames(2)
	for mv in [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 3], [3, 0]]:
		m.submit_move(Vector2i(mv[0], mv[1]))
	await _frames(2)
	var gs := _screen() as GameScreen
	gs.start_replay()
	await _frames(1)
	check(gs._replay != null, "avspilleren vises")
	gs._replay.seek(3)
	check_eq(app.board._pieces.size(), 3)
	check(gs._replay.entries[4].forced, "trekk 5 (tre på rad) er tvunget")
	gs._replay.seek(7)
	check_eq(app.board._pieces.size(), 7)
	var play_img := ReplayPlayer._icon("play").get_image()
	var next_img := ReplayPlayer._icon("next").get_image()
	check(play_img.get_data() != next_img.get_data(), "spill av og neste ser forskjellige ut")
	gs._replay.closed.emit()
	await _frames(1)
	check(gs._replay == null and gs._result_overlay.visible, "«Lukk» gir resultatet tilbake")
	Engine.time_scale = 1.0
	# Reprise av et lagret parti (som fra profilen)
	var record := { "options": { "must_block": false, "no_gift": false }, "first": 1,
		"moves": [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 3], [3, 0]], "result": 1, "reason": 1,
		"players": [{ "name": "Ada", "skin": "plasma", "elo": 1300 }, { "name": "Bo" }], "time": "2026-10-21T18:03:00" }
	app.show_replay(record, app.show_menu)
	await _frames(2)
	var rs := _screen() as ReplayScreen
	check(rs != null, "reprise-skjermen vises")
	rs.player.seek(7)
	check_eq(app.board._pieces.size(), 7)
	rs._on_back()
	await _frames(2)
	check(_screen() is MainMenu)


func test_puzzle_screen_can_be_solved() -> void:
	app.show_puzzle()
	await _frames(2)
	var ps := _screen() as PuzzleScreen
	var p := Puzzle.generate("2026-10-21")
	ps.load_puzzle(p)
	var sol := Puzzle.solution(p)
	for i in range(0, sol.size(), 2):
		ps.play(sol[i])
		await tree.create_timer(PuzzleScreen.REPLY_DELAY_S + 0.2, true, false, true).timeout
	check(ps._solved, "oppgaven er løst")
	check_eq(Settings.puzzle_day, "2026-10-21")
	ps._retry()
	check(not ps._solved and ps._attempts == 2, "nytt forsøk")
	# Oppgavebanken: «Vanskelig» laster en oppgave med fem trekk
	ps.set_mode(3)
	check_eq(int(ps._puzzle.depth), 5)
	check(ps._progress.text.contains("15"), "fremdriften vises")
	ps.set_mode(0)
	# Et trekk som ikke truer noe, slipper motstanderen unna
	var s := Puzzle.start_state(p)
	for col in s.legal_moves():
		if not Puzzle._creates_threat(s, col, s.current_player):
			ps.play(col)
			break
	await tree.create_timer(PuzzleScreen.REPLY_DELAY_S + 0.2, true, false, true).timeout
	check(ps._retry_button.visible, "feil trekk gir «Prøv igjen»")
	Engine.time_scale = 1.0


func test_global_chat_keeps_history_when_menu_is_rebuilt() -> void:
	var old_msgs := Net.global_messages.duplicate()
	var old_presence := Net.presence.duplicate()
	Net._handle({ "t": Protocol.GLOBAL_HISTORY, "messages": [{ "kind": "chat", "from": "Ada", "elo": -1, "text": "Hei fra før" }] })
	Net._handle({ "t": Protocol.PRESENCE, "online": 7, "playing": 2 })
	Net._handle({ "t": Protocol.GLOBAL_MSG, "kind": "chat", "from": "Bob", "elo": -1, "text": "Ny melding" })
	app.show_settings()
	await _frames(2)
	app.show_menu()   # som å gå inn i en meny og tilbake
	await _frames(2)
	var chat := (_screen() as MainMenu)._chat
	var text := chat._log.get_parsed_text()
	check(text.contains("Hei fra før") and text.contains("Ny melding"), "chatten husker meldingene")
	check_eq(chat._online, 7, "og hvor mange som er online:")
	Net.global_messages = old_msgs
	Net.presence = old_presence


func test_chat_stays_open_while_typing_on_phone() -> void:
	var old_size := app.get_window().size
	app.get_window().size = Vector2i(400, 820)
	app.show_menu()
	await _frames(3)
	var menu := _screen() as MainMenu
	var chat := menu._chat
	chat._toggle.pressed.emit()   # åpne chatten
	await _frames(2)
	chat._input.grab_focus()
	app.ui.offset_bottom = -380.0   # som når skjermtastaturet kommer opp
	await _frames(3)
	check(chat.open and chat._log.visible and chat._input.visible, "chatten er fortsatt åpen")
	check(chat.compact, "beholder mobil-oppsettet mens man skriver")
	check(chat.size.y > menu.size.y * 0.8, "chatten fyller plassen over tastaturet (%d av %d)" % [chat.size.y, menu.size.y])
	chat._input.release_focus()
	app.ui.offset_bottom = 0.0
	await _frames(3)
	check(chat.open, "fortsatt åpen etter at tastaturet er borte")
	app.get_window().size = old_size


func test_global_chat_in_menu_and_locked_decals() -> void:
	await _frames(2)
	var menu := _screen() as MainMenu
	menu._chat.add_entry({ "kind": "event", "key": "%s rykket opp til %s!", "args": ["Ada", "Gull"],
		"text": "Ada rykket opp til Gull!" })
	menu._chat.add_entry({ "kind": "chat", "from": "Bo", "elo": 1500, "text": "Hei [alle]" })
	var text := menu._chat._log.get_parsed_text()
	check(text.contains("Ada rykket opp til Gull!"), "hendelser vises")
	check(text.contains("Hei [alle]"), "chat vises, med hakeparenteser")
	check_eq(GlobalChat.name_color("Ada"), GlobalChat.name_color("ada"), "samme navn, samme farge:")
	check(GlobalChat.name_color("Ada") != GlobalChat.name_color("Bob"), "ulike navn, ulike farger")
	var old_elo := Settings.last_elo
	Settings.last_elo = -1
	app.show_settings()
	await _frames(2)
	var locked := 0
	for b in _screen().find_children("*", "Button", true, false):
		if (b as Button).text == "Krone":
			check((b as Button).disabled, "gjester har ikke krone")
			locked += 1
	check_eq(locked, 1)
	Settings.last_elo = 1600
	check(EloTiers.decal_unlocked("crown", Settings.known_elo()), "Elo fra sist låser opp uten nett")
	Settings.last_elo = old_elo


func test_lobby_lists_live_games_and_puzzle_shows_colors() -> void:
	app.show_online()
	await _frames(2)
	var lobby := _screen() as LobbyScreen
	lobby.show_live([{ "code": "ABCDE", "moves": 12, "spectators": 2, "tournament": "",
		"players": [{ "name": "Ada", "elo": 1300, "skin": "lava" }, { "name": "Bob", "elo": null, "skin": "ocean" }] }])
	await _frames(1)
	var watch := 0
	for b in lobby._live_box.find_children("*", "Button", true, false):
		if (b as Button).text == "Se på":
			watch += 1
	check_eq(watch, 1, "«Se på» for partiet:")
	app.show_puzzle()
	await _frames(2)
	var ps := _screen() as PuzzleScreen
	ps.load_puzzle(Puzzle.generate("2026-10-21"))
	await _frames(1)
	var legend_text := []
	for l in ps._legend.find_children("*", "Label", true, false):
		legend_text.append((l as Label).text)
	check(legend_text.has("Dine brikker") and legend_text.has("Motstanderen"), "fargeforklaringen vises")


func test_spectator_room_hides_player_buttons() -> void:
	app.show_room({ "code": "ABCDE", "you": 0, "options": {}, "tournament": { "id": 3, "name": "Cup" }, "players": [
		{ "seat": 1, "name": "Ada", "skin": "ocean", "ready": false, "connected": true, "elo": 1300 },
		{ "seat": 2, "name": "Bo", "skin": "lava", "ready": false, "connected": true, "elo": 1250 }] })
	await _frames(2)
	var room := _screen() as RoomScreen
	check(not room._ready_button.visible and not room._skin_button.visible, "tilskuere kan ikke spille eller bytte skin")
	check_eq(room._leave_button.text, "Slutt å se på")


func test_change_settings_between_games_and_custom_clock() -> void:
	var m := OfflineMatch.new(GameOptions.from_dict({ "must_block": false, "no_gift": false }))
	app.start_match(m)
	await _frames(2)
	for mv in [[0, 0], [0, 3], [1, 0], [1, 3], [2, 0], [2, 3], [3, 0]]:
		m.submit_move(Vector2i(mv[0], mv[1]))
	await _frames(2)
	var gs := _screen() as GameScreen
	check(gs._change_button.visible, "«Endre innstillinger» etter partiet")
	gs.change_settings()
	await _frames(2)
	var setup := _screen() as SetupScreen
	check(setup != null and setup.mode == "local", "oppsettet åpnes for samme type parti")
	var spins := setup.find_children("*", "SpinBox", true, false)
	check_eq(spins.size(), 2, "minutter og sekunder per trekk:")
	(spins[0] as SpinBox).value = 7
	(spins[1] as SpinBox).value = 4
	for b in setup.find_children("*", "Button", true, false):
		if (b as Button).text == "Egen":
			(b as Button).pressed.emit()
	check_eq(setup.options.time_base_s, 420, "egne minutter:")
	check_eq(setup.options.time_increment_s, 4, "egne sekunder per trekk:")
	setup._on_start()
	await _frames(2)
	check(_screen() is GameScreen and app.current_match.options.time_base_s == 420, "nytt parti med ny klokke")
	Engine.time_scale = 1.0


func test_every_win_animation_runs() -> void:
	var m := OfflineMatch.new(GameOptions.from_dict({ "must_block": false, "no_gift": false }))
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
	server.data_dir = ":memory:"   # testene skal aldri skrive til de ekte brukerdataene
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
	# Venterommet viser motstanderens skin, og eget bytte går til serveren
	check(await wait_until(func() -> bool:
		poll_b.call()
		return (_screen() as RoomScreen)._preview_names.text.ends_with("Bo")
	), "venterommet viser ikke motstanderen")
	var old_skin := Settings.skin_id
	(_screen() as RoomScreen)._pick_skin("copper")
	check(await wait_until(func() -> bool:
		poll_b.call()
		var ps: Array = (_screen() as RoomScreen)._room.get("players", [])
		return ps.size() > 0 and ps[0] is Dictionary and ps[0].skin == "copper"
	), "skin-bytte i venterommet kom ikke fram")
	Settings.skin_id = old_skin
	Settings.save()
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
	check_eq(m.players[2].skin, "lime")
	if m.is_local_turn():
		app.board.column_tapped.emit(Vector2i(1, 1), false)
		check(await wait_until(func() -> bool:
			poll_b.call()
			return m.state.history.size() == 1
		), "trekket kom ikke tilbake fra serveren")
	b.close()


func test_account_profile_and_tournament_screens() -> void:
	server = ServerMain.new()
	server.port = PORT + 2   # egen port: Windows holder forrige tests port opptatt en stund
	server.data_dir = ":memory:"   # testene skal aldri skrive til de ekte brukerdataene
	root.add_child(server)
	server.lobby.accounts.iterations = 10
	var old_session := Settings.session_token
	Settings.server_url = "ws://127.0.0.1:%d" % (PORT + 2)
	app.show_online()
	check(await wait_until(func() -> bool: return Net.is_online()), "lobbyen koblet ikke til")

	# Registrer konto via skjermen
	app.show_account()
	await _frames(2)
	var acc := _screen() as AccountScreen
	acc._register = true
	acc._refresh()
	check(not acc._submit.disabled, "innlogging tillatt mot localhost")
	acc._user_edit.text = "Testadmin"
	acc._pass_edit.text = "hemmelig123"
	acc._pass2_edit.text = "hemmelig123"
	acc._on_submit()
	check(await wait_until(func() -> bool: return Net.is_logged_in()), "ble ikke logget inn")
	check(await wait_until(func() -> bool: return _screen() is LobbyScreen), "tilbake til lobbyen")

	# Profil og toppliste
	app.show_profile()
	check(await wait_until(func() -> bool:
		return (_screen() as ProfileScreen)._stats_box.get_child_count() > 3
	), "statistikken vises")

	# Gjør brukeren til admin (som å sette "admin": true i users.json) og lag en turnering
	server.lobby.accounts.set_admin("Testadmin", true)
	app.show_tournaments()
	check(await wait_until(func() -> bool: return (_screen() as TournamentsScreen)._new_button.visible), "admin ser «Ny turnering»")
	app.show_tournament_edit()
	await _frames(2)
	var edit := _screen() as TournamentEditScreen
	edit._name.text = "Testcup"
	edit._on_create()
	check(await wait_until(func() -> bool: return _screen() is TournamentScreen), "turneringssiden vises")
	var ts := _screen() as TournamentScreen
	check(await wait_until(func() -> bool: return ts._t.get("status") == "open"), "publisert")
	ts._send(Protocol.TOURNAMENT_JOIN)
	check(await wait_until(func() -> bool:
		return (ts._t.get("player_list", []) as Array).size() == 1
	), "påmeldt")
	Net.logout()
	await _frames(2)
	Settings.session_token = old_session
