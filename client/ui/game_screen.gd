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
var _watchers: Label
var _bottom: Control
var _replay: ReplayPlayer
var _resign_button: Button
var _leave_button: Button
var _change_button: Button
var _result_leave: Button            ## «Til hovedmenyen» / «Tilbake til turneringen» i resultatet
var _review: MoveReview               ## AI-analysen av partiet (regnes ut litt etter litt etter partiet)
var _analysis_label: Label
var _chat_tabs: HBoxContainer        ## «Kamp» / «Turnering» (bare i turneringskamper)
var _tchat: GlobalChat                ## turneringschatten (samme som i menyen og på turneringssiden)
var _tab := 0                         ## 0 = kampen, 1 = turneringen
var _match_tab: Button
var _tour_tab: Button
var _reactions: HBoxContainer         ## reaksjonsknappene (tilskuere)
var _countdown: Label                  ## 3, 2, 1 før partiet
var _countdown_shown := -1
# Runde 17: stillingsmåleren (tilskuere og trening) og treneren (trening mot AI)
const LIVE_SLICE_USEC := 5000          ## så lenge stillingsmåleren søker per bilde
const BETTER_PAUSE_MS := 1800          ## treningen: så lenge boten venter når trekket ditt kunne vært bedre
var _eval_bar: EvalBar
var _live: LiveEval                    ## null når måleren ikke vises
var _coach: PanelContainer             ## treningspanelet over bunnlinjen
var _coach_label: Label
var _hint_button: Button
var _undo_result: Button               ## «Angre siste trekk» i resultatet (trening)
var _hint_wanted := false              ## «Vis beste trekk» ble trykket før stillingen var vurdert
var _bot_hold_until := 0               ## boten legger tidligst nå (treningen, se BETTER_PAUSE_MS)
var _feedback_for := -1                ## antall trekk da vurderingen av trekket ditt sist ble vist


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
	match_ctrl.undone.connect(_on_undone)
	if _is_training():
		(match_ctrl as OfflineMatch).gate = _bot_may_move
	if match_ctrl is OnlineMatch:
		var online := match_ctrl as OnlineMatch
		online.reaction_received.connect(_on_reaction)
		online.tournament_chat_received.connect(_on_tournament_chat)
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
	var top_box := UI.vbox(8)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	var cards := UI.hbox(10)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_child(cards)
	for p in [1, 2]:
		cards.add_child(_make_card(p))
	# Stillingsmåleren under spillerne (tilskuere og trening): hvem som leder
	_eval_bar = EvalBar.new()
	_eval_bar.visible = false
	top_box.add_child(_eval_bar)

	# Bunn: meny, status, chat
	var bottom := MarginContainer.new()
	_bottom = bottom
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		bottom.add_theme_constant_override("margin_" + side, 12)
	add_child(bottom)
	var bottom_box := UI.vbox(8)
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bottom_box)
	if _is_training():
		bottom_box.add_child(_build_coach())
	var bar := UI.hbox(10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(bar)
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
	_watchers = UI.label("", "Muted")
	_watchers.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_watchers.visible = false
	bar.add_child(_watchers)
	_reactions = UI.hbox(4)
	_reactions.visible = false
	for kind in Protocol.REACTIONS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.theme_type_variation = "GhostButton"
		var icon := ReactionView.new(kind, 26)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(icon)
		b.pressed.connect(func() -> void: (match_ctrl as OnlineMatch).send_reaction(kind))
		_reactions.add_child(b)
	bar.add_child(_reactions)
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

	_countdown = UI.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_countdown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_countdown.add_theme_font_size_override("font_size", 96)
	_countdown.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_countdown.add_theme_constant_override("shadow_offset_y", 4)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -160
	_countdown.offset_right = 160
	_countdown.offset_top = -70
	_countdown.offset_bottom = 70
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.visible = false
	add_child(_countdown)

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
	var name_row := UI.hbox(6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := EloBadge.make(-1, 18)
	name_row.add_child(badge)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	names.add_child(name_row)
	names.add_child(sub)
	row.add_child(names)
	var clock := UI.label("")
	clock.add_theme_font_size_override("font_size", 22)
	clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(clock)
	_cards[player] = { "panel": panel, "avatar": avatar, "name": name_label, "sub": sub, "clock": clock, "badge": badge }
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
		EloBadge.set_elo(c.badge, int(info.get("elo", -1)), 18)
		(c.avatar as AvatarView).set_avatar(str(info.get("avatar", "")), str(info.name), match_ctrl.color_of(p))
	var online := match_ctrl as OnlineMatch
	if online:
		_watchers.visible = online.spectators > 0
		_watchers.text = tr("%d ser på") % online.spectators
		_resign_button.visible = not online.is_spectator()
		if online.is_spectator():
			_leave_button.text = tr("Tilbake til turneringen") if not online.tournament.is_empty() else tr("Slutt å se på")
		else:
			_leave_button.text = tr("Tilbake til turneringen") if not online.tournament.is_empty() else tr("Til hovedmenyen")
		_result_leave.text = _leave_button.text
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
	# Trykk utenfor kortet lukker menyen (som «Fortsett»)
	_menu_overlay.gui_input.connect(func(e: InputEvent) -> void:
		var tap := e as InputEventMouseButton
		if tap and tap.pressed and tap.button_index == MOUSE_BUTTON_LEFT:
			_menu_overlay.visible = false
			accept_event()
	)
	var v := UI.centered_card(_menu_overlay, 360)
	v.add_child(UI.label("Pause", "Heading"))
	v.add_child(UI.label(match_ctrl.options.describe(), "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UI.button("Fortsett", func() -> void: _menu_overlay.visible = false, "PrimaryButton"))
	_resign_button = UI.button("Gi opp", func() -> void:
		_menu_overlay.visible = false
		match_ctrl.resign()
	)
	v.add_child(_resign_button)
	_leave_button = UI.button("Til hovedmenyen", _leave)
	v.add_child(_leave_button)


func _build_result_overlay() -> void:
	_result_overlay = _overlay()
	_result_overlay.color = Color(0, 0, 0, 0.35)
	var v := UI.centered_card(_result_overlay, 380)
	_result_title = UI.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_result_reason = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_result_title)
	v.add_child(_result_reason)
	_analysis_label = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_CENTER, true)
	_analysis_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_analysis_label.visible = false
	v.add_child(_analysis_label)
	v.add_child(UI.spacer(6))
	_rematch_button = UI.button("Spill igjen", func() -> void:
		_rematch_button.disabled = match_ctrl.mode == "online"
		match_ctrl.request_rematch()
	, "PrimaryButton")
	v.add_child(_rematch_button)
	_change_button = UI.button("Endre innstillinger", change_settings)
	v.add_child(_change_button)
	_undo_result = UI.button("Angre siste trekk", _undo)
	_undo_result.visible = _is_training()
	v.add_child(_undo_result)
	v.add_child(UI.button("Se partiet igjen", start_replay))
	v.add_child(UI.button("Se på brettet", func() -> void: _result_overlay.visible = false))
	_result_leave = UI.button("Til hovedmenyen", _leave)
	v.add_child(_result_leave)


## Turneringskamp (spillere og tilskuere): tilbake til turneringssiden. Ellers går tilskuere til
## lobbyen og spillere til hovedmenyen.
func _leave() -> void:
	var online := match_ctrl as OnlineMatch
	if online and not online.tournament.is_empty():
		var id := int(online.tournament.id)
		app.end_match()
		app.show_tournament(id)
	elif online and online.is_spectator():
		app.end_match()
		app.show_online()
	else:
		app.show_menu()


## Endre tid, brett og regler før neste parti. Online: verten lagrer, og motstanderen får beskjed
## og trykker «Spill igjen». Mot AI og lokalt starter «Start» et nytt parti med de nye innstillingene.
func change_settings() -> void:
	var online := match_ctrl as OnlineMatch
	Settings.last_options = match_ctrl.options.to_dict()
	if online:
		online.keep_room = true
		var room := online.room_snapshot()
		app.end_match()
		app.show_setup("online", app.online_set_options.bind(room), app.show_room.bind(room))
	else:
		var mode := match_ctrl.mode
		app.end_match()
		app.show_setup(mode)


## «Se partiet igjen»: avspilleren nederst, med tvungne trekk markert. «Lukk» gir resultatet tilbake.
func start_replay() -> void:
	var s := match_ctrl.state
	if s == null or _replay != null:
		return
	_result_overlay.visible = false
	_bottom.visible = false
	_chat_drawer.visible = false
	var names := { 1: str(match_ctrl.players[1].name), 2: str(match_ctrl.players[2].name) }
	var colors := { 1: match_ctrl.color_of(1), 2: match_ctrl.color_of(2) }
	_replay = ReplayPlayer.new(app.board, match_ctrl.options, s.first_player, s.history.duplicate(), names, colors)
	_replay.review = _review
	var holder := MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# På PC: smalere linje på midten, og brettet flyttes litt opp så linjen ikke dekker det.
	var side_margin := maxf(12.0, (size.x - 820.0) * 0.5)
	holder.add_theme_constant_override("margin_left", side_margin)
	holder.add_theme_constant_override("margin_right", side_margin)
	holder.add_theme_constant_override("margin_bottom", 12)
	holder.add_child(_replay)
	add_child(holder)
	if size.x > size.y:
		app.camera.view_offset = Vector2(0, -1.0)
	_replay.closed.connect(func() -> void:
		app.camera.view_offset = Vector2.ZERO
		_replay.seek(_replay.entries.size())
		app.board.clear_hints()
		holder.queue_free()
		_replay = null
		_bottom.visible = true
		_result_overlay.visible = true
	)


func _build_chat_drawer() -> void:
	_chat_drawer = MarginContainer.new()
	_chat_drawer.visible = false
	add_child(_chat_drawer)
	var inner := UI.vbox(6)
	_chat_drawer.add_child(inner)
	# Faner (bare i turneringskamper): chatten i kampen og turneringschatten
	_chat_tabs = UI.hbox(6)
	_chat_tabs.visible = false
	_match_tab = UI.button("Kamp", func() -> void: _show_tab(0), "ChoiceButton")
	_tour_tab = UI.button("Turnering", func() -> void: _show_tab(1), "ChoiceButton")
	for b in [_match_tab, _tour_tab]:
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chat_tabs.add_child(b)
	inner.add_child(_chat_tabs)
	_chat = ChatPanel.new()
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_chat)
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


## Turneringskamp: turneringschatten blir en egen fane ved siden av chatten i kampen.
func _setup_tournament_chat(online: OnlineMatch) -> void:
	if _tchat != null or online.tournament.is_empty():
		return
	_tchat = GlobalChat.new()
	_tchat.tournament_only = true
	_tchat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tchat.visible = false
	_chat.get_parent().add_child(_tchat)
	_tchat.set_tournament(int(online.tournament.id), str(online.tournament.get("name", "")))
	_chat_tabs.visible = true
	_show_tab(0)
	if online.is_spectator():
		_chat.add_system(tr("Spillerne ser ikke det tilskuerne skriver her, bare reaksjonene."))


func _show_tab(i: int) -> void:
	_tab = i
	_match_tab.set_pressed_no_signal(i == 0)
	_tour_tab.set_pressed_no_signal(i == 1)
	_chat.visible = i == 0
	if _tchat:
		_tchat.visible = i == 1
	_tour_tab.text = tr("Turnering")
	_match_tab.text = tr("Kamp")


## Ny melding i turneringschatten (GlobalChat viser den): prikk på fanen hvis den ikke er åpen.
func _on_tournament_chat(_messages: Array, history: bool) -> void:
	if _tchat == null:
		return
	if not history and (not _chat_drawer.visible or _tab != 1):
		_tour_tab.text = tr("Turnering") + " •"
		if not _chat_drawer.visible:
			_chat_button.text = "Chat •"


## En tilskuer reagerte: ikonet flyr opp fra hjørnet der antall tilskuere står.
func _on_reaction(kind: String) -> void:
	if kind in Protocol.REACTIONS and is_inside_tree():
		ReactionView.float_up(self, kind, Vector2(size.x - 70, size.y - 120))


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
	if _replay != null:
		_replay.closed.emit()
	_result_overlay.visible = false
	_rematch_button.disabled = false
	_review = null
	_analysis_label.visible = false
	app.board.setup(s.size)
	_refresh_players()
	# Tegn brikker som allerede finnes (f.eks. ved gjenkobling online).
	for i in s.cells.size():
		if s.cells[i] != 0:
			app.board.add_piece(s.lines.pos_of(i), s.cells[i], false)
	app.board.input_enabled = true
	_update_turn_status()
	_update_clocks()
	var online := match_ctrl as OnlineMatch
	if online:
		_setup_tournament_chat(online)
		_reactions.visible = online.is_spectator()
	_setup_live()
	_countdown_shown = -1
	WinFx.prewarm(app.board)


func _on_move_applied(_col: Vector2i, pos: Vector3i, player: int) -> void:
	app.board.hide_target()
	app.board.clear_hints()
	app.board.add_piece(pos, player)
	Sfx.play("drop", 1.0 if player == 1 else 0.85)
	Settings.vibrate(20)
	if _live != null:
		_hint_wanted = false
		_live.update(match_ctrl.state)
		_on_live_changed()


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
	_result_reason.text = tr(reasons.get(reason, ""))
	var online := match_ctrl as OnlineMatch
	if online and not online.last_elo.is_empty():
		var before := int(online.last_elo.before)
		var after := int(online.last_elo.after)
		_result_reason.text += "\nElo %d → %d (%s%d)" % [before, after, "+" if after >= before else "", after - before]
		var new_tier := EloBadge.tier(after)
		if new_tier.id != EloBadge.tier(before).id:
			var text := tr("Nytt nivå: %s!") if after > before else tr("Ned til %s")
			_result_reason.text += "\n" + text % tr(new_tier.name)
	if online and not online.last_xp.is_empty():
		_result_reason.text += "\n" + xp_text(online.last_xp)
	# Mellom partier kan innstillingene endres: alltid mot AI og lokalt, online bare av verten.
	_change_button.visible = online == null or (online.tournament.is_empty() and online.my_seat() == 1)
	_change_button.text = tr("Endre regler") if online else tr("Endre innstillinger")
	if online and (not online.tournament.is_empty() or online.is_spectator()):
		_rematch_button.visible = false
		_result_reason.text += "\n" + tr("Turnering: %s") % online.tournament.name
	_show_status(_result_title.text, UI.TEXT, 0.0)
	# AI-analysen: regnes ut i bakgrunnen mens resultatet vises
	_review = MoveReview.new(match_ctrl.options, s.first_player, s.history.duplicate())
	_analysis_label.visible = true
	_update_analysis()

	var delay := 0.4
	if not line.is_empty():
		app.board.highlight(line)
		app.board.dim_except(line)
		var color := match_ctrl.color_of(winner)
		# Vent til den siste brikken har landet før smellet.
		await get_tree().create_timer(0.38).timeout
		var fx := str(match_ctrl.players[winner].get("win_fx", "classic"))
		WinFx.play(app.board, app.camera, line, color, fx)
		_flash.color = Color(color.lerp(Color.WHITE, 0.7), 0.28)
		var t := create_tween().set_ignore_time_scale(true)
		t.tween_property(_flash, "color:a", 0.0, 0.4)
		delay = 4.2 if fx == "chaos" else 1.6   # «Kaos» varer lenger: vent med resultatet
	if me != 0 and winner != me and result != GameState.Result.DRAW:
		Sfx.play("lose")
	else:
		Sfx.play("win")
	await get_tree().create_timer(delay, true, false, true).timeout
	if is_inside_tree() and match_ctrl.state == s and _replay == null:
		_result_overlay.visible = true


## «+35 XP · Nivå 6», og «Nivå 7! Låst opp: Lava» når noe nytt er nådd (runde 17). Brukes også av
## dagens oppgave. Fikk partiet ingen XP (samme motstander for mange ganger i dag), står det.
static func xp_text(xp: Dictionary) -> String:
	var gained := int(xp.get("gained", 0))
	var text := I18n.t("+%d XP · Nivå %d") % [gained, int(xp.get("level", 1))] if gained > 0 \
		else I18n.t("Ingen XP for dette partiet (for kort, eller mange mot samme motstander i dag).")
	if int(xp.get("level", 1)) > int(xp.get("level_before", 1)):
		text += "\n" + I18n.t("Nytt nivå: %d!") % int(xp.level)
	var unlocked: Array = xp.get("unlocked", [])
	if not unlocked.is_empty():
		text += "\n" + I18n.t("Låst opp: %s") % ", ".join(unlocked.map(func(item: String) -> String: return Progression.item_name(item)))
	return text


func _on_chat(from_name: String, text: String) -> void:
	_chat.add_message(from_name, text)
	if not _chat_drawer.visible or (_tchat != null and _tab != 0):
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
	if match_ctrl.countdown_left_ms() > 0:
		_show_status(tr("Gjør deg klar…"), UI.TEXT, 0.0)
		return
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


## Litt av AI-analysen hvert bilde (høyst ca. 8 ms), så skjermen ikke fryser.
func _step_review() -> void:
	if _review == null or _review.done():
		return
	var until := Time.get_ticks_usec() + 8000
	while not _review.done() and Time.get_ticks_usec() < until:
		_review.step()
	_update_analysis()


## «Treffsikkerhet: Du 87 % · Bob 72 %» under resultatet (AI-ens vurdering av trekkene).
func _update_analysis() -> void:
	if _review == null:
		return
	if not _review.done():
		_analysis_label.text = tr("Analyserer partiet… %d %%") % roundi(_review.progress() * 100.0)
		return
	var sum := _review.summary()
	var me := match_ctrl.my_seat()
	var parts := []
	for p in ([me, GameState.opponent(me)] if me != 0 else [1, 2]):
		var who := tr("Du") if p == me else str(match_ctrl.players[p].name)
		var line := tr("%s %d %%") % [who, int(sum[p].accuracy)]
		var errors := int(sum[p].mistakes) + int(sum[p].blunders)
		if errors > 0:
			line += " " + (tr("(%d feil)") % errors)
		parts.append(line)
	_analysis_label.text = tr("Treffsikkerhet (AI): %s") % "  ·  ".join(parts) + "\n" \
		+ tr("«Se partiet igjen» viser tips for hvert trekk.")


## Nedtellingen før partiet: 3, 2, 1 midt på skjermen. Brikkene kan ikke legges før den er ferdig.
func _update_countdown() -> void:
	var left := match_ctrl.countdown_left_ms()
	var n := ceili(left / 1000.0)
	if n == _countdown_shown:
		return
	var was := _countdown_shown
	_countdown_shown = n
	if n <= 0:
		if was > 0:
			_flash_countdown(tr("Spill!"), UI.SUCCESS)
			app.board.refresh_hover()
			_update_turn_status()
		return
	_flash_countdown(str(n), UI.TEXT)
	Sfx.play("tick")


func _flash_countdown(text: String, color: Color) -> void:
	_countdown.text = text
	_countdown.add_theme_color_override("font_color", color)
	_countdown.visible = true
	_countdown.pivot_offset = _countdown.size * 0.5
	var t := _countdown.create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(_countdown, "scale", Vector2.ONE, 0.35).from(Vector2.ONE * 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_countdown, "modulate:a", 0.0, 0.3).from(1.0).set_delay(0.6)


func _process(delta: float) -> void:
	_step_review()
	if _live != null and _live.step(LIVE_SLICE_USEC):
		_on_live_changed()
	_update_countdown()
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


# ---------------------------------------------------------------- Stillingsmåler og trening (runde 17)

func _is_training() -> bool:
	return match_ctrl is OfflineMatch and (match_ctrl as OfflineMatch).training


## Stillingsmåleren vises for tilskuere og i treningen (ikke for spillerne i et vanlig parti).
func _setup_live() -> void:
	var online := match_ctrl as OnlineMatch
	var show := _is_training() or (online != null and online.is_spectator())
	_eval_bar.visible = show
	if not show:
		_live = null
		return
	if _live == null:
		_live = LiveEval.new()
	_eval_bar.colors = { 1: match_ctrl.color_of(1), 2: match_ctrl.color_of(2) }
	_eval_bar.set_unknown()
	_feedback_for = -1
	_hint_wanted = false
	_live.update(match_ctrl.state)
	_on_live_changed()


## Ny vurdering (eller ny stilling som ikke er vurdert ennå).
func _on_live_changed() -> void:
	var e := _live.get_eval(match_ctrl.state)
	if e.is_empty():
		_eval_bar.set_pending()
	else:
		_eval_bar.set_eval(float(e.p1), str(e.text), int(e.leader))
	if _is_training():
		_update_coach()


## Treningen: vurderingen av trekket du nettopp gjorde (når stillingen før og etter er vurdert), og
## beste trekk når du har bedt om det.
func _update_coach() -> void:
	var s := match_ctrl.state
	var human := match_ctrl.my_seat()
	var my_turn := not s.is_over() and s.current_player == human
	_hint_button.disabled = not my_turn
	var n := s.history.size()
	var last_mine := n > 0 and (s.first_player if (n - 1) % 2 == 0 else GameState.opponent(s.first_player)) == human
	if last_mine and _feedback_for != n:
		var r := _live.judge_last(s)
		if not r.is_empty():
			_feedback_for = n
			_set_coach(tr("Ditt trekk: %s") % MoveReview.describe(r), ReplayPlayer.GRADE_COLORS.get(str(r.grade), UI.MUTED))
			var better: Vector3i = r.better
			if better.x >= 0 and not s.is_over():
				app.board.add_hints([better], BoardView.BETTER)
				_bot_hold_until = Time.get_ticks_msec() + BETTER_PAUSE_MS
		elif _live.is_busy():
			_set_coach(tr("Vurderer trekket ditt…"), UI.MUTED)
		else:
			_feedback_for = n
			_set_coach(tr("Du la før AI-en var ferdig med stillingen, så trekket ble ikke vurdert."), UI.MUTED)
	if _hint_wanted and my_turn:
		var e := _live.get_eval(s)
		if e.is_empty():
			_set_coach(tr("AI-en tenker…"), UI.MUTED)
			return
		_hint_wanted = false
		var info: Dictionary = e.info
		if info.get("best_pos", Vector3i(-1, -1, -1)).x >= 0:
			app.board.add_hints([info.best_pos], BoardView.BETTER)
		_set_coach(tr("Beste trekk (grønn): %s") % MoveReview.best_text(info, int(e.score)), BoardView.BETTER)


func _set_coach(text: String, color: Color) -> void:
	_coach_label.text = text
	_coach_label.add_theme_color_override("font_color", color)


## Treningen: boten venter til trekket ditt er vurdert (og litt til hvis det kunne vært bedre, så du
## rekker å se den grønne markøren).
func _bot_may_move() -> bool:
	return _live == null or (not _live.get_eval(match_ctrl.state).is_empty() and Time.get_ticks_msec() >= _bot_hold_until)


func _build_coach() -> PanelContainer:
	_coach = PanelContainer.new()
	_coach.add_theme_stylebox_override("panel", UI._box(UI.PANEL, UI.RADIUS, UI.BORDER, 12, 8))
	var v := UI.vbox(6)
	_coach.add_child(v)
	_coach_label = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_coach_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_coach_label.text = tr("Trening: «Vis beste trekk» gir et tips, og «Angre» lar deg prøve igjen.")
	v.add_child(_coach_label)
	var row := UI.hbox(8)
	_hint_button = UI.button("Vis beste trekk", func() -> void:
		_hint_wanted = true
		_update_coach()
	, "PrimaryButton")
	_hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hint_button)
	var undo := UI.button("Angre", _undo)
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(undo)
	v.add_child(row)
	return _coach


func _undo() -> void:
	var offline := match_ctrl as OfflineMatch
	if offline == null or not offline.undo():
		_show_status(tr("Ingenting å angre."), UI.MUTED, 2.0)


## Trekk ble angret: tegn brettet på nytt (også etter at partiet var slutt).
func _on_undone() -> void:
	var s := match_ctrl.state
	_result_overlay.visible = false
	_review = null
	_analysis_label.visible = false
	app.board.setup(s.size)
	_refresh_players()
	for i in s.cells.size():
		if s.cells[i] != 0:
			app.board.add_piece(s.lines.pos_of(i), s.cells[i], false)
	app.board.input_enabled = true
	_feedback_for = s.history.size()
	_hint_wanted = false
	_bot_hold_until = 0
	if _coach_label:
		_set_coach(tr("Angret. Prøv et annet trekk!"), UI.MUTED)
	_update_turn_status()
	if _live != null:
		_live.update(s)
		_on_live_changed()


func _on_back() -> void:
	if _replay != null:
		_replay.closed.emit()
	elif _result_overlay.visible:
		_leave()
	elif _menu_overlay.visible:
		_menu_overlay.visible = false
	else:
		_open_menu()
