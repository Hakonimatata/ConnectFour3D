class_name SettingsScreen
extends Screen
## Innstillinger: navn, profilbilde, brikke (skin, merke, seiersanimasjon),
## hurtigmeldinger i chat, språk, lyd og (avansert) serveradresse.

const MAX_PRESETS := 6
const LANGUAGES := ["auto", "nb", "en"]

var _name_edit: LineEdit
var _server_edit: LineEdit
var _avatar_view: AvatarView
var _remove_avatar: Button
var _avatar_status: Label
var _picker: AvatarPicker
var _preview: PiecePreview
var _preset_edits: Array[LineEdit] = []


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 500)
	v.add_child(UI.label("Innstillinger", "Heading"))

	v.add_child(UI.section("Kallenavn"))
	_name_edit = UI.line_edit(Settings.player_name, "Navnet ditt", 16)
	v.add_child(_name_edit)

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
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh_avatar())

	# --- Brikke: forhåndsvisning, skin, merke og seiersanimasjon
	v.add_child(UI.section("Brikke"))
	_preview = PiecePreview.new(150)
	v.add_child(_preview)
	v.add_child(UI.label("Venstre: hjemmedrakt. Høyre: bortedrakt (brukes når motstanderen har samme skin).",
		"Muted", HORIZONTAL_ALIGNMENT_CENTER, true))

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
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(84, 70)
		b.button_pressed = skin.id == Settings.skin_id
		var id: String = skin.id
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			Settings.skin_id = id
			_refresh_look()
		)
		grid.add_child(b)
	v.add_child(grid)

	v.add_child(UI.section("Merke på toppen"))
	var decal_names: Array = Skins.DECALS.map(func(d: Dictionary) -> String: return d.name)
	v.add_child(UI.choice(decal_names, Skins.decal_index(Settings.decal_id), func(i: int) -> void:
		Settings.decal_id = Skins.DECALS[i].id
		_refresh_look()
	))

	v.add_child(UI.section("Seiersanimasjon"))
	var fx_names: Array = Skins.WIN_FX.map(func(d: Dictionary) -> String: return d.name)
	var fx_index := maxi(0, Skins.WIN_FX.map(func(d: Dictionary) -> String: return d.id).find(Settings.win_fx_id))
	v.add_child(UI.choice(fx_names, fx_index, func(i: int) -> void: Settings.win_fx_id = Skins.WIN_FX[i].id))

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
	_refresh_look()


func _refresh_look() -> void:
	_preview.set_look(Settings.look())
	_refresh_avatar()


func _refresh_avatar() -> void:
	_avatar_view.set_avatar(Settings.avatar, _name_edit.text, Skins.color_of(Settings.skin_id))
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


## Lagrer feltene som ikke lagres med en gang (navn, hurtigmeldinger, server).
func _store_fields() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "":
		Settings.player_name = n
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
