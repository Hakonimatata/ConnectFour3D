class_name TournamentScreen
extends Screen
## Én turnering: pokalen (og vinneren når den er ferdig), info, påmelding, deltakere,
## turneringstreet (utslag), runder/kamper, tabell og admin-knapper.
## Serveren sender endringer med en gang mens siden er oppe.

var tournament_id := 0
var _t: Dictionary = {}
var _admin := false
var _you := 0
var _content: VBoxContainer
var _status: Label
var back_to_menu := false   ## åpnet fra menyen: «Tilbake» går dit


func _init(p_app: ClientRoot, id: int, p_back_to_menu := false) -> void:
	super(p_app)
	tournament_id = id
	back_to_menu = p_back_to_menu


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 680)   # bredt nok til treet med pokalen i midten (8 spillere) på PC
	_content = UI.vbox(10)
	v.add_child(_content)
	_content.add_child(UI.label("Henter…", "Muted"))
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	v.add_child(UI.button("Tilbake", _on_back))
	Net.message.connect(_on_message)
	Net.connected.connect(func(_r: bool) -> void: _refresh())
	# Serveren sender endringer med en gang (view_tournament). Timeren er bare en reserve.
	var timer := Timer.new()
	timer.wait_time = 15.0
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)
	_refresh()


## get_tournament (ikke view_tournament): den nye serveren følger siden og sender endringer med en
## gang, og en eldre server som ikke kjenner view_tournament, svarer likevel.
func _refresh() -> void:
	Net.send({ "t": Protocol.GET_TOURNAMENT, "id": tournament_id })


