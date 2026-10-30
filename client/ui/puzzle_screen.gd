class_name PuzzleScreen
extends Screen
## Dagens oppgave: finn den tvungne seieren. Motstanderen forsvarer seg så godt det går
## (Puzzle.defend), og glipper den tvungne seieren, må du prøve igjen.
## Runde 17: dagens oppgave bytter mellom tre typer (Puzzle.kind_for): tving frem seier (som over),
## «Vinn på N trekk» (stille trekk er lov, motstanderen svarer etter løsningen, line) og «Finn beste
## trekk» (eneste trekk som redder deg; bommer du, vises hvordan motstanderen vinner).
## Løsningen sendes til serveren, som sjekker den og fører listen over dagens løsere.
## Uten nett lages oppgaven lokalt (samme oppgave, siden den lages fra datoen).
## «Flere oppgaver»: oppgavebanken (ai/puzzle_bank.gd) med fire vanskelighetsgrader, 3–6 trekk.
## De løses lokalt, og fremgangen lagres på enheten.

const REPLY_DELAY_S := 0.55
const OFFLINE_AFTER_S := 4.0
const MODES := ["Dagens", "Lett", "Middels", "Vanskelig", "Ekspert"]

var _puzzle: Dictionary = {}
var _daily: Dictionary = {}
var _mode := 0                  ## 0 = dagens oppgave, ellers indeks i PuzzleBank.LEVELS + 1
var _progress: Label
var _next_button: Button
var _daily_box: Control
var _state: GameState
var _me := 1
var _my_moves: Array = []
var _attempts := 1
var _busy := false
var _solved := false
var _shown_solution := false
var _generation := 0
var _panel: MarginContainer
var _scroll: ScrollContainer
var _collapse_button: Button
var _collapsed := false
var _goal: Label
var _legend: HBoxContainer
var _status: Label
var _attempts_label: Label
var _retry_button: Button
var _solution_button: Button
var _solvers_box: VBoxContainer
var _solvers_title: Label
var _tip: Label


func _ready() -> void:
	app.camera.auto_rotate = false
	app.board.input_enabled = false
	app.board.clear_pieces()

	_panel = MarginContainer.new()
	add_child(_panel)
	var card := PanelContainer.new()
	_panel.add_child(card)
	var column := UI.vbox(10)
	card.add_child(column)
	# Fast øverst: tittelen og «Skjul», som legger kortet sammen så hele brettet synes (mobil)
	var head := UI.hbox(8)
	var title := UI.label("Oppgaver", "Heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_collapse_button = UI.button("Skjul", toggle_collapsed, "GhostButton")
	_collapse_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_collapse_button)
	column.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.smooth_scroll(_scroll)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(func() -> void:
		if _collapsed:
			_layout()
	)
	_layout.call_deferred()

	v.add_child(UI.choice(MODES, 0, set_mode))
	_progress = UI.label("", "Muted")
	_progress.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_progress)
	_goal = UI.label("Henter oppgaven…", "", HORIZONTAL_ALIGNMENT_LEFT, true)
	_goal.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_goal)
	_legend = UI.hbox(8)
	v.add_child(_legend)
	_attempts_label = UI.label("", "Muted")
	_attempts_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_attempts_label)
	_tip = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_tip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_tip)

	var daily := UI.vbox(6)
	_daily_box = daily
	_solvers_title = UI.section("Løst i dag")
	daily.add_child(_solvers_title)
	_solvers_box = UI.vbox(4)
	daily.add_child(_solvers_box)
	v.add_child(daily)

	# Fast nederst (synes også når kortet er lagt sammen): status og knappene
	_status = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_status)
	_next_button = UI.button("Neste oppgave", _next_puzzle, "PrimaryButton")
	_next_button.visible = false
	column.add_child(_next_button)
	var row := UI.hbox(8)
	row.add_child(UI.button("Tilbake", _on_back))
	_solution_button = UI.button("Vis løsning", _show_solution)
	_solution_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_solution_button)
	_retry_button = UI.button("Prøv igjen", _retry, "PrimaryButton")
	_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_retry_button)
	column.add_child(row)

	app.board.column_tapped.connect(_on_column_tapped)
	app.board.column_hovered.connect(_on_column_hovered)
	Net.message.connect(_on_message)
	Net.connected.connect(_on_connected)
	if Net.is_online():
		Net.send({ "t": Protocol.GET_PUZZLE })
	else:
		Net.ensure_connected()
	# Svarer ikke serveren, lager vi oppgaven selv (samme oppgave, men uten toppliste).
	await get_tree().create_timer(OFFLINE_AFTER_S).timeout
	if is_inside_tree() and _daily.is_empty():
		_daily = Puzzle.generate(Time.get_date_string_from_system())
		if _mode == 0 and _puzzle.is_empty():
			load_puzzle(_daily)
		_solvers_box.add_child(UI.label("Uten nett: løsningen kommer ikke på listen.", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))


