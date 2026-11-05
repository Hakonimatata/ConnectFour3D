class_name TournamentDisplay
extends Screen
## Storskjerm for en turnering (runde 18): viser på en TV eller prosjektor hva som skjer, uten knapper for
## spillerne og uten innlogging. Åpnes med ?vis=KODE i lenken, eller «Vis på storskjerm» på
## turneringssiden. Alt legges ut for 1280 × 720 og skaleres til skjermen, så det kan leses på avstand.
## - Før start: QR-kode og lenke for å bli med, og deltakerne etter hvert som de kommer. Er arrangøren
##   (eller admin) logget inn på skjermen, står «Start nå» under deltakerne. En TV uten innlogging får den ikke.
##   Under innsjekken: nedtellingen, og hvem som er her (de som ikke er kommet, er dempet).
## - Underveis: bare turneringstreet (utslag), eller tabellen og rundens kamper (alle mot alle), over hele
##   skjermen. Brettet er skjult.
## - Finalen (og omkampen om seieren): det eneste partiet som vises. Brettet står midt på skjermen, helt
##   synlig, med navnene og stillingsmåleren over.
## - Ferdig: vinneren med pokalen over brettet, som spiller av finalen, og pallen under.

const DESIGN := Vector2(1280, 720)
const LINGER_MS := 8_000         ## så lenge sluttstillingen i finalen står før den spilles av på nytt
const STEP_S := 0.8              ## tid mellom trekkene når finalen spilles av

var code := ""
var _t: Dictionary = {}
var _manage := false             ## arrangøren (eller admin) er logget inn her: «Start nå» vises
var _root: Control               ## alt innhold, skalert til skjermen
var _eval_bar: EvalBar           ## stillingsmåleren i finalen (lages på nytt når siden bygges)
var _last_eval: Dictionary = {}  ## siste vurdering av finalen, så måleren beholder den
var _notice: Label               ## svar på «Start nå» (f.eks. for få deltakere)
var _countdown: Label            ## «Starter om 1:45» under innsjekken (oppdateres i _tick)
var _seen := {}                  ## deltakere som er vist (nye toner inn)
var _clock_offset := 0
var _live: OnlineMatch           ## finalen, sett som tilskuer
var _live_room := ""
var _live_over_at := 0
var _eval := LiveEval.new()
var _empty_board := false        ## finalen har ikke startet: tomt brett står klart
var _replay: Dictionary = {}     ## finalen fra partiloggen (spilles av når turneringen er ferdig)
var _replay_state: GameState
var _replay_i := 0
var _wanted_game := 0


func _init(p_app: ClientRoot, p_code: String) -> void:
	super(p_app)
	code = p_code.strip_edges().to_upper()


func _ready() -> void:
	app.camera.auto_rotate = true
	app.board.input_enabled = false
	app.board.clear_pieces()
	app.board.visible = false
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var tools := UI.hbox(8)
	tools.add_child(UI.button("Fullskjerm", func() -> void:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	, "GhostButton"))
	tools.add_child(UI.button("Lukk", _on_back, "GhostButton"))
	add_child(tools)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	resized.connect(_layout)
	Net.message.connect(_on_message)
	Net.connected.connect(func(_resumed: bool) -> void: _refresh())
	Net.ensure_connected()
	_timer(15.0, _refresh)   # serveren sender endringer med en gang; dette er bare en reserve
	_timer(STEP_S, _tick)
	if OS.has_feature("web"):   # skjermen skal ikke slukke midt i turneringen
		JavaScriptBridge.eval("navigator.wakeLock && navigator.wakeLock.request('screen').catch(function(){})", true)
	_root.add_child(_margin(_plain(tr("Henter turneringen…"), "Heading")))
	_layout.call_deferred()
	_refresh()


func _timer(seconds: float, call: Callable) -> void:
	var t := Timer.new()
	t.wait_time = seconds
	t.autostart = true
	t.timeout.connect(call)
	add_child(t)


## Alt skaleres så 1280 × 720 fyller skjermen. Brettet (bare i finalen) står midt i plassen mellom
## navnene over og linjen under.
func _layout() -> void:
	var k := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_root.scale = Vector2(k, k)
	_root.size = size / k
	app.camera.view_offset = Vector2(0, 0.35)
	app.camera.dist_target = app.camera.max_distance * 0.8


