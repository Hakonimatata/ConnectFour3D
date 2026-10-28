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


## Et spillernavn som ser ut som tekst, men kan trykkes på (f.eks. for å se profilen). Lyser opp under musen.
static func name_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT_HOVER)
	b.add_theme_color_override("font_pressed_color", ACCENT_HOVER)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.pressed.connect(func() -> void: Sfx.play("click"))
	b.pressed.connect(on_pressed)
	return b


## Tekstfelt som er lett å bruke på mobil: trykk markerer all tekst, og en
## liten x-knapp tømmer feltet.
static func line_edit(text: String, placeholder := "", max_length := 0) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	if max_length > 0:
		e.max_length = max_length
	e.select_all_on_focus = true
	e.clear_button_enabled = true
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## Tekstfelt til chat. Feltet beholder fokus etter Enter, så man kan skrive neste melding med en gang
## (på PC måtte man ellers klikke i feltet for hver melding).
static func chat_input(placeholder: String) -> LineEdit:
	var e := line_edit("", placeholder, Protocol.MAX_CHAT)
	e.select_all_on_focus = false
	e.clear_button_enabled = false
	e.keep_editing_on_text_submit = true
	return e


## Etter «Send»-knappen: tilbake i feltet på PC. På telefon lar vi være (tastaturet ville sprette opp).
static func refocus_chat(e: LineEdit) -> void:
	if not is_touch_device():
		e.grab_focus()


static func is_touch_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Et kort midt på skjermen med maks bredde. Er innholdet for høyt, scrolles det inne i kortet.
## Gir innholds-VBoxen tilbake. Knapper i card_footer(content) ligger fast nederst i kortet,
## så «Tilbake» og «Lagre» alltid synes uten at man må scrolle helt ned.
static func centered_card(parent: Control, max_width := 460.0) -> VBoxContainer:
	var holder := CardHolder.new()
	holder.max_width = max_width
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	holder.card = PanelContainer.new()
	holder.add_child(holder.card)
	var column := vbox(14)
	holder.card.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	smooth_scroll(scroll)
	column.add_child(scroll)
	holder.content = vbox(14)
	holder.content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder.content)
	holder.footer = vbox(10)
	holder.footer.visible = false
	column.add_child(holder.footer)
	holder.content.set_meta("card_footer", holder.footer)
	holder.resized.connect(holder.fit)
	holder.content.minimum_size_changed.connect(holder.fit)
	holder.footer.minimum_size_changed.connect(holder.fit)
	holder.footer.child_entered_tree.connect(holder.fit_later.unbind(1))
	holder.footer.child_exiting_tree.connect(holder.fit_later.unbind(1))
	holder.fit_later()
	return holder.content


## Holder kortet fra centered_card på plass: så høyt som innholdet, men aldri høyere enn skjermen
## (da scrolles innholdet), midt på, og smalere på smale skjermer.
class CardHolder extends Control:
	var max_width := 460.0
	var card: PanelContainer
	var content: VBoxContainer
	var footer: VBoxContainer

	func fit_later() -> void:
		fit.call_deferred()

	func fit() -> void:
		if card == null or not is_inside_tree():
			return
		footer.visible = footer.get_child_count() > 0
		var pad := card.get_theme_stylebox("panel").get_minimum_size()
		var w := minf(max_width, size.x - 24.0)
		var footer_h := footer.get_combined_minimum_size().y + 14.0 if footer.visible else 0.0
		var h := minf(content.get_combined_minimum_size().y + footer_h + pad.y, size.y - 24.0)
		card.size = Vector2(w, maxf(h, 0.0))
		card.position = ((size - card.size) * 0.5).floor()


## Den faste raden nederst i et centered_card (alltid synlig). Legg «Tilbake» og lignende her.
static func card_footer(content: VBoxContainer) -> VBoxContainer:
	return content.get_meta("card_footer")


