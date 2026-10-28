class_name TournamentEditScreen
extends Screen
## Skjema for å lage en turnering (bare admin). Det viktigste står øverst: navn, dag og klokkeslett
## (med piler), format, antall deltakere og pokalen. Resten (beskrivelse, regler, pauser,
## møtefrist og publisering) ligger under «Flere valg».

const FORMATS := ["knockout", "round_robin"]
const MAX_PLAYERS := [4, 8, 16, 32]
const GAPS_MIN := [1, 2, 5, 10]
const SHOW_UP_MIN := [2, 5, 10]
const MAX_DAYS := 60
const MINUTE_STEP := 15

var options := GameOptions.new()
var _name: LineEdit
var _desc: LineEdit
var _format := 0
var _max := 2
var _gap := 1
var _show_up := 1
var _publish := true
var _status: Label
var _created := false
var _trophy: Dictionary
var _trophy_view: TrophyView
## Starttid: dager fra i dag, time og minutt (lokal tid)
var _day := 0
var _hour := 20
var _minute := 0
var _day_label: Label
var _time_label: Label
var _when_label: Label
var _create_button: Button
var _advanced: VBoxContainer
var _ranked := true
var _with_trophy := true
var _trophy_row: Control


func _ready() -> void:
	app.camera.auto_rotate = true
	options.time_base_s = 180
	options.time_increment_s = 2
	# Standard: i kveld kl. 20, eller i morgen kl. 20 hvis det er for sent i dag
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var local := Time.get_datetime_dict_from_unix_time(now + bias)
	_day = 0 if int(local.hour) < 19 else 1

	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Ny turnering", "Heading"))
	v.add_child(UI.section("Navn"))
	_name = UI.line_edit("", "F.eks. Fredagscup", 40)
	v.add_child(_name)

	# --- Når
	v.add_child(UI.section("Når"))
	_day_label = _value_label()
	v.add_child(_stepper(_day_label, func(d: int) -> void: _day = clampi(_day + d, 0, MAX_DAYS)))
	_time_label = _value_label()
	v.add_child(_stepper(_time_label, func(d: int) -> void:
		var total := posmod(_hour * 60 + _minute + d * MINUTE_STEP, 24 * 60)
		_hour = total / 60
		_minute = total % 60
	))
	var hours := UI.hbox(6)
	for h in [18, 19, 20, 21]:
		var text := "%d:00" % h
		var b := UI.button(text, func() -> void:
			_hour = h
			_minute = 0
			_update_when()
		, "GhostButton")
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hours.add_child(b)
	v.add_child(hours)
	_when_label = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_when_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_when_label)

	v.add_child(UI.section("Format"))
	v.add_child(UI.choice(["Utslag", "Alle mot alle"], _format, func(i: int) -> void: _format = i))
	v.add_child(UI.section("Maks deltakere"))
	v.add_child(UI.choice(MAX_PLAYERS.map(func(n: int) -> String: return str(n)), _max, func(i: int) -> void: _max = i))

	# --- Rangert eller uranket. Uranket: ingen Elo, vises ikke i menyen og hedres ikke.
	v.add_child(UI.toggle_row("Rangert", "Partiene teller på Elo, og turneringen vises i menyen og i hall of fame.", _ranked,
		func(on: bool) -> void: _ranked = on))
	v.add_child(UI.toggle_row("Pokal til vinneren", "Vinneren får pokalen med turneringens navn på profilen sin.", _with_trophy,
		func(on: bool) -> void:
			_with_trophy = on
			_trophy_row.visible = on))

	# --- Pokalen vinneren får. En tilfeldig er valgt, og «Ny pokal» trekker en ny.
	v.add_child(UI.section("Pokal"))
	var trophy_row := UI.hbox(14)
	_trophy_row = trophy_row
	_trophy = Trophy.generate(randi())
	_trophy_view = TrophyView.new(_trophy, 120)
	trophy_row.add_child(_trophy_view)
	var trophy_side := UI.vbox(8)
	trophy_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trophy_side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trophy_side.add_child(UI.label("Vinneren får denne pokalen med turneringens navn på profilen sin.", "Muted",
		HORIZONTAL_ALIGNMENT_LEFT, true))
	trophy_side.add_child(UI.button("Ny pokal", func() -> void:
		_trophy = Trophy.generate(randi())
		_trophy_view.set_design(_trophy)
	))
	trophy_row.add_child(trophy_side)
	v.add_child(trophy_row)

	# --- Flere valg (skjult til man trenger dem)
	var more := UI.button("Flere valg", func() -> void: pass, "GhostButton")
	more.toggle_mode = true
	v.add_child(more)
	_advanced = UI.vbox(14)
	_advanced.visible = false
	more.toggled.connect(func(on: bool) -> void:
		_advanced.visible = on
		more.text = tr("Færre valg") if on else tr("Flere valg")
	)
	_advanced.add_child(UI.section("Beskrivelse"))
	_desc = UI.line_edit("", "Valgfritt", 300)
	_advanced.add_child(_desc)
	_advanced.add_child(UI.section("Pause mellom rundene"))
	_advanced.add_child(UI.choice(GAPS_MIN.map(func(n: int) -> String: return "%d min" % n), _gap,
		func(i: int) -> void: _gap = i))
	_advanced.add_child(UI.section("Møtefrist (ellers walkover)"))
	_advanced.add_child(UI.choice(SHOW_UP_MIN.map(func(n: int) -> String: return "%d min" % n), _show_up,
		func(i: int) -> void: _show_up = i))
	SetupScreen.add_option_fields(_advanced, options)
	_advanced.add_child(UI.toggle_row("Publiser med en gang", "Ellers lagres den som utkast som bare admin ser.", _publish,
		func(on: bool) -> void: _publish = on))
	v.add_child(_advanced)

	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	var buttons := UI.hbox(10)
	var back := UI.button("Tilbake", _on_back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button = UI.button("Opprett", _on_create, "PrimaryButton")
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	buttons.add_child(_create_button)
	UI.card_footer(v).add_child(buttons)
	Net.message.connect(_on_message)
	_update_when()
	# Hold «om X min» og «har passert» oppdatert
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.autostart = true
	timer.timeout.connect(_update_when)
	add_child(timer)


## [‹]  verdi  [›] — on_step(-1 eller 1) endrer verdien.
func _stepper(value: Label, on_step: Callable) -> HBoxContainer:
	var row := UI.hbox(8)
	for dir in [-1, 1]:
		var arrow := "‹" if dir < 0 else "›"
		var b := UI.button(arrow, func() -> void:
			on_step.call(dir)
			_update_when()
		)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size.x = 52
		if dir < 0:
			row.add_child(b)
			row.add_child(value)
		else:
			row.add_child(b)
	return row


func _value_label() -> Label:
	var l := UI.label("", "", HORIZONTAL_ALIGNMENT_CENTER)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 20)
	return l


