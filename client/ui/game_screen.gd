class_name GameScreen
extends Screen
## Spillskjermen: HUD (spillere, klokker, status), meny, resultat og chat.
## Snakker bare med en MatchController og BoardView.

var match_ctrl: MatchController
var _cards := {}            ## spiller -> { panel, clock, name }
var _status: Label
var _status_timer := 0.0
var _menu_overlay: Control
var _result_overlay: Control
var _result_title: Label
var _result_reason: Label
var _rematch_button: Button
var _chat_drawer: Control
var _chat: ChatPanel
var _chat_button: Button
var _flash: ColorRect
var _touch_hint_shown := false
var _last_tick_s := -1


func _init(p_app: ClientRoot, p_match: MatchController) -> void:
	super(p_app)
	match_ctrl = p_match


func _ready() -> void:
	app.camera.auto_rotate = false
	_build_hud()
	match_ctrl.started.connect(_on_started)
	match_ctrl.move_applied.connect(_on_move_applied)
	match_ctrl.move_rejected.connect(_on_move_rejected)
	match_ctrl.turn_changed.connect(_on_turn_changed)
	match_ctrl.finished.connect(_on_finished)
	match_ctrl.chat_received.connect(_on_chat)
	match_ctrl.info.connect(func(t: String) -> void: _show_status(t, UI.MUTED, 3.0))
	match_ctrl.players_changed.connect(_refresh_players)
	app.board.column_tapped.connect(_on_column_tapped)
	app.board.column_hovered.connect(_on_column_hovered)


func _exit_tree() -> void:
	app.board.column_tapped.disconnect(_on_column_tapped)
	app.board.column_hovered.disconnect(_on_column_hovered)
	app.board.input_enabled = false
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	# Topp: spillerkort
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + side, 12)
	add_child(top)
	var cards := UI.hbox(10)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(cards)
	for p in [1, 2]:
		cards.add_child(_make_card(p))

	# Bunn: meny, status, chat
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		bottom.add_theme_constant_override("margin_" + side, 12)
	add_child(bottom)
	var bar := UI.hbox(10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bar)
	bar.add_child(UI.button("Meny", _open_menu))
	_status = UI.label("", "", HORIZONTAL_ALIGNMENT_CENTER)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_status.add_theme_constant_override("shadow_offset_y", 2)
	bar.add_child(_status)
	_chat_button = UI.button("Chat", _toggle_chat)
	_chat_button.visible = match_ctrl.supports_chat()
	bar.add_child(_chat_button)
	if not match_ctrl.supports_chat():
		# Hold status midtstilt: tom plass på høyre side like bred som Meny-knappen.
		var pad := Control.new()
		pad.custom_minimum_size.x = 80
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(pad)

	_build_chat_drawer()

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_build_menu_overlay()
	_build_result_overlay()


