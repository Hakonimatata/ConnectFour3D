class_name GlobalChat
extends PanelContainer
## Global chat i hovedmenyen: alle som er online kan skrive, og serveren publiserer hendelser
## her (nye Elo-nivåer, seiersrekker, turneringsvinnere og dagens oppgave) og kunngjøringer fra admin.
## Øverst står hvor mange som er online og hvor mange som spiller nå, og under det hvem som er online.
## Kanalene «Generelt», «Velkommen» og «Innspill» (tilbakemeldinger) velges med faner. En prikk på fanen betyr
## nye meldinger der. Kunngjøringer vises i alle kanalene.
## På mobil er den kompakt: én linje med siste melding og en knapp som åpner hele chatten.

signal toggled(open: bool)

const CHANNELS := ["generelt", "velkommen", "tilbakemelding"]
const CHANNEL_NAMES := ["Generelt", "Velkommen", "Innspill"]
const PLACEHOLDERS := ["Skriv til alle…", "Si hei!", "Ønsker, feil eller ros…"]
const INTROS := ["",
	"Velkommen til Fire på rad i 3D! Si hei, spør om reglene, eller finn noen å spille med.",
	"Fant du en feil, eller har du et ønske? Skriv det her. Admin leser alt."]

var channel := "generelt"
var _tabs: Array[Button] = []
var _unread := {}            ## kanal -> true
var _messages: Array = []    ## alle meldingene vi har (alle kanaler)

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
var _who: RichTextLabel
var _users: Array = []
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

	# Hvem som er online: navnene på én eller noen få linjer
	_who = RichTextLabel.new()
	_who.bbcode_enabled = true
	_who.fit_content = true
	_who.scroll_active = false
	_who.selection_enabled = false
	_who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_who.add_theme_font_size_override("normal_font_size", 14)
	_who.add_theme_font_size_override("bold_font_size", 14)
	v.add_child(_who)

	# Kanalene
	var tabs := UI.hbox(6)
	var group := ButtonGroup.new()
	for i in CHANNELS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "ChoiceButton"
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size.y = 32
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.button_pressed = i == 0
		var c: String = CHANNELS[i]
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			set_channel(c)
		)
		tabs.add_child(b)
		_tabs.append(b)
	v.add_child(tabs)
	_body.append(tabs)

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
	# Fyll inn det vi allerede vet (menyen lages på nytt hver gang den vises)
	_online = int(Net.presence.online)
	_playing = int(Net.presence.playing)
	_users = Net.presence.get("users", [])
	_messages = Net.global_messages.duplicate()
	_unread.clear()
	_rebuild()
	if not _messages.is_empty():
		_preview.text = _plain(_messages[-1])
	_update_state()


## Bytter kanal: loggen viser bare den kanalen (og kunngjøringene).
func set_channel(c: String) -> void:
	channel = c if c in CHANNELS else CHANNELS[0]
	_unread.erase(channel)
	for i in _tabs.size():
		_tabs[i].button_pressed = CHANNELS[i] == channel
	_input.placeholder_text = tr(PLACEHOLDERS[CHANNELS.find(channel)])
	_rebuild()


func _rebuild() -> void:
	_log.clear()
	var intro: String = INTROS[CHANNELS.find(channel)]
	if intro != "":
		_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [UI.MUTED.to_html(false), _escape(tr(intro))])
	for m in _messages:
		if _channel_of(m) in [channel, "*"]:
			_render(m)
	_update_tabs()


func _update_tabs() -> void:
	for i in _tabs.size():
		_tabs[i].text = tr(CHANNEL_NAMES[i]) + ("  •" if _unread.has(CHANNELS[i]) else "")


static func _channel_of(m: Dictionary) -> String:
	return str(m.get("channel", "generelt"))


func _on_connected(_resumed: bool) -> void:
	_update_state()


