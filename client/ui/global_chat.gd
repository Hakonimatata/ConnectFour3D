class_name GlobalChat
extends PanelContainer
## Global chat i hovedmenyen: alle som er online kan skrive, og serveren publiserer hendelser
## her (nye Elo-nivåer, seiersrekker, turneringsvinnere og dagens oppgave).
## Øverst står hvor mange som er online og hvor mange som spiller nå.
## På mobil er den kompakt: én linje med siste melding og en knapp som åpner hele chatten.

signal toggled(open: bool)

var compact := false:
	set(v):
		if compact != v:
			compact = v
			_apply_compact()
var open := false
var _preview: Label
var _toggle: Button
var _body: Array[Control] = []

var _dot: Panel
var _header: Label
var _log: RichTextLabel
var _input: LineEdit
var _send_button: Button
var _reconnect: Button
var _online := 0
var _playing := 0
static var _star: Texture2D


func _ready() -> void:
	var v := UI.vbox(6)
	add_child(v)
	var top := UI.hbox(8)
	_dot = UI.dot(UI.SUCCESS, 10)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_dot)
	_header = UI.label("", "Muted")
	_header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_reconnect = UI.button("Koble til", func() -> void: Net.ensure_connected(), "GhostButton")
	top.add_child(_reconnect)
	_toggle = UI.button("Chat", func() -> void:
		open = not open
		_apply_compact()
		toggled.emit(open)
	, "GhostButton")
	top.add_child(_toggle)
	v.add_child(top)
	_preview = UI.label("", "Muted")
	_preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_preview.clip_text = true
	_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_preview)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 60
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_size_override("bold_font_size", 15)
	v.add_child(_log)
	_body.append(_log)

	var row := UI.hbox(6)
	_input = UI.line_edit("", "Skriv til alle…", Protocol.MAX_CHAT)
	_input.select_all_on_focus = false
	_input.clear_button_enabled = false
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_input)
	_send_button = UI.button("Send", _send)
	row.add_child(_send_button)
	v.add_child(row)
	_body.append(row)
	_apply_compact()

	Net.message.connect(_on_message)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_update_state)
	_update_state()


func _on_connected(_resumed: bool) -> void:
	_update_state()


func _process(_delta: float) -> void:
	if Net.status == Net.Status.CONNECTING:
		_update_state()


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.GLOBAL_HISTORY:
			_log.clear()
			for m in msg.get("messages", []):
				if m is Dictionary:
					_append(m)
		Protocol.GLOBAL_MSG:
			_append(msg)
		Protocol.PRESENCE:
			_online = int(msg.get("online", 0))
			_playing = int(msg.get("playing", 0))
			_update_state()


## Legger en melding nederst i loggen (også brukt av testene).
func add_entry(m: Dictionary) -> void:
	_append(m)


func _apply_compact() -> void:
	if _toggle == null:
		return
	var show_all := not compact or open
	for c in _body:
		c.visible = show_all
	_preview.visible = not show_all and _preview.text != ""
	_toggle.visible = compact
	_toggle.text = tr("Lukk") if open else tr("Chat")


func _append(m: Dictionary) -> void:
	_preview.text = _plain(m)
	_preview.visible = compact and not open and _preview.text != ""
	if str(m.get("kind", "chat")) == "event":
		# Hendelser: nøkkelen oversettes, og ord i args (f.eks. nivånavn) også
		var args: Array = (m.get("args", []) as Array).map(func(a: Variant) -> Variant: return I18n.t(a) if a is String else a)
		var text := I18n.server_text({ "key": m.get("key", ""), "args": args, "text": m.get("text", "") })
		_log.add_image(_star_icon(), 14, 14)
		_log.append_text(" [color=#ffd76a]%s[/color]\n" % _escape(text))
		return
	var elo := int(m.get("elo", -1))
	if elo >= 0:
		_log.add_image(EloBadge.icon(elo, 16), 16, 16)
		_log.append_text(" ")
	_log.append_text("[color=#%s][b]%s[/b][/color]  %s\n" % [UI.ACCENT.lightened(0.25).to_html(false),
		_escape(str(m.get("from", "?"))), _escape(str(m.get("text", "")))])


func _send() -> void:
	var t := _input.text.strip_edges()
	if t == "" or not Net.is_online():
		return
	Net.send({ "t": Protocol.GLOBAL_CHAT, "text": t })
	_input.clear()


func _update_state() -> void:
	var online := Net.is_online()
	_input.editable = online
	_send_button.disabled = not online
	_reconnect.visible = Net.status == Net.Status.OFFLINE
	_dot.modulate = Color.WHITE if online else Color(1, 1, 1, 0.25)
	if online:
		_header.text = tr("%d online · %d spiller nå") % [_online, _playing]
	elif Net.status == Net.Status.CONNECTING:
		_header.text = tr("Kobler til…")
	else:
		_header.text = tr("Frakoblet – chatten trenger serveren")


## Meldingen som ren tekst (til den kompakte linjen).
static func _plain(m: Dictionary) -> String:
	if str(m.get("kind", "chat")) == "event":
		var args: Array = (m.get("args", []) as Array).map(func(a: Variant) -> Variant: return I18n.t(a) if a is String else a)
		return I18n.server_text({ "key": m.get("key", ""), "args": args, "text": m.get("text", "") })
	return "%s: %s" % [str(m.get("from", "?")), str(m.get("text", ""))]


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


## En liten gullstjerne foran hendelser (tegnet i kode).
static func _star_icon() -> Texture2D:
	if _star != null:
		return _star
	var px := 28
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var pts := []
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(cos(a), sin(a)) * (0.95 if i % 2 == 0 else 0.42))
	for y in px:
		for x in px:
			var p := Vector2((x + 0.5) / px * 2.0 - 1.0, (y + 0.5) / px * 2.0 - 1.0)
			if Geometry2D.is_point_in_polygon(p, PackedVector2Array(pts)):
				img.set_pixel(x, y, Color("ffd76a"))
	_star = ImageTexture.create_from_image(img)
	return _star
