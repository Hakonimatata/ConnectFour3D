class_name UI
extends RefCounted
## Felles utseende (tema) og små hjelpefunksjoner for å bygge UI i kode.
## Endre farger og størrelser her, så endres hele spillet.

const BG := Color("0f1218")
const PANEL := Color("181c25")
const PANEL_LIGHT := Color("222836")
const BORDER := Color("2c3344")
const TEXT := Color("e8ecf3")
const MUTED := Color("8b93a7")
const ACCENT := Color("4c8dff")
const ACCENT_HOVER := Color("6aa0ff")
const DANGER := Color("ff5c5c")
const SUCCESS := Color("3ddc97")
const RADIUS := 14


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, RADIUS, BORDER))
	t.set_stylebox("panel", "Panel", _box(PANEL, RADIUS, BORDER))

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(PANEL_LIGHT, 10, BORDER, 14, 10))
		t.set_stylebox("hover", type, _box(Color("2a3142"), 10, Color("3a4357"), 14, 10))
		t.set_stylebox("pressed", type, _box(Color("1c2130"), 10, ACCENT, 14, 10))
		t.set_stylebox("disabled", type, _box(Color("191d27"), 10, Color("232938"), 14, 10))
		t.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), 10, Color(ACCENT, 0.7), 14, 10))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.6))

	# «Primær»-knapp: blå
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(ACCENT, 10, ACCENT, 14, 10))
	t.set_stylebox("hover", "PrimaryButton", _box(ACCENT_HOVER, 10, ACCENT_HOVER, 14, 10))
	t.set_stylebox("pressed", "PrimaryButton", _box(Color("3a74d8"), 10, Color("3a74d8"), 14, 10))

	# Valgt knapp i en gruppe (segmentert valg)
	t.set_type_variation("ChoiceButton", "Button")
	t.set_stylebox("normal", "ChoiceButton", _box(PANEL_LIGHT, 10, BORDER, 10, 8))
	t.set_stylebox("pressed", "ChoiceButton", _box(Color(ACCENT, 0.25), 10, ACCENT, 10, 8))
	t.set_stylebox("hover_pressed", "ChoiceButton", _box(Color(ACCENT, 0.32), 10, ACCENT, 10, 8))
	t.set_stylebox("hover", "ChoiceButton", _box(Color("2a3142"), 10, Color("3a4357"), 10, 8))

	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 12, 8))
	t.set_stylebox("hover", "GhostButton", _box(Color(1, 1, 1, 0.06), 10, Color(0, 0, 0, 0), 12, 8))
	t.set_stylebox("pressed", "GhostButton", _box(Color(1, 1, 1, 0.1), 10, Color(0, 0, 0, 0), 12, 8))

	t.set_stylebox("normal", "LineEdit", _box(Color("12151c"), 10, BORDER, 12, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color("12151c"), 10, ACCENT, 12, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))

	t.set_type_variation("Title", "Label")
	t.set_font_size("font_size", "Title", 40)
	t.set_type_variation("Heading", "Label")
	t.set_font_size("font_size", "Heading", 24)
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 15)

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, 10, BORDER, 6, 6))
	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(1, 1, 1, 0.15), 4))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func _box(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), pad_x := 18, pad_y := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0:
		s.set_border_width_all(1)
		s.border_color = border
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s


# ---------------------------------------------------------------- Byggeklosser

## wrap = bryt lange tekster over flere linjer (bruk i kort, ikke i rader med andre elementer).
static func label(text: String, variation := "", align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = variation
	return l


static func button(text: String, on_pressed: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: Sfx.play("click"))
	b.pressed.connect(on_pressed)
	return b


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Et kort midt på skjermen med maks bredde, som kan scrolles hvis det er for høyt.
## Gir innholds-VBoxen tilbake.
static func centered_card(parent: Control, max_width := 460.0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	center.add_child(margin)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = max_width
	margin.add_child(card)
	var content := vbox(14)
	card.add_child(content)
	# Krymp kortet på smale skjermer
	var fit := func() -> void:
		card.custom_minimum_size.x = minf(max_width, parent.size.x - 24.0)
	parent.resized.connect(fit)
	fit.call_deferred()
	return content


## Segmentert valg: en rad med knapper der én er valgt. on_change(indeks).
static func choice(options: Array, selected: int, on_change: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "ChoiceButton"
		b.custom_minimum_size = Vector2(56, 42)
		b.button_pressed = i == selected
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			on_change.call(i)
		)
		row.add_child(b)
	return row


## En rad med tekst til venstre og en av/på-bryter til høyre.
static func toggle_row(text: String, hint: String, value: bool, on_change: Callable) -> Control:
	var row := hbox(12)
	var texts := vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(label(text))
	if hint != "":
		texts.add_child(label(hint, "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	row.add_child(texts)
	var t := CheckButton.new()
	t.button_pressed = value
	t.toggled.connect(func(on: bool) -> void:
		Sfx.play("click")
		on_change.call(on)
	)
	row.add_child(t)
	return row


static func section(text: String) -> Label:
	var l := label(text.to_upper(), "Muted")
	l.add_theme_font_size_override("font_size", 13)
	return l


## En liten fargeprikk (for spiller og skins).
static func dot(color: Color, diameter := 16.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.add_theme_stylebox_override("panel", _box(color, int(diameter / 2.0)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func spacer(height := 4.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