func _exit_tree() -> void:
	Net.send({ "t": Protocol.VIEW_TOURNAMENT, "id": 0 })   # siden er lukket: ikke send flere endringer


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
			if int(msg.tournament.id) == tournament_id:
				if msg.tournament == _t and bool(msg.get("admin", false)) == _admin and int(msg.get("you", 0)) == _you:
					return   # ingenting nytt (siden hentes hvert 3. sekund): ikke bygg på nytt
				_t = msg.tournament
				_admin = bool(msg.get("admin", false))
				_you = int(msg.get("you", 0))
				_rebuild()
		Protocol.TOURNAMENT_LIST:
			app.show_tournaments()   # etter sletting
		Protocol.ERROR:
			_status.text = I18n.server_text(msg)


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	var t := _t
	_content.add_child(_plain(str(t.name), "Heading"))
	if str(t.description) != "":
		var d := _plain(str(t.description), "Muted")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(d)
	_content.add_child(_trophy_block(t))
	var opts := GameOptions.from_dict(t.options)
	var info := [
		"%s · %s" % [tr(format_name(t.format)), opts.describe()],
		tr("Status: %s") % tr(status_name(t.status)),
		tr("Start: %s") % UI.format_time(int(t.start_time)),
		tr("Deltakere: %d av %d") % [int(t.players), int(t.max_players)],
		tr("Møt opp innen %d min, pause mellom rundene %d min.") % [int(t.show_up_s) / 60, int(t.round_gap_s) / 60],
	]
	for line in info:
		var l := _plain(line, "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)

	# --- Din status som deltaker: neste kamp, at den spilles, eller at du er ute
	var status := my_status()
	if status != "":
		var s := _plain(status, "")
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_color_override("font_color", BracketView.YOU)
		_content.add_child(s)

	# --- Din neste kamp
	var mine := _my_waiting_match()
	if not mine.is_empty():
		var go := UI.button("Gå til kamp!", func() -> void: app.join_room(str(mine.room)), "PrimaryButton")
		_content.add_child(go)

	# --- Påmelding
	var joined := _you in (t.player_list as Array).map(func(p: Dictionary) -> int: return int(p.id))
	if t.status == "open":
		if not Net.is_logged_in():
			_content.add_child(UI.button("Logg inn for å melde deg på", func() -> void: app.show_account()))
		elif joined:
			_content.add_child(UI.button("Meld meg av", func() -> void: _send(Protocol.TOURNAMENT_LEAVE)))
		else:
			_content.add_child(UI.button("Meld meg på", func() -> void: _send(Protocol.TOURNAMENT_JOIN), "PrimaryButton"))
	_content.add_child(UI.button("Del lenke til turneringen", func() -> void:
		_status.text = app.share_link("turnering", str(tournament_id), str(t.name))
	))

	# --- Deltakere
	_content.add_child(UI.section("Deltakere"))
	if (t.player_list as Array).is_empty():
		_content.add_child(UI.label("Ingen påmeldte ennå.", "Muted"))
	for p in t.player_list:
		_content.add_child(_with_badge(int(p.elo), _plain("%s  ·  Elo %d" % [p.username, int(p.elo)], "")))

	# --- Tabell (alle mot alle)
	if t.has("standings"):
		_content.add_child(UI.section("Tabell"))
		var place := 1
		for row in t.standings:
			_content.add_child(_with_badge(int(row.get("elo", -1)), _plain(tr("%d. %s – %s poeng (%d–%d–%d)") % [place,
				row.username, _points(int(row.points2)), int(row.wins), int(row.draws), int(row.losses)], "")))
			place += 1

	# --- Turneringstreet (utslag)
	var knockout: bool = t.format == "knockout" and not (t.rounds as Array).is_empty()
	if knockout:
		_content.add_child(UI.section("Turneringstre"))
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var bracket := BracketView.new(t.rounds, _you, t.get("trophy", {}))
		bracket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bracket.watch_requested.connect(func(code: String) -> void: Net.send({ "t": Protocol.WATCH, "code": code }))
		scroll.add_child(bracket)
		_content.add_child(scroll)

	# --- Runder og kamper (i en ferdig utslagsturnering sier treet alt)
	for r in (t.rounds as Array).size():
		if knockout and t.status == "finished":
			break
		_content.add_child(UI.section(tr("Runde %d") % (r + 1)))
		for m in t.rounds[r]:
			var label := _plain(_match_text(m), "Muted" if m.status == "done" else "")
			var own_match := _you != 0 and _you in [int(m.p1), int(m.p2)]
			if m.status == "playing" and str(m.room) != "" and not own_match:
				var row := UI.hbox(8)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.add_child(label)
				var code := str(m.room)
				row.add_child(UI.button("Se på", func() -> void: Net.send({ "t": Protocol.WATCH, "code": code })))
				_content.add_child(row)
			else:
				_content.add_child(label)

	# --- Admin
	if _admin:
		_content.add_child(UI.section("Admin"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		if t.status == "draft":
			row.add_child(UI.button("Publiser", func() -> void: _admin_action("publish"), "PrimaryButton"))
		if t.status in ["draft", "open"]:
			row.add_child(UI.button("Start nå", func() -> void: _admin_action("start")))
			# Bytt pokalen vinneren får (trykk til du liker den; siden oppdateres med en gang)
			row.add_child(UI.button("Ny pokal", func() -> void:
				Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id,
					"data": { "trophy": Trophy.generate(randi()) } })
			))
		if t.status in ["draft", "open", "running"]:
			row.add_child(UI.button("Avlys", func() -> void: _admin_action("cancel")))
		row.add_child(UI.button("Slett", func() -> void: _admin_action("delete")))
		_content.add_child(row)


## Ferdig med vinner: en hedersplass med pokalen (som gløder), «Vinner» og navnet i gull.
## Ellers: pokalen det spilles om.
func _trophy_block(t: Dictionary) -> Control:
	var winner := str(t.get("winner", ""))
	if t.status == "finished" and winner != "":
		var hero := PanelContainer.new()
		hero.add_theme_stylebox_override("panel", UI._box(Color("2a2617"), 14, Color("b8913a"), 16, 12, 4))
		var row := UI.hbox(16)
		row.add_child(TrophyView.new(t.get("trophy", {}), 132, true))
		var texts := UI.vbox(2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var title := UI.label("Vinner", "Muted")
		title.add_theme_color_override("font_color", Color(BracketView.GOLD, 0.75))
		texts.add_child(title)
		var name := _plain(winner, "Title")
		name.add_theme_color_override("font_color", BracketView.GOLD)
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		texts.add_child(name)
		var sub := _plain(tr("Vant pokalen «%s»") % t.name, "Muted")
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(sub)
		if int(t.get("finished_at", 0)) > 0:
			texts.add_child(_plain(UI.format_time(int(t.finished_at)), "Muted"))
		row.add_child(texts)
		hero.add_child(row)
		return hero
	var row := UI.hbox(14)
	row.add_child(TrophyView.new(t.get("trophy", {}), 84))
	var l := UI.label("Det spilles om denne pokalen. Vinneren får den med turneringens navn på profilen sin.", "Muted",
		HORIZONTAL_ALIGNMENT_LEFT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _match_text(m: Dictionary) -> String:
	var names := "%s – %s" % [m.p1_name, m.p2_name]
	match str(m.status):
		"done":
			var winner := str(m.p1_name) if int(m.winner) == int(m.p1) else str(m.p2_name)
			match str(m.reason):
				"bye": return tr("%s: fri runde") % winner
				"walkover": return tr("%s · %s vant på walkover") % [names, winner]
				"no_show": return tr("%s · ingen møtte") % names
				"draw": return tr("%s · uavgjort") % names
			return tr("%s · %s vant") % [names, winner] if int(m.winner) != 0 else names
		"waiting": return tr("%s · venter på spillerne") % names
		"playing": return tr("%s · spilles nå") % names
		"scheduled": return tr("%s · starter %s") % [names, UI.format_time(int(m.start_at))]
	return names


## Statuslinjen for en deltaker i en pågående turnering. Tom for andre.
func my_status() -> String:
	if _you == 0 or _t.is_empty() or _t.status != "running" or (_t.rounds as Array).is_empty():
		return ""
	for m in _t.rounds[int(_t.current_round)]:
		if not _you in [int(m.p1), int(m.p2)]:
			continue
		var names := "%s – %s" % [m.p1_name, m.p2_name]
		match str(m.status):
			"scheduled": return tr("Din kamp: %s · starter %s") % [names, UI.format_time(int(m.start_at))]
			"waiting": return tr("Din kamp: %s · nå! Trykk «Gå til kamp».") % names
			"playing": return tr("Din kamp: %s · spilles nå") % names
			"done":
				if int(m.winner) == _you:
					return tr("Du vant kampen! Neste runde starter når de andre kampene er ferdige.")
	if _t.format == "knockout" and _you in (_t.player_list as Array).map(func(p: Dictionary) -> int: return int(p.id)):
		return tr("Du er ute av turneringen. Takk for innsatsen!")
	return ""


func _my_waiting_match() -> Dictionary:
	if _you == 0 or _t.is_empty() or _t.status != "running":
		return {}
	for m in _t.rounds[int(_t.current_round)]:
		if m.status in ["waiting", "playing"] and _you in [int(m.p1), int(m.p2)]:
			return m
	return {}


func _send(t: String) -> void:
	Net.send({ "t": t, "id": tournament_id })


func _admin_action(action: String) -> void:
	Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": tournament_id, "action": action })


## Elo-merket foran en etikett.
func _with_badge(elo: int, label: Control) -> Control:
	var row := UI.hbox(8)
	row.add_child(EloBadge.make(elo, 20))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## Etikett som ikke oversettes (navn og ferdig utfylt tekst).
func _plain(text: String, variation: String) -> Label:
	var l := UI.label(text, variation)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


static func _points(points2: int) -> String:
	return str(points2 / 2) + ("½" if points2 % 2 == 1 else "")


static func format_name(f: String) -> String:
	return "Alle mot alle" if f == "round_robin" else "Utslag"


static func status_name(s: String) -> String:
	match s:
		"draft": return "Utkast"
		"open": return "Åpen for påmelding"
		"running": return "Pågår"
		"finished": return "Ferdig"
		"cancelled": return "Avlyst"
	return s


static func status_order(s: String) -> int:
	return ["running", "open", "draft", "finished", "cancelled"].find(s)


func _on_back() -> void:
	if back_to_menu:
		app.show_menu()
	else:
		app.show_tournaments()
