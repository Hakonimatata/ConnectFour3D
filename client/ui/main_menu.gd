class_name MainMenu
extends Screen
## Hovedmenyen. I bakgrunnen spilles det siste partiet på serveren av, med spillerne og hvordan
## det endte. Uten nett (eller før noen har spilt) spiller to boter mot hverandre.
## Menyen tar en kort «titt» på serveren (uten å mase hvis den ikke svarer), og viser
## aktive turneringer, den globale chatten (med hvor mange som er online) og Elo-merket ditt.

const MAX_TOURNAMENTS := 3

var _demo: GameState
var _replay: Dictionary = {}    ## partiet som spilles av (fra serveren). Tom = bot-demo
var _replay_i := 0
var _replay_pause := 0
var _caption_box: PanelContainer
var _caption: Label
const REPLAY_PAUSE_STEPS := 5  ## hvor lenge sluttstillingen blir stående (i demo-steg)
var _demo_bot := Bot.new(BotProfile.create(BotProfile.Level.MEDIUM))
var _panel: Control
var _vbox: VBoxContainer
var _tour_box: VBoxContainer
var _tour_list: VBoxContainer
var _badge: TextureRect
var _chat: GlobalChat
var _who_name: Label
var _account_button: Button
var _last_portrait := true


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
	_vbox = v
	card.add_child(v)

	v.add_child(UI.label("Fire på rad", "Title"))
	v.add_child(UI.label("i 3D · mot AI, lokalt eller online", "Muted"))
	v.add_child(UI.spacer(8))
	v.add_child(UI.button("Spill mot AI", func() -> void: app.show_setup("ai"), "PrimaryButton"))
	v.add_child(UI.button("To spillere på samme enhet", func() -> void: app.show_setup("local")))
	v.add_child(UI.button("Spill online", func() -> void: app.show_online()))
	var solved := Settings.puzzle_day == Time.get_date_string_from_system()
	var puzzle := UI.button(tr("Dagens oppgave") + ("  ·  " + tr("løst") if solved else ""), func() -> void: app.show_puzzle())
	puzzle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(puzzle)
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
	avatar.set_avatar(Settings.avatar, Settings.display_name(), Skins.color_of(Settings.skin_id))
	who.add_child(avatar)
	_badge = EloBadge.make(-1, 20)
	who.add_child(_badge)
	_who_name = UI.label(Settings.display_name(), "Muted")
	_who_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_who_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_who_name.clip_text = true
	_who_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(_who_name)
	# Logg inn (gjest) eller Min profil (innlogget), rett ved profilbildet
	_account_button = UI.button("Logg inn", _on_account_pressed, "GhostButton")
	_account_button.custom_minimum_size.y = 36
	who.add_child(_account_button)
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

	# Teksten over brettet: hvem som spilte det siste partiet, og hvordan det endte
	_caption_box = PanelContainer.new()
	_caption_box.add_theme_stylebox_override("panel", UI._box(UI.PANEL, 12, UI.BORDER, 14, 8))
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.visible = false
	_caption = UI.label("", "", HORIZONTAL_ALIGNMENT_CENTER)
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_caption_box.add_child(_caption)
	add_child(_caption_box)

	_chat = GlobalChat.new()
	_chat.toggled.connect(func(_open: bool) -> void: _layout())
	add_child(_chat)
	# Når man begynner/slutter å skrive, legges chatten om (tastaturet på mobil)
	_chat._input.focus_entered.connect(_layout)
	_chat._input.focus_exited.connect(_layout)

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
	# Tastaturet på mobil krymper skjermen. Ikke bytt oppsett mens man skriver i chatten.
	var typing := _chat.is_typing()
	if typing:
		portrait = _last_portrait
	_last_portrait = portrait
	_panel.visible = not (typing and portrait)   # på mobil dekker chatten menyen mens man skriver
	var w := minf(400.0, size.x - 32.0)
	_panel.custom_minimum_size.x = w
	# Flytt brettet bort fra kortet: opp på mobil, til høyre på PC.
	if portrait:
		# Mobil: menyen midtstilt nederst og litt tettere, chatten som en smal linje øverst,
		# og brettet midt i plassen mellom dem (og litt lenger unna, så det får plass).
		w = minf(400.0, size.x - 20.0)
		_panel.custom_minimum_size.x = w
		_vbox.add_theme_constant_override("separation", 8)
		var h := _panel.get_combined_minimum_size().y
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -w * 0.5
		_panel.offset_right = w * 0.5
		_panel.offset_top = -h - 10.0
		_panel.offset_bottom = -10.0
		var card_top := size.y - h - 10.0
		_chat.compact = true
		_chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_chat.offset_left = 10
		_chat.offset_right = -10
		_chat.offset_top = 10
		var chat_bottom := 10.0 + _chat.get_combined_minimum_size().y
		if typing:
			_chat.open = true
			_chat._apply_compact()
			_chat.offset_bottom = maxf(10 + 180.0, size.y - 10.0)   # hele plassen over tastaturet
		else:
			_chat.offset_bottom = maxf(10 + 180.0, card_top - 10.0) if _chat.open else chat_bottom
		_caption_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		_caption_box.offset_top = chat_bottom + 8.0
		_caption_box.offset_bottom = _caption_box.offset_top + _caption_box.get_combined_minimum_size().y
		app.camera.dist_target = app.camera.max_distance * 0.78
		var px_per_unit := size.x / 10.5
		app.camera.view_offset = Vector2(0, ((chat_bottom + card_top) * 0.5 - size.y * 0.5) / px_per_unit)
	else:
		_vbox.add_theme_constant_override("separation", 12)
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 48)
		app.camera.view_offset = Vector2(-1.2, -0.5)
		# Chatten nede til høyre
		_chat.compact = false
		# Teksten øverst, over brettet (til høyre for menyen)
		_caption_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
		var shift := size.x * 0.17
		_caption_box.offset_left += shift
		_caption_box.offset_right += shift
		var cw := minf(380.0, size.x * 0.3)
		var ch := minf(360.0, size.y * 0.48)
		_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_chat.offset_left = -cw - 16
		_chat.offset_right = -16
		_chat.offset_top = -ch - 16
		_chat.offset_bottom = -16


