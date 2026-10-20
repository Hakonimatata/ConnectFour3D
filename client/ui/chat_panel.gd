class_name ChatPanel
extends PanelContainer
## Enkel chat: meldingsliste, hurtigmeldinger og tekstfelt. Brukes i venterom og i spillet.

signal send_requested(text: String)

const MAX_LENGTH := 200

var _log: RichTextLabel
var _input: LineEdit


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
	_input = UI.line_edit("", "Skriv en melding…", MAX_LENGTH)
	_input.select_all_on_focus = false
	_input.clear_button_enabled = false
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_input)
	row.add_child(UI.button("Send", _send))
	v.add_child(row)


func add_message(from_name: String, text: String, color := UI.ACCENT) -> void:
	_log.append_text("[color=#%s][b]%s[/b][/color]  %s\n" % [color.to_html(false), _escape(from_name), _escape(text)])


func add_system(text: String) -> void:
	_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [UI.MUTED.to_html(false), _escape(text)])


func _send() -> void:
	var t := _input.text.strip_edges()
	if t == "":
		return
	send_requested.emit(t)
	_input.clear()


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")
