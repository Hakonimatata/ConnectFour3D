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
var _deleted := false       ## admin trykket «Slett»: når listen kommer, gå til turneringslisten
var _clock_offset := 0      ## serverens klokke minus vår (sekunder), så nedtellingene stemmer
var _ticking: Array = []    ## [etikett, funksjon som gir teksten] som oppdateres hvert sekund
var _chat: GlobalChat
var _wanted_game := 0       ## partiet som er bedt om (reprise av en kamp, f.eks. finalen)


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
	# Turneringschatten ligger utenfor innholdet, så den ikke tømmes når siden bygges på nytt
	v.add_child(UI.section("Turneringschat"))
	_chat = GlobalChat.new()
	_chat.tournament_only = true
	_chat.custom_minimum_size.y = 230
	_chat.profile_requested.connect(func(name: String) -> void: app.show_profile(name, back_to_menu))
	v.add_child(_chat)
	_chat.set_tournament(tournament_id, "")
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
	Net.send({ "t": Protocol.GET_TOURNAMENT, "id": tournament_id })


func _exit_tree() -> void:
	Net.send({ "t": Protocol.VIEW_TOURNAMENT, "id": 0 })   # siden er lukket: ikke send flere endringer


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
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
	for c in _content.get_children():
		c.queue_free()
	_ticking.clear()
	var t := _t
	var title_row := UI.hbox(10)
	var title := _plain(str(t.name), "Heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(title)
	if not bool(t.get("ranked", true)):
		var tag := UI.label("Uranket", "Muted")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tag)
	_content.add_child(title_row)
	if str(t.description) != "":
		var d := _plain(str(t.description), "Muted")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(d)

	# --- Turneringstreet (utslag) øverst, så man ser hvor turneringen står med en gang
	var knockout: bool = t.format == "knockout" and not (t.rounds as Array).is_empty()
	if knockout:
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var bracket := BracketView.new(t.rounds, _you, t.get("trophy", {}) if bool(t.get("with_trophy", true)) else {})
		bracket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bracket.watch_requested.connect(func(code: String) -> void: Net.send({ "t": Protocol.WATCH, "code": code }))
		bracket.replay_requested.connect(open_game)
		scroll.add_child(bracket)
		_content.add_child(scroll)
	# Pokalen står midt i treet; egen blokk bare uten tre, eller med vinneren når den er ferdig
	var prize := _trophy_block(t) if not knockout or t.status == "finished" else null
	if prize != null:
		_content.add_child(prize)

	# --- Nedtelling til start
	if t.status in ["draft", "open"] and int(t.start_time) > now_s():
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UI._box(Color("1d2a42"), 12, UI.ACCENT_HOVER, 14, 10))
		var col := UI.vbox(0)
		col.add_child(UI.label("Starter om", "Muted", HORIZONTAL_ALIGNMENT_CENTER))
		var big := _plain("", "Title")
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var start := int(t.start_time)
		var text := func() -> String: return countdown_text(start - now_s())
		big.text = text.call()
		_ticking.append([big, text])
		col.add_child(big)
		var when := _plain(UI.format_time(start), "Muted")
		when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(when)
		box.add_child(col)
		_content.add_child(box)

	# --- Din status som deltaker: neste kamp, at den spilles, eller at du er ute
	var status := my_status()
	if status != "":
		var s := _plain(status, "")
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_color_override("font_color", BracketView.YOU)
		_content.add_child(s)
	var mine_next := _my_scheduled_match()
	if not mine_next.is_empty():
		var at := int(mine_next.start_at)
		var next_text := func() -> String: return tr("Din kamp starter om %s.") % countdown_text(at - now_s())
		var next := _plain(next_text.call(), "Muted")
		_ticking.append([next, next_text])
		_content.add_child(next)
		# Klar? Trykker begge, starter kampen med en gang i stedet for å vente ut pausen
		var me_first := int(mine_next.p1) == _you
		var ready: Array = mine_next.get("ready", [false, false])
		var i_am_ready := bool(ready[0 if me_first else 1])
		var other_ready := bool(ready[1 if me_first else 0])
		if i_am_ready:
			var wait := UI.button("Venter på at motstanderen trykker «Klar»…", func() -> void: pass)
			wait.disabled = true
			_content.add_child(wait)
		else:
			_content.add_child(UI.button("Motstanderen er klar – start nå!" if other_ready else "Klar – start uten å vente",
				func() -> void: _send(Protocol.TOURNAMENT_READY), "PrimaryButton"))

	# --- Din neste kamp (du kastes inn når den starter, men knappen er her hvis du gikk ut)
	var mine := _my_waiting_match()
	if not mine.is_empty():
		var go := UI.button("Gå til kamp!", func() -> void: app.join_room(str(mine.room)), "PrimaryButton")
		_content.add_child(go)

	# --- Påmelding, kalender og deling (bare før start)
	var joined := _you in (t.player_list as Array).map(func(p: Dictionary) -> int: return int(p.id))
	if t.status == "open":
		if not Net.is_logged_in():
			_content.add_child(UI.button("Logg inn for å melde deg på", func() -> void: app.show_account()))
		elif joined:
			_content.add_child(UI.button("Meld meg av", func() -> void: _send(Protocol.TOURNAMENT_LEAVE)))
		else:
			_content.add_child(UI.button("Meld meg på", func() -> void: _send(Protocol.TOURNAMENT_JOIN), "PrimaryButton"))
	if t.status in ["draft", "open"]:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		row.add_child(UI.button("Legg i kalender", _add_to_calendar))
		row.add_child(UI.button("Del lenke til turneringen", func() -> void:
			_status.text = app.share_link("turnering", str(tournament_id), str(t.name))
		))
		_content.add_child(row)

	# --- Regler: alt man må vite før start
	_content.add_child(UI.section("Regler"))
	for line in rules(t):
		var l := _plain("•  " + line, "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)
	var info := [
		tr("Status: %s") % tr(status_name(t.status)),
		tr("Start: %s") % UI.format_time(int(t.start_time)),
		tr("Deltakere: %d av %d") % [int(t.players), int(t.max_players)],
	]
	for line in info:
		var l := _plain(line, "Muted")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)

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

	# --- Runder og kamper (i en ferdig utslagsturnering sier treet alt)
	for r in (t.rounds as Array).size():
		if knockout and t.status == "finished":
			break
		_content.add_child(UI.section(tr("Runde %d") % (r + 1)))
		for m in t.rounds[r]:
			var label := _plain(_match_text(m), "Muted" if m.status == "done" else "")
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if m.status == "waiting" and m.has("walkover_at"):
				var match_info: Dictionary = m
				var text := func() -> String: return _match_text(match_info)
				_ticking.append([label, text])
			var own_match := _you != 0 and _you in [int(m.p1), int(m.p2)]
			var games: Array = m.get("games", [])
			if m.status == "playing" and str(m.room) != "" and not own_match:
				var row := UI.hbox(8)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				var code := str(m.room)
				row.add_child(UI.button("Se på", func() -> void: Net.send({ "t": Protocol.WATCH, "code": code })))
				_content.add_child(row)
			elif m.status == "done" and not games.is_empty():
				var row := UI.hbox(8)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				var game_id := int(games[-1])
				row.add_child(UI.button("Reprise", func() -> void: open_game(game_id)))
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
		if t.status != "cancelled":
			row.add_child(UI.button("Endre", func() -> void: app.show_tournament_edit(_t)))
		if t.status in ["draft", "open"]:
			row.add_child(UI.button("Start nå", func() -> void: _admin_action("start")))
			if bool(t.get("with_trophy", true)):
				# Bytt pokalen vinneren får (trykk til du liker den; siden oppdateres med en gang)
				row.add_child(UI.button("Ny pokal", func() -> void:
					Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id,
						"data": { "trophy": Trophy.generate(randi()) } })
				))
		if t.status in ["draft", "open", "running"]:
			row.add_child(UI.button("Avlys", func() -> void: _admin_action("cancel")))
		row.add_child(UI.button("Slett", func() -> void: _admin_action("delete")))
		_content.add_child(row)
		# Alle mot alle: admin kan endre antall runder helt til turneringen starter
		if t.format == "round_robin" and t.status in ["draft", "open"]:
			_content.add_child(UI.label("Antall runder", "Muted"))
			var limits: Array = TournamentEditScreen.ROUND_LIMITS
			var current := maxi(0, limits.find(int(t.get("max_rounds", 0))))
			_content.add_child(UI.choice(limits.map(func(n: int) -> String: return tr("Alle") if n == 0 else str(n)), current,
				func(i: int) -> void:
					Net.send({ "t": Protocol.TOURNAMENT_UPDATE, "id": tournament_id, "data": { "max_rounds": limits[i] } })
			))


