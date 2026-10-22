class_name ReplayScreen
extends Screen
## Reprise av et lagret parti (fra profilen): hvem som spilte, resultatet og avspilleren.
## record er et parti fra serveren (games.jsonl): { options, first, moves, players, result, reason, time }.

var record: Dictionary
var player: ReplayPlayer
var _back: Callable


func _init(p_app: ClientRoot, p_record: Dictionary, back: Callable) -> void:
	super(p_app)
	record = p_record
	_back = back


func _ready() -> void:
	app.camera.auto_rotate = false
	app.board.input_enabled = false
	var options := GameOptions.from_dict(record.get("options", {}) if record.get("options") is Dictionary else {})
	app.board.setup(options.size)

	# Utseendet fra partiet (eldre partier har ikke skin lagret: da brukes standardfargene)
	var recs: Array = record.get("players", [])
	var looks := []
	var names := {}
	for i in 2:
		var rec: Dictionary = recs[i] if i < recs.size() and recs[i] is Dictionary else {}
		names[i + 1] = str(rec.get("name", tr("Spiller %d") % (i + 1)))
		looks.append(Skins.look(str(rec.get("skin", Skins.DEFAULT_P1 if i == 0 else Skins.DEFAULT_P2)),
			str(rec.get("decal", "none")), "classic", false, str(rec.get("decal_color", "auto"))))
	var pair := Skins.resolve_pair(looks[0], looks[1])
	app.board.set_looks(pair[0], pair[1])
	var colors := { 1: Skins.ui_color(pair[0]), 2: Skins.ui_color(pair[1]) }

	# Toppen: spillerne og resultatet
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + side, 12)
	add_child(top)
	var card := PanelContainer.new()
	top.add_child(card)
	var head := UI.hbox(10)
	card.add_child(head)
	head.add_child(UI.button("Tilbake", _on_back, "GhostButton"))
	var texts := UI.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.label(str(names[1]) + "  –  " + str(names[2]))
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	texts.add_child(title)
	var sub := UI.label(_result_text(names) + "  ·  " + str(record.get("time", "")).replace("T", " ").substr(0, 16), "Muted")
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	texts.add_child(sub)
	head.add_child(texts)
	for i in 2:
		var rec: Dictionary = recs[i] if i < recs.size() and recs[i] is Dictionary else {}
		if int(rec.get("elo", -1)) >= 0:
			head.add_child(EloBadge.make(int(rec.elo), 22))

	# Bunnen: avspilleren
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for side in ["left", "right", "bottom"]:
		bottom.add_theme_constant_override("margin_" + side, 12)
	add_child(bottom)
	player = ReplayPlayer.new(app.board, options, int(record.get("first", 1)), record.get("moves", []), names,
		colors, false)
	bottom.add_child(player)


func _result_text(names: Dictionary) -> String:
	var result := int(record.get("result", 0))
	if result == GameState.Result.DRAW:
		return tr("Uavgjort")
	if result == GameState.Result.P1_WON:
		return tr("%s vant!") % names[1]
	if result == GameState.Result.P2_WON:
		return tr("%s vant!") % names[2]
	return ""


func _on_back() -> void:
	app.board.clear_pieces()
	app.board.clear_hints()
	_back.call()
