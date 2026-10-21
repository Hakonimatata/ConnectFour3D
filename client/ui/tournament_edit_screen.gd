class_name TournamentEditScreen
extends Screen
## Skjema for å lage en turnering (bare admin).

const FORMATS := ["knockout", "round_robin"]
const MAX_PLAYERS := [4, 8, 16, 32]
const STARTS_MIN := [5, 15, 30, 60, 120, 1440]
const GAPS_MIN := [1, 2, 5, 10]
const SHOW_UP_MIN := [2, 5, 10]

var options := GameOptions.new()
var _name: LineEdit
var _desc: LineEdit
var _time: LineEdit
var _format := 0
var _max := 2
var _start := 1
var _gap := 1
var _show_up := 1
var _publish := true
var _status: Label
var _created := false


func _ready() -> void:
	app.camera.auto_rotate = true
	options.time_base_s = 180
	options.time_increment_s = 2
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Ny turnering", "Heading"))
	v.add_child(UI.section("Navn"))
	_name = UI.line_edit("", "F.eks. Fredagscup", 40)
	v.add_child(_name)
	v.add_child(UI.section("Beskrivelse"))
	_desc = UI.line_edit("", "Valgfritt", 300)
	v.add_child(_desc)

	v.add_child(UI.section("Format"))
	v.add_child(UI.choice(["Utslag", "Alle mot alle"], _format, func(i: int) -> void: _format = i))
	v.add_child(UI.section("Maks deltakere"))
	v.add_child(UI.choice(MAX_PLAYERS.map(func(n: int) -> String: return str(n)), _max, func(i: int) -> void: _max = i))

	v.add_child(UI.section("Start (påmeldingen stenger da)"))
	v.add_child(UI.choice(["5 min", "15 min", "30 min", "1 time", "2 timer", "I morgen"], _start,
		func(i: int) -> void: _start = i))
	_time = UI.line_edit("", "Eller klokkeslett, f.eks. 20:00", 5)
	v.add_child(_time)
	v.add_child(UI.section("Pause mellom rundene"))
	v.add_child(UI.choice(GAPS_MIN.map(func(n: int) -> String: return "%d min" % n), _gap,
		func(i: int) -> void: _gap = i))
	v.add_child(UI.section("Møtefrist (ellers walkover)"))
	v.add_child(UI.choice(SHOW_UP_MIN.map(func(n: int) -> String: return "%d min" % n), _show_up,
		func(i: int) -> void: _show_up = i))

	SetupScreen.add_option_fields(v, options)

	v.add_child(UI.toggle_row("Publiser med en gang", "Ellers lagres den som utkast som bare admin ser.", _publish,
		func(on: bool) -> void: _publish = on))
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	var buttons := UI.hbox(10)
	var back := UI.button("Tilbake", _on_back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var create := UI.button("Opprett", _on_create, "PrimaryButton")
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	buttons.add_child(create)
	v.add_child(buttons)
	Net.message.connect(_on_message)


## Starttid i unix-sekunder: klokkeslett hvis skrevet inn (i dag, eller i morgen hvis passert),
## ellers «om N minutter».
func start_time(now: int) -> int:
	var text := _time.text.strip_edges().replace(".", ":")
	var parts := text.split(":")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var bias := int(Time.get_time_zone_from_system().bias) * 60
		var local := Time.get_datetime_dict_from_unix_time(now + bias)
		local.hour = clampi(int(parts[0]), 0, 23)
		local.minute = clampi(int(parts[1]), 0, 59)
		local.second = 0
		var t := Time.get_unix_time_from_datetime_dict(local) - bias
		if t <= now:
			t += 86400
		return t
	return now + STARTS_MIN[_start] * 60


func _on_create() -> void:
	var now := int(Time.get_unix_time_from_system())
	var start := start_time(now)
	_status.text = tr("Lagrer…")
	Net.send({ "t": Protocol.TOURNAMENT_CREATE, "data": {
		"name": _name.text.strip_edges(), "description": _desc.text.strip_edges(), "format": FORMATS[_format],
		"max_players": MAX_PLAYERS[_max], "start_time": start, "signup_deadline": start,
		"round_gap_s": GAPS_MIN[_gap] * 60, "show_up_s": SHOW_UP_MIN[_show_up] * 60, "options": options.to_dict(),
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
