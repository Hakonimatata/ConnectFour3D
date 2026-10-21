class_name AccountScreen
extends Screen
## Logg inn eller registrer en konto (brukernavn + passord).

var _register := false
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _pass2_edit: LineEdit
var _status: Label
var _submit: Button
var _toggle: Button
var _title: Label


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 420)
	_title = UI.label("", "Heading")
	v.add_child(_title)
	v.add_child(UI.label("Med konto får du statistikk, Elo-rating og kan være med i turneringer.",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))

	v.add_child(UI.section("Brukernavn"))
	_user_edit = UI.line_edit("", "3–16 tegn", 16)
	v.add_child(_user_edit)
	v.add_child(UI.section("Passord"))
	_pass_edit = UI.line_edit("", "Minst 8 tegn", 72)
	_pass_edit.secret = true
	_pass_edit.select_all_on_focus = false
	v.add_child(_pass_edit)
	_pass2_edit = UI.line_edit("", "Gjenta passordet", 72)
	_pass2_edit.secret = true
	_pass2_edit.select_all_on_focus = false
	v.add_child(_pass2_edit)
	_pass_edit.text_submitted.connect(func(_t: String) -> void: _on_submit())
	_pass2_edit.text_submitted.connect(func(_t: String) -> void: _on_submit())

	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	_submit = UI.button("", _on_submit, "PrimaryButton")
	v.add_child(_submit)
	_toggle = UI.button("", func() -> void:
		_register = not _register
		_refresh()
	, "GhostButton")
	v.add_child(_toggle)
	v.add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	if not Net.can_send_password():
		_status.text = tr("Passord kan bare sendes over en sikker forbindelse (https). Innlogging er slått av her.")
		_status.add_theme_color_override("font_color", UI.DANGER)
	_refresh()


func _refresh() -> void:
	_title.text = tr("Ny konto") if _register else tr("Logg inn")
	_submit.text = tr("Registrer") if _register else tr("Logg inn")
	_toggle.text = tr("Har du konto? Logg inn") if _register else tr("Ny her? Lag en konto")
	_pass2_edit.visible = _register
	_submit.disabled = not Net.can_send_password() or not Net.is_online()


func _on_submit() -> void:
	if _submit.disabled:
		return
	if _register and _pass_edit.text != _pass2_edit.text:
		_show_error(tr("Passordene er ikke like."))
		return
	_submit.disabled = true
	_status.text = tr("Vent litt…")
	_status.remove_theme_color_override("font_color")
	Net.send({ "t": Protocol.REGISTER if _register else Protocol.LOGIN,
		"username": _user_edit.text.strip_edges(), "password": _pass_edit.text })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.SESSION:
			app.show_online()
		Protocol.AUTH_ERROR:
			_show_error(I18n.server_text(msg))
			_submit.disabled = false


func _show_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UI.DANGER)


func _on_back() -> void:
	app.show_online()
