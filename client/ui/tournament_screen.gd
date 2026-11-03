class_name TournamentScreen
extends Screen
## Én turnering. Det som skjer nå står øverst (runde 18): nedtellingen eller innsjekken, påmeldingen,
## din kamp, og treet eller tabellen. Så turneringschatten, og under den kampene, deltakerne, reglene
## (bak knappen «Regler») og arrangørens knapper. Serveren sender endringer med en gang mens siden er oppe.
## Innsjekken: de siste 2 minuttene før start er du med så lenge denne siden er oppe (se Tournaments).

var tournament_id := 0
var _t: Dictionary = {}
var _admin := false
var _you := 0
var _top: VBoxContainer       ## det som skjer nå (bygges på nytt ved hver endring)
var _content: VBoxContainer   ## resten under chatten (bygges også på nytt)
var _status: Label
var back_to_menu := false   ## åpnet fra menyen: «Tilbake» går dit
var _deleted := false       ## admin trykket «Slett»: når listen kommer, gå til turneringslisten
var _clock_offset := 0      ## serverens klokke minus vår (sekunder), så nedtellingene stemmer
var _ticking: Array = []    ## [etikett, funksjon som gir teksten] som oppdateres hvert sekund
var _chat: GlobalChat
var _chat_title: Control
var _wanted_game := 0       ## partiet som er bedt om (reprise av en kamp, f.eks. finalen)
var code := ""              ## åpnet med koden (lenken ?t=KODE): hentes med den, så private turneringer også vises
var _nickname: LineEdit     ## kallenavnet til en gjest som vil bli med i en privat turnering
var _rules_open := false    ## «Regler» er åpnet (huskes når siden bygges på nytt)


func _init(p_app: ClientRoot, id: int, p_back_to_menu := false, p_code := "") -> void:
	super(p_app)
	tournament_id = id
	back_to_menu = p_back_to_menu
	code = p_code.strip_edges().to_upper()


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 680)   # bredt nok til treet med pokalen i midten (8 spillere) på PC
	_top = UI.vbox(10)
	v.add_child(_top)
	_top.add_child(UI.label("Henter…", "Muted"))
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_status)
	# Turneringschatten ligger utenfor innholdet, så den ikke tømmes når siden bygges på nytt
	_chat_title = UI.section("Turneringschat")
	v.add_child(_chat_title)
	_chat = GlobalChat.new()
	_chat.tournament_only = true
	_chat.custom_minimum_size.y = 230
	_chat.profile_requested.connect(func(name: String) -> void: app.show_profile(name, back_to_menu))
	v.add_child(_chat)
	if tournament_id != 0:
		_chat.set_tournament(tournament_id, "")
	_content = UI.vbox(10)
	v.add_child(_content)
	UI.card_footer(v).add_child(UI.button("Tilbake", _on_back))
	Net.ensure_connected()
	Net.message.connect(_on_message)
	Net.connected.connect(_on_connected)
	var second := Timer.new()
	second.wait_time = 1.0
	second.autostart = true
	second.timeout.connect(_tick)
	add_child(second)
	# Serveren sender endringer med en gang (view_tournament). Timeren er bare en reserve.
	var timer := Timer.new()
	timer.wait_time = 15.0
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)
	_refresh()


## get_tournament (ikke view_tournament): den nye serveren følger siden og sender endringer med en
## gang, og en eldre server som ikke kjenner view_tournament, svarer likevel.
func _on_connected(_resumed: bool) -> void:
	_refresh()


## Nå i serverens tid (unix-sekunder).
func now_s() -> int:
	return int(Time.get_unix_time_from_system()) + _clock_offset


func _tick() -> void:
	for pair in _ticking:
		if is_instance_valid(pair[0]):
			(pair[0] as Label).text = (pair[1] as Callable).call()


