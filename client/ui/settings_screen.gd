class_name SettingsScreen
extends Screen
## Innstillinger: navn, profilbilde, brikke (skin, drakt, merke, merkefarge, seiersanimasjon),
## brett-tema, hurtigmeldinger i chat, språk, lyd og (avansert) serveradresse.
##
## Kortet står til venstre (PC) eller nederst (mobil), og selve brettet er forhåndsvisning:
## dine brikker i hjemmedrakt mot bortedrakt, og seiersanimasjonen kan spilles av der.

const MAX_PRESETS := 6
const LANGUAGES := ["auto", "nb", "en"]
## Demo-stilling: spiller 1 har en diagonal (vinnerlinjen), spiller 2 noen brikker rundt.
const DEMO_LINE: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 1, 0), Vector3i(2, 2, 0), Vector3i(3, 3, 0)]
const DEMO_P2: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(2, 1, 0), Vector3i(0, 3, 0), Vector3i(3, 1, 0), Vector3i(1, 0, 1)]

var _server_edit: LineEdit
var _avatar_view: AvatarView
var _remove_avatar: Button
var _avatar_status: Label
var _picker: AvatarPicker
var _preset_edits: Array[LineEdit] = []
var _panel: MarginContainer
var _fx_generation := 0


func _ready() -> void:
	app.camera.auto_rotate = true
	app.board.input_enabled = false
	app.board.setup(4)
	_apply_looks()
	_place_demo()

	_panel = MarginContainer.new()
	add_child(_panel)
	var card := PanelContainer.new()
	_panel.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.smooth_scroll(scroll)
	card.add_child(scroll)
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	resized.connect(_layout)
	_layout.call_deferred()

	v.add_child(UI.label("Innstillinger", "Heading"))
	var who := UI.label(tr("Du spiller som %s.") % Settings.display_name() + " " + (tr("Navnet kommer fra kontoen din.")
		if Settings.last_username != "" or Net.is_logged_in() else tr("Lag en konto under «Spill online» for å få eget navn.")),
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(who)

	# --- Profilbilde
	v.add_child(UI.section("Profilbilde"))
	var avatar_row := UI.hbox(14)
	_avatar_view = AvatarView.new(72)
	avatar_row.add_child(_avatar_view)
	var avatar_buttons := UI.vbox(8)
	avatar_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_buttons.add_child(UI.button("Velg bilde…", _pick_avatar))
	_remove_avatar = UI.button("Fjern bilde", _clear_avatar)
	avatar_buttons.add_child(_remove_avatar)
	avatar_row.add_child(avatar_buttons)
	v.add_child(avatar_row)
	_avatar_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_avatar_status.visible = false
	v.add_child(_avatar_status)
	_picker = AvatarPicker.new()
	_picker.picked.connect(_on_avatar_picked)
	add_child(_picker)

	# --- Brikke
	v.add_child(UI.section("Brikke"))
	v.add_child(UI.label("Brettet viser dine brikker i hjemmedrakt mot bortedrakt (bortedrakten brukes når motstanderen har samme skin).",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for skin in Skins.ALL:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "ChoiceButton"
		b.text = skin.name
		b.icon = Skins.swatch(skin.id)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(80, 66)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = skin.name
		b.button_pressed = skin.id == Settings.skin_id
		var id: String = skin.id
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			Settings.skin_id = id
			_apply_looks()
		)
		grid.add_child(b)
	v.add_child(grid)

	v.add_child(UI.section("Merke på toppen"))
	v.add_child(_decal_picker())
	var hint := "Noen merker låses opp av Elo-nivået ditt. Logg inn og spill rangerte partier for å låse opp flere." \
		if Settings.known_elo() < 0 else "Noen merker låses opp av Elo-nivået ditt. Merket viser hvilket nivå som trengs."
	v.add_child(UI.label(hint, "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UI.section("Farge på merket"))
	var color_ids: Array = Skins.DECAL_COLORS.map(func(d: Dictionary) -> String: return d.id)
	v.add_child(UI.choice(Skins.DECAL_COLORS.map(func(d: Dictionary) -> String: return d.name),
		maxi(0, color_ids.find(Settings.decal_color_id)), func(i: int) -> void:
			Settings.decal_color_id = Skins.DECAL_COLORS[i].id
			_apply_looks()
	))

	v.add_child(UI.section("Seiersanimasjon"))
	var fx_ids: Array = Skins.WIN_FX.map(func(d: Dictionary) -> String: return d.id)
	v.add_child(UI.choice(Skins.WIN_FX.map(func(d: Dictionary) -> String: return d.name),
		maxi(0, fx_ids.find(Settings.win_fx_id)), func(i: int) -> void:
			Settings.win_fx_id = Skins.WIN_FX[i].id
			play_fx_preview()
	))
	v.add_child(UI.button("Vis seiersanimasjonen", play_fx_preview))

	v.add_child(UI.section("Brett"))
	var board_ids: Array = Skins.BOARDS.map(func(d: Dictionary) -> String: return d.id)
	v.add_child(UI.choice(Skins.BOARDS.map(func(d: Dictionary) -> String: return d.name),
		maxi(0, board_ids.find(Settings.board_theme)), func(i: int) -> void:
			Settings.board_theme = Skins.BOARDS[i].id
			app.board.set_theme(Settings.board_theme)
	))

	# --- Hurtigmeldinger i chatten
	v.add_child(UI.section("Hurtigmeldinger i chatten"))
	var presets := Settings.chat_messages()
	for i in MAX_PRESETS:
		var e := UI.line_edit(presets[i] if i < presets.size() else "", "Tom", 40)
		_preset_edits.append(e)
		v.add_child(e)
	v.add_child(UI.button("Tilbakestill hurtigmeldinger", _reset_presets))

	# --- Språk
	v.add_child(UI.section("Språk / Language"))
	v.add_child(UI.choice(["Automatisk", "Norsk", "English"], maxi(0, LANGUAGES.find(Settings.language)),
		func(i: int) -> void: _set_language(LANGUAGES[i])))

	# --- Lyd og følelse
	v.add_child(UI.section("Lyd og følelse"))
	v.add_child(UI.toggle_row("Lyd", "", Settings.sound, func(on: bool) -> void: Settings.sound = on))
	v.add_child(UI.toggle_row("Vibrasjon", "På mobil, der nettleseren støtter det.", Settings.vibration,
		func(on: bool) -> void: Settings.vibration = on))

	v.add_child(UI.section("Server (avansert)"))
	_server_edit = UI.line_edit(Settings.server_url, Settings.resolved_server_url(), 200)
	v.add_child(_server_edit)

	v.add_child(UI.spacer(6))
	v.add_child(UI.button("Lagre", _on_back, "PrimaryButton"))
	_refresh_avatar()


## Merkene som knapper. Låste merker er grået ut og viser nivået som trengs.
func _decal_picker() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	var elo := Settings.known_elo()
	for d in Skins.DECALS:
		var id: String = d.id
		var need := EloTiers.required_tier(id)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "ChoiceButton"
		b.text = d.name
		b.button_pressed = id == Settings.decal_id and EloTiers.decal_unlocked(id, elo)
		if not need.is_empty():
			b.icon = EloBadge.icon(int(need.min), 16)
			b.add_theme_constant_override("icon_max_width", 16)
			var unlocked := EloTiers.decal_unlocked(id, elo)
			b.disabled = not unlocked
			b.tooltip_text = tr("Låses opp på %s (%d Elo)") % [tr(need.name), int(need.min)] if not unlocked \
				else tr("Låst opp på %s") % tr(need.name)
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			Settings.decal_id = id
			_apply_looks()
		)
		flow.add_child(b)
	return flow


## Bred skjerm: kortet til venstre og brettet til høyre. Smal (mobil): brettet øverst, kortet under.
func _layout() -> void:
	if size.y > size.x:
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.5
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 10
		_panel.offset_right = -10
		_panel.offset_top = 0
		_panel.offset_bottom = -10
		app.camera.view_offset = Vector2(0, -4.0)
	else:
		var w := minf(480.0, size.x * 0.48)
		_panel.anchor_left = 0.0
		_panel.anchor_right = 0.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 16
		_panel.offset_right = 16 + w
		_panel.offset_top = 16
		_panel.offset_bottom = -16
		app.camera.view_offset = Vector2(-2.0, 0)


## Brettet viser hjemmedrakt (spiller 1) mot bortedrakt (spiller 2) med valgt merke.
func _apply_looks() -> void:
	var home := Settings.look()
	var away := home.duplicate()
	away.away = true
	app.board.set_looks(home, away)
	app.board.refresh_pieces()
	_refresh_avatar()


func _place_demo() -> void:
	app.board.clear_pieces()
	for p in DEMO_LINE:
		app.board.add_piece(p, 1, false)
	for p in DEMO_P2:
		app.board.add_piece(p, 2, false)


## Spiller av valgt seiersanimasjon på demo-stillingen, og setter brettet tilbake etterpå.
func play_fx_preview() -> void:
	_fx_generation += 1
	var gen := _fx_generation
	_place_demo()
	app.board.highlight(DEMO_LINE)
	WinFx.play(app.board, app.camera, DEMO_LINE, Skins.ui_color(Settings.look()), Settings.win_fx_id)
	await get_tree().create_timer(3.0, true, false, true).timeout
	if is_inside_tree() and gen == _fx_generation:
		_place_demo()


func _refresh_avatar() -> void:
	if _avatar_view == null:
		return
	_avatar_view.set_avatar(Settings.avatar, Settings.display_name(), Skins.color_of(Settings.skin_id))
	_remove_avatar.disabled = Settings.avatar == ""


func _pick_avatar() -> void:
	_picker.pick()


func _on_avatar_picked(bytes: PackedByteArray) -> void:
	var b64 := AvatarData.from_bytes(bytes)
	_avatar_status.visible = b64 == ""
	_avatar_status.text = tr("Kunne ikke lese bildet. Prøv et PNG- eller JPEG-bilde.")
	if b64 != "":
		Settings.avatar = b64
		Settings.save()
		_refresh_avatar()


func _clear_avatar() -> void:
	Settings.avatar = ""
	Settings.save()
	_refresh_avatar()


func _reset_presets() -> void:
	Settings.chat_presets.clear()
	var defaults := Settings.chat_messages()
	for i in _preset_edits.size():
		_preset_edits[i].text = defaults[i] if i < defaults.size() else ""


func _set_language(lang: String) -> void:
	_store_fields()
	Settings.language = lang
	I18n.apply(lang)
	Settings.save()
	app.show_settings()   # bygg skjermen på nytt på det nye språket


## Lagrer feltene som ikke lagres med en gang (hurtigmeldinger, server).
func _store_fields() -> void:
	var msgs: Array[String] = []
	for e in _preset_edits:
		var t := e.text.strip_edges()
		if t != "":
			msgs.append(t)
	Settings.set_chat_messages(msgs)
	Settings.server_url = _server_edit.text.strip_edges()


func _on_back() -> void:
	_store_fields()
	Settings.save()
	app.show_menu()
