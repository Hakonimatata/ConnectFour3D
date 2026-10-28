class_name TournamentsScreen
extends Screen
## Liste over turneringer og hall of fame (vinnerne av rangerte turneringer). Admin kan lage nye.

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
		if not bool(t.get("ranked", true)):
			line2 += " · " + tr("Uranket")
		b.text = "%s\n%s" % [t.name, line2]
		var id := int(t.id)
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			app.show_tournament(id)
		)
		_list_box.add_child(b)
	_add_hall_of_fame(list)


## Hall of fame: vinnerne av rangerte turneringer, nyeste først, med pokalen de vant.
func _add_hall_of_fame(list: Array) -> void:
	var champs := list.filter(func(t: Dictionary) -> bool:
		return t.status == "finished" and str(t.get("winner", "")) != "" and bool(t.get("ranked", true)))
	if champs.is_empty():
		return
	champs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("finished_at", a.start_time)) > int(b.get("finished_at", b.start_time)))
	_list_box.add_child(UI.section("Hall of fame"))
	for t in champs:
		var row := UI.hbox(12)
		if bool(t.get("with_trophy", true)):
			row.add_child(TrophyView.new(t.get("trophy", {}), 52))
		var texts := UI.vbox(0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name := UI.name_button(str(t.winner), func() -> void: app.show_profile(str(t.winner)))
		name.add_theme_color_override("font_color", BracketView.GOLD)
		texts.add_child(name)
		var when := int(t.get("finished_at", 0)) if int(t.get("finished_at", 0)) > 0 else int(t.start_time)
		var sub := UI.label("%s · %s" % [t.name, UI.format_day(when)], "Muted")
		sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		texts.add_child(sub)
		row.add_child(texts)
		_list_box.add_child(row)


func _on_back() -> void:
	app.show_online()
