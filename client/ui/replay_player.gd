class_name ReplayPlayer
extends PanelContainer
## Avspiller for et ferdig parti på brettet: hopp, fram og tilbake, spill av, og en tidslinje
## der tvungne trekk er markert. På brettet vises plassen motstanderen må blokkere.
## Brukes av resultatskjermen («Se partiet igjen») og av ReplayScreen (partier fra profilen).

signal closed

const STEP_S := 0.9

var board: BoardView
var options: GameOptions
var first_player := 1
var moves: Array = []
var names := { 1: "", 2: "" }
var colors := { 1: Color.WHITE, 2: Color.WHITE }
var entries: Array = []
var ply := 0
var _playing := false
var _timer := 0.0
var _timeline: ReplayTimeline
var _count: Label
var _info: Label
var _play_button: Button
var _show_close := true
static var _icons: Dictionary = {}


func _init(p_board: BoardView, p_options: GameOptions, p_first: int, p_moves: Array, p_names: Dictionary,
		p_colors: Dictionary, show_close := true) -> void:
	board = p_board
	options = p_options
	first_player = p_first
	moves = p_moves
	names = p_names
	colors = p_colors
	_show_close = show_close
	entries = GameAnalysis.timeline(options, first_player, moves)


func _ready() -> void:
	var v := UI.vbox(8)
	add_child(v)
	var top := UI.hbox(10)
	_count = UI.label("", "Muted")
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	top.add_child(_count)
	_info = UI.label("", "", HORIZONTAL_ALIGNMENT_RIGHT)
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.clip_text = true
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_info)
	v.add_child(top)

	_timeline = ReplayTimeline.new()
	_timeline.entries = entries
	_timeline.colors = colors
	_timeline.seek_requested.connect(func(n: int) -> void:
		_playing = false
		seek(n)
	)
	v.add_child(_timeline)

	var row := UI.hbox(6)
	row.add_child(_icon_button("first", func() -> void: _stop_and(func() -> void: seek(0))))
	row.add_child(_icon_button("prev", func() -> void: _stop_and(func() -> void: seek(ply - 1))))
	_play_button = _icon_button("play", _toggle_play)
	_play_button.theme_type_variation = "PrimaryButton"
	_play_button.custom_minimum_size.x = 64
	row.add_child(_play_button)
	row.add_child(_icon_button("next", func() -> void: _stop_and(func() -> void: seek(ply + 1, true))))
	row.add_child(_icon_button("last", func() -> void: _stop_and(func() -> void: seek(entries.size()))))
	var legend := UI.label("Tvunget trekk", "Muted")
	legend.add_theme_color_override("font_color", ReplayTimeline.FORCED)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(legend)
	if _show_close:
		row.add_child(UI.button("Lukk", func() -> void:
			_playing = false
			closed.emit()
		))
	v.add_child(row)
	seek(0)


func _process(delta: float) -> void:
	if not _playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP_S
		if ply >= entries.size():
			_set_playing(false)
		else:
			seek(ply + 1, true)


## Viser stillingen etter n trekk. Med animate faller det siste trekket ned.
func seek(n: int, animate := false) -> void:
	n = clampi(n, 0, entries.size())
	ply = n
	board.clear_pieces()
	board.clear_hints()
	var s := GameState.new(options, first_player)
	for i in n:
		var e: Dictionary = entries[i]
		s.play(e.col, false)
		board.add_piece(e.pos, int(e.player), animate and i == n - 1)
	if not s.winning_line.is_empty():
		board.highlight(s.winning_line)
	_timeline.ply = n
	_count.text = tr("Trekk %d av %d") % [n, entries.size()]
	_info.text = ""
	_info.remove_theme_color_override("font_color")
	if n == 0:
		return
	var e: Dictionary = entries[n - 1]
	var me := int(e.player)
	var opp := GameState.opponent(me)
	if e.won:
		_info.text = tr("%s fikk fire på rad!") % names[me]
		_info.add_theme_color_override("font_color", ReplayTimeline.WIN)
	elif e.double:
		_info.text = tr("Dobbel trussel! %s kan ikke blokkere begge.") % names[opp]
		_info.add_theme_color_override("font_color", ReplayTimeline.DOUBLE)
		board.show_hints(e.threats)
	elif e.forced:
		_info.text = tr("Tvunget trekk: %s må blokkere.") % names[opp]
		_info.add_theme_color_override("font_color", ReplayTimeline.FORCED)
		board.show_hints(e.threats)
	elif n >= 2 and entries[n - 2].forced:
		_info.text = tr("%s blokkerte.") % names[me]


func _toggle_play() -> void:
	if not _playing and ply >= entries.size():
		seek(0)
	_set_playing(not _playing)
	_timer = 0.15


func _set_playing(on: bool) -> void:
	_playing = on
	_play_button.icon = _icon("pause" if on else "play")


func _stop_and(f: Callable) -> void:
	_set_playing(false)
	f.call()


func _icon_button(kind: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.icon = _icon(kind)
	b.custom_minimum_size = Vector2(48, 42)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		on_pressed.call()
	)
	return b



## Små ikoner tegnet i kode: trekanter og streker (fonten har ikke avspillersymboler).
static func _icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var px := 36
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var cover := 0.0
			for sy in 3:
				for sx in 3:
					var p := Vector2((x + (sx + 0.5) / 3.0) / px * 2.0 - 1.0, (y + (sy + 0.5) / 3.0) / px * 2.0 - 1.0)
					if _inside(kind, p):
						cover += 1.0 / 9.0
			if cover > 0.0:
				img.set_pixel(x, y, Color(UI.TEXT, cover))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(18, 18))
	_icons[kind] = tex
	return tex


static func _inside(kind: String, p: Vector2) -> bool:
	# Trekant mot høyre/venstre med midtpunkt cx og halv bredde w, og en loddrett strek.
	var right := func(cx: float, w: float) -> bool: return absf(p.y) <= 0.62 * (1.0 - (p.x - (cx - w)) / (2.0 * w)) and p.x >= cx - w
	var left := func(cx: float, w: float) -> bool: return absf(p.y) <= 0.62 * (1.0 - ((cx + w) - p.x) / (2.0 * w)) and p.x <= cx + w
	var bar := func(cx: float) -> bool: return absf(p.x - cx) <= 0.1 and absf(p.y) <= 0.62
	match kind:
		"play": return right.call(0.08, 0.5)                                       # stor ▶
		"pause": return bar.call(-0.28) or bar.call(0.28)
		"next": return right.call(-0.12, 0.34) or bar.call(0.42)                   # ▶|  ett trekk fram
		"prev": return left.call(0.12, 0.34) or bar.call(-0.42)                    # |◀  ett trekk tilbake
		"last": return right.call(-0.42, 0.3) or right.call(0.12, 0.3) or bar.call(0.58)   # ▶▶|
		"first": return left.call(0.42, 0.3) or left.call(-0.12, 0.3) or bar.call(-0.58)   # |◀◀
	return false
