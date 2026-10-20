class_name RoomScreen
extends Screen
## Venterom: romkode, spillere, innstillinger, «klar»-knapp og chat.
## Når begge er klare starter serveren partiet (game_start).

var _room: Dictionary
var _code_label: Label
var _desc_label: Label
var _players_box: VBoxContainer
var _ready_button: Button
var _options_button: Button
var _chat: ChatPanel
var _is_ready := false


func _init(p_app: ClientRoot, room_state: Dictionary) -> void:
	super(p_app)
	_room = room_state


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Rom", "Muted"))
	_code_label = UI.label("", "Title")
	v.add_child(_code_label)
	v.add_child(UI.label("Gi koden til en venn, så kan de bli med.", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	_desc_label = UI.label("", "", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_desc_label)

	v.add_child(UI.section("Spillere"))
	_players_box = UI.vbox(8)
	v.add_child(_players_box)

	var row := UI.hbox(10)
	_ready_button = UI.button("Klar!", _toggle_ready, "PrimaryButton")
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_button = UI.button("Endre regler", _edit_options)
	row.add_child(_ready_button)
	row.add_child(_options_button)
	v.add_child(row)

	v.add_child(UI.section("Chat"))
	_chat = ChatPanel.new()
	_chat.custom_minimum_size.y = 220
	_chat.send_requested.connect(func(t: String) -> void: Net.send({ "t": Protocol.CHAT, "text": t }))
	v.add_child(_chat)

	v.add_child(UI.button("Forlat rommet", _on_back))

	Net.message.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)
	_show(_room)


func _on_disconnected() -> void:
	_chat.add_system("Mistet forbindelsen. Kobler til igjen…")


func _show(room: Dictionary) -> void:
	_room = room
	_code_label.text = str(room.get("code", ""))
	_desc_label.text = str(room.get("description", ""))
	var you := int(room.get("you", 1))
	_options_button.visible = you == 1
	for c in _players_box.get_children():
		c.queue_free()
	var players: Array = room.get("players", [])
	var both := true
	for i in 2:
		var info = players[i] if i < players.size() else null
		var row := UI.hbox(10)
		if info == null:
			both = false
			row.add_child(UI.dot(UI.BORDER))
			row.add_child(UI.label("Venter på motstander…", "Muted"))
		else:
			row.add_child(UI.dot(Skins.color_of(str(info.skin))))
			var name_label := UI.label(str(info.name) + (" (deg)" if int(info.seat) == you else ""))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var state_text := "klar" if bool(info.ready) else "ikke klar"
			if not bool(info.connected):
				state_text = "frakoblet"
			var s := UI.label(state_text, "Muted")
			if bool(info.ready):
				s.add_theme_color_override("font_color", UI.SUCCESS)
			row.add_child(s)
			if int(info.seat) == you:
				_is_ready = bool(info.ready)
		_players_box.add_child(row)
	_ready_button.text = "Ikke klar likevel" if _is_ready else "Klar!"
	_ready_button.disabled = not both


func _toggle_ready() -> void:
	Net.send({ "t": Protocol.READY, "ready": not _is_ready })


func _edit_options() -> void:
	var current := GameOptions.from_dict(_room.get("options", {}))
	Settings.last_options = current.to_dict()
	var room := _room
	app.show_setup("online", func(options: GameOptions, _private: bool) -> void:
		Net.send({ "t": Protocol.SET_OPTIONS, "options": options.to_dict() })
		app.show_room(room)
	, func() -> void: app.show_room(room))


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.ROOM_STATE:
			_show(msg)
		Protocol.CHAT_MSG:
			var seat := int(msg.get("seat", 0))
			var players: Array = _room.get("players", [])
			var color := UI.ACCENT
			if seat >= 1 and seat <= players.size() and players[seat - 1] != null:
				color = Skins.color_of(str(players[seat - 1].skin))
			_chat.add_message(str(msg.get("from", "")), str(msg.get("text", "")), color)
		Protocol.NOTICE, Protocol.ERROR:
			_chat.add_system(str(msg.get("text", "")))
		Protocol.GAME_START, Protocol.GAME_SYNC:
			app.start_match(OnlineMatch.new(msg))


func _on_back() -> void:
	Net.send({ "t": Protocol.LEAVE_ROOM })
	app.show_online()
