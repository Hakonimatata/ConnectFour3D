class_name TournamentEditScreen
extends Screen
## Skjema for å lage en turnering (bare admin). Det viktigste står øverst: navn, dag og klokkeslett
## (med piler), format, antall deltakere og pokalen. Resten (beskrivelse, regler, pauser,
## møtefrist og publisering) ligger under «Flere valg».
## Med en turnering (editing) endres den i stedet (runde 17): skjemaet fylles ut, og «Lagre» sender
## endringene. Har den startet, vises bare det som fortsatt kan endres (se Tournaments.update).

const FORMATS := ["knockout", "round_robin"]
const MAX_PLAYERS := [4, 8, 16, 32]
const ROUND_LIMITS := [0, 3, 5, 7]   ## alle mot alle: høyst så mange runder (0 = alle)
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
var _rounds := 0                    ## indeks i ROUND_LIMITS
var _rounds_box: Control
var _estimate: Label
var _prize := ""                    ## premien vinneren låser opp (Progression), "" = ingen
var editing: Dictionary = {}        ## turneringen som endres ({} = ny turnering)
var _locked := false                ## turneringen har startet: bare noe kan endres
var _saving := false


func _init(p_app: ClientRoot, p_tournament := {}) -> void:
	super(p_app)
	editing = p_tournament


