class_name ClientRoot
extends Node
## Roten i klienten: 3D-verdenen (lys, kamera, brett) og UI-laget med én aktiv skjerm.
## Brettet og kameraet lever hele tiden, så menyen kan ha brettet i bakgrunnen.

var world: Node3D
var camera: CameraRig
var board: BoardView
var ui: Control
var current_match: MatchController
var lobby_message := ""       ## Vises øverst i lobbyen (f.eks. «Rommet ble lukket»)
var _banner: Control
var _pending_join := ""       ## romkode fra ?rom= i lenken
var _pending_tournament := 0  ## turnering fra ?turnering= i lenken
var keyboard_height := 0.0    ## Hvor mye av skjermen tastaturet dekker (UI-enheter)
## Hvor mye av nettleservinduet som er dekket nederst (tastatur), i fysiske piksler.
const KEYBOARD_JS := "(function(){var vv=window.visualViewport;if(!vv)return 0;return Math.max(0,window.innerHeight-vv.height-vv.offsetTop)*(window.devicePixelRatio||1);})()"
var _screen: Control
var _keyboard_check := 0.0


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
	Net.message.connect(_on_net_message)
	Net.connected.connect(_on_net_connected)
	show_menu()
	_read_link()


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


## Når skjermtastaturet er oppe på mobil, krymper UI-laget nedenfra slik at
## tekstfeltet (f.eks. chatten) havner over tastaturet.
func _process(delta: float) -> void:
	_keyboard_check -= delta
	if _keyboard_check > 0.0:
		return
	_keyboard_check = 0.15
	var focus := get_viewport().gui_get_focus_owner()
	var px := _keyboard_pixels() if focus is LineEdit else 0.0
	var h := px / maxf(get_window().content_scale_factor, 0.01)
	if absf(h - keyboard_height) < 2.0:
		return
	keyboard_height = h
	ui.offset_bottom = -h
	if focus:
		_reveal.call_deferred(focus)


## Høyden på skjermtastaturet i vinduspiksler (0 hvis det ikke vises).
func _keyboard_pixels() -> float:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval(KEYBOARD_JS, true)
		return float(v) if v != null else 0.0
	if OS.has_feature("mobile"):
		return float(DisplayServer.virtual_keyboard_get_height())
	return 0.0


## Ruller feltet frem hvis det ligger i en rulleliste.
func _reveal(control: Control) -> void:
	var p := control.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(control)
			return
		p = p.get_parent()


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


func show_account() -> void:
	show_screen(AccountScreen.new(self))


func show_profile(username := "") -> void:
	show_screen(ProfileScreen.new(self, username))


func show_tournaments() -> void:
	show_screen(TournamentsScreen.new(self))


func show_tournament(id: int, back_to_menu := false) -> void:
	show_screen(TournamentScreen.new(self, id, back_to_menu))


func show_tournament_edit() -> void:
	show_screen(TournamentEditScreen.new(self))


func join_room(code: String) -> void:
	_hide_banner()
	Net.send({ "t": Protocol.JOIN_ROOM, "code": code })


# ---------------------------------------------------------------- Meldinger som gjelder alle skjermer

func _on_net_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.ROOM_STATE:
			# Ble med i et rom (fra lobbyen, en lenke eller «Gå til kamp»): vis venterommet.
			if not (_screen is RoomScreen or _screen is GameScreen or _screen is SetupScreen):
				show_room(msg)
		Protocol.TOURNAMENT_NOTICE:
			_show_banner(I18n.server_text(msg), str(msg.get("room", "")))
		Protocol.ROOM_CLOSED:
			lobby_message = I18n.server_text(msg)
			if _screen is RoomScreen:
				show_online()


func _on_net_connected(_resumed: bool) -> void:
	if _pending_join != "":
		join_room(_pending_join)
		_pending_join = ""
	elif _pending_tournament != 0:
		show_tournament(_pending_tournament)
		_pending_tournament = 0


## Lenker som https://…/?rom=KXRTA eller ?turnering=3 åpner rommet/turneringen direkte.
func _read_link() -> void:
	if not OS.has_feature("web"):
		return
	var room = JavaScriptBridge.eval("new URLSearchParams(location.search).get('rom') || ''")
	var tour = JavaScriptBridge.eval("new URLSearchParams(location.search).get('turnering') || ''")
	if room is String and room != "":
		_pending_join = room.to_upper()
		show_online()
	elif tour is String and tour.is_valid_int():
		_pending_tournament = int(tour)
		show_online()


## Lager en delbar lenke (web) eller gir koden (PC), og deler/kopierer den. Gir en statustekst.
func share_link(param: String, value: String, title: String) -> String:
	if OS.has_feature("web"):
		var base = JavaScriptBridge.eval("location.origin + location.pathname")
		var link := "%s?%s=%s" % [base, param, value]
		var shared = JavaScriptBridge.eval("(function(){ if (navigator.share) { navigator.share({ title: %s, url: %s }); return true; } return false; })()" \
			% [JSON.stringify(title), JSON.stringify(link)], true)
		if shared == true:
			return ""
		DisplayServer.clipboard_set(link)
		return tr("Lenken er kopiert: %s") % link
	DisplayServer.clipboard_set(value)
	return tr("Koden %s er kopiert.") % value


func _show_banner(text: String, room: String) -> void:
	_hide_banner()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var row := UI.hbox(12)
	panel.add_child(row)
	var label := UI.label(text)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(label)
	if room != "":
		row.add_child(UI.button("Gå til kamp", func() -> void: join_room(room), "PrimaryButton"))
	row.add_child(UI.button("×", _hide_banner, "GhostButton"))
	ui.add_child(margin)
	_banner = margin
	Sfx.play("win", 1.4)
	Settings.vibrate(120)


func _hide_banner() -> void:
	if _banner and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = null


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
