class_name ChatPanel
extends PanelContainer
## Enkel chat: meldingsliste, hurtigmeldinger og tekstfelt. Brukes i venterom, i spillet og på
## turneringssiden (uten hurtigmeldinger). Feltet beholder fokus etter sending på PC.

signal send_requested(text: String)

const MAX_LENGTH := 200

var with_quick := true
var placeholder := "Skriv en melding…"
var _log: RichTextLabel
var _input: LineEdit


func _init(p_with_quick := true, p_placeholder := "Skriv en melding…") -> void:
	with_quick = p_with_quick
	placeholder = p_placeholder


func _ready() -> void:
	var v := UI.vbox(8)
	add_child(v)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 120
	_log.selection_enabled = false
	v.add_child(_log)

	if with_quick:
		var quick := HFlowContainer.new()
		quick.add_theme_constant_override("h_separation", 6)
		quick.add_theme_constant_override("v_separation", 6)
		for q in Settings.chat_messages():
			var b := UI.button(q, func() -> void: send_requested.emit(q), "ChoiceButton")
			b.custom_minimum_size.y = 36
			b.add_theme_font_size_override("font_size", 15)
			quick.add_child(b)
		v.add_child(quick)

	var row := UI.hbox(8)
	_input = UI.chat_input(placeholder)
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_input)
	row.add_child(UI.button("Send", func() -> void:
		_send()
		UI.refocus_chat(_input)
	))
	v.add_child(row)


func add_message(from_name: String, text: String, color := UI.ACCENT) -> void:
	_log.append_text("[color=#%s][b]%s[/b][/color]  %s\n" % [color.to_html(false), _escape(from_name), _escape(text)])


func add_system(text: String) -> void:
	_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [UI.MUTED.to_html(false), _escape(text)])


func clear_log() -> void:
	_log.clear()


func _send() -> void:
	var t := _input.text.strip_edges()
	if t == "":
		return
	send_requested.emit(t)
	_input.clear()


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")