func _exit_tree() -> void:
	app.board.column_tapped.disconnect(_on_column_tapped)
	app.board.column_hovered.disconnect(_on_column_hovered)
	app.board.input_enabled = false
	app.board.clear_hints()
	Engine.time_scale = 1.0


## «Skjul» / «Vis mer»: lagt sammen viser kortet bare tittelen, status og knappene, og brettet får plassen.
func toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_scroll.visible = not _collapsed
	_collapse_button.text = tr("Vis mer") if _collapsed else tr("Skjul")
	_layout()


## Kortet til venstre (PC) eller nederst (mobil), brettet ved siden av.
## Lagt sammen er kortet bare så høyt som det trenger, nederst (mobil) eller øverst til venstre (PC).
func _layout() -> void:
	if _collapsed:
		var h := _panel.get_combined_minimum_size().y
		var portrait := size.y > size.x
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0 if portrait else 0.0
		_panel.anchor_top = 1.0 if portrait else 0.0
		_panel.anchor_bottom = 1.0 if portrait else 0.0
		_panel.offset_left = 10 if portrait else 16
		_panel.offset_right = -10 if portrait else 16 + minf(420.0, size.x * 0.42)
		_panel.offset_top = -10 - h if portrait else 16
		_panel.offset_bottom = -10 if portrait else 16 + h
		app.camera.view_offset = Vector2(0, -1.2) if portrait else Vector2(-1.2, 0)
		return
	if size.y > size.x:
		_panel.anchor_left = 0.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.5
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 10
		_panel.offset_right = -10
		_panel.offset_top = 0
		_panel.offset_bottom = -10
		app.camera.view_offset = Vector2(0, -3.6)
	else:
		var w := minf(420.0, size.x * 0.42)
		_panel.anchor_left = 0.0
		_panel.anchor_right = 0.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 16
		_panel.offset_right = 16 + w
		_panel.offset_top = 16
		_panel.offset_bottom = -16
		app.camera.view_offset = Vector2(-1.8, 0)


func _on_connected(_resumed: bool) -> void:
	Net.send({ "t": Protocol.GET_PUZZLE })


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.PUZZLE:
			var p = msg.get("puzzle")
			if p is Dictionary and not p.is_empty() and str(p.get("day", "")) != str(_daily.get("day", "-")):
				_daily = p
				# Bytt bare hvis ingen oppgave er i gang (ikke midt i et forsøk).
				if _mode == 0 and (_puzzle.is_empty() or _my_moves.is_empty()):
					load_puzzle(p)
			_show_solvers(msg.get("solvers", []), int(msg.get("count", 0)))
			if bool(msg.get("solved", false)) and not _solved:
				_status.text = tr("Du har allerede løst dagens oppgave. Prøv gjerne igjen!")
		Protocol.PUZZLE_RESULT:
			if bool(msg.get("ok", false)):
				var rank := int(msg.get("rank", 0))
				if rank > 0:
					_status.text = tr("Løst! Du er nr. %d i dag.") % rank
				elif not Net.is_logged_in():
					_status.text = tr("Løst! Logg inn for å komme på listen.")
				var xp = msg.get("xp", {})
				if xp is Dictionary and int(xp.get("gained", 0)) > 0:
					_status.text += "\n" + GameScreen.xp_text(xp)
					if int(msg.get("streak", 0)) > 1:
						_status.text += "\n" + tr("%d dager på rad!") % int(msg.streak)
			else:
				_status.text = I18n.server_text(msg)


