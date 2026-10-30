class_name ProfileScreen
extends Screen
## Statistikk for en spiller (deg selv som standard), pokalene, de siste partiene (med reprise) og topplister.
## Er det en annen spiller, står venneknappen øverst: «Legg til venn», «Godta», «Forespørsel sendt» eller
## «Utfordre» / «Se på» når dere er venner. Navnene i topplisten kan trykkes på for å se profilen deres.

var username := ""          ## tom = deg selv
var _stats_box: VBoxContainer
var _board_box: VBoxContainer
var _board := "elo"
var _boards: Dictionary = {}
var _games_box: VBoxContainer
var _back_to_menu := false
var _actions: HBoxContainer   ## venneknappene (bare på andres profil)
var _user: Dictionary = {}


func _init(p_app: ClientRoot, p_username := "", back_to_menu := false) -> void:
	super(p_app)
	username = p_username
	_back_to_menu = back_to_menu


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Statistikk", "Heading"))
	_stats_box = UI.vbox(6)
	v.add_child(_stats_box)
	_stats_box.add_child(UI.label("Henter…", "Muted"))

	v.add_child(UI.section("Siste partier"))
	_games_box = UI.vbox(6)
	v.add_child(_games_box)
	_games_box.add_child(UI.label("Henter…", "Muted"))

	v.add_child(UI.section("Toppliste"))
	v.add_child(UI.choice(["Elo", "Flest seire", "Lengste tvungne seier", "Dagens oppgave"], 0, func(i: int) -> void:
		_board = ["elo", "wins", "forced", "puzzles"][i]
		_show_board()
	))
	_board_box = UI.vbox(4)
	v.add_child(_board_box)
	UI.card_footer(v).add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	Net.send({ "t": Protocol.GET_STATS, "username": username })
	if is_other() and Net.is_logged_in():
		Net.send({ "t": Protocol.FRIEND, "action": "list" })
	Net.send({ "t": Protocol.GET_LEADERBOARD })
	Net.send({ "t": Protocol.LIST_GAMES, "username": username })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.STATS:
			if not is_other() or (msg.get("user") is Dictionary and str(msg.user.username).to_lower() == username.to_lower()):
				_show_stats(msg.get("user"))
		Protocol.FRIENDS:
			_update_actions()
		Protocol.LEADERBOARD:
			_boards = msg.get("boards", {})
			_show_board()
		Protocol.GAME_LIST:
			show_games(msg.get("games", []))
		Protocol.GAME_RECORD:
			if msg.get("game") is Dictionary:
				app.show_replay(msg.game, app.show_profile.bind(username, _back_to_menu))