## Musehjulet scroller et fast, lite stykke med en myk overgang. Godot scroller ellers en
## åttendedel av det synlige området per hakk, noe som blir store hopp i høye vinduer.
static func smooth_scroll(scroll: ScrollContainer, step := 70.0) -> void:
	scroll.gui_input.connect(func(e: InputEvent) -> void:
		# Touch (mus etterlignet fra touch): dra 1:1, også når fingeren starter på en knapp.
		if e.device == InputEvent.DEVICE_ID_EMULATION and (e is InputEventMouseButton or e is InputEventMouseMotion):
			_touch_scroll(scroll, e)
			return
		var mb := e as InputEventMouseButton
		if mb == null or not mb.pressed:
			return
		if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			return
		var bar := scroll.get_v_scroll_bar()
		var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		var factor := mb.factor if mb.factor > 0.0 else 1.0
		var target: float = scroll.get_meta("scroll_target", float(scroll.scroll_vertical))
		if absf(target - scroll.scroll_vertical) > step * 6.0:
			target = scroll.scroll_vertical
		target = clampf(target + dir * step * factor, 0.0, maxf(0.0, bar.max_value - bar.page))
		scroll.set_meta("scroll_target", target)
		var old = (scroll.get_meta("scroll_tween") if scroll.has_meta("scroll_tween") else null)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		var tw := scroll.create_tween()
		tw.tween_property(scroll, "scroll_vertical", int(target), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		scroll.set_meta("scroll_tween", tw)
		scroll.accept_event()
	)


const TOUCH_SLOP := 10.0   ## så langt fingeren må flytte seg før det regnes som scrolling (ikke trykk)


## Dra med fingeren: innholdet følger fingeren nøyaktig, og fortsetter litt ved et raskt sveip.
## Knappen fingeren startet på får beskjed (NOTIFICATION_SCROLL_BEGIN), så den ikke trykkes.
static func _touch_scroll(scroll: ScrollContainer, e: InputEvent) -> void:
	var bar := scroll.get_v_scroll_bar()
	var max_scroll := maxf(0.0, bar.max_value - bar.page)
	var mb := e as InputEventMouseButton
	if mb:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var old = (scroll.get_meta("scroll_tween") if scroll.has_meta("scroll_tween") else null)
			if old is Tween and (old as Tween).is_valid():
				(old as Tween).kill()
			scroll.set_meta("touch", { "down": true, "from": mb.position.y, "start": float(scroll.scroll_vertical),
				"dragging": false, "vel": 0.0 })
		else:
			var st: Dictionary = scroll.get_meta("touch", {})
			scroll.set_meta("touch", {})
			if st.get("dragging", false):
				var target := clampf(scroll.scroll_vertical - float(st.vel) * 0.3, 0.0, max_scroll)
				var tw := scroll.create_tween()
				tw.tween_property(scroll, "scroll_vertical", int(target), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				scroll.set_meta("scroll_tween", tw)
				scroll.set_meta("scroll_target", target)
				scroll.accept_event()
		return
	var mm := e as InputEventMouseMotion
	var st: Dictionary = scroll.get_meta("touch", {})
	if mm == null or not st.get("down", false):
		return
	var dy: float = mm.position.y - float(st.from)
	if not st.dragging and absf(dy) > TOUCH_SLOP:
		st.dragging = true
		st.from = mm.position.y
		dy = 0.0
		scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	if st.dragging:
		scroll.scroll_vertical = int(clampf(float(st.start) - dy, 0.0, max_scroll))
		scroll.set_meta("scroll_target", float(scroll.scroll_vertical))
		st.vel = mm.velocity.y
		scroll.accept_event()


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
	# Oversett før store bokstaver (oversettelsen slår opp på den vanlige teksten).
	var l := label(I18n.t(text).to_upper(), "Muted")
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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


## Unix-tid som lokal dato og klokkeslett, f.eks. «21.10 20:00».
const WEEKDAYS := ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"]
const MONTHS := ["jan.", "feb.", "mars", "april", "mai", "juni", "juli", "aug.", "sep.", "okt.", "nov.", "des."]


## Hvor mange dager fra i dag (lokal tid) et tidspunkt er: 0 = i dag, 1 = i morgen, -1 = i går.
static func days_from_today(unix: int, now: int = -1) -> int:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	return int(floor((unix + bias) / 86400.0)) - int(floor((now + bias) / 86400.0))


## «I dag», «I morgen» eller «lørdag 1. nov.»
static func format_day(unix: int) -> String:
	var days := days_from_today(unix)
	if days == 0:
		return TranslationServer.translate("I dag")
	if days == 1:
		return TranslationServer.translate("I morgen")
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return TranslationServer.translate("%s %d. %s") % [TranslationServer.translate(WEEKDAYS[int(d.weekday)]),
		int(d.day), TranslationServer.translate(MONTHS[int(d.month) - 1])]


## «I morgen kl. 20:00», «lørdag 1. nov. kl. 20:00»
static func format_when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return TranslationServer.translate("%s kl. %02d:%02d") % [format_day(unix), int(d.hour), int(d.minute)]


## «om 2 t 15 min», «om 3 dager»
static func format_until(unix: int, now: int = -1) -> String:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var s := maxi(0, unix - now)
	if s >= 2 * 86400:
		return TranslationServer.translate("om %d dager") % (s / 86400)
	if s >= 3600:
		return TranslationServer.translate("om %d t %d min") % [s / 3600, (s % 3600) / 60]
	return TranslationServer.translate("om %d min") % maxi(1, s / 60)


static func format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d.%02d %02d:%02d" % [d.day, d.month, d.hour, d.minute]


static func spacer(height := 4.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
