class_name FriendsScreen
extends Screen
## Venner: legg til med brukernavn, godta eller avslå forespørsler, og se hvem som er online.
## «Utfordre» åpner oppsettet for et privat rom, og vennen inviteres når rommet er laget.
## Spiller vennen nå, kan du se på partiet. Listen oppdateres av seg selv når noen kommer eller går.

var _add_edit: LineEdit
var _status: Label
var _requests_title: Label
var _requests_box: VBoxContainer
var _friends_box: VBoxContainer
var _back_to_menu := false
var _confirm_remove := ""   ## brukernavnet som er trykket «Fjern» på én gang (trykk igjen for å fjerne)


func _init(p_app: ClientRoot, back_to_menu := false) -> void:
	super(p_app)
	_back_to_menu = back_to_menu


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 500)
	v.add_child(UI.label("Venner", "Heading"))
	if not Net.is_logged_in():
		v.add_child(UI.label("Logg inn for å legge til venner og se hvem som er online.", "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UI.button("Logg inn / ny konto", func() -> void: app.show_account(_back_to_menu), "PrimaryButton"))
		v.add_child(UI.button("Tilbake", _on_back))
		return
	var add := UI.hbox(8)
	_add_edit = UI.line_edit("", "Brukernavn", Protocol.MAX_NAME)
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_t: String) -> void: _add())
	add.add_child(_add_edit)
	add.add_child(UI.button("Legg til", _add, "PrimaryButton"))
	v.add_child(add)
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_status)
	_requests_title = UI.section("Venneforespørsler")
	v.add_child(_requests_title)
	_requests_box = UI.vbox(6)
	v.add_child(_requests_box)
	v.add_child(UI.section("Vennene dine"))
	_friends_box = UI.vbox(6)
	v.add_child(_friends_box)
	v.add_child(UI.spacer(4))
	v.add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	Net.connected.connect(func(_r: bool) -> void: _send("list"))
	Net.ensure_connected()
	show_friends(Net.friends)
	_send("list")


func _send(action: String, username := "") -> void:
	Net.send({ "t": Protocol.FRIEND, "action": action, "username": username })


func _add() -> void:
	var name := _add_edit.text.strip_edges()
	if name == "":
		return
	_send("request", name)
	_status.text = tr("Forespørsel sendt til %s.") % name
	_add_edit.clear()


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.FRIENDS:
			show_friends(msg)
		Protocol.ERROR, Protocol.NOTICE:
			_status.text = I18n.server_text(msg)


## Forespørsler øverst (godta/avslå), så vennene: online først, med «Se på» eller «Utfordre».
func show_friends(data: Dictionary) -> void:
	for box in [_requests_box, _friends_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var requests: Array = data.get("requests", [])
	_requests_title.visible = not requests.is_empty()
	for r in requests:
		var row := _name_row(str(r.username), int(r.get("elo", -1)), tr("vil bli venn med deg"), UI.ACCENT)
		var name := str(r.username)
		row.add_child(UI.button("Godta", func() -> void: _send("accept", name), "PrimaryButton"))
		row.add_child(UI.button("Avslå", func() -> void: _send("decline", name), "GhostButton"))
		_requests_box.add_child(row)
	var friends: Array = data.get("friends", [])
	if friends.is_empty():
		_friends_box.add_child(UI.label("Ingen venner ennå. Skriv et brukernavn over for å legge til en.", "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
	for f in friends:
		var name := str(f.username)
		var playing := bool(f.get("playing", false))
		var online := bool(f.get("online", false))
		var state := tr("spiller nå") if playing else (tr("online") if online else tr("offline"))
		var color := UI.ACCENT_HOVER if playing else (UI.SUCCESS if online else Color(UI.MUTED, 0.5))
		var row := _name_row(name, int(f.get("elo", -1)), state, color)
		if playing and str(f.get("room", "")) != "":
			var code := str(f.room)
			row.add_child(UI.button("Se på", func() -> void: Net.send({ "t": Protocol.WATCH, "code": code })))
		elif online:
			row.add_child(UI.button("Utfordre", func() -> void: app.challenge(name), "PrimaryButton"))
		var remove := UI.button("Sikker?" if _confirm_remove == name else "Fjern", func() -> void:
			if _confirm_remove == name:
				_confirm_remove = ""
				_send("remove", name)
			else:
				_confirm_remove = name
				show_friends(Net.friends)
		, "GhostButton")
		row.add_child(remove)
		_friends_box.add_child(row)


## [prikk] [Elo-merke] Navn · status
func _name_row(name: String, elo: int, state: String, color: Color) -> HBoxContainer:
	var row := UI.hbox(8)
	var dot := UI.dot(color, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(EloBadge.make(elo, 20))
	var texts := UI.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UI.label(name)
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(n)
	var s := UI.label(state, "Muted")
	s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	texts.add_child(s)
	row.add_child(texts)
	return row


func _on_back() -> void:
	if _back_to_menu:
		app.show_menu()
	else:
		app.show_online()