func _process(_delta: float) -> void:
	if Net.status == Net.Status.CONNECTING:
		_update_state()


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.GLOBAL_HISTORY:
			_messages = (msg.get("messages", []) as Array).filter(func(m: Variant) -> bool: return m is Dictionary)
			_unread.clear()
			_rebuild()
			if not _messages.is_empty():
				_preview.text = _plain(_messages[-1])
		Protocol.GLOBAL_MSG:
			_append(msg)
		Protocol.PRESENCE:
			_online = int(msg.get("online", 0))
			_playing = int(msg.get("playing", 0))
			_users = msg.get("users", []) if msg.get("users") is Array else []
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
	_who.visible = show_all and Net.is_online() and not _users.is_empty()
	_preview.visible = not show_all and _preview.text != ""
	_toggle.visible = compact
	_toggle.text = tr("Lukk") if open else tr("Chat")


## En ny melding: vises hvis den er i kanalen som er valgt, ellers får fanen en prikk.
func _append(m: Dictionary) -> void:
	_messages.append(m)
	if _messages.size() > Net.GLOBAL_KEEP:
		_messages.pop_front()
	_preview.text = _plain(m)
	_preview.visible = compact and not open and _preview.text != ""
	var c := _channel_of(m)
	if c in [channel, "*"]:
		_render(m)
	elif c in CHANNELS:
		_unread[c] = true
		_update_tabs()


func _render(m: Dictionary) -> void:
	if str(m.get("kind", "chat")) == "announcement":
		_log.append_text("[bgcolor=#2a3550][color=#cfe0ff] [b]%s[/b] %s [/color][/bgcolor]\n" % [
			_escape(tr("Kunngjøring:")), _escape(str(m.get("text", "")))])
		return
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
	var who := str(m.get("from", "?"))
	_log.append_text("[color=#%s][b]%s[/b][/color]  %s\n" % [name_color(who).to_html(false),
		_escape(who), _escape(str(m.get("text", "")))])


## Skriver spilleren i chatten nå? (Da er tastaturet oppe på mobil.)
func is_typing() -> bool:
	return _input != null and _input.has_focus()


func _send() -> void:
	var t := _input.text.strip_edges()
	if t == "" or not Net.is_online():
		return
	Net.send({ "t": Protocol.GLOBAL_CHAT, "text": t, "channel": channel })
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
	_show_users(_users if online else [])


## Navnene på dem som er online, med Elo-merke og samme farge som i chatten.
func _show_users(users: Array) -> void:
	_who.clear()
	_apply_compact()
	var first := true
	for u in users:
		if not u is Dictionary:
			continue
		if not first:
			_who.append_text("[color=#%s]  ·  [/color]" % UI.MUTED.to_html(false))
		first = false
		var elo := int(u.get("elo", -1))
		if elo >= 0:
			_who.add_image(EloBadge.icon(elo, 14), 14, 14)
			_who.append_text(" ")
		var who := str(u.get("name", "?"))
		_who.append_text("[color=#%s][b]%s[/b][/color]" % [name_color(who).to_html(false), _escape(who)])
		if u.get("playing", false):
			_who.append_text(" [color=#%s](%s)[/color]" % [UI.MUTED.to_html(false), tr("i parti")])


## En fast farge per navn, så det er lett å se hvem som skriver. Samme navn gir alltid samme farge.
## Fargene er tydelig forskjellige og lesbare på mørk bakgrunn.
const NAME_COLORS := ["ff8a65", "ffd54f", "aed581", "4dd0e1", "64b5f6", "b39ddb", "f06292", "ffb74d",
	"81c784", "4db6ac", "ce93d8", "e57373"]


static func name_color(who: String) -> Color:
	return Color(NAME_COLORS[absi(who.to_lower().hash()) % NAME_COLORS.size()])


## Meldingen som ren tekst (til den kompakte linjen).
static func _plain(m: Dictionary) -> String:
	if str(m.get("kind", "chat")) == "announcement":
		return "%s %s" % [TranslationServer.translate("Kunngjøring:"), str(m.get("text", ""))]
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