func _show_stats(u: Variant) -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	if not u is Dictionary:
		_stats_box.add_child(UI.label("Ingen statistikk ennå. Logg inn og spill online!", "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	var s: Dictionary = u.stats
	var games := int(s.games)
	var pct := int(round(100.0 * int(s.wins) / games)) if games > 0 else 0
	var elo := int(u.elo)
	_user = u
	var head := UI.hbox(14)
	var avatar := AvatarView.new(56)
	avatar.set_avatar(str(u.get("avatar", "")), str(u.username), UI.ACCENT)
	head.add_child(avatar)
	head.add_child(EloBadge.make(elo, 52))
	var head_text := UI.vbox(0)
	var title := UI.label(str(u.username), "Title")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head_text.add_child(title)
	var next := EloBadge.next_tier(elo)
	var tier_text := tr(EloBadge.tier(elo).name) + "  ·  " + (tr("%d Elo til %s") % [int(next.min) - elo, tr(next.name)]
		if not next.is_empty() else tr("Høyeste nivå"))
	var tier_label := UI.label(tier_text, "Muted")
	tier_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head_text.add_child(tier_label)
	head.add_child(head_text)
	_stats_box.add_child(head)
	if u.has("xp"):
		_stats_box.add_child(LevelView.new(Progression.progress_of(u)))   # nivå og XP (runde 17)
	_actions = UI.hbox(8)
	_stats_box.add_child(_actions)
	_update_actions()
	var rows := [
		["Elo", str(int(u.elo))],
		["Partier", str(games)],
		["Seire – tap – uavgjort", "%d – %d – %d" % [int(s.wins), int(s.losses), int(s.draws)]],
		["Vinnerprosent", "%d %%" % pct],
		["Seiersrekke (nå / beste)", "%d / %d" % [int(s.current_streak), int(s.best_streak)]],
		["Raskeste seier", tr("%d trekk") % int(s.fastest_win) if int(s.fastest_win) > 0 else "—"],
		["Tvungne trekk", str(int(s.forced_moves))],
		["Doble trusler", str(int(s.double_threats))],
		["Lengste tvungne seier", tr("%d trekk") % int(s.best_forced_win) if int(s.best_forced_win) > 0 else "—"],
		["Seire på tid / ga opp / walkover", "%d / %d / %d" % [int(s.wins_time), int(s.wins_resign), int(s.wins_walkover)]],
		["Turneringer vunnet", str(int(s.tournaments_won))],
		["Dagens oppgave på rad (nå / beste)", "%d / %d" % [int(s.puzzle_streak), int(s.best_puzzle_streak)]],
	]
	for r in rows:
		var row := UI.hbox(10)
		var name := UI.label(r[0], "Muted")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value := UI.label(r[1])
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(value)
		_stats_box.add_child(row)
	_stats_box.add_child(_trophy_shelf(u.get("trophies", [])))


## Er dette en annen spillers profil (ikke din egen)?
func is_other() -> bool:
	return username != "" and username.to_lower() != str(Net.user.get("username", "")).to_lower()


## Venneknappene etter hvordan dere står: venner, forespørsel til deg, sendt av deg, eller ingenting ennå.
func _update_actions() -> void:
	if _actions == null or _user.is_empty():
		return
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	_actions.visible = is_other() and Net.is_logged_in()
	if not _actions.visible:
		return
	var name := str(_user.username)
	var key := name.to_lower()
	var friend: Dictionary = {}
	for f in Net.friends.get("friends", []):
		if str(f.username).to_lower() == key:
			friend = f
	var asked := (Net.friends.get("requests", []) as Array).any(func(r: Variant) -> bool: return str(r.username).to_lower() == key)
	var sent := (Net.friends.get("sent", []) as Array).any(func(s: Variant) -> bool: return str(s).to_lower() == key)
	var friend_request := func(action: String) -> void: Net.send({ "t": Protocol.FRIEND, "action": action, "username": name })
	if not friend.is_empty():
		var state := UI.label("Venner", "Muted")
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions.add_child(state)
		if bool(friend.get("playing", false)) and str(friend.get("room", "")) != "":
			var code := str(friend.room)
			_actions.add_child(UI.button("Se på", func() -> void: Net.send({ "t": Protocol.WATCH, "code": code })))
		elif bool(friend.get("online", false)):
			_actions.add_child(UI.button("Utfordre", func() -> void: app.challenge(name), "PrimaryButton"))
	elif asked:
		var ask := UI.label(tr("%s vil bli venn med deg.") % name, "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
		ask.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		ask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions.add_child(ask)
		_actions.add_child(UI.button("Godta", friend_request.bind("accept"), "PrimaryButton"))
	elif sent:
		var b := UI.button("Forespørsel sendt", func() -> void: pass)
		b.disabled = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions.add_child(b)
	else:
		var b := UI.button("Legg til venn", friend_request.bind("request"), "PrimaryButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions.add_child(b)


## Pokalhylla: hver pokal med navnet og datoen under. Nyeste først.
func _trophy_shelf(trophies: Variant) -> Control:
	var box := UI.vbox(8)
	box.add_child(UI.section("Pokaler"))
	var list: Array = trophies if trophies is Array else []
	if list.is_empty():
		box.add_child(UI.label("Ingen pokaler ennå. Vinn en turnering for å få en!", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		return box
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for e in list:
		if not e is Dictionary:
			continue
		var card := UI.vbox(2)
		card.custom_minimum_size.x = 104
		var view := TrophyView.new(e.get("design", {}), 92)
		view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_child(view)
		var name := UI.label(str(e.get("name", "")), "", HORIZONTAL_ALIGNMENT_CENTER, true)
		name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name.add_theme_font_size_override("font_size", 14)
		name.custom_minimum_size.x = 104
		card.add_child(name)
		var date := UI.label(str(e.get("date", "")), "Muted", HORIZONTAL_ALIGNMENT_CENTER)
		date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		date.add_theme_font_size_override("font_size", 12)
		card.add_child(date)
		flow.add_child(card)
	box.add_child(flow)
	return box


func _show_board() -> void:
	for c in _board_box.get_children():
		c.queue_free()
	var list: Array = _boards.get(_board, [])
	if list.is_empty():
		_board_box.add_child(UI.label("Ingen her ennå.", "Muted"))
		return
	for i in list.size():
		var e: Dictionary = list[i]
		var row := UI.hbox(10)
		var place := UI.label("%d." % (i + 1), "Muted")
		place.custom_minimum_size.x = 32
		row.add_child(place)
		row.add_child(EloBadge.make(int(e.get("elo", -1)), 20))
		# Navnet er en knapp: trykk for å se profilen
		var who := str(e.username)
		var name := UI.name_button(who, func() -> void: app.show_profile(who, _back_to_menu))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value := ""
		match _board:
			"elo": value = str(int(e.elo))
			"wins": value = tr("%d seire") % int(e.wins)
			"forced": value = tr("%d trekk") % int(e.best_forced_win)
			"puzzles": value = tr("%d løst · rekke %d") % [int(e.get("puzzles_solved", 0)), int(e.get("puzzle_streak", 0))]
		var v := UI.label(value, "Muted")
		v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(v)
		_board_box.add_child(row)


## Partiene til spilleren, nyeste først. Trykk for å se partiet igjen.
func show_games(games: Array) -> void:
	for c in _games_box.get_children():
		c.queue_free()
	if games.is_empty():
		_games_box.add_child(UI.label("Ingen lagrede partier ennå. Spill online med konto!", "Muted",
			HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for g in games.slice(0, 10):
		var names: Array = g.get("players", ["?", "?"])
		var seat := int(g.get("seat", 0))
		var result := int(g.get("result", 0))
		var outcome := tr("Uavgjort")
		if result != GameState.Result.DRAW and seat != 0:
			var won := (result == GameState.Result.P1_WON and seat == 1) or (result == GameState.Result.P2_WON and seat == 2)
			outcome = tr("Seier") if won else tr("Tap")
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		b.custom_minimum_size.y = 56
		b.text = "%s – %s\n%s · %s · %s" % [names[0], names[1] if names.size() > 1 else "?", outcome,
			tr("%d trekk") % int(g.get("moves", 0)), str(g.get("time", "")).replace("T", " ").substr(0, 16)]
		var id := int(g.id)
		b.pressed.connect(func() -> void:
			Sfx.play("click")
			Net.send({ "t": Protocol.GET_GAME, "id": id })
		)
		_games_box.add_child(b)


func _on_back() -> void:
	if _back_to_menu:
		app.show_menu()
	else:
		app.show_online()
