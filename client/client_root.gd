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
## Hvor mye av spillflaten (canvas) som ikke synes øverst og nederst, i canvas-piksler («topp,bunn»).
## Måles mot canvas og ikke innerHeight, fordi noen nettlesere krymper innerHeight med tastaturet
## og andre ikke, og noen skyver siden opp i stedet.
const KEYBOARD_JS := "(function(){var vv=window.visualViewport,c=document.getElementById('canvas');if(!vv||!c)return '0,0';var r=c.getBoundingClientRect();if(r.height<=0)return '0,0';var s=c.height/r.height;return (Math.max(0,vv.offsetTop-r.top)*s)+','+(Math.max(0,r.bottom-vv.offsetTop-vv.height)*s);})()"
var _screen: Control
var _keyboard_check := 0.0
var _keyboard_top := 0.0
var _keyboard_focus: Control
var _keyboard_window := Vector2i.ZERO


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
	get_tree().node_added.connect(_on_node_added)
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


## Når skjermtastaturet er oppe på mobil, krymper UI-laget til den delen av skjermen som synes,
## slik at tekstfeltet (chat, innstillinger) havner over tastaturet. Feltet rulles frem når
## tastaturet, vindusstørrelsen eller feltet med fokus endrer seg.
func _process(delta: float) -> void:
	_keyboard_check -= delta
	if _keyboard_check > 0.0:
		return
	_keyboard_check = 0.15
	var focus := get_viewport().gui_get_focus_owner()
	var editing := focus is LineEdit
	var hidden := _hidden_pixels() if editing else Vector2.ZERO
	var scale := maxf(get_window().content_scale_factor, 0.01)
	var top := hidden.x / scale
	var bottom := hidden.y / scale
	var moved := absf(bottom - keyboard_height) >= 2.0 or absf(top - _keyboard_top) >= 2.0
	if moved:
		keyboard_height = bottom
		_keyboard_top = top
		ui.offset_top = top
		ui.offset_bottom = -bottom
	var win := get_window().size
	if editing and (moved or focus != _keyboard_focus or win != _keyboard_window):
		_reveal(focus)
	_keyboard_focus = focus
	_keyboard_window = win


## Hvor mye av vinduet som er skjult øverst (x) og nederst (y), i vinduspiksler.
func _hidden_pixels() -> Vector2:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval(KEYBOARD_JS, true)
		var parts := str(v).split(",")
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
		return Vector2.ZERO
	if OS.has_feature("mobile"):
		return Vector2(0.0, float(DisplayServer.virtual_keyboard_get_height()))
	return Vector2.ZERO


## Ruller feltet frem hvis det ligger i en rulleliste. Venter til oppsettet har fått ny størrelse.
func _reveal(control: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	var p := control.get_parent()
	while p != null:
		if p is ScrollContainer:
			var old = p.get_meta("scroll_tween") if p.has_meta("scroll_tween") else null
			if old is Tween and (old as Tween).is_valid():
				(old as Tween).kill()   # et sveip som fortsatt ruller, skal ikke dra feltet bort igjen
			(p as ScrollContainer).ensure_control_visible(control)
			return
		p = p.get_parent()


## Skalerer UI etter skjermen: større på store skjermer, tettere på mobil.
## (Stretch-modus er «disabled», så 3D tegnes i full oppløsning.)
## Knapper og felt inne i en ScrollContainer slipper musen/fingeren videre (PASS i stedet for STOP).
## Da kan man scrolle ved å dra, også når fingeren starter på en knapp (f.eks. skin-knappene).
## Paneler utenfor en rulleliste (menykortet, chatten, banneret) stopper musen og fingrene, så
## scrolling over dem ikke zoomer brettet bak. Uten det slapp de gjennom alt som ikke traff en knapp.
func _on_node_added(n: Node) -> void:
	var c := n as Control
	if c == null:
		return
	var in_scroll := false
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			in_scroll = true
			break
		p = p.get_parent()
	if c is PanelContainer and not in_scroll and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		# Musehjul og fingerbevegelser går videre selv med STOP hvis ingen bruker dem. Panelet tar dem.
		c.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if (mb and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT,
					MOUSE_BUTTON_WHEEL_RIGHT]) or e is InputEventGesture or e is InputEventScreenTouch \
					or e is InputEventScreenDrag:
				c.accept_event()
		)
		return
	if in_scroll and c.mouse_filter == Control.MOUSE_FILTER_STOP and not (c is ScrollContainer or c is Range):
		c.mouse_filter = Control.MOUSE_FILTER_PASS


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


## back_to_menu: åpnet fra hovedmenyen, så «Tilbake» (og innlogging) går dit i stedet for til lobbyen.
func show_account(back_to_menu := false) -> void:
	show_screen(AccountScreen.new(self, back_to_menu))


func show_profile(username := "", back_to_menu := false) -> void:
	show_screen(ProfileScreen.new(self, username, back_to_menu))


func show_tournaments() -> void:
	show_screen(TournamentsScreen.new(self))


func show_tournament(id: int, back_to_menu := false) -> void:
	show_screen(TournamentScreen.new(self, id, back_to_menu))


func show_tournament_edit() -> void:
	show_screen(TournamentEditScreen.new(self))


func show_admin() -> void:
	show_screen(AdminScreen.new(self))


func show_puzzle() -> void:
	_end_match()
	show_screen(PuzzleScreen.new(self))


## Reprise av et lagret parti. back kalles når spilleren trykker «Tilbake».
func show_replay(record: Dictionary, back: Callable) -> void:
	_end_match()
	show_screen(ReplayScreen.new(self, record, back))


## Avslutter partiet som vises (f.eks. når en tilskuer går tilbake til turneringen).
func end_match() -> void:
	_end_match()


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
		Protocol.GLOBAL_MSG:
			# Kunngjøring fra admin: banner hos alle som er online (historikken gir ikke banner)
			if str(msg.get("kind", "")) == "announcement":
				_show_banner(tr("Kunngjøring: %s") % str(msg.get("text", "")), "")
		Protocol.ERROR:
			if msg.get("code") == "banned":
				_show_banner(I18n.server_text(msg), "")
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # lange kunngjøringer brytes over flere linjer
	label.custom_minimum_size.x = clampf(text.length() * 9.0, 120.0, maxf(160.0, minf(480.0, ui.size.x - 170.0)))
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