func _refresh() -> void:
	Net.send({ "t": Protocol.TOURNAMENT_CODE, "code": code })


func _exit_tree() -> void:
	_stop_live()
	app.board.visible = true
	if not (app._screen is TournamentScreen or app._screen is TournamentDisplay):   # se TournamentScreen._exit_tree
		Net.send({ "t": Protocol.VIEW_TOURNAMENT, "id": 0 })


func now_s() -> int:
	return int(Time.get_unix_time_from_system()) + _clock_offset


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.TOURNAMENT_STATE:
			if not _t.is_empty() and int(msg.tournament.id) != int(_t.id):
				return
			if msg.has("now"):
				_clock_offset = int(msg.now) - int(Time.get_unix_time_from_system())
			if msg.tournament != _t or bool(msg.get("admin", false)) != _manage:
				_t = msg.tournament
				_manage = bool(msg.get("admin", false))
				_rebuild()
			_update_board()
		Protocol.GAME_START, Protocol.GAME_SYNC:
			if _live_room != "" and _live == null:
				_live = OnlineMatch.new(msg)
				add_child(_live)
				_live.started.connect(_draw_live)
				_live.move_applied.connect(func(_c: Vector2i, pos: Vector3i, player: int) -> void:
					app.board.add_piece(pos, player)
					_eval.update(_live.state))
				_live.finished.connect(func(_r: int, _reason: int, line: Array) -> void:
					app.board.highlight(line)
					_live_over_at = Time.get_ticks_msec())
				_live.start_game()
		Protocol.GAME_RECORD:
			if int(msg.game.get("id", 0)) == _wanted_game and _live == null:
				_start_replay(msg.game)
		Protocol.ERROR:
			if str(msg.get("code", "")) == "no_tournament":
				_clear(_root)
				_root.add_child(_margin(_plain(I18n.server_text(msg), "Heading")))
			elif _notice != null and is_instance_valid(_notice):
				_notice.text = I18n.server_text(msg)


func _process(_delta: float) -> void:
	if _live != null and _live.state != null and _eval.step(4000):
		_last_eval = _eval.get_eval(_live.state)
		_show_eval()


# ---------------------------------------------------------------- Fasene

## open (før start), tree (underveis), final (finalen spilles), finished eller cancelled.
func _phase() -> String:
	match str(_t.get("status", "")):
		"draft", "open": return "open"
		"running": return "tree" if _final_match().is_empty() else "final"
		"finished": return "finished"
	return "cancelled"


## Finalen i runden som pågår: utslag med én kamp igjen, eller omkampen om seieren. Ellers {}.
func _final_match() -> Dictionary:
	var rounds: Array = _t.get("rounds", [])
	if rounds.is_empty():
		return {}
	var round: Array = rounds[int(_t.current_round)]
	if round.size() != 1 or int(round[0].p1) == 0 or int(round[0].p2) == 0:
		return {}
	return round[0] if _t.format == "knockout" or bool(round[0].get("playoff", false)) else {}


func _rebuild() -> void:
	_clear(_root)
	_eval_bar = null
	_notice = null
	_countdown = null
	var phase := _phase()
	app.board.visible = phase == "final" or (phase == "finished" and int(_t.get("final_game", 0)) > 0)
	match phase:
		"open": _build_open()
		"tree": _build_tree()
		"final", "finished": _build_stage(phase == "finished")
		_: _root.add_child(_margin(_plain("%s · %s" % [str(_t.name), tr("Avlyst")], "Title")))
	_layout()


