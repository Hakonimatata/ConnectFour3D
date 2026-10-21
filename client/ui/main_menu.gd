class_name MainMenu
extends Screen
## Hovedmenyen. I bakgrunnen spiller to boter mot hverandre mens kameraet roterer.
## Menyen tar en kort «titt» på serveren (uten å mase hvis den ikke svarer), og viser
## aktive turneringer og Elo-merket ditt hvis du er innlogget.

const MAX_TOURNAMENTS := 3

var _demo: GameState
var _demo_bot := Bot.new(BotProfile.create(BotProfile.Level.MEDIUM))
var _panel: Control
var _tour_box: VBoxContainer
var _tour_list: VBoxContainer
var _badge: TextureRect


func _ready() -> void:
	app.camera.auto_rotate = true
	app.board.input_enabled = false
	app.board.setup(4)
	var pair := Skins.resolve_pair(Settings.look(), Skins.look(Skins.DEFAULT_P2))
	app.board.set_looks(pair[0], pair[1])
	_demo_bot.profile.think_time_s = 0.0

	_panel = MarginContainer.new()
	add_child(_panel)
	var card := PanelContainer.new()
	_panel.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)

	v.add_child(UI.label("Fire på rad", "Title"))
	v.add_child(UI.label("i 3D · mot AI, lokalt eller online", "Muted"))
	v.add_child(UI.spacer(8))
	v.add_child(UI.button("Spill mot AI", func() -> void: app.show_setup("ai"), "PrimaryButton"))
	v.add_child(UI.button("To spillere på samme enhet", func() -> void: app.show_setup("local")))
	v.add_child(UI.button("Spill online", func() -> void: app.show_online()))
	v.add_child(UI.button("Innstillinger", func() -> void: app.show_settings()))

	# Aktive turneringer (vises bare når serveren svarer og noe er åpent eller pågår)
	_tour_box = UI.vbox(6)
	_tour_box.visible = false
	_tour_box.add_child(UI.spacer(2))
	_tour_box.add_child(UI.section("Aktive turneringer"))
	_tour_list = UI.vbox(6)
	_tour_box.add_child(_tour_list)
	v.add_child(_tour_box)
	v.add_child(UI.spacer(4))

	var who := UI.hbox(8)
	var avatar := AvatarView.new(30)
	avatar.set_avatar(Settings.avatar, Settings.player_name, Skins.color_of(Settings.skin_id))
	who.add_child(avatar)
	_badge = EloBadge.make(-1, 20)
	who.add_child(_badge)
	who.add_child(UI.label(Settings.player_name, "Muted"))
	v.add_child(who)

	Net.message.connect(_on_net_message)
	Net.connected.connect(_on_net_connected)
	Net.account_changed.connect(_update_badge)
	var tour_timer := Timer.new()
	tour_timer.wait_time = 20.0
	tour_timer.autostart = true
	tour_timer.timeout.connect(_ask_tournaments)
	add_child(tour_timer)
	if Net.status == Net.Status.OFFLINE:
		Net.connect_to_server("", false)
	else:
		_ask_tournaments()
	_update_badge()

	resized.connect(_layout)
	_layout.call_deferred()

	var timer := Timer.new()
	timer.wait_time = 0.9
	timer.autostart = true
	timer.timeout.connect(_demo_step)
	add_child(timer)
	_demo = GameState.new()


## Bred skjerm: kortet til venstre. Smal (mobil): kortet nederst.
func _layout() -> void:
	var portrait := size.y > size.x
	var w := minf(400.0, size.x - 32.0)
	_panel.custom_minimum_size.x = w
	# Flytt brettet bort fra kortet: opp på mobil, til høyre på PC.
	if portrait:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
		app.camera.view_offset = Vector2(0, -1.4)
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 48)
		app.camera.view_offset = Vector2(-1.8, 0)


func _on_net_connected(_resumed: bool) -> void:
	_ask_tournaments()


func _ask_tournaments() -> void:
	if Net.is_online():
		Net.send({ "t": Protocol.LIST_TOURNAMENTS })


func _on_net_message(msg: Dictionary) -> void:
	if msg.t == Protocol.TOURNAMENT_LIST:
		show_tournaments(msg.get("tournaments", []))


func _update_badge() -> void:
	EloBadge.set_elo(_badge, int(Net.user.get("elo", -1)) if Net.is_logged_in() else -1, 20)


## Viser turneringer som pågår eller er åpne for påmelding (pågående først).
func show_tournaments(list: Array) -> void:
	for c in _tour_list.get_children():
		c.queue_free()
	var active := list.filter(func(t: Dictionary) -> bool: return t.get("status") in ["running", "open"])
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return TournamentScreen.status_order(a.status) < TournamentScreen.status_order(b.status) \
			or (a.status == b.status and a.start_time < b.start_time)
	)
	_tour_box.visible = not active.is_empty()
	for t in active.slice(0, MAX_TOURNAMENTS):
		_tour_list.add_child(_tournament_button(t))
	if active.size() > MAX_TOURNAMENTS:
		_tour_list.add_child(UI.button(tr("Alle turneringer (%d)") % active.size(), func() -> void:
			Net.ensure_connected()
			app.show_tournaments()
		, "GhostButton"))
	_layout.call_deferred()


func _tournament_button(t: Dictionary) -> Button:
	var running: bool = t.status == "running"
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.custom_minimum_size.y = 58
	b.icon = _dot_icon(UI.SUCCESS if running else UI.ACCENT)
	var when := tr("Pågår nå") if running else tr("Påmelding åpen") + " · " + tr("starter %s") % UI.format_time(int(t.start_time))
	b.text = "%s\n%s · %d/%d" % [t.name, when, int(t.players), int(t.max_players)]
	var id := int(t.id)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		Net.ensure_connected()
		app.show_tournament(id, true)
	)
	if running:
		# Pågående turnering pulserer svakt, så den synes på forsiden
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "self_modulate", Color(1.12, 1.12, 1.12), 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return b


static func _dot_icon(color: Color) -> Texture2D:
	var px := 28
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - px / 2.0, y + 0.5 - px / 2.0).length()
			var a := clampf(px * 0.3 - d + 0.5, 0.0, 1.0)
			var ring := clampf(px * 0.48 - d + 0.5, 0.0, 1.0) * 0.25
			img.set_pixel(x, y, Color(color, maxf(a, ring)))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(14, 14))
	return tex


func _demo_step() -> void:
	if _demo.is_over():
		_demo = GameState.new()
		app.board.clear_pieces()
		return
	var player := _demo.current_player
	var r := _demo.play(_demo_bot.choose_move(_demo))
	app.board.add_piece(r.pos, player)
	if _demo.is_over() and not _demo.winning_line.is_empty():
		app.board.highlight(_demo.winning_line)