## Reglene i klartekst: format, brett og tid, møtefrist, uavgjort, Elo og pokal.
static func rules(t: Dictionary) -> Array:
	var o := GameOptions.from_dict(t.get("options", {}))
	var out := []
	var limit := int(t.get("max_rounds", 0))
	if t.get("format") == "round_robin" and limit > 0:
		out.append(I18n.t("Alle mot alle, men høyst %d runder: hver spiller spiller %d partier (én færre ved fri runde). Seier gir 1 poeng, uavgjort ½.") \
			% [limit, limit])
	elif t.get("format") == "round_robin":
		out.append(I18n.t("Alle mot alle: alle møter alle én gang. Seier gir 1 poeng, uavgjort ½."))
	else:
		out.append(I18n.t("Utslag: taperen er ute, vinneren går videre til neste runde."))
		out.append(I18n.t("Uavgjort spilles om (inntil 3 ganger). Blir det fortsatt uavgjort, går den med høyest Elo videre."))
	out.append(I18n.t("Spill: %s") % o.describe())
	if o.has_clock():
		out.append(I18n.t("Tid: %d min hver, pluss %d s per trekk. Går tiden ut, taper du.") % [o.time_base_s / 60, o.time_increment_s])
	var players := maxi(int(t.get("players", 0)), 2)
	var n := round_count(str(t.get("format", "")), players, limit)
	out.append(I18n.t("Varighet: ca. %s (%d runder med %d spillere).") % [
		duration_text(estimate_minutes(n, o, int(t.get("round_gap_s", 120)))), n, players])
	out.append(I18n.t("Hvem som starter, byttes for hvert parti."))
	out.append(I18n.t("Du kastes rett inn når kampen din begynner. Den starter når begge er i rommet."))
	out.append(I18n.t("Møt opp innen %d min, ellers taper du på walkover. Pause mellom rundene: %d min.") \
		% [int(t.get("show_up_s", 300)) / 60, int(t.get("round_gap_s", 120)) / 60])
	if bool(t.get("ranked", true)):
		out.append(I18n.t("Rangert: partiene teller på Elo."))
	else:
		out.append(I18n.t("Uranket: partiene endrer ikke Elo."))
	if bool(t.get("with_trophy", true)):
		out.append(I18n.t("Vinneren får pokalen på profilen sin."))
	var prize := str(t.get("prize", ""))
	if prize != "":
		out.append(I18n.t("Premie: vinneren låser opp «%s» (ellers %s).") % [Progression.item_name(prize),
			Progression.requirement_text(prize).to_lower()])
	if bool(t.get("ranked", true)):
		out.append(I18n.t("XP etter plassering: vinneren 150, finalisten 75, semifinalistene 40, alle andre som spilte 20."))
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
## Ellers: pokalen det spilles om. Uten pokal: bare vinneren (eller null før den er ferdig).
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
	if not with_trophy:
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
		"waiting":
			if not m.has("here"):
				return tr("%s · venter på spillerne") % names
			var missing := []
			if not bool(m.here[0]):
				missing.append(str(m.p1_name))
			if not bool(m.here[1]):
				missing.append(str(m.p2_name))
			var left := countdown_text(int(m.walkover_at) - now_s())
			if missing.is_empty():
				return tr("%s · starter nå") % names
			return tr("%s · venter på %s (walkover om %s)") % [names, ", ".join(missing), left]
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
			"waiting":
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
	if _t.format == "knockout" and _you in (_t.player_list as Array).map(func(p: Dictionary) -> int: return int(p.id)):
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