## Starter en oppgave (fra serveren, eller laget lokalt uten nett).
func load_puzzle(p: Dictionary) -> void:
	if p.is_empty():
		_goal.text = tr("Ingen oppgave i dag.")
		return
	_puzzle = p
	_attempts = 1
	_reset()


## Bytter mellom dagens oppgave (0) og nivåene i oppgavebanken.
func set_mode(i: int) -> void:
	_mode = i
	_daily_box.visible = i == 0
	if i == 0:
		_progress.text = ""
		if not _daily.is_empty():
			load_puzzle(_daily)
		return
	var level: int = PuzzleBank.LEVELS[i - 1]
	var list := _bank(level)
	var next: Dictionary = list[0]
	for p in list:
		if not str(p.id) in Settings.solved_puzzles:
			next = p
			break
	load_puzzle(next)


func _bank(level: int) -> Array:
	return PuzzleBank.PUZZLES.filter(func(p: Dictionary) -> bool: return int(p.depth) == level)


func _update_progress() -> void:
	if _mode == 0:
		_progress.text = ""
		return
	var list := _bank(PuzzleBank.LEVELS[_mode - 1])
	var solved := list.filter(func(p: Dictionary) -> bool: return str(p.id) in Settings.solved_puzzles).size()
	var index := list.find(_puzzle) + 1
	_progress.text = tr("Oppgave %d av %d · %d løst") % [index, list.size(), solved]


func _next_puzzle() -> void:
	var list := _bank(PuzzleBank.LEVELS[_mode - 1])
	var i := list.find(_puzzle)
	load_puzzle(list[(i + 1) % list.size()])


func _reset() -> void:
	_generation += 1
	_state = Puzzle.start_state(_puzzle)
	_me = _state.current_player
	_my_moves.clear()
	_busy = false
	_solved = false
	app.board.setup(_state.size)
	var other := GameState.opponent(_me)
	var pair := Skins.resolve_pair(Settings.look(), Skins.look(Skins.DEFAULT_P2))
	var looks := { _me: pair[0], other: pair[1] }
	app.board.set_looks(looks[1], looks[2])
	for i in _state.cells.size():
		if _state.cells[i] != 0:
			app.board.add_piece(_state.lines.pos_of(i), _state.cells[i], false)
	app.board.input_enabled = true
	var depth := int(_puzzle.get("depth", Puzzle.MIN_DEPTH))
	match _kind():
		"win":
			_goal.text = tr("Vinn på %d trekk! Her holder det ikke bare med trusler: et stille trekk må til. Motstanderen forsvarer seg så godt den kan.") % depth
			_tip.text = tr("Tips: let etter et trekk som forbereder to trusler samtidig, gjerne på kryss og tvers gjennom flere høyder.")
		"defend":
			_goal.text = tr("Finn beste trekk! Motstanderen truer med å tvinge frem seier, og bare ett trekk redder deg.")
			_tip.text = tr("Tips: se etter plassen motstanderen trenger for å lage to trusler samtidig, og ta den først.")
		_:
			_goal.text = tr("Du har tur. Finn den tvungne seieren med %d trekk – motstanderen forsvarer seg så godt den kan.") % depth
			_tip.text = tr("Tips: et tvunget trekk lager en trussel motstanderen må blokkere. Sett opp to trusler samtidig, så vinner du.")
	_goal.add_theme_color_override("font_color", app.board.colors[_me].lerp(Color.WHITE, 0.35))
	_show_legend(looks[_me], looks[other])
	_status.text = ""
	_retry_button.visible = false
	_next_button.visible = false
	_update_attempts()
	_update_progress()


## Viser hvilke brikker som er dine og hvilke som er motstanderens (fargeprikk og skin).
func _show_legend(mine: Dictionary, theirs: Dictionary) -> void:
	for c in _legend.get_children():
		c.queue_free()
	for side in [[mine, tr("Dine brikker")], [theirs, tr("Motstanderen")]]:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI._box(UI.PANEL_LIGHT, 10, Skins.ui_color(side[0]), 10, 6))
		var row := UI.hbox(8)
		row.add_child(UI.dot(Skins.ui_color(side[0]), 16))
		var l := UI.label(side[1])
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_color_override("font_color", Skins.ui_color(side[0]).lerp(Color.WHITE, 0.4))
		row.add_child(l)
		chip.add_child(row)
		_legend.add_child(chip)


