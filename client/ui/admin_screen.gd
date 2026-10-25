class_name AdminScreen
extends Screen
## Admin: kunngjøringer til alle, utestenging av spillere og pokaler til en spiller.
## Knappen hit vises i hovedmenyen bare for brukere med "admin": true. Serveren sjekker det også.

var _announce: LineEdit
var _ban_user: LineEdit
var _ban_reason: LineEdit
var _banned_box: VBoxContainer
var _award_user: LineEdit
var _award_name: LineEdit
var _preview: TrophyView
var _design: Dictionary
var _status: Label


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Admin", "Heading"))

	# --- Kunngjøring
	v.add_child(UI.section("Kunngjøring"))
	v.add_child(UI.label("Vises som et banner hos alle som er online, og blir stående i den globale chatten.",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	_announce = UI.line_edit("", "Skriv til alle spillerne…", Protocol.MAX_ANNOUNCEMENT)
	_announce.text_submitted.connect(func(_t: String) -> void: _send_announcement())
	v.add_child(_announce)
	v.add_child(UI.button("Send til alle", _send_announcement, "PrimaryButton"))

	# --- Utestenging
	v.add_child(UI.section("Utesteng en spiller"))
	v.add_child(UI.label("Kontoen kan ikke logge inn lenger, og spilleren kastes ut hvis den er online.",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	_ban_user = UI.line_edit("", "Brukernavn", Protocol.MAX_NAME)
	v.add_child(_ban_user)
	_ban_reason = UI.line_edit("", "Grunn (valgfritt, vises for spilleren)", 200)
	v.add_child(_ban_reason)
	v.add_child(UI.button("Utesteng", func() -> void:
		_send({ "action": "ban", "username": _ban_user.text.strip_edges(), "reason": _ban_reason.text.strip_edges() })
	))
	_banned_box = UI.vbox(6)
	v.add_child(_banned_box)

	# --- Pokal
	v.add_child(UI.section("Gi en pokal"))
	v.add_child(UI.label("Pokalen havner på profilen til spilleren og kunngjøres i chatten. Trykk «Ny pokal» til du finner en du liker.",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := UI.hbox(14)
	_design = Trophy.generate(randi())
	_preview = TrophyView.new(_design, 128)
	row.add_child(_preview)
	var fields := UI.vbox(8)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_award_name = UI.line_edit("", "Navn på pokalen", Trophy.MAX_NAME)
	fields.add_child(_award_name)
	_award_user = UI.line_edit("", "Brukernavn", Protocol.MAX_NAME)
	fields.add_child(_award_user)
	fields.add_child(UI.button("Ny pokal", _reroll))
	row.add_child(fields)
	v.add_child(row)
	v.add_child(UI.button("Gi pokal", func() -> void:
		_send({ "action": "award", "username": _award_user.text.strip_edges(), "name": _award_name.text.strip_edges(),
			"design": _design })
	, "PrimaryButton"))

	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_status)
	v.add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	Net.connected.connect(_on_connected)
	Net.ensure_connected()
	if Net.is_online():
		_send({ "action": "banned_list" })


func _on_connected(_resumed: bool) -> void:
	_status.text = ""
	_send({ "action": "banned_list" })


func _send(msg: Dictionary) -> void:
	msg.t = Protocol.ADMIN
	if not Net.is_online():
		_status.text = tr("Ikke koblet til serveren.")
		return
	Net.send(msg)


func _send_announcement() -> void:
	_send({ "action": "announce", "text": _announce.text.strip_edges() })


func _reroll() -> void:
	_design = Trophy.generate(randi())
	_preview.set_design(_design)


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.ADMIN_RESULT:
			if str(msg.get("action", "")) != "banned_list":
				_status.text = I18n.server_text(msg)
			if bool(msg.get("ok", false)):
				match str(msg.get("action", "")):
					"announce": _announce.clear()
					"ban":
						_ban_user.clear()
						_ban_reason.clear()
					"award":
						_award_name.clear()
						_reroll()
			show_banned(msg.get("banned", []))
		Protocol.ERROR:
			_status.text = I18n.server_text(msg)


## Utestengte spillere, med grunn og en knapp for å oppheve.
func show_banned(list: Array) -> void:
	for c in _banned_box.get_children():
		c.queue_free()
	if list.is_empty():
		_banned_box.add_child(UI.label("Ingen er utestengt.", "Muted"))
		return
	for b in list:
		var row := UI.hbox(8)
		var text := str(b.get("username", "?"))
		if str(b.get("reason", "")) != "":
			text += "  ·  " + str(b.reason)
		var l := UI.label(text)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
		var name := str(b.get("username", ""))
		row.add_child(UI.button("Opphev", func() -> void: _send({ "action": "unban", "username": name }), "GhostButton"))
		_banned_box.add_child(row)


func _on_back() -> void:
	app.show_menu()