func _make_card(player: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UI.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var avatar := AvatarView.new(36)
	row.add_child(avatar)
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UI.label("")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	var sub := UI.label("", "Muted")
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	names.add_child(name_label)
	names.add_child(sub)
	row.add_child(names)
	var clock := UI.label("")
	clock.add_theme_font_size_override("font_size", 22)
	clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(clock)
	_cards[player] = { "panel": panel, "avatar": avatar, "name": name_label, "sub": sub, "clock": clock }
	return panel


func _refresh_players() -> void:
	for p in [1, 2]:
		var c: Dictionary = _cards[p]
		var info: Dictionary = match_ctrl.players[p]
		var label: String = info.name
		if match_ctrl.my_seat() == p:
			label = tr("%s (deg)") % label
		c.name.text = label
		c.sub.text = info.get("subtitle", "")
		c.sub.visible = c.sub.text != ""
		(c.avatar as AvatarView).set_avatar(str(info.get("avatar", "")), str(info.name), match_ctrl.color_of(p))
	app.board.set_looks(match_ctrl.look_of(1), match_ctrl.look_of(2))
	_highlight_turn()


func _highlight_turn() -> void:
	var s := match_ctrl.state
	for p in [1, 2]:
		var active: bool = s != null and not s.is_over() and s.current_player == p
		var border := match_ctrl.color_of(p) if active else UI.BORDER
		var box := UI._box(UI.PANEL if not active else UI.PANEL_LIGHT, UI.RADIUS, border, 14, 10)
		if active:
			box.set_border_width_all(2)
		_cards[p].panel.add_theme_stylebox_override("panel", box)


## Under partiet: pausemeny (med «Gi opp»). Etter partiet: resultatet (spill igjen / meny).
func _open_menu() -> void:
	var s := match_ctrl.state
	if s != null and s.is_over():
		_menu_overlay.visible = false
		_result_overlay.visible = true
	else:
		_menu_overlay.visible = true


func _build_menu_overlay() -> void:
	_menu_overlay = _overlay()
	var v := UI.centered_card(_menu_overlay, 360)
	v.add_child(UI.label("Pause", "Heading"))
	v.add_child(UI.label(match_ctrl.options.describe(), "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UI.button("Fortsett", func() -> void: _menu_overlay.visible = false, "PrimaryButton"))
	v.add_child(UI.button("Gi opp", func() -> void:
		_menu_overlay.visible = false
		match_ctrl.resign()
	))
	v.add_child(UI.button("Til hovedmenyen", func() -> void: app.show_menu()))


func _build_result_overlay() -> void:
	_result_overlay = _overlay()
	_result_overlay.color = Color(0, 0, 0, 0.35)
	var v := UI.centered_card(_result_overlay, 380)
	_result_title = UI.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_result_reason = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_result_title)
	v.add_child(_result_reason)
	v.add_child(UI.spacer(6))
	_rematch_button = UI.button("Spill igjen", func() -> void:
		_rematch_button.disabled = match_ctrl.mode == "online"
		match_ctrl.request_rematch()
	, "PrimaryButton")
	v.add_child(_rematch_button)
	v.add_child(UI.button("Se på brettet", func() -> void: _result_overlay.visible = false))
	v.add_child(UI.button("Til hovedmenyen", func() -> void: app.show_menu()))


func _build_chat_drawer() -> void:
	_chat_drawer = MarginContainer.new()
	_chat_drawer.visible = false
	add_child(_chat_drawer)
	_chat = ChatPanel.new()
	_chat_drawer.add_child(_chat)
	_chat.send_requested.connect(func(t: String) -> void: match_ctrl.send_chat(t))
	resized.connect(_layout_chat)
	_layout_chat.call_deferred()


func _layout_chat() -> void:
	# Liggende: panel til høyre. Stående: panel over bunnlinjen.
	if size.x > size.y:
		_chat_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_chat_drawer.offset_left = -minf(380.0, size.x * 0.4)
		_chat_drawer.offset_right = -12
		_chat_drawer.offset_top = 100
		_chat_drawer.offset_bottom = -80
	else:
		_chat_drawer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_chat_drawer.offset_left = 12
		_chat_drawer.offset_right = -12
		_chat_drawer.offset_top = -size.y * 0.45
		_chat_drawer.offset_bottom = -80


func _toggle_chat() -> void:
	_chat_drawer.visible = not _chat_drawer.visible
	_chat_button.text = "Chat"


func _overlay() -> ColorRect:
	var o := ColorRect.new()
	o.color = Color(0, 0, 0, 0.55)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	add_child(o)
	return o


# ---------------------------------------------------------------- Hendelser fra partiet

func _on_started() -> void:
	var s := match_ctrl.state
	_result_overlay.visible = false
	_rematch_button.disabled = false
	app.board.setup(s.size)
	_refresh_players()
	# Tegn brikker som allerede finnes (f.eks. ved gjenkobling online).
	for i in s.cells.size():
		if s.cells[i] != 0:
			app.board.add_piece(s.lines.pos_of(i), s.cells[i], false)
	app.board.input_enabled = true
	_update_turn_status()
	_update_clocks()


func _on_move_applied(_col: Vector2i, pos: Vector3i, player: int) -> void:
	app.board.hide_target()
	app.board.clear_hints()
	app.board.add_piece(pos, player)
	Sfx.play("drop", 1.0 if player == 1 else 0.85)
	Settings.vibrate(20)


func _on_move_rejected(text: String, hints: Array) -> void:
	_show_status(text, UI.DANGER, 2.0)
	Sfx.play("error")
	Settings.vibrate(60)
	if not hints.is_empty():
		app.board.show_hints(hints)


func _on_turn_changed(_player: int) -> void:
	_highlight_turn()
	app.board.refresh_hover()
	_update_turn_status()
	var s := match_ctrl.state
	# Med «må blokkere» viser vi med en gang hvor man må legge.
	if match_ctrl.is_local_turn() and s.options.must_block and s.winning_columns(s.current_player).is_empty():
		var threats := s.threat_positions(s.current_player)
		if not threats.is_empty():
			app.board.show_hints(threats)


func _on_finished(result: int, reason: int, line: Array) -> void:
	app.board.input_enabled = false
	app.board.hide_target()
	app.board.clear_hints()
	_highlight_turn()
	var s := match_ctrl.state
	var winner := s.winner()
	var me := match_ctrl.my_seat()

	if result == GameState.Result.DRAW:
		_result_title.text = "Uavgjort"
	elif me == 0:
		_result_title.text = tr("%s vant!") % match_ctrl.players[winner].name
	elif winner == me:
		_result_title.text = "Du vant!"
	else:
		_result_title.text = "Du tapte"
	var reasons := {
		GameState.EndReason.LINE: "Fire på rad",
		GameState.EndReason.BOARD_FULL: "Brettet er fullt",
		GameState.EndReason.TIMEOUT: "Tiden gikk ut",
		GameState.EndReason.RESIGN: "Ga opp",
		GameState.EndReason.DISCONNECT: "Motstanderen forlot partiet",
	}
	_result_reason.text = reasons.get(reason, "")
	_show_status(_result_title.text, UI.TEXT, 0.0)

	var delay := 0.4
	if not line.is_empty():
		app.board.highlight(line)
		app.board.dim_except(line)
		var color := match_ctrl.color_of(winner)
		# Vent til den siste brikken har landet før smellet.
		await get_tree().create_timer(0.38).timeout
		WinFx.play(app.board, app.camera, line, color, str(match_ctrl.players[winner].get("win_fx", "classic")))
		_flash.color = Color(color.lerp(Color.WHITE, 0.7), 0.28)
		var t := create_tween().set_ignore_time_scale(true)
		t.tween_property(_flash, "color:a", 0.0, 0.4)
		delay = 1.6
	if me != 0 and winner != me and result != GameState.Result.DRAW:
		Sfx.play("lose")
	else:
		Sfx.play("win")
	await get_tree().create_timer(delay, true, false, true).timeout
	if is_inside_tree() and match_ctrl.state == s:
		_result_overlay.visible = true


func _on_chat(from_name: String, text: String) -> void:
	_chat.add_message(from_name, text)
	if not _chat_drawer.visible:
		_chat_button.text = "Chat •"
		_show_status("%s: %s" % [from_name, text], UI.TEXT, 3.0)


# ---------------------------------------------------------------- Input fra brettet

func _on_column_hovered(col: Vector2i) -> void:
	var s := match_ctrl.state
	if col == BoardView.NO_COLUMN or not match_ctrl.is_local_turn() or not s.is_column_open(col):
		app.board.hide_target()
		return
	app.board.show_target(s.landing_pos(col), s.current_player, col)


func _on_column_tapped(col: Vector2i, from_touch: bool) -> void:
	var s := match_ctrl.state
	if not match_ctrl.is_local_turn():
		return
	if not s.is_column_open(col):
		_on_move_rejected(GameState.error_text(GameState.MoveError.COLUMN_FULL), [])
		return
	# På touch: første trykk viser hvor brikken lander, andre trykk legger den.
	if from_touch and (app.board.target_column() != col or not app.board.ghost_visible()):
		app.board.show_target(s.landing_pos(col), s.current_player, col, true)
		Sfx.play("click")
		if not _touch_hint_shown:
			_touch_hint_shown = true
			_show_status("Trykk igjen for å legge brikken", UI.MUTED, 2.5)
		return
	match_ctrl.submit_move(col)


# ---------------------------------------------------------------- Status og klokker

func _update_turn_status() -> void:
	var s := match_ctrl.state
	if s == null or s.is_over():
		return
	var p := s.current_player
	var text := ""
	match match_ctrl.mode:
		"local":
			text = tr("%s sin tur") % match_ctrl.players[p].name
		"ai":
			text = "Din tur" if match_ctrl.is_local_turn() else "Boten tenker…"
		_:
			text = tr("Din tur") if match_ctrl.is_local_turn() else tr("Venter på %s…") % match_ctrl.players[p].name
	_show_status(text, match_ctrl.color_of(p).lerp(Color.WHITE, 0.45), 0.0)


## duration 0 = blir stående. Ellers går den tilbake til turstatus etterpå.
func _show_status(text: String, color: Color, duration: float) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status_timer = duration


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_update_turn_status()
	_update_clocks()


func _update_clocks() -> void:
	var s := match_ctrl.state
	var enabled := match_ctrl.clock.enabled
	for p in [1, 2]:
		var label: Label = _cards[p].clock
		label.visible = enabled
		if not enabled:
			continue
		var ms := match_ctrl.time_left_ms(p)
		label.text = ChessClock.format_ms(ms)
		var low := ms < 10_000
		label.add_theme_color_override("font_color", UI.DANGER if low else UI.TEXT)
		if low and s != null and not s.is_over() and s.current_player == p and match_ctrl.is_local_turn():
			var sec := int(ms / 1000)
			if sec != _last_tick_s:
				_last_tick_s = sec
				Sfx.play("tick")


func _on_back() -> void:
	if _result_overlay.visible:
		app.show_menu()
	elif _menu_overlay.visible:
		_menu_overlay.visible = false
	else:
		_open_menu()