func _ready() -> void:
	app.camera.auto_rotate = true
	options.time_base_s = 180
	options.time_increment_s = 2
	# Standard: i kveld kl. 20, eller i morgen kl. 20 hvis det er for sent i dag
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().bias) * 60
	var local := Time.get_datetime_dict_from_unix_time(now + bias)
	_day = 0 if int(local.hour) < 19 else 1
	_trophy = Trophy.generate(randi())
	if not editing.is_empty():
		_prefill(editing, now, bias)

	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Endre turnering" if not editing.is_empty() else "Ny turnering", "Heading"))
	if _locked:
		v.add_child(UI.label("Turneringen har startet. Format, deltakere, tid og regler ligger fast.", "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UI.section("Navn"))
	_name = UI.line_edit(str(editing.get("name", "")), "F.eks. Fredagscup", 40)
	v.add_child(_name)

	if not _locked:
		_add_when(v)
		v.add_child(UI.section("Format"))
		v.add_child(UI.choice(["Utslag", "Alle mot alle"], _format, func(i: int) -> void:
			_format = i
			_update_estimate()
		))
		v.add_child(UI.section("Maks deltakere"))
		v.add_child(UI.choice(MAX_PLAYERS.map(func(n: int) -> String: return str(n)), _max, func(i: int) -> void:
			_max = i
			_update_estimate()
		))
		# Alle mot alle: begrens antall runder (16 spillere og alle runder tar ca. 2 timer)
		var rounds := UI.vbox(8)
		rounds.add_child(UI.section("Antall runder"))
		rounds.add_child(UI.choice(ROUND_LIMITS.map(func(n: int) -> String: return tr("Alle") if n == 0 else str(n)), _rounds,
			func(i: int) -> void:
				_rounds = i
				_update_estimate()
		))
		rounds.add_child(UI.label("Hver spiller spiller så mange partier (én færre ved fri runde). Flest poeng vinner.",
			"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		_rounds_box = rounds
		v.add_child(rounds)
		_estimate = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
		_estimate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(_estimate)

		# --- Rangert eller uranket. Uranket: ingen Elo, vises ikke i menyen og hedres ikke.
		v.add_child(UI.toggle_row("Rangert", "Partiene teller på Elo, og turneringen vises i menyen og i hall of fame.", _ranked,
			func(on: bool) -> void: _ranked = on))

	# --- Pokalen vinneren får (kan byttes til vinneren er kåret). En tilfeldig er valgt, og «Ny pokal» trekker en ny.
	var running := str(editing.get("status", "")) == "running"
	if not _locked or running:
		v.add_child(UI.toggle_row("Pokal til vinneren", "Vinneren får pokalen med turneringens navn på profilen sin.", _with_trophy,
			func(on: bool) -> void:
				_with_trophy = on
				_trophy_row.visible = on))
		var trophy_row := UI.hbox(14)
		_trophy_row = trophy_row
		trophy_row.visible = _with_trophy
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
		v.add_child(_prize_picker())

	# --- Flere valg (skjult til man trenger dem, men åpne når en turnering som har startet endres)
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
	_desc = UI.line_edit(str(editing.get("description", "")), "Valgfritt", 300)
	_advanced.add_child(_desc)
	if not _locked or running:
		_advanced.add_child(UI.section("Pause mellom rundene"))
		_advanced.add_child(UI.choice(GAPS_MIN.map(func(n: int) -> String: return "%d min" % n), _gap,
			func(i: int) -> void:
				_gap = i
				_update_estimate()
		))
		_advanced.add_child(UI.section("Møtefrist (ellers walkover)"))
		_advanced.add_child(UI.choice(SHOW_UP_MIN.map(func(n: int) -> String: return "%d min" % n), _show_up,
			func(i: int) -> void: _show_up = i))
	if not _locked:
		SetupScreen.add_option_fields(_advanced, options)
	if editing.is_empty():
		_advanced.add_child(UI.toggle_row("Publiser med en gang", "Ellers lagres den som utkast som bare admin ser.", _publish,
			func(on: bool) -> void: _publish = on))
	v.add_child(_advanced)
	if _locked:
		more.button_pressed = true

	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	var buttons := UI.hbox(10)
	var back := UI.button("Tilbake", _on_back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button = UI.button("Lagre" if not editing.is_empty() else "Opprett", _on_create, "PrimaryButton")
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


## Premie (runde 17): en skin eller seiersanimasjon som ellers låses opp av nivå. Vinneren får den.
func _prize_picker() -> Control:
	var box := UI.vbox(6)
	box.add_child(UI.section("Premie"))
	var pick := OptionButton.new()
	pick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var items: Array[String] = [""]
	pick.add_item(tr("Ingen"))
	for item in Progression.items():
		if Progression.UNLOCKS.get(item) is int:
			items.append(item)
			pick.add_item("%s (%s)" % [Progression.item_name(item), Progression.requirement_text(item)])
	pick.selected = maxi(0, items.find(_prize))
	pick.item_selected.connect(func(i: int) -> void: _prize = items[i])
	box.add_child(pick)
	box.add_child(UI.label("Vinneren låser opp premien med en gang, uansett nivå.", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	return box


## Dag og klokkeslett (med piler og snarveier).
func _add_when(v: VBoxContainer) -> void:
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


## Endre en turnering: skjemaet fylles ut med det som er valgt (nærmeste valg når verdien ikke finnes).
func _prefill(t: Dictionary, now: int, bias: int) -> void:
	_locked = not str(t.get("status", "")) in ["draft", "open"]
	options = GameOptions.from_dict(t.get("options", {}) if t.get("options") is Dictionary else {})
	_format = maxi(0, FORMATS.find(str(t.get("format", ""))))
	_max = _nearest(MAX_PLAYERS, int(t.get("max_players", 16)))
	_rounds = maxi(0, ROUND_LIMITS.find(int(t.get("max_rounds", 0))))
	_gap = _nearest(GAPS_MIN, int(t.get("round_gap_s", 120)) / 60)
	_show_up = _nearest(SHOW_UP_MIN, int(t.get("show_up_s", 300)) / 60)
	_ranked = bool(t.get("ranked", true))
	_with_trophy = bool(t.get("with_trophy", true))
	if t.get("trophy") is Dictionary and not (t.trophy as Dictionary).is_empty():
		_trophy = t.trophy
	_publish = false
	_prize = str(t.get("prize", ""))
	var start := int(t.get("start_time", now))
	var local := Time.get_datetime_dict_from_unix_time(start + bias)
	_hour = int(local.hour)
	_minute = int(local.minute) / MINUTE_STEP * MINUTE_STEP
	_day = clampi(floori((start + bias) / 86400.0) - floori((now + bias) / 86400.0), 0, MAX_DAYS)


static func _nearest(list: Array, value: int) -> int:
	var best := 0
	for i in list.size():
		if absi(int(list[i]) - value) < absi(int(list[best]) - value):
			best = i
	return best


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


## «Varighet med 16 spillere: ca. 1 t 50 min (15 runder)» – så admin ser hva valgene betyr.
func _update_estimate() -> void:
	if _estimate == null:
		return
	_rounds_box.visible = _format == 1
	var players: int = MAX_PLAYERS[_max]
	var max_rounds: int = ROUND_LIMITS[_rounds] if _format == 1 else 0
	var n := TournamentScreen.round_count(FORMATS[_format], players, max_rounds)
	var minutes := TournamentScreen.estimate_minutes(n, options, GAPS_MIN[_gap] * 60)
	_estimate.text = tr("Varighet med %d spillere: ca. %s (%d runder).") % [players, TournamentScreen.duration_text(minutes), n]


func _update_when() -> void:
	_update_estimate()
	if _locked:
		return
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
	var data := {
		"name": _name.text.strip_edges(), "description": _desc.text.strip_edges(),
		"round_gap_s": GAPS_MIN[_gap] * 60, "show_up_s": SHOW_UP_MIN[_show_up] * 60,
		"trophy": _trophy, "with_trophy": _with_trophy, "prize": _prize,
	}
	if not _locked:
		var now := int(Time.get_unix_time_from_system())
		var start := start_time(now)
		if start <= now:
			_update_when()
			return
		data.merge({ "format": FORMATS[_format], "max_players": MAX_PLAYERS[_max],
			"max_rounds": ROUND_LIMITS[_rounds] if _format == 1 else 0, "start_time": start, "signup_deadline": start,
			"options": options.to_dict(), "ranked": _ranked })
	_status.text = tr("Lagrer…")
	_saving = true
	if editing.is_empty():
		Net.send({ "t": Protocol.TOURNAMENT_CREATE, "data": data })
	else:
		Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": int(editing.id), "data": data })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
			if not _saving:
				return
			var id := int(msg.tournament.id)
			if _publish and not _created:
				_created = true
				Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": id, "action": "publish" })
			app.show_tournament(id)
		Protocol.ERROR:
			_saving = false
			_status.text = I18n.server_text(msg)


func _on_back() -> void:
	if editing.is_empty():
		app.show_tournaments()
	else:
		app.show_tournament(int(editing.id))