func _update_attempts() -> void:
	_attempts_label.text = tr("Forsøk: %d") % _attempts


func _on_column_hovered(col: Vector2i) -> void:
	if not _can_play() or col == BoardView.NO_COLUMN or not _state.is_column_open(col):
		app.board.hide_target()
		return
	app.board.show_target(_state.landing_pos(col), _me, col)


func _on_column_tapped(col: Vector2i, from_touch: bool) -> void:
	if not _can_play() or not _state.is_column_open(col):
		return
	if from_touch and (app.board.target_column() != col or not app.board.ghost_visible()):
		app.board.show_target(_state.landing_pos(col), _me, col, true)
		Sfx.play("click")
		return
	play(col)


func _can_play() -> bool:
	return _state != null and not _busy and not _solved and _state.current_player == _me and not _state.is_over()


## Spiller ditt trekk, og svarer for motstanderen. Brukes også av testene.
func play(col: Vector2i) -> void:
	var err := _state.check_move(col)
	if err != GameState.MoveError.OK:
		_status.text = tr(GameState.error_text(err))
		Sfx.play("error")
		if err == GameState.MoveError.MUST_BLOCK:
			app.board.show_hints(_state.threat_positions(_me))
		return
	app.board.hide_target()
	app.board.clear_hints()
	var r := _state.play(col)
	app.board.add_piece(r.pos, _me)
	Sfx.play("drop")
	_my_moves.append([col.x, col.y])
	if r.won:
		_on_solved()
		return
	if _state.is_over():
		_fail(tr("Brettet ble fullt."))
		return
	match _kind():
		"win":
			_reply_from_line(col)
			return
		"defend":
			_check_defense(col)
			return
	# Et trekk uten trussel gir motstanderen et fritt trekk: da er den tvungne seieren borte.
	var quiet := _state.winning_columns(_me).is_empty()
	_busy = true
	var gen := _generation
	await get_tree().create_timer(REPLY_DELAY_S).timeout
	if not is_inside_tree() or gen != _generation:
		return
	var left := int(_puzzle.depth) - _my_moves.size()
	var reply := Puzzle.defend(_state, 0 if quiet else left)
	var r2 := _state.play(reply, false)
	app.board.add_piece(r2.pos, GameState.opponent(_me))
	Sfx.play("drop", 0.85)
	if quiet:
		_fail(tr("Det trekket truet ingenting, så motstanderen fikk et fritt trekk."))
		return
	if r2.won or _state.is_over() or left <= 0 or Puzzle.win_depth(_state, left) == 0:
		_fail(tr("Motstanderen slapp unna. Den tvungne seieren glapp."))
		return
	_status.text = tr("Bra! %d trekk igjen.") % left
	_busy = false


func _kind() -> String:
	return str(_puzzle.get("kind", "forced"))


## «Vinn på N trekk»: trekket må være neste i løsningen (den er entydig), og motstanderen svarer
## som i løsningen. Siste trekk: alle vinnertrekk godtas (det tar play()).
func _reply_from_line(col: Vector2i) -> void:
	var line: Array = _puzzle.get("line", [])
	var i := (_my_moves.size() - 1) * 2
	if i + 1 >= line.size() or col != Puzzle._vec(line[i]):
		_fail(tr("Ikke det trekket – nå slipper motstanderen unna. Prøv igjen!"))
		return
	_busy = true
	var gen := _generation
	await get_tree().create_timer(REPLY_DELAY_S).timeout
	if not is_inside_tree() or gen != _generation:
		return
	var r2 := _state.play(Puzzle._vec(line[i + 1]), false)
	app.board.add_piece(r2.pos, GameState.opponent(_me))
	Sfx.play("drop", 0.85)
	_status.text = tr("Bra! %d trekk igjen.") % ((line.size() - i - 1) / 2)
	_busy = false


