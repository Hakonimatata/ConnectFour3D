class_name Screen
extends Control
## Base for alle skjermer (meny, oppsett, spill, ...). ClientRoot viser én om gangen.

var app: ClientRoot


func _init(p_app: ClientRoot) -> void:
	app = p_app
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Tilbake-knappen på Android og Esc på PC.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _on_back() -> void:
	pass
