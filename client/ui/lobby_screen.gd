class_name LobbyScreen
extends Screen
## Online-lobby: kobler til serveren, viser åpne rom, lar deg opprette eller bli med med kode.

var _status: Label
var _rooms_box: VBoxContainer
var _code_edit: LineEdit
var _buttons: Array[Button] = []
var _refresh_timer: Timer
var _account_row: HBoxContainer


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 500)
	v.add_child(UI.label("Spill online", "Heading"))
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	_account_row = UI.hbox(8)
	v.add_child(_account_row)
	var more := UI.hbox(8)
	var tour := UI.button("Turneringer", func() -> void: app.show_tournaments())
	tour.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stats := UI.button("Statistikk og toppliste", func() -> void: app.show_profile())
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more.add_child(tour)
	more.add_child(stats)
	_buttons.append(tour)
	_buttons.append(stats)
	v.add_child(more)

	var create := UI.button("Opprett rom", _on_create, "PrimaryButton")
	v.add_child(create)
	_buttons.append(create)

	v.add_child(UI.section("Bli med med kode"))
	var row := UI.hbox(8)
	_code_edit = UI.line_edit("", "F.eks. KXRTA", Lobby.CODE_LENGTH)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join(_code_edit.text))
	row.add_child(_code_edit)
	var join := UI.button("Bli med", func() -> void: _join(_code_edit.text))
	row.add_child(join)
	_buttons.append(join)
	v.add_child(row)

	v.add_child(UI.section("Åpne rom"))
	_rooms_box = UI.vbox(8)
	v.add_child(_rooms_box)

	v.add_child(UI.spacer(4))
	v.add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_update_status)
	Net.account_changed.connect(_update_status)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 3.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)

	Net.ensure_connected()
	_refresh()
	_update_status()
	_show_rooms([])


func _process(_delta: float) -> void:
	if Net.status == Net.Status.CONNECTING:
		_update_status()


func _update_status() -> void:
	var online := Net.is_online()
	for b in _buttons:
		b.disabled = not online
	_rebuild_account_row()
	match Net.status:
		Net.Status.ONLINE:
			if Net.is_logged_in():
				_status.text = tr("Innlogget som %s · Elo %d") % [Net.user.username, int(Net.user.elo)]
			else:
				_status.text = tr("Tilkoblet som %s (gjest)") % Settings.player_name
		Net.Status.CONNECTING:
			_status.text = tr("Kobler til %s…%s") % [Net.url, ("\n" + Net.last_error) if Net.last_error != "" else ""]
		_:
			_status.text = Net.last_error if Net.last_error != "" else tr("Frakoblet")
	if app.lobby_message != "" and Net.is_online():
		_status.text = app.lobby_message + "\n" + _status.text


func _rebuild_account_row() -> void:
	for c in _account_row.get_children():
		c.queue_free()
	if not Net.is_online():
		return
	if Net.is_logged_in():
		var profile := UI.button("Min profil", func() -> void: app.show_profile())
		profile.icon = EloBadge.icon(int(Net.user.elo), 20)
		profile.tooltip_text = EloBadge.describe(int(Net.user.elo))
		profile.add_theme_constant_override("icon_max_width", 20)
		profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_account_row.add_child(profile)
		_account_row.add_child(UI.button("Logg ut", func() -> void: Net.logout(), "GhostButton"))
	else:
		var login := UI.button("Logg inn / ny konto", func() -> void: app.show_account(), "GhostButton")
		login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_account_row.add_child(login)


func _on_connected(_resumed: bool) -> void:
	_update_status()
	_refresh()


func _refresh() -> void:
	if Net.is_online():
		Net.send({ "t": Protocol.LIST_ROOMS })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.ROOM_LIST:
			_show_rooms(msg.get("rooms", []))
		Protocol.ERROR:
			_status.text = I18n.server_text(msg)


func _show_rooms(rooms: Array) -> void:
	for c in _rooms_box.get_children():
		c.queue_free()
	if rooms.is_empty():
		_rooms_box.add_child(UI.label("Ingen åpne rom akkurat nå. Opprett ett!", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for r in rooms:
		var row := UI.hbox(10)
		if r.get("host_elo") != null:
			row.add_child(EloBadge.make(int(r.host_elo), 22))
		var texts := UI.vbox(2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_child(UI.label(tr("%s sitt rom") % str(r.get("host", "?"))))
		var opts = r.get("options", {})
		texts.add_child(UI.label(GameOptions.from_dict(opts if opts is Dictionary else {}).describe(), "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
		row.add_child(texts)
		var code := str(r.get("code", ""))
		row.add_child(UI.button("Bli med", func() -> void: _join(code)))
		_rooms_box.add_child(row)


func _on_create() -> void:
	# NB: callbacken må tilhøre app (ClientRoot), ikke denne skjermen. Skjermen
	# slettes når oppsettet vises, og en callback bundet til den ville peke på null.
	app.show_setup("online", app.online_create_room)


func _join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code != "":
		Net.send({ "t": Protocol.JOIN_ROOM, "code": code })


func _on_back() -> void:
	app.lobby_message = ""
	Net.close()
	app.show_menu()