## Før start: stor QR-kode og lenke til venstre, deltakerne til høyre (nye toner inn).
func _build_open() -> void:
	var row := UI.hbox(28)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 560
	var left := UI.vbox(12)
	panel.add_child(left)
	row.add_child(panel)
	left.add_child(_title())
	_countdown = _plain(_start_text(), "Heading")
	left.add_child(_countdown)
	var link := app.link_for("t", code)
	var qr := QrView.new()
	qr.custom_minimum_size = Vector2(300, 300)
	qr.set_text(link)
	left.add_child(qr)
	left.add_child(_center(_plain(tr("Skann for å bli med, eller gå til"), "Muted")))
	left.add_child(_center(_plain(link.get_slice("://", 1), "Heading")))
	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var players: Array = _t.player_list
	var checkin := bool(_t.get("checkin", false))
	var here := players.filter(func(p: Dictionary) -> bool: return bool(p.get("here", false))).size()
	right.add_child(_plain(tr("Her nå: %d av %d") % [here, players.size()] if checkin else tr("Deltakere (%d)") % players.size(),
		"Heading"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for p in players:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI._box(UI.PANEL, 10, UI.BORDER, 14, 8))
		var name := _plain(str(p.username), "")
		name.add_theme_font_size_override("font_size", 24)
		chip.add_child(name)
		flow.add_child(chip)
		var alpha := 0.4 if checkin and not bool(p.get("here", false)) else 1.0   # innsjekken: ikke kommet ennå
		chip.modulate.a = alpha
		if not _seen.has(int(p.id)):
			_seen[int(p.id)] = true
			chip.modulate.a = 0.0
			chip.create_tween().tween_property(chip, "modulate:a", alpha, 0.6)
	right.add_child(flow)
	if players.is_empty():
		right.add_child(_plain(tr("Venter på de første…"), "Muted"))
	if _manage:   # bare for arrangøren (eller admin) som er logget inn på denne skjermen
		var start := UI.button("Start med dem som er her" if checkin else "Start nå", func() -> void:
			Net.send({ "t": Protocol.TOURNAMENT_ACTION, "id": int(_t.id), "action": "start" }), "PrimaryButton")
		start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		start.custom_minimum_size = Vector2(220, 56)
		right.add_child(start)
		_notice = _plain("", "Muted")
		right.add_child(_notice)
	_root.add_child(_margin(row))


## Underveis: bare treet (utslag), eller tabellen og rundens kamper (alle mot alle), over hele skjermen.
func _build_tree() -> void:
	var panel := PanelContainer.new()
	var v := UI.vbox(10)
	panel.add_child(v)
	var head := UI.hbox(16)
	var title := _title()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var status := _plain(_round_text(), "Heading")
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	v.add_child(head)
	if _t.format == "knockout":
		var bracket := BracketView.new(_t.rounds, 0, _t.get("trophy", {}) if bool(_t.get("with_trophy", true)) else {})
		bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_fit(bracket))
	else:
		var cols := UI.hbox(40)
		cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var table := UI.vbox(4)
		table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(UI.section("Tabell"))
		var place := 1
		for row in (_t.get("standings", []) as Array).slice(0, 12):
			table.add_child(_plain(tr("%d. %s – %s poeng (%d–%d–%d)") % [place, row.username,
				TournamentScreen._points(int(row.points2)), int(row.wins), int(row.draws), int(row.losses)], ""))
			place += 1
		cols.add_child(table)
		var matches := UI.vbox(4)
		matches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		matches.add_child(UI.section("Kampene nå"))
		for m in _t.rounds[int(_t.current_round)]:
			if int(m.p2) != 0:
				matches.add_child(_plain(TournamentScreen.match_line(m, now_s()), "Muted"))
		cols.add_child(matches)
		v.add_child(_fit(cols))
	v.add_child(_follow())
	_root.add_child(_margin(panel))