## «12:34» eller «1 t 05 min» til et tidspunkt.
static func countdown_text(seconds: int) -> String:
	seconds = maxi(0, seconds)
	if seconds >= 3600:
		return I18n.t("%d t %02d min") % [seconds / 3600, (seconds % 3600) / 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _refresh() -> void:
	if code != "":
		Net.send({ "t": Protocol.TOURNAMENT_CODE, "code": code })
	else:
		Net.send({ "t": Protocol.GET_TOURNAMENT, "id": tournament_id })


## Siden er lukket: ikke send flere endringer. Viser neste skjerm også en turnering (f.eks. storskjermen),
## har den allerede bedt om sin, og da skal ikke denne beskjeden komme etter og stoppe det.
func _exit_tree() -> void:
	if not (app._screen is TournamentScreen or app._screen is TournamentDisplay):
		Net.send({ "t": Protocol.VIEW_TOURNAMENT, "id": 0 })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
			if tournament_id == 0 and code != "":   # svaret på koden: nå vet vi hvilken turnering det er
				tournament_id = int(msg.tournament.id)
				_chat.set_tournament(tournament_id, "")
			if int(msg.tournament.id) == tournament_id:
				if msg.has("now"):
					_clock_offset = int(msg.now) - int(Time.get_unix_time_from_system())
				if msg.tournament == _t and bool(msg.get("admin", false)) == _admin and int(msg.get("you", 0)) == _you:
					return   # ingenting nytt (siden hentes hvert 3. sekund): ikke bygg på nytt
				_t = msg.tournament
				_admin = bool(msg.get("admin", false))
				_you = int(msg.get("you", 0))
				_rebuild()
		Protocol.TOURNAMENT_LIST:
			# Serveren svarer med listen når admin har slettet turneringen. Andre lister (f.eks. den
			# hovedmenyen ba om rett før) skal ikke kaste deg ut av siden.
			if _deleted:
				app.show_tournaments()
		Protocol.GAME_RECORD:
			if _wanted_game != 0 and int(msg.game.get("id", 0)) == _wanted_game:
				_wanted_game = 0
				app.show_replay(msg.game, app.show_tournament.bind(tournament_id, back_to_menu))
		Protocol.ERROR:
			_wanted_game = 0
			_status.text = I18n.server_text(msg)


## Reprise av et parti i turneringen (finalen eller en annen kamp).
func open_game(id: int) -> void:
	if id <= 0:
		return
	_wanted_game = id
	_status.text = tr("Henter partiet…")
	Net.send({ "t": Protocol.GET_GAME, "id": id })


func _rebuild() -> void:
	for box in [_top, _content]:
		for c in box.get_children():
			c.queue_free()
	_ticking.clear()
	var t := _t
	_chat.visible = bool(t.get("chat", true)) or _admin   # arrangøren kan slå av chatten for deltakerne
	_chat_title.visible = _chat.visible
	_build_head(t)
	match str(t.status):
		"draft", "open": _build_open(t)
		"running": _build_running(t)
		"finished": _build_finished(t)
		_: _top.add_child(UI.label("Turneringen ble avlyst.", "Muted"))
	if _admin and t.status in ["draft", "open", "running"]:
		_top.add_child(_organizer_row(t))
	_build_matches(t)
	_build_players(t)
	_build_rules_and_links(t)
	if _admin:
		_build_admin(t)


## Navnet, en kort linje med format, status og deltakere, og beskrivelsen.
func _build_head(t: Dictionary) -> void:
	var title_row := UI.hbox(10)
	var title := _plain(str(t.name), "Heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(title)
	var tag_text := "Privat" if bool(t.get("private", false)) else ("Uranket" if not bool(t.get("ranked", true)) else "")
	if tag_text != "":
		var tag := UI.label(tag_text, "Muted")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tag)
	_top.add_child(title_row)
	var info := [tr(format_name(str(t.format))), tr(status_name(str(t.status))),
		tr("Deltakere: %d av %d") % [int(t.players), int(t.max_players)]]
	if t.status in ["draft", "open"]:
		info.append(tr("Starter når arrangøren trykker «Start nå».") if bool(t.get("private", false))
			else tr("Start: %s") % UI.format_time(int(t.start_time)))
	var line := _plain(" · ".join(info), "Muted")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_top.add_child(line)
	if str(t.description) != "":
		var d := _plain(str(t.description), "")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_top.add_child(d)


## Før start: nedtellingen (eller innsjekken), påmeldingen og pokalen det spilles om.
func _build_open(t: Dictionary) -> void:
	var private := bool(t.get("private", false))
	if bool(t.get("checkin", false)):
		_top.add_child(_checkin_box(t))
	elif int(t.start_time) > now_s() and not private:
		var under := UI.format_time(int(t.start_time))
		if bool(t.get("ranked", true)):
			under += "  ·  " + tr("Møt opp og få %d XP") % Progression.SHOW_UP_XP
		_top.add_child(_countdown_box(int(t.start_time), "Starter om", under))
	if t.status == "open":
		if not Net.is_logged_in() and private and code != "":
			_top.add_child(_join_with_nickname())
		elif not Net.is_logged_in():
			_top.add_child(UI.button("Logg inn for å melde deg på", func() -> void: app.show_account()))
		elif _joined():
			_top.add_child(UI.button("Meld meg av", func() -> void: _send(Protocol.TOURNAMENT_LEAVE)))
		else:
			_top.add_child(UI.button("Meld meg på", func() -> void: _send(Protocol.TOURNAMENT_JOIN), "PrimaryButton"))
	var prize := _trophy_block(t)
	if prize != null:
		_top.add_child(prize)


## Stor nedtelling i en boks. under = en linje under tallet ("" = klokkeslettet).
func _countdown_box(at: int, heading: String, under: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI._box(Color("1d2a42"), 12, UI.ACCENT_HOVER, 14, 10))
	var col := UI.vbox(0)
	col.add_child(UI.label(heading, "Muted", HORIZONTAL_ALIGNMENT_CENTER))
	var big := _plain("", "Title")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text := func() -> String: return countdown_text(at - now_s())
	big.text = text.call()
	_ticking.append([big, text])
	col.add_child(big)
	var sub := _plain(under if under != "" else UI.format_time(at), "Muted")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	box.add_child(col)
	return box


## Innsjekken (de siste 2 minuttene): nedtellingen, om du er med, og hvem som er her.
func _checkin_box(t: Dictionary) -> Control:
	var box := _countdown_box(int(t.start_time), "Starter om",
		tr("Ha denne siden oppe til start. De som ikke er her, er ikke med."))
	var col: VBoxContainer = box.get_child(0)
	var players: Array = t.player_list
	var here := players.filter(func(p: Dictionary) -> bool: return bool(p.get("here", false)))
	var me := players.filter(func(p: Dictionary) -> bool: return int(p.id) == _you)
	var mine := ""
	if not me.is_empty():
		mine = tr("Du er med! Kampen din starter av seg selv.") if bool(me[0].get("here", false)) else tr("Sjekker deg inn…")
	if mine != "":
		var you := _plain(mine, "")
		you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		you.add_theme_color_override("font_color", BracketView.YOU)
		col.add_child(you)
	var waiting := players.filter(func(p: Dictionary) -> bool: return not bool(p.get("here", false))) \
		.map(func(p: Dictionary) -> String: return str(p.username))
	var count := tr("Her nå: %d av %d") % [here.size(), players.size()]
	if not waiting.is_empty():
		count += "  ·  " + tr("Venter på: %s") % ", ".join(waiting)
	var who := _plain(count, "Muted")
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(who)
	return box


## Underveis: din status og kamp, så treet (utslag) eller tabellen (alle mot alle).
func _build_running(t: Dictionary) -> void:
	var status := my_status()
	if status != "":
		var s := _plain(status, "")
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_color_override("font_color", BracketView.YOU)
		_top.add_child(s)
	var mine_next := _my_scheduled_match()
	if not mine_next.is_empty():
		var at := int(mine_next.start_at)
		var next_text := func() -> String: return tr("Din kamp starter om %s.") % countdown_text(at - now_s())
		var next := _plain(next_text.call(), "Muted")
		_ticking.append([next, next_text])
		_top.add_child(next)
		# Klar? Trykker begge, starter kampen med en gang i stedet for å vente ut pausen
		var me_first := int(mine_next.p1) == _you
		var ready: Array = mine_next.get("ready", [false, false])
		var i_am_ready := bool(ready[0 if me_first else 1])
		var other_ready := bool(ready[1 if me_first else 0])
		if i_am_ready:
			var wait := UI.button("Venter på at motstanderen trykker «Klar»…", func() -> void: pass)
			wait.disabled = true
			_top.add_child(wait)
		else:
			_top.add_child(UI.button("Motstanderen er klar – start nå!" if other_ready else "Klar – start uten å vente",
				func() -> void: _send(Protocol.TOURNAMENT_READY), "PrimaryButton"))
	# Din kamp (du kastes inn når den starter, men knappen er her hvis du gikk ut)
	var mine := _my_waiting_match()
	if not mine.is_empty():
		_top.add_child(UI.button("Gå til kamp!", func() -> void: app.join_room(str(mine.room)), "PrimaryButton"))
	_add_bracket_or_table(t)


func _build_finished(t: Dictionary) -> void:
	var prize := _trophy_block(t)
	if prize != null:
		_top.add_child(prize)
	_add_bracket_or_table(t)


## Turneringstreet (utslag) eller tabellen (alle mot alle).
func _add_bracket_or_table(t: Dictionary) -> void:
	if t.format == "knockout" and not (t.rounds as Array).is_empty():
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var bracket := BracketView.new(t.rounds, _you, t.get("trophy", {}) if bool(t.get("with_trophy", true)) else {})
		bracket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bracket.watch_requested.connect(func(room: String) -> void: Net.send({ "t": Protocol.WATCH, "code": room }))
		bracket.replay_requested.connect(open_game)
		scroll.add_child(bracket)
		_top.add_child(scroll)
	elif t.has("standings"):
		_top.add_child(UI.section("Tabell"))
		var place := 1
		for row in t.standings:
			_top.add_child(_with_badge(int(row.get("elo", -1)), _plain(tr("%d. %s – %s poeng (%d–%d–%d)") % [place,
				row.username, _points(int(row.points2)), int(row.wins), int(row.draws), int(row.losses)], "")))
			place += 1


## Arrangøren: det som trengs nå. Før start «Start nå» (under innsjekken: start med dem som er her),
## og hele tiden lenken og storskjermen.
func _organizer_row(t: Dictionary) -> Control:
	var box := UI.vbox(6)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	if t.status == "draft":
		row.add_child(UI.button("Publiser", func() -> void: _admin_action("publish"), "PrimaryButton"))
	if t.status in ["draft", "open"]:
		row.add_child(UI.button("Start med dem som er her" if bool(t.get("checkin", false)) else "Start nå",
			func() -> void: _admin_action("start"), "PrimaryButton"))
	var tcode := str(t.get("code", ""))
	if tcode != "":
		row.add_child(UI.button("Vis på storskjerm", func() -> void: app.show_tournament_display(tcode)))
		row.add_child(UI.button("Kopier lenke", func() -> void: _status.text = app.share_link("t", tcode, str(t.name))))
	box.add_child(row)
	if tcode != "":
		var link := _plain(tr("Kode: %s  ·  %s") % [tcode, app.link_for("t", tcode).get_slice("://", 1)], "Muted")
		link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(link)
	return box


## Kampene: runden som pågår først, så de før. I utslag viser treet resten, så bare runden som pågår.
func _build_matches(t: Dictionary) -> void:
	var rounds: Array = t.rounds
	var knockout: bool = t.format == "knockout"
	if rounds.is_empty() or (knockout and t.status == "finished"):
		return
	var regular := int(t.get("regular_rounds", 0))
	var last := rounds.size() - 1 if t.status == "finished" else int(t.current_round)
	var first := last if knockout else 0
	for r in range(last, first - 1, -1):
		var round_list: Array = rounds[r]
		if not round_list.is_empty() and bool(round_list[0].get("playoff", false)):
			_content.add_child(UI.section("Omkamp om seieren"))
		elif str(t.get("pairing", "")) == "swiss":
			_content.add_child(UI.section(tr("Runde %d av %d") % [r + 1, regular]))
		else:
			_content.add_child(UI.section(tr("Runde %d") % (r + 1)))
		for m in round_list:
			_content.add_child(_match_row(m))


func _match_row(m: Dictionary) -> Control:
	var label := _plain(_match_text(m), "Muted" if m.status == "done" else "")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if m.status == "waiting" and m.has("walkover_at"):
		var text := func() -> String: return _match_text(m)
		_ticking.append([label, text])
	var own_match := _you != 0 and _you in [int(m.p1), int(m.p2)]
	var games: Array = m.get("games", [])
	var button: Button = null
	if m.status == "playing" and str(m.room) != "" and not own_match:
		var room := str(m.room)
		button = UI.button("Se på", func() -> void: Net.send({ "t": Protocol.WATCH, "code": room }))
	elif m.status == "done" and not games.is_empty():
		var game_id := int(games[-1])
		button = UI.button("Reprise", func() -> void: open_game(game_id))
	if button == null:
		return label
	var row := UI.hbox(8)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(button)
	return row


## Deltakerne som små merker (under innsjekken er de som ikke har kommet, dempet). Arrangøren av en privat
## turnering får en rad per deltaker med «Endre» (gjestens kallenavn) og «Fjern».
func _build_players(t: Dictionary) -> void:
	var players: Array = t.player_list
	_content.add_child(UI.section(tr("Deltakere (%d)") % players.size()))
	if players.is_empty():
		_content.add_child(UI.label("Ingen påmeldte ennå.", "Muted"))
	var rows: bool = _admin and bool(t.get("private", false)) and t.status == "open"
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	var checkin := bool(t.get("checkin", false))
	for p in players:
		var chip := UI.hbox(6)
		chip.add_child(EloBadge.make(int(p.elo), 20))
		var name := _plain(str(p.username), "")
		if int(p.id) == _you:
			name.add_theme_color_override("font_color", BracketView.YOU)
		chip.add_child(name)
		if checkin and not bool(p.get("here", false)):
			chip.modulate.a = 0.45   # ikke kommet til innsjekken ennå
		if rows:
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_participant_buttons(chip, p)
			_content.add_child(chip)
		else:
			flow.add_child(chip)
	if not rows and not players.is_empty():
		_content.add_child(flow)
	if t.has("missed"):
		var missed := _plain(tr("Møtte ikke til start: %s") % ", ".join(t.missed), "Muted")
		missed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(missed)


## «Regler» (åpner reglene her), og før start kalender og deling (ikke private turneringer).
func _build_rules_and_links(t: Dictionary) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var rules_box := UI.vbox(6)
	rules_box.visible = _rules_open
	var toggle := UI.button("Skjul reglene" if _rules_open else "Regler", func() -> void: pass)
	toggle.pressed.connect(func() -> void:
		_rules_open = not _rules_open
		rules_box.visible = _rules_open
		toggle.text = "Skjul reglene" if _rules_open else "Regler")   # knappen oversettes selv
	row.add_child(toggle)
	if t.status in ["draft", "open"] and not bool(t.get("private", false)):
		row.add_child(UI.button("Legg i kalender", _add_to_calendar))
		row.add_child(UI.button("Del lenke til turneringen", func() -> void:
			_status.text = app.share_link("turnering", str(tournament_id), str(t.name))
		))
	_content.add_child(row)
	for line in rules(t):
		var l := _plain("•  " + line, "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_box.add_child(l)
	_content.add_child(rules_box)


## Arrangøren (og admin): resten av knappene, nederst.
func _build_admin(t: Dictionary) -> void:
	_content.add_child(UI.section("Arrangør"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	if t.status != "cancelled":
		row.add_child(UI.button("Endre", func() -> void: app.show_tournament_edit(_t)))
	if t.status in ["draft", "open"] and bool(t.get("with_trophy", true)):
		# Bytt pokalen vinneren får (trykk til du liker den; siden oppdateres med en gang)
		row.add_child(UI.button("Ny pokal", func() -> void:
			Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id,
				"data": { "trophy": Trophy.generate(randi()) } })
		))
	var tcode := str(t.get("code", ""))
	if tcode != "" and t.status in ["draft", "open", "running"]:
		row.add_child(UI.button("Lenke til storskjermen", func() -> void:
			_status.text = app.share_link("vis", tcode, str(t.name))))
	if t.status in ["draft", "open", "running"]:
		row.add_child(UI.button("Avlys", func() -> void: _admin_action("cancel")))
	row.add_child(UI.button("Slett", func() -> void: _admin_action("delete")))
	_content.add_child(row)
	_content.add_child(UI.toggle_row("Chat for deltakerne", "Av: bare du kan skrive i turneringschatten.",
		bool(t.get("chat", true)), func(on: bool) -> void:
			Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id, "data": { "chat": on } })))
	# Alle mot alle: antall runder kan endres helt til turneringen starter
	if t.format == "round_robin" and t.status in ["draft", "open"]:
		_content.add_child(UI.label("Antall runder", "Muted"))
		var limits: Array = TournamentEditScreen.ROUND_LIMITS
		var current := maxi(0, limits.find(int(t.get("max_rounds", 0))))
		_content.add_child(UI.choice(limits.map(func(n: int) -> String: return tr("Alle") if n == 0 else str(n)), current,
			func(i: int) -> void:
				Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id, "data": { "max_rounds": limits[i] } })
		))


