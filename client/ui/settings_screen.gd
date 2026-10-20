class_name SettingsScreen
extends Screen
## Innstillinger: navn, brikkefarge, lyd, vibrasjon og (avansert) serveradresse.

var _name_edit: LineEdit
var _server_edit: LineEdit


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 480)
	v.add_child(UI.label("Innstillinger", "Heading"))

	v.add_child(UI.section("Kallenavn"))
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Navnet ditt"
	v.add_child(_name_edit)

	v.add_child(UI.section("Brikkefarge"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var group := ButtonGroup.new()
	for skin in Skins.ALL:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "ChoiceButton"
		b.tooltip_text = skin.name
		b.custom_minimum_size = Vector2(52, 52)
		b.button_pressed = skin.id == Settings.skin_id
		var dot := UI.dot(skin.color, 26)
		dot.set_anchors_preset(Control.PRESET_CENTER)
		dot.offset_left = -13
		dot.offset_top = -13
		dot.offset_right = 13
		dot.offset_bottom = 13
		b.add_child(dot)
		var id: String = skin.id
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			Settings.skin_id = id
		)
		grid.add_child(b)
	v.add_child(grid)

	v.add_child(UI.section("Lyd og følelse"))
	v.add_child(UI.toggle_row("Lyd", "", Settings.sound, func(on: bool) -> void: Settings.sound = on))
	v.add_child(UI.toggle_row("Vibrasjon", "På mobil, der nettleseren støtter det.", Settings.vibration,
		func(on: bool) -> void: Settings.vibration = on))

	v.add_child(UI.section("Server (avansert)"))
	_server_edit = LineEdit.new()
	_server_edit.text = Settings.server_url
	_server_edit.placeholder_text = Settings.resolved_server_url()
	v.add_child(_server_edit)

	v.add_child(UI.spacer(6))
	v.add_child(UI.button("Lagre", _on_back, "PrimaryButton"))


func _on_back() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "":
		Settings.player_name = n
	Settings.server_url = _server_edit.text.strip_edges()
	Settings.save()
	app.show_menu()