func _on_net_connected(_resumed: bool) -> void:
	_ask_tournaments()


func _ask_tournaments() -> void:
	if Net.is_online():
		Net.send({ "t": Protocol.LIST_TOURNAMENTS })


func _on_net_message(msg: Dictionary) -> void:
	if msg.t == Protocol.TOURNAMENT_LIST:
		show_tournaments(msg.get("tournaments", []))


func _on_account_pressed() -> void:
	Sfx.play("click")
	if Net.is_logged_in():
		app.show_profile("", true)
	else:
		app.show_account(true)


func _update_badge() -> void:
	_who_name.text = Settings.display_name()
	_account_button.text = tr("Min profil") if Net.is_logged_in() else tr("Logg inn")
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
	# Det siste partiet på serveren vinner over bot-demoen
	if _replay.is_empty() and not Net.last_game.is_empty():
		_start_replay(Net.last_game)
		return
	if not _replay.is_empty():
		_replay_step()
		return
	if _demo.is_over():
		_demo = GameState.new()
		app.board.clear_pieces()
		return
	var player := _demo.current_player
	var r := _demo.play(_demo_bot.choose_move(_demo))
	app.board.add_piece(r.pos, player)
	if _demo.is_over() and not _demo.winning_line.is_empty():
		app.board.highlight(_demo.winning_line)


# ---------------------------------------------------------------- Siste parti

func _start_replay(rec: Dictionary) -> void:
	_replay = rec
	_replay_i = 0
	_replay_pause = 0
	var opts := GameOptions.from_dict(rec.get("options", {}) if rec.get("options") is Dictionary else {})
	_demo = GameState.new(opts, int(rec.get("first", 1)))
	if app.board.size != opts.size:
		app.board.setup(opts.size)
		_layout()
	app.board.clear_pieces()
	var recs: Array = rec.get("players", [])
	var looks := []
	for i in 2:
		var p: Dictionary = recs[i] if i < recs.size() and recs[i] is Dictionary else {}
		looks.append(Skins.look(str(p.get("skin", Skins.DEFAULT_P1 if i == 0 else Skins.DEFAULT_P2)),
			str(p.get("decal", "none")), "classic", bool(p.get("away", false)), str(p.get("decal_color", "auto"))))
	var pair := Skins.resolve_pair(looks[0], looks[1])
	app.board.set_looks(pair[0], pair[1])
	_caption.text = tr("Siste parti: %s") % _names(rec)
	_caption_box.visible = true


func _replay_step() -> void:
	var moves: Array = _replay.get("moves", [])
	if _replay_i < moves.size():
		var m = moves[_replay_i]
		_replay_i += 1
		var player := _demo.current_player
		var r := _demo.play(Vector2i(int(m[0]), int(m[1])), false)
		if r.get("ok", false):
			app.board.add_piece(r.pos, player)
		if _replay_i == moves.size():
			if not _demo.winning_line.is_empty():
				app.board.highlight(_demo.winning_line)
			_caption.text = tr("Siste parti: %s") % _names(_replay) + "\n" + result_text(_replay)
		return
	# Sluttstillingen står en stund, så starter siste parti (kanskje et nytt) på nytt
	_replay_pause += 1
	if _replay_pause >= REPLAY_PAUSE_STEPS:
		_replay = {}


static func _names(rec: Dictionary) -> String:
	var recs: Array = rec.get("players", [])
	var names := []
	for i in 2:
		names.append(str(recs[i].get("name", "?")) if i < recs.size() and recs[i] is Dictionary else "?")
	return "%s – %s" % names


## «Ada vant på tid», «Uavgjort – fullt brett» osv.
static func result_text(rec: Dictionary) -> String:
	var recs: Array = rec.get("players", [])
	var result := int(rec.get("result", 0))
	if result == GameState.Result.DRAW:
		return str(TranslationServer.translate("Uavgjort – fullt brett"))
	var seat := 1 if result == GameState.Result.P1_WON else 2
	var winner := str(recs[seat - 1].get("name", "?")) if seat - 1 < recs.size() and recs[seat - 1] is Dictionary else "?"
	var key := "%s vant med fire på rad"
	match int(rec.get("reason", 0)):
		GameState.EndReason.TIMEOUT: key = "%s vant på tid"
		GameState.EndReason.RESIGN: key = "%s vant – motstanderen ga opp"
		GameState.EndReason.DISCONNECT: key = "%s vant – motstanderen forlot partiet"
	return str(TranslationServer.translate(key)) % winner