## Finalen (eller vinneren): navnene og stillingsmåleren over, brettet helt synlig i midten, og en
## linje under. Ferdig uten finale å vise (alle mot alle): pokalen i midten i stedet for brettet.
func _build_stage(finished: bool) -> void:
	var v := UI.vbox(10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var banner := PanelContainer.new()
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var b := UI.vbox(4)
	banner.add_child(b)
	b.add_child(_center(_plain(str(_t.name), "Muted")))
	var podium := _podium(_t) if finished else []
	var bottom := ""
	if finished:
		var hero := UI.hbox(14)
		if bool(_t.get("with_trophy", true)) and app.board.visible:
			hero.add_child(TrophyView.new(_t.get("trophy", {}), 84, true))
		var names := UI.vbox(0)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_child(_plain(tr("Vinner"), "Muted"))
		var name := _plain(str(podium[0]) if not podium.is_empty() else "", "Title")
		name.add_theme_color_override("font_color", BracketView.GOLD)
		names.add_child(name)
		hero.add_child(names)
		b.add_child(hero)
		var rest := []
		for i in range(1, mini(podium.size(), 4)):
			rest.append("%d. %s" % [mini(i + 1, 3), podium[i]])
		bottom = "   ·   ".join(rest)
	else:
		var m := _final_match()
		b.add_child(_center(_plain(tr("Omkamp om seieren") if bool(m.get("playoff", false)) else tr("Finale"), "Heading")))
		b.add_child(_center(_plain("%s – %s" % [m.p1_name, m.p2_name], "Title")))
		_eval_bar = EvalBar.new()
		_eval_bar.custom_minimum_size.x = 560
		b.add_child(_eval_bar)
		_show_eval()
		bottom = TournamentScreen.match_line(m, now_s())
	v.add_child(banner)
	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if finished and not app.board.visible and bool(_t.get("with_trophy", true)):
		middle.add_child(TrophyView.new(_t.get("trophy", {}), 260, true))
	v.add_child(middle)
	var foot := _follow()
	var line := _plain(bottom, "Heading")
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(line)
	v.add_child(foot)
	_root.add_child(_margin(v))


## Når den starter: nedtellingen under innsjekken, ellers klokkeslettet (private: når arrangøren vil).
func _start_text() -> String:
	if bool(_t.get("checkin", false)):
		return tr("Starter om %s") % TournamentScreen.countdown_text(int(_t.start_time) - now_s())
	if bool(_t.get("private", false)):
		return tr("Bli med nå! Vi starter snart.")
	return tr("Starter %s") % UI.format_time(int(_t.start_time))


func _round_text() -> String:
	if str(_t.get("pairing", "")) == "swiss":
		return tr("Runde %d av %d") % [int(_t.current_round) + 1, int(_t.get("regular_rounds", 0))]
	return tr("Runde %d") % (int(_t.current_round) + 1)


## Plasseringene: tabellen (alle mot alle), eller finalen og semifinalene (utslag).
static func _podium(t: Dictionary) -> Array:
	if t.format != "knockout":
		return (t.get("standings", []) as Array).slice(0, 3).map(func(r: Dictionary) -> String: return str(r.username))
	var out := [str(t.get("winner", ""))]
	var rounds: Array = t.rounds
	for back in [1, 2]:
		if rounds.size() < back:
			break
		for m in rounds[rounds.size() - back]:
			if int(m.winner) != 0 and int(m.p1) != 0 and int(m.p2) != 0:
				out.append(str(m.p2_name) if int(m.winner) == int(m.p1) else str(m.p1_name))
	return out


# ---------------------------------------------------------------- Brettet (bare finalen)

## Finalen vises når den spilles, og spilles av når turneringen er ferdig. Ellers er brettet skjult.
func _update_board() -> void:
	match _phase():
		"final":
			var m := _final_match()
			if m.status == "playing" and str(m.room) != "":
				if str(m.room) != _live_room:
					_watch(str(m.room))
			elif _live == null and _live_room == "" and not _empty_board:
				app.board.setup(GameOptions.from_dict(_t.get("options", {})).size)   # finalen starter snart
				_empty_board = true
		"finished":
			if _live != null and _live_over_at > 0 and Time.get_ticks_msec() - _live_over_at < LINGER_MS:
				return   # sluttstillingen i finalen står litt før reprisen
			if _live_room != "":
				_stop_live()
			var final_id := int(_t.get("final_game", 0))
			if final_id > 0 and final_id != _wanted_game:
				_wanted_game = final_id
				Net.send({ "t": Protocol.GET_GAME, "id": final_id })
		_:
			_stop_live()
			_replay = {}


func _watch(room: String) -> void:
	_stop_live()
	_replay = {}
	_live_room = room
	_last_eval = {}
	Net.send({ "t": Protocol.WATCH, "code": room })


func _stop_live() -> void:
	if _live != null:
		_live.leave()   # tilskuer: går bare ut av rommet
		_live.queue_free()
		_live = null
	elif _live_room != "":
		Net.send({ "t": Protocol.LEAVE_ROOM, "code": _live_room })
	_live_room = ""
	_live_over_at = 0


func _draw_live() -> void:
	var s := _live.state
	_empty_board = false
	app.board.setup(s.size)
	app.board.set_looks(_live.look_of(1), _live.look_of(2))
	for i in s.cells.size():
		if s.cells[i] != 0:
			app.board.add_piece(s.lines.pos_of(i), s.cells[i], false)
	_eval.update(s)
	_show_eval()


func _show_eval() -> void:
	if _eval_bar == null or not is_instance_valid(_eval_bar):
		return
	if _live != null:
		_eval_bar.colors = { 1: _live.color_of(1), 2: _live.color_of(2) }
	if _last_eval.is_empty() and _live != null:
		_eval_bar.set_pending()
	elif _last_eval.is_empty():
		_eval_bar.set_unknown()
	else:
		_eval_bar.set_eval(float(_last_eval.p1), str(_last_eval.text), int(_last_eval.leader))


func _start_replay(game: Dictionary) -> void:
	_replay = game
	_replay_i = 0
	_empty_board = false
	var o := GameOptions.from_dict(game.get("options", {}))
	_replay_state = GameState.new(o, int(game.get("first", 1)))
	var recs: Array = game.get("players", [])
	var look := func(i: int) -> Dictionary:
		var r: Dictionary = recs[i] if i < recs.size() and recs[i] is Dictionary else {}
		return Skins.look_of(r, "")
	var pair := Skins.resolve_pair(look.call(0), look.call(1))
	app.board.setup(o.size)
	app.board.set_looks(pair[0], pair[1])


## Spiller av ett trekk i finalen (når turneringen er ferdig), og ser om brettet skal endres.
func _tick() -> void:
	if not _t.is_empty():
		_update_board()
	if _countdown != null and is_instance_valid(_countdown):
		_countdown.text = _start_text()
	if _replay.is_empty() or _live != null:
		return
	var moves: Array = _replay.get("moves", [])
	if _replay_i < moves.size():
		var col := Vector2i(int(moves[_replay_i][0]), int(moves[_replay_i][1]))
		var player := _replay_state.current_player
		var r := _replay_state.play(col, false)
		if r.ok:
			app.board.add_piece(r.pos, player)
			if r.won:
				app.board.highlight(_replay_state.winning_line)
	elif _replay_i > moves.size() + 6:   # sluttstillingen står litt, så begynner den på nytt
		_start_replay(_replay)
		return
	_replay_i += 1


# ---------------------------------------------------------------- Hjelpere

func _title() -> Label:
	var title := _plain(str(_t.name), "Title")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return title


## Liten QR-kode for å følge med på mobilen (nederst).
func _follow() -> HBoxContainer:
	var row := UI.hbox(14)
	var qr := QrView.new()
	qr.custom_minimum_size = Vector2(96, 96)
	qr.set_text(app.link_for("t", code))
	row.add_child(qr)
	var text := _plain(tr("Følg med på mobilen:") + "\n" + app.link_for("t", code).get_slice("://", 1), "Muted")
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	return row


## Legger c i en holder som fyller resten av høyden, og skalerer den ned hvis den er for høy
## (treet med mange spillere, mange kamper). Treet forstørres også for å fylle plassen, men ikke mer
## enn at det fortsatt får plass speilvendt (pokalen i midten).
func _fit(c: Control) -> Control:
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(c)
	var fit := func() -> void:
		var need := maxf(1.0, c.get_combined_minimum_size().y)
		var most := minf(1.5, holder.size.x / (c as BracketView).mirror_width()) if c is BracketView else 1.0
		var s := minf(maxf(most, 0.1), holder.size.y / need)
		c.scale = Vector2(s, s)
		c.size = Vector2(holder.size.x / maxf(s, 0.01), need)
	holder.resized.connect(fit)
	c.minimum_size_changed.connect(fit)
	return holder


func _margin(child: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 48)   # plass til «Fullskjerm» og «Lukk» øverst til høyre
	margin.add_child(child)
	return margin


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _plain(text: String, variation: String) -> Label:
	var l := UI.label(text, variation)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _on_back() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _t.is_empty():
		app.show_menu()
	else:
		app.show_tournament(int(_t.id))