func _joined() -> bool:
	return _you in (_t.get("player_list", []) as Array).map(func(p: Dictionary) -> int: return int(p.id))


## Bli med i en privat turnering uten konto: bare et kallenavn (serveren lager en gjestekonto).
func _join_with_nickname() -> Control:
	var box := UI.vbox(6)
	var row := UI.hbox(8)
	if _nickname == null or not is_instance_valid(_nickname):
		_nickname = UI.line_edit("", "Kallenavn", Accounts.GUEST_NAME_MAX)
		_nickname.text_submitted.connect(func(_t: String) -> void: _join_as_guest())
	elif _nickname.get_parent():
		_nickname.get_parent().remove_child(_nickname)   # beholder det som er skrevet når siden bygges på nytt
	_nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_nickname)
	row.add_child(UI.button("Bli med", _join_as_guest, "PrimaryButton"))
	box.add_child(row)
	box.add_child(UI.label("Ingen konto trengs. Vi lagrer bare kallenavnet, og sletter det etter 14 dager uten bruk.",
		"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UI.button("Har du konto? Logg inn", func() -> void: app.show_account(), "GhostButton"))
	return box


func _join_as_guest() -> void:
	_status.text = tr("Melder deg på…")
	Net.send({ "t": Protocol.TOURNAMENT_CODE, "code": code, "join": true, "name": _nickname.text.strip_edges() })


## Arrangøren: rett kallenavnet til en gjest, eller fjern en deltaker (før start).
func _participant_buttons(row: Control, p: Dictionary) -> void:
	var uid := int(p.id)
	if bool(p.get("guest", false)):
		var edit := UI.line_edit(str(p.username), "", Accounts.GUEST_NAME_MAX)
		edit.visible = false
		edit.custom_minimum_size.x = 140
		edit.text_submitted.connect(func(name: String) -> void:
			Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": tournament_id, "action": "rename", "user": uid, "name": name }))
		row.add_child(edit)
		row.add_child(UI.button("Endre", func() -> void:
			edit.visible = not edit.visible
			if edit.visible:
				edit.grab_focus()
		, "GhostButton"))
	row.add_child(UI.button("Fjern", func() -> void:
		Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": tournament_id, "action": "kick", "user": uid })
	, "GhostButton"))


## Reglene i korte linjer (vises under «Regler»): format, uavgjort, spill og tid, varighet, innsjekk og
## møtefrist, Elo, pokal, premie og XP.
static func rules(t: Dictionary) -> Array:
	var o := GameOptions.from_dict(t.get("options", {}))
	var out := []
	var limit := int(t.get("max_rounds", 0))
	var players := maxi(int(t.get("players", 0)), 2)
	var round_robin: bool = t.get("format") == "round_robin"
	if bool(t.get("private", false)):
		out.append(I18n.t("Privat: bare de med koden eller lenken ser den. Ingen konto trengs."))
	if round_robin and limit > 0 and limit < round_count("round_robin", players, 0):
		out.append(I18n.t("Sveitsisk, %d runder: du møter en med like mange poeng, aldri den samme to ganger.") % limit)
	elif round_robin:
		out.append(I18n.t("Alle mot alle: alle møter alle én gang."))
	else:
		out.append(I18n.t("Utslag: taperen er ute. Uavgjort spilles om; blir tredje parti uavgjort, går den som ikke startet, videre."))
	if round_robin:
		out.append(I18n.t("Seier 1 poeng, uavgjort ½, fri runde 1. Likt: innbyrdes, Buchholz, Sonneborn-Berger, seire, så omkamp."))
		out.append(I18n.t("Møter ikke motstanderen din, spiller du mot en annen uten motstander, om det finnes."))
	out.append(I18n.t("Spill: %s") % o.describe())
	if o.has_clock():
		out.append(I18n.t("Tid: %d min + %d s per trekk.") % [o.time_base_s / 60, o.time_increment_s])
	var n := round_count(str(t.get("format", "")), players, limit)
	out.append(I18n.t("Varighet: ca. %s (%d runder).") % [
		duration_text(estimate_minutes(n, o, int(t.get("round_gap_s", 120)))), n])
	out.append(I18n.t("Innsjekk: ha turneringssiden oppe de siste 2 minuttene før start, ellers er du ikke med."))
	out.append(I18n.t("Du kastes inn når kampen din starter. Møt opp innen %d min, ellers taper du på walkover.") \
		% (int(t.get("show_up_s", 300)) / 60))
	out.append(I18n.t("Rangert: partiene teller på Elo.") if bool(t.get("ranked", true)) \
		else I18n.t("Uranket: partiene endrer ikke Elo."))
	if bool(t.get("with_trophy", true)):
		out.append(I18n.t("Vinneren får pokalen på profilen sin."))
	var prize := str(t.get("prize", ""))
	if prize != "":
		out.append(I18n.t("Premie: vinneren låser opp «%s» (ellers %s).") % [Progression.item_name(prize),
			Progression.requirement_text(prize).to_lower()])
	if bool(t.get("ranked", true)):
		out.append(I18n.t("XP: %d for å møte opp. Etter plassering: vinneren 150, finalisten 75, semifinalistene 40, andre som spilte 20.") \
			% Progression.SHOW_UP_XP)
	else:
		out.append(I18n.t("XP: %d for å møte opp (med konto, én urangert turnering per dag).") % Progression.SHOW_UP_XP)
	return out


## Antall runder: utslag log2(spillere), alle mot alle spillere − 1 (eller spillere ved oddetall),
## men høyst max_rounds når admin har begrenset det.
static func round_count(format: String, players: int, max_rounds: int) -> int:
	players = maxi(players, 2)
	if format == "round_robin":
		var all := players - 1 if players % 2 == 0 else players
		return mini(all, max_rounds) if max_rounds > 0 else all
	var n := 0
	while (1 << n) < players:
		n += 1
	return n


## Omtrent hvor lang tid turneringen tar: en runde er ferdig når det tregeste partiet er ferdig. Med
## klokke regnes 70 % av all tiden begge har (rundt 50 trekk), uten klokke 5 min, pluss pausen.
static func estimate_minutes(rounds: int, o: GameOptions, gap_s: int) -> int:
	var game_s := int((o.time_base_s * 2 + o.time_increment_s * 50) * 0.7) if o.has_clock() else 300
	return int(ceil(rounds * (game_s + 3 + gap_s) / 60.0))


## «45 min» eller «1 t 50 min».
static func duration_text(minutes: int) -> String:
	if minutes < 60:
		return I18n.t("%d min") % minutes
	return I18n.t("%d t %02d min") % [minutes / 60, minutes % 60]


## «Legg i kalender»: på nett åpnes en kalenderfil fra serveren (telefonen spør om du vil legge
## den inn). På PC åpnes Google Kalender med turneringen fylt ut.
func _add_to_calendar() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(new URL('kalender/%d.ics', location.href).href, '_blank')" % tournament_id)
		return
	var start := int(_t.start_time)
	var stamp := func(unix: int) -> String:
		return Time.get_datetime_string_from_unix_time(unix).replace("-", "").replace(":", "") + "Z"
	var url := "https://calendar.google.com/calendar/render?action=TEMPLATE&text=%s&dates=%s/%s&details=%s" % [
		("Turnering: " + str(_t.name)).uri_encode(), stamp.call(start), stamp.call(start + 3600),
		str(_t.get("description", "")).uri_encode()]
	OS.shell_open(url)


## Ferdig med vinner: en hedersplass med pokalen (som gløder), «Vinner» og navnet i gull.
## Før start: pokalen det spilles om. Uten pokal: bare vinneren (eller null før den er ferdig).
func _trophy_block(t: Dictionary) -> Control:
	var winner := str(t.get("winner", ""))
	var with_trophy := bool(t.get("with_trophy", true))
	if t.status == "finished" and winner != "":
		var hero := PanelContainer.new()
		hero.add_theme_stylebox_override("panel", UI._box(Color("2a2617"), 14, Color("b8913a"), 16, 12, 4))
		var row := UI.hbox(16)
		if with_trophy:
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
		var sub := _plain((tr("Vant pokalen «%s»") if with_trophy else tr("Vant «%s»")) % t.name, "Muted")
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(sub)
		if int(t.get("finished_at", 0)) > 0:
			texts.add_child(_plain(UI.format_time(int(t.finished_at)), "Muted"))
		var final_id := int(t.get("final_game", 0))
		if final_id > 0:
			var watch := UI.button("Se finalen", func() -> void: open_game(final_id), "PrimaryButton")
			watch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			texts.add_child(watch)
		row.add_child(texts)
		hero.add_child(row)
		return hero
	if not with_trophy or t.status == "finished":
		return null
	var row := UI.hbox(14)
	row.add_child(TrophyView.new(t.get("trophy", {}), 84))
	var l := UI.label("Det spilles om denne pokalen. Vinneren får den med turneringens navn på profilen sin.", "Muted",
		HORIZONTAL_ALIGNMENT_LEFT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _match_text(m: Dictionary) -> String:
	return match_line(m, now_s())


## Én kamp i klartekst («Ada – Bo · spilles nå»). Brukes også av storskjermen.
static func match_line(m: Dictionary, now: int) -> String:
	var names := "%s – %s" % [m.p1_name, m.p2_name]
	match str(m.status):
		"done":
			var winner := str(m.p1_name) if int(m.winner) == int(m.p1) else str(m.p2_name)
			match str(m.reason):
				"bye": return I18n.t("%s: fri runde") % winner
				"walkover": return I18n.t("%s · %s vant på walkover") % [names, winner]
				"no_show": return I18n.t("%s · ingen møtte") % names
				"forfeit": return I18n.t("%s · %s møtte ikke") % [names, str(m.get("absent_name", ""))]
				"draw": return I18n.t("%s · uavgjort") % names
				"draws": return I18n.t("%s · %s gikk videre etter tre uavgjorte") % [names, winner]
			return I18n.t("%s · %s vant") % [names, winner] if int(m.winner) != 0 else names
		"waiting":
			if int(m.get("lonely", 0)) != 0:
				return I18n.t("%s · motstanderen møtte ikke, ser etter en annen uten motstander") % names
			if not m.has("here"):
				return I18n.t("%s · venter på spillerne") % names
			var missing := []
			if not bool(m.here[0]):
				missing.append(str(m.p1_name))
			if not bool(m.here[1]):
				missing.append(str(m.p2_name))
			var left := countdown_text(int(m.walkover_at) - now)
			if missing.is_empty():
				return I18n.t("%s · starter nå") % names
			return I18n.t("%s · venter på %s (walkover om %s)") % [names, ", ".join(missing), left]
		"playing": return I18n.t("%s · spilles nå") % names
		"scheduled": return I18n.t("%s · starter %s") % [names, UI.format_time(int(m.start_at))]
	return names


## Statuslinjen for en deltaker i en pågående turnering. Tom for andre.
func my_status() -> String:
	if _you == 0 or _t.is_empty() or _t.status != "running" or (_t.rounds as Array).is_empty():
		return ""
	# Kampen som pågår eller kommer, går foran en som er ferdig (etter walkover kan du få en ny kamp i runden)
	var mine: Array = (_t.rounds[int(_t.current_round)] as Array).filter(func(m: Dictionary) -> bool:
		return _you in [int(m.p1), int(m.p2)])
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.status != "done" and b.status == "done")
	for m in mine:
		var names := "%s – %s" % [m.p1_name, m.p2_name]
		match str(m.status):
			"scheduled": return tr("Din kamp: %s · starter %s") % [names, UI.format_time(int(m.start_at))]
			"waiting":
				if int(m.get("lonely", 0)) == _you:
					return tr("Motstanderen din møtte ikke. Står en annen også uten motstander, spiller dere mot hverandre; ellers vinner du på walkover.")
				var other_here: bool = m.has("here") and bool(m.here[1 if int(m.p1) == _you else 0])
				if m.has("here") and not other_here:
					return tr("Din kamp: %s · motstanderen har ikke kommet. Kommer hen ikke, vinner du på walkover.") % names
				return tr("Din kamp: %s · nå! Trykk «Gå til kamp».") % names
			"playing": return tr("Din kamp: %s · spilles nå") % names
			"done":
				if int(m.winner) == _you:
					match str(m.reason):
						"bye": return tr("Du har fri denne runden (ingen motstander) og går videre.")
						"walkover": return tr("Motstanderen møtte ikke. Du vant på walkover og går videre.")
					return tr("Du vant kampen! Neste runde starter når de andre kampene er ferdige.")
	if _t.format == "knockout" and _joined():
		return tr("Du er ute av turneringen. Takk for innsatsen!")
	return ""


## Din neste kamp som ikke har startet ennå (for nedtellingen), eller {}.
func _my_scheduled_match() -> Dictionary:
	if _you == 0 or _t.is_empty() or _t.status != "running":
		return {}
	for m in _t.rounds[int(_t.current_round)]:
		if m.status == "scheduled" and _you in [int(m.p1), int(m.p2)] and int(m.start_at) > now_s():
			return m
	return {}


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
	_deleted = action == "delete"
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
