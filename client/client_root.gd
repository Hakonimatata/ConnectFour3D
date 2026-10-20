class_name ClientRoot
extends Node
## Roten i klienten: 3D-verdenen (lys, kamera, brett) og UI-laget med én aktiv skjerm.
## Brettet og kameraet lever hele tiden, så menyen kan ha brettet i bakgrunnen.

var world: Node3D
var camera: CameraRig
var board: BoardView
var ui: Control
var current_match: MatchController
var _screen: Control


func _ready() -> void:
	_build_world()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UI.build_theme()
	layer.add_child(ui)

	get_window().size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	show_menu()


func _build_world() -> void:
	world = Node3D.new()
	add_child(world)

	# Bakgrunn: en gradient tegnet på et eget lag bak 3D-verdenen (BG_CANVAS).
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = preload("res://assets/shaders/background.gdshader")
	bg_mat.set_shader_parameter("top_color", UI.BG_TOP)
	bg_mat.set_shader_parameter("bottom_color", UI.BG_BOTTOM)
	bg_mat.set_shader_parameter("glow_color", UI.BG_GLOW)
	bg.material = bg_mat
	bg_layer.add_child(bg)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9aa1ae")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.85
	sun.shadow_opacity = 0.5   # mykere, mindre kontrastfylte skygger
	sun.light_color = Color("fff7ee")
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	world.add_child(sun)

	camera = CameraRig.new()
	world.add_child(camera)
	board = BoardView.new()
	board.camera_rig = camera
	world.add_child(board)


## Skalerer UI etter skjermen: større på store skjermer, tettere på mobil.
## (Stretch-modus er «disabled», så 3D tegnes i full oppløsning.)
func _update_ui_scale() -> void:
	var win := get_window()
	var px := Vector2(win.size)
	var dpr := 1.0
	if OS.has_feature("web") or OS.has_feature("mobile"):
		dpr = maxf(1.0, DisplayServer.screen_get_scale())
	var logical := px / dpr
	var adapt := clampf(minf(logical.x, logical.y) / 760.0, 0.8, 1.3)
	win.content_scale_factor = dpr * adapt


# ---------------------------------------------------------------- Navigasjon

func show_screen(screen: Control) -> void:
	if _screen:
		_screen.queue_free()
	camera.view_offset = Vector2.ZERO
	_screen = screen
	ui.add_child(screen)


func show_menu() -> void:
	_end_match()
	show_screen(MainMenu.new(self))


func show_setup(mode: String, on_confirm := Callable(), on_cancel := Callable()) -> void:
	show_screen(SetupScreen.new(self, mode, on_confirm, on_cancel))


func show_settings() -> void:
	show_screen(SettingsScreen.new(self))


func show_online() -> void:
	_end_match()
	show_screen(LobbyScreen.new(self))


func show_room(room_state: Dictionary) -> void:
	show_screen(RoomScreen.new(self, room_state))


## Kalles fra oppsett-skjermen (online). Ligger her fordi skjermene byttes ut underveis.
func online_create_room(options: GameOptions, private: bool) -> void:
	Net.send({ "t": Protocol.CREATE_ROOM, "options": options.to_dict(), "private": private })
	show_online()   # lobbyen bytter til venterommet når serveren svarer


func online_set_options(options: GameOptions, _private: bool, room_state: Dictionary) -> void:
	Net.send({ "t": Protocol.SET_OPTIONS, "options": options.to_dict() })
	show_room(room_state)


func start_match(m: MatchController) -> void:
	_end_match()
	current_match = m
	add_child(m)
	board.clear_pieces()
	show_screen(GameScreen.new(self, m))
	m.start_game()


func _end_match() -> void:
	Engine.time_scale = 1.0
	board.clear_pieces()
	if current_match:
		current_match.leave()
		current_match.queue_free()
		current_match = null