## «Finn beste trekk»: riktig trekk løser oppgaven. Ellers vises motstanderens første trekk i
## seieren (lagret i oppgaven, refute), og du kan prøve igjen.
func _check_defense(col: Vector2i) -> void:
	if col == Puzzle._vec(_puzzle.get("answer", [])):
		_on_solved()
		return
	_busy = true
	var gen := _generation
	await get_tree().create_timer(REPLY_DELAY_S).timeout
	if not is_inside_tree() or gen != _generation:
		return
	var win := Puzzle._vec((_puzzle.get("refute", {}) as Dictionary).get("%d,%d" % [col.x, col.y], []))
	if win.x >= 0 and _state.is_column_open(win):
		var r2 := _state.play(win, false)
		app.board.add_piece(r2.pos, GameState.opponent(_me))
		Sfx.play("drop", 0.85)
		_fail(tr("Da kan motstanderen tvinge frem seier, og slik begynner den. Prøv igjen!"))
	else:
		_fail(tr("Ikke det trekket. Prøv igjen!"))


func _fail(text: String) -> void:
	_busy = true
	_status.text = text
	_retry_button.visible = true
	Sfx.play("lose")


func _retry() -> void:
	_attempts += 1
	_shown_solution = false
	_reset()


func _on_solved() -> void:
	_solved = true
	app.board.input_enabled = false
	if not _state.winning_line.is_empty():
		app.board.highlight(_state.winning_line)
		WinFx.play(app.board, app.camera, _state.winning_line, app.board.colors[_me], Settings.look().win_fx)
	else:
		Sfx.play("win")   # «Finn beste trekk»: ingen fire på rad, bare riktig trekk
	_retry_button.visible = true
	if _shown_solution:
		_status.text = tr("Slik løses den. Prøv selv neste gang!")
		_next_button.visible = _mode != 0
		return
	_status.text = tr("Løst på %d forsøk!") % _attempts
	if _kind() == "defend":
		_status.text = tr("Riktig! Det var det eneste trekket som redder deg. Løst på %d forsøk.") % _attempts
	if _mode != 0:
		if not str(_puzzle.id) in Settings.solved_puzzles:
			Settings.solved_puzzles.append(str(_puzzle.id))
			Settings.save()
		_next_button.visible = true
		_update_progress()
		return
	Settings.puzzle_day = str(_puzzle.get("day", ""))
	Settings.save()
	if Net.is_online():
		Net.send({ "t": Protocol.PUZZLE_SOLVE, "day": _puzzle.get("day", ""), "moves": _my_moves, "attempts": _attempts })


## Spiller av løsningen på brettet (teller ikke som løst).
func _show_solution() -> void:
	if _puzzle.is_empty():
		return
	_shown_solution = true
	_reset()
	_busy = true
	var gen := _generation
	var moves := Puzzle.solution(_puzzle)
	for col in moves:
		await get_tree().create_timer(0.7).timeout
		if not is_inside_tree() or gen != _generation:
			return
		var player := _state.current_player
		var r := _state.play(col, false)
		app.board.add_piece(r.pos, player)
		Sfx.play("drop", 1.0 if player == _me else 0.85)
		if r.won:
			_on_solved()
			return
	if _kind() == "defend":
		_on_solved()


func _show_solvers(list: Array, count: int) -> void:
	for c in _solvers_box.get_children():
		c.queue_free()
	_solvers_title.text = (tr("Løst i dag (%d)") % count).to_upper()
	if list.is_empty():
		_solvers_box.add_child(UI.label("Ingen har løst den ennå. Bli den første!", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for i in list.size():
		var e: Dictionary = list[i]
		var row := UI.hbox(8)
		var place := UI.label("%d." % (i + 1), "Muted")
		place.custom_minimum_size.x = 28
		row.add_child(place)
		row.add_child(EloBadge.make(int(e.get("elo", -1)), 18))
		var name := UI.label(str(e.username))
		name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var tries := UI.label(tr("%d forsøk") % int(e.attempts), "Muted")
		tries.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(tries)
		_solvers_box.add_child(row)


func _on_back() -> void:
	app.show_menu()
