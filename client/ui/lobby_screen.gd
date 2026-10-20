class_name LobbyScreen
extends Screen
## Online-lobby: kobler til serveren, viser åpne rom, lar deg opprette eller bli med med kode.

var _status: Label
var _rooms_box: VBoxContainer
var _code_edit: LineEdit
var _buttons: Array[Button] = []
var _refresh_timer: Timer


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 500)
	v.add_child(UI.label("Spill online", "Heading"))
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)

	var create := UI.button("Opprett rom", _on_create, "PrimaryButton")
	v.add_child(create)
	_buttons.append(create)

	v.add_child(UI.section("Bli med med kode"))
	var row := UI.hbox(8)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "F.eks. KXRTA"
	_code_edit.max_length = Lobby.CODE_LENGTH
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 3.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)

	if Net.status == Net.Status.OFFLINE:
		Net.connect_to_server()
	else:
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
	match Net.status:
		Net.Status.ONLINE:
			_status.text = "Tilkoblet som %s" % Settings.player_name
		Net.Status.CONNECTING:
			_status.text = "Kobler til %s…%s" % [Net.url, ("\n" + Net.last_error) if Net.last_error != "" else ""]
		_:
			_status.text = Net.last_error if Net.last_error != "" else "Frakoblet"


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
		Protocol.ROOM_STATE:
			app.show_room(msg)
		Protocol.ERROR:
			_status.text = str(msg.get("text", "Feil"))


func _show_rooms(rooms: Array) -> void:
	for c in _rooms_box.get_children():
		c.queue_free()
	if rooms.is_empty():
		_rooms_box.add_child(UI.label("Ingen åpne rom akkurat nå. Opprett ett!", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for r in rooms:
		var row := UI.hbox(10)
		var texts := UI.vbox(2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_child(UI.label("%s sitt rom" % str(r.get("host", "?"))))
		texts.add_child(UI.label(str(r.get("description", "")), "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
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
	Net.close()
	app.show_menu()
