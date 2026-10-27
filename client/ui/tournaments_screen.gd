class_name TournamentsScreen
extends Screen
## Liste over turneringer. Admin kan lage nye.

var _list_box: VBoxContainer
var _new_button: Button


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 540)
	v.add_child(UI.label("Turneringer", "Heading"))
	_new_button = UI.button("Ny turnering", func() -> void: app.show_tournament_edit(), "PrimaryButton")
	_new_button.visible = false
	v.add_child(_new_button)
	_list_box = UI.vbox(8)
	v.add_child(_list_box)
	_list_box.add_child(UI.label("Henter…", "Muted"))
	UI.card_footer(v).add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	var timer := Timer.new()
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)
	_refresh()


func _refresh() -> void:
	Net.send({ "t": Protocol.LIST_TOURNAMENTS })


func _on_message(msg: Dictionary) -> void:
	if msg.t != Protocol.TOURNAMENT_LIST:
		return
	_new_button.visible = bool(msg.get("admin", false))
	for c in _list_box.get_children():
		c.queue_free()
	var list: Array = msg.get("tournaments", [])
	if list.is_empty():
		_list_box.add_child(UI.label("Ingen turneringer ennå.", "Muted"))
		return
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return TournamentScreen.status_order(a.status) < TournamentScreen.status_order(b.status) \
			or (a.status == b.status and a.start_time < b.start_time)
	)
	for t in list:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 64
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var line2 := "%s · %s · %d/%d · %s" % [tr(TournamentScreen.format_name(t.format)), tr(TournamentScreen.status_name(t.status)),
			int(t.players), int(t.max_players), UI.format_time(int(t.start_time))]
		if str(t.get("winner", "")) != "":
			line2 += " · " + tr("Vinner: %s") % str(t.winner)
		b.text = "%s\n%s" % [t.name, line2]
		var id := int(t.id)
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			app.show_tournament(id)
		)
		_list_box.add_child(b)


func _on_back() -> void:
	app.show_online()
