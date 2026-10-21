class_name ProfileScreen
extends Screen
## Statistikk for en spiller (deg selv som standard) og topplister.

var username := ""          ## tom = deg selv
var _stats_box: VBoxContainer
var _board_box: VBoxContainer
var _board := "elo"
var _boards: Dictionary = {}


func _init(p_app: ClientRoot, p_username := "") -> void:
	super(p_app)
	username = p_username


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Statistikk", "Heading"))
	_stats_box = UI.vbox(6)
	v.add_child(_stats_box)
	_stats_box.add_child(UI.label("Henter…", "Muted"))

	v.add_child(UI.section("Toppliste"))
	v.add_child(UI.choice(["Elo", "Flest seire", "Lengste tvungne seier"], 0, func(i: int) -> void:
		_board = ["elo", "wins", "forced"][i]
		_show_board()
	))
	_board_box = UI.vbox(4)
	v.add_child(_board_box)
	v.add_child(UI.spacer(4))
	v.add_child(UI.button("Tilbake", _on_back))

	Net.message.connect(_on_message)
	Net.send({ "t": Protocol.GET_STATS, "username": username })
	Net.send({ "t": Protocol.GET_LEADERBOARD })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.STATS:
			_show_stats(msg.get("user"))
		Protocol.LEADERBOARD:
			_boards = msg.get("boards", {})
			_show_board()


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
	var head := UI.hbox(14)
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
		var name := UI.label(str(e.username))
		name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value := ""
		match _board:
			"elo": value = str(int(e.elo))
			"wins": value = tr("%d seire") % int(e.wins)
			"forced": value = tr("%d trekk") % int(e.best_forced_win)
		var v := UI.label(value, "Muted")
		v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(v)
		_board_box.add_child(row)


func _on_back() -> void:
	app.show_online()
