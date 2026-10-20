class_name UI
extends RefCounted
## Felles utseende (tema) og små hjelpefunksjoner for å bygge UI i kode.
## Endre farger og størrelser her, så endres hele spillet.

const BG_TOP := Color("343a47")        ## Bakgrunnsgradient (se client_root.gd)
const BG_BOTTOM := Color("1a1d24")
const BG_GLOW := Color("464d5c")
const PANEL := Color(0.085, 0.094, 0.115, 0.94)
const PANEL_LIGHT := Color("1d2129")
const BORDER := Color("2b303a")
const BUTTON := Color("2a2f39")
const BUTTON_HOVER := Color("343a46")
const BUTTON_PRESSED := Color("22262e")
const BUTTON_BORDER := Color("3d4452")
const TEXT := Color("e4e6eb")
const MUTED := Color("8d93a0")
const ACCENT := Color("6a83b8")          ## Dempet blå
const ACCENT_HOVER := Color("7891c4")
const ACCENT_PRESSED := Color("5a71a3")
const DANGER := Color("d4706e")
const SUCCESS := Color("6fb894")
const RADIUS := 14


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, RADIUS, BORDER, 18, 18, 10))
	t.set_stylebox("panel", "Panel", _box(PANEL, RADIUS, BORDER))

	# Vanlige knapper: lysere enn panelet, med kant og en svak skygge så de «løfter seg».
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(BUTTON, 10, BUTTON_BORDER, 14, 10, 3))
		t.set_stylebox("hover", type, _box(BUTTON_HOVER, 10, Color("4b5364"), 14, 10, 4))
		t.set_stylebox("pressed", type, _box(BUTTON_PRESSED, 10, ACCENT, 14, 10))
		t.set_stylebox("disabled", type, _box(Color("1b1e24"), 10, Color("262a32"), 14, 10))
		t.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), 10, Color(ACCENT, 0.6), 14, 10))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.5))

	# «Primær»-knapp: dempet blå
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(ACCENT, 10, ACCENT_HOVER, 14, 10, 4))
	t.set_stylebox("hover", "PrimaryButton", _box(ACCENT_HOVER, 10, Color("8ea3cf"), 14, 10, 5))
	t.set_stylebox("pressed", "PrimaryButton", _box(ACCENT_PRESSED, 10, ACCENT_PRESSED, 14, 10))
	t.set_color("font_color", "PrimaryButton", Color.WHITE)

	# Valg i en gruppe (segmentert valg). Valgt = fylt med dempet aksentfarge.
	t.set_type_variation("ChoiceButton", "Button")
	t.set_stylebox("normal", "ChoiceButton", _box(BUTTON, 10, BUTTON_BORDER, 10, 8, 2))
	t.set_stylebox("hover", "ChoiceButton", _box(BUTTON_HOVER, 10, Color("4b5364"), 10, 8, 2))
	t.set_stylebox("pressed", "ChoiceButton", _box(Color("3c4a66"), 10, ACCENT_HOVER, 10, 8))
	t.set_stylebox("hover_pressed", "ChoiceButton", _box(Color("445373"), 10, ACCENT_HOVER, 10, 8))
	t.set_color("font_color", "ChoiceButton", Color(TEXT, 0.85))
	t.set_color("font_pressed_color", "ChoiceButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "ChoiceButton", Color.WHITE)

	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 12, 8))
	t.set_stylebox("hover", "GhostButton", _box(Color(1, 1, 1, 0.06), 10, Color(0, 0, 0, 0), 12, 8))
	t.set_stylebox("pressed", "GhostButton", _box(Color(1, 1, 1, 0.1), 10, Color(0, 0, 0, 0), 12, 8))

	t.set_stylebox("normal", "LineEdit", _box(Color("111317"), 10, BUTTON_BORDER, 12, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color("111317"), 10, ACCENT, 12, 10))
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
	# Av/på-bryter med tydelig forskjell: av = grå med lys knott til venstre, på = blå med knott til høyre.
	var off := _switch_icon(false)
	var on := _switch_icon(true)
	t.set_icon("unchecked", "CheckButton", off)
	t.set_icon("checked", "CheckButton", on)
	t.set_icon("unchecked_mirrored", "CheckButton", off)
	t.set_icon("checked_mirrored", "CheckButton", on)
	t.set_icon("unchecked_disabled", "CheckButton", off)
	t.set_icon("checked_disabled", "CheckButton", on)
	t.set_icon("unchecked_disabled_mirrored", "CheckButton", off)
	t.set_icon("checked_disabled_mirrored", "CheckButton", on)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, 10, BORDER, 6, 6))
	# Tynt, diskré scrollefelt
	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 3, 3))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(1, 1, 1, 0.12), 3, Color(0, 0, 0, 0), 3, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(1, 1, 1, 0.2), 3, Color(0, 0, 0, 0), 3, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(Color(1, 1, 1, 0.26), 3, Color(0, 0, 0, 0), 3, 3))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


## Tegner en av/på-bryter (pille med knott) som bilde, med myke kanter.
static func _switch_icon(on: bool) -> ImageTexture:
	var w := 52
	var h := 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color("4a505c")
	var track_border := ACCENT_HOVER if on else Color("6b7280")
	var knob := Color.WHITE if on else Color("c9cdd5")
	var r := h / 2.0
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			# Pille: avstand til linjestykket mellom de to halvsirklenes sentre
			var cx := clampf(px.x, r, w - r)
			var d_track := px.distance_to(Vector2(cx, r)) - (r - 0.5)
			var a_track := clampf(0.5 - d_track, 0.0, 1.0)
			var border := clampf(0.5 - absf(d_track + 1.0) + 0.5, 0.0, 1.0)
			var c := track.lerp(track_border, border * 0.8)
			c.a = a_track
			var d_knob := px.distance_to(Vector2(knob_x, r)) - (r - 4.0)
			var a_knob := clampf(0.5 - d_knob, 0.0, 1.0)
			c = Color(c.lerp(knob, a_knob), maxf(c.a, a_knob))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## shadow > 0 gir en myk skygge under boksen (piksler).
static func _box(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), pad_x := 18, pad_y := 18, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0:
		s.set_border_width_all(1)
		s.border_color = border
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
		s.shadow_color = Color(0, 0, 0, 0.28)
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