## Starttid i unix-sekunder fra valgt dag og klokkeslett (lokal tid).
func start_time(now: int) -> int:
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var local := Time.get_datetime_dict_from_unix_time(now + bias)
	local.hour = _hour
	local.minute = _minute
	local.second = 0
	return Time.get_unix_time_from_datetime_dict(local) - bias + _day * 86400


func _update_when() -> void:
	var now := int(Time.get_unix_time_from_system())
	var start := start_time(now)
	_day_label.text = UI.format_day(start)
	_time_label.text = "%02d:%02d" % [_hour, _minute]
	var past := start <= now
	_when_label.text = tr("Tidspunktet har passert. Velg et senere klokkeslett.") if past \
		else tr("Påmeldingen er åpen til start: %s (%s).") % [UI.format_when(start), UI.format_until(start, now)]
	_when_label.add_theme_color_override("font_color", UI.DANGER if past else UI.MUTED)
	_create_button.disabled = past


func _on_create() -> void:
	var now := int(Time.get_unix_time_from_system())
	var start := start_time(now)
	if start <= now:
		_update_when()
		return
	_status.text = tr("Lagrer…")
	Net.send({ "t": Protocol.TOURNAMENT_CREATE, "data": {
		"name": _name.text.strip_edges(), "description": _desc.text.strip_edges(), "format": FORMATS[_format],
		"max_players": MAX_PLAYERS[_max], "start_time": start, "signup_deadline": start,
		"round_gap_s": GAPS_MIN[_gap] * 60, "show_up_s": SHOW_UP_MIN[_show_up] * 60, "options": options.to_dict(),
		"trophy": _trophy, "ranked": _ranked, "with_trophy": _with_trophy,
	} })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
			var id := int(msg.tournament.id)
			if _publish and not _created:
				_created = true
				Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": id, "action": "publish" })
			app.show_tournament(id)
		Protocol.ERROR:
			_status.text = I18n.server_text(msg)


func _on_back() -> void:
	app.show_tournaments()
