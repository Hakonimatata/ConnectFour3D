class_name LevelView
extends VBoxContainer
## Nivået og XP-en (runde 17): «Nivå 6», en stolpe mot neste nivå og «1 120 / 1 350 XP».
## Brukes i innstillingene, på profilen og i resultatet etter et parti.

var _title: Label
var _bar: ProgressBar
var _detail: Label


func _init(progress := {}) -> void:
	add_theme_constant_override("separation", 4)
	var row := UI.hbox(8)
	_title = UI.label("", "")
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_size_override("font_size", 18)
	row.add_child(_title)
	_detail = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
	_detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_detail)
	add_child(row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	var bg := UI._box(UI.PANEL_LIGHT, 5, UI.BORDER, 0, 0)
	var fill := UI._box(Color("e8c35a"), 5, Color(0, 0, 0, 0), 0, 0)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	add_child(_bar)
	set_progress(progress)


func set_progress(progress: Dictionary) -> void:
	var xp := int(progress.get("xp", 0))
	var level := Progression.level_for(xp)
	var from := Progression.xp_for_level(level)
	var to := Progression.xp_for_level(level + 1)
	_title.text = I18n.t("Nivå %d") % level
	_detail.text = I18n.t("%d / %d XP") % [xp, to]
	_bar.max_value = to - from
	_bar.value = xp - from
