class_name BoardView
extends Node3D
## 3D-visningen av brettet. Bygges i kode ut fra størrelsen (4×4×4, 5×5×5, ...).
## Vet ingenting om regler. Den viser brikker og sier fra når en kolonne trykkes.
##
## Koordinater: regelmotoren bruker (x, y) = kolonne og z = høyde.
## Godot har Y opp, så grid_to_world() oversetter (x, y, z) -> (X, Y=z, Z=y).
##
## Velge kolonne: man trykker på flaten man vil legge brikken oppå. Det er enten
## ruten på brettet eller toppen av den øverste brikken. Hver kolonne har en flat
## «klikkflate» der neste brikke vil lande, og hver brikke har en egen
## kollisjonsform, slik at et trykk på siden av en brikke også velger kolonnen.

signal column_tapped(col: Vector2i, from_touch: bool)
signal column_hovered(col: Vector2i)   ## (-1, -1) = ingen

const NO_COLUMN := Vector2i(-1, -1)
const SPACING := 1.0          ## Avstand mellom kolonner
const LAYER := 0.52           ## Høyde per brikke
const PIECE_SCALE := 4.0      ## piece.obj er 0,17 bred, 0,126 høy
const PIECE_RADIUS := 0.35    ## Radius etter skalering
const BOARD_MARGIN := 0.4     ## Kant utenfor rutenettet
const BOARD_THICKNESS := 0.22
const DRAG_THRESHOLD := 10.0  ## Piksler før et trykk regnes som dra (roter)
const PICK_LAYER := 2

var size := 4
var camera_rig: CameraRig
var input_enabled := false
var colors := { 1: Skins.color_of(Skins.DEFAULT_P1), 2: Skins.color_of(Skins.DEFAULT_P2) }

var _piece_mesh: Mesh = preload("res://assets/models/piece.obj")
var _toon: Shader = preload("res://assets/shaders/toon.gdshader")
var _board_top: Shader = preload("res://assets/shaders/board_top.gdshader")
var _static_root: Node3D
var _pieces_root: Node3D
var _hints_root: Node3D
var _pieces: Dictionary = {}    ## Vector3i -> MeshInstance3D (selve brikken)
var _slots: Dictionary = {}     ## Vector2i -> StaticBody3D (klikkflaten der neste brikke lander)
var _heights: Dictionary = {}   ## Vector2i -> antall brikker i kolonnen
var _marker: MeshInstance3D     ## Ring som viser hvor man peker
var _ghost: MeshInstance3D      ## Gjennomsiktig brikke (valgt kolonne på touch)
var _target_col := NO_COLUMN
var _hover_col := NO_COLUMN

# Input-tilstand
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _touches: Dictionary = {}   ## finger-indeks -> posisjon
var _pinch_distance := 0.0
var _last_touch_ms := -10_000


func _ready() -> void:
	_static_root = Node3D.new()
	_pieces_root = Node3D.new()
	_hints_root = Node3D.new()
	add_child(_static_root)
	add_child(_pieces_root)
	add_child(_hints_root)

	_ghost = MeshInstance3D.new()
	_ghost.mesh = _piece_mesh
	_ghost.scale = Vector3.ONE * PIECE_SCALE
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _transparent(Color(1, 1, 1, 0.3))
	_ghost.visible = false
	add_child(_ghost)

	var ring := TorusMesh.new()
	ring.inner_radius = PIECE_RADIUS * 0.82
	ring.outer_radius = PIECE_RADIUS * 1.02
	ring.rings = 48
	ring.ring_segments = 8
	_marker = MeshInstance3D.new()
	_marker.mesh = ring
	_marker.scale = Vector3(1, 0.12, 1)   # flat ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.material_override = _transparent(Color(1, 1, 1, 0.6))
	_marker.visible = false
	add_child(_marker)
	var pulse := _marker.create_tween().set_loops()
	pulse.tween_method(_set_marker_alpha, 0.35, 0.7, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_method(_set_marker_alpha, 0.7, 0.35, 0.7).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- Oppsett

func setup(p_size: int) -> void:
	size = p_size
	clear_pieces()
	for c in _static_root.get_children():
		c.queue_free()
	_slots.clear()

	var width := size * SPACING + BOARD_MARGIN * 2.0
	var board := MeshInstance3D.new()
	board.mesh = BoardMesh.build(width, BOARD_THICKNESS, 0.38)
	var top := ShaderMaterial.new()
	top.shader = _board_top
	top.set_shader_parameter("cells", float(size))
	top.set_shader_parameter("spacing", SPACING)
	board.mesh.surface_set_material(0, top)
	var side := StandardMaterial3D.new()
	side.albedo_color = Color("1f232b")
	side.roughness = 0.7
	board.mesh.surface_set_material(1, side)
	_static_root.add_child(board)

	var slot_shape := BoxShape3D.new()
	slot_shape.size = Vector3(SPACING * 0.94, 0.06, SPACING * 0.94)
	for x in size:
		for y in size:
			var col := Vector2i(x, y)
			var slot := _pick_body(col)
			var shape := CollisionShape3D.new()
			shape.shape = slot_shape
			slot.add_child(shape)
			_static_root.add_child(slot)
			_slots[col] = slot
			_heights[col] = 0
			_place_slot(col)

	if camera_rig:
		camera_rig.frame_board(width, size * LAYER)


func set_colors(p1: Color, p2: Color) -> void:
	colors = { 1: p1, 2: p2 }


func grid_to_world(p: Vector3i) -> Vector3:
	var half := (size - 1) * SPACING * 0.5
	return Vector3(p.x * SPACING - half, p.z * LAYER, p.y * SPACING - half)


func center_of(positions: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in positions:
		sum += grid_to_world(p)
	return sum / maxf(1.0, positions.size()) + Vector3(0, LAYER * 0.5, 0)


# ---------------------------------------------------------------- Brikker

func clear_pieces() -> void:
	for c in _pieces_root.get_children():
		c.queue_free()
	_pieces.clear()
	for col in _slots:
		_heights[col] = 0
		_place_slot(col)
	clear_hints()
	hide_target()


## Legger til en brikke. Med animate faller den ned og spretter.
func add_piece(pos: Vector3i, player: int, animate := true) -> void:
	var col := Vector2i(pos.x, pos.y)
	var root := Node3D.new()        # uskalert, så kollisjonsformen ikke skaleres
	_pieces_root.add_child(root)

	var piece := MeshInstance3D.new()
	piece.mesh = _piece_mesh
	piece.scale = Vector3.ONE * PIECE_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = _toon
	mat.set_shader_parameter("base_color", colors[player])
	piece.material_override = mat
	piece.set_meta("player", player)
	root.add_child(piece)
	_pieces[pos] = piece

	var body := _pick_body(col)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = PIECE_RADIUS
	cyl.height = LAYER * 0.96
	shape.shape = cyl
	shape.position.y = LAYER * 0.48
	body.add_child(shape)
	root.add_child(body)

	_heights[col] = maxi(_heights.get(col, 0), pos.z + 1)
	_place_slot(col)

	var target := grid_to_world(pos)
	if not animate:
		root.position = target
		return
	root.position = target + Vector3(0, size * LAYER + 1.2 - pos.z * LAYER * 0.5, 0)
	var t := root.create_tween()
	t.tween_property(root, "position", target, 0.42).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Lar vinnerbrikkene pulsere med glød.
func highlight(positions: Array) -> void:
	for p in positions:
		if not _pieces.has(p):
			continue
		var piece: MeshInstance3D = _pieces[p]
		var mat: ShaderMaterial = piece.material_override
		var t := piece.create_tween().set_loops()
		t.tween_method(_set_emission.bind(mat), 0.4, 1.6, 0.45)
		t.tween_method(_set_emission.bind(mat), 1.6, 0.4, 0.45)
		var bump := piece.create_tween()
		bump.tween_property(piece, "scale", Vector3.ONE * PIECE_SCALE * 1.18, 0.15)
		bump.tween_property(piece, "scale", Vector3.ONE * PIECE_SCALE, 0.3)


## Gjør alle brikker som ikke er i vinnerlinjen litt mørkere.
func dim_except(positions: Array) -> void:
	for p in _pieces:
		if p in positions:
			continue
		var piece: MeshInstance3D = _pieces[p]
		var mat: ShaderMaterial = piece.material_override
		var player: int = piece.get_meta("player")
		mat.set_shader_parameter("base_color", Color(colors[player]).darkened(0.55))


func _set_emission(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("emission_energy", value)


# ---------------------------------------------------------------- Markør, spøkelsesbrikke og hint

## Viser hvor neste brikke havner: en rolig ring på flaten.
## with_ghost viser i tillegg en gjennomsiktig brikke (brukes når en kolonne er valgt på touch).
func show_target(pos: Vector3i, player: int, col: Vector2i, with_ghost := false) -> void:
	_target_col = col
	var at := grid_to_world(pos)
	var tint: Color = Color(colors[player]).lerp(Color.WHITE, 0.35)
	_marker.position = at + Vector3(0, 0.012, 0)
	(_marker.material_override as StandardMaterial3D).albedo_color = Color(tint, _marker_alpha())
	_marker.visible = true
	_ghost.visible = with_ghost
	if with_ghost:
		_ghost.position = at
		(_ghost.material_override as StandardMaterial3D).albedo_color = Color(colors[player], 0.32)


func hide_target() -> void:
	_target_col = NO_COLUMN
	_hover_col = NO_COLUMN   # så markøren kommer tilbake (med ny høyde) neste frame
	if _marker:
		_marker.visible = false
		_ghost.visible = false


## Kolonnen som er valgt/pekt på, eller NO_COLUMN.
func target_column() -> Vector2i:
	return _target_col


func ghost_visible() -> bool:
	return _ghost.visible


func _marker_alpha() -> float:
	return (_marker.material_override as StandardMaterial3D).albedo_color.a


func _set_marker_alpha(a: float) -> void:
	var m := _marker.material_override as StandardMaterial3D
	m.albedo_color.a = a


## Viser pulserende hvite plasser (f.eks. der man må blokkere).
func show_hints(positions: Array) -> void:
	clear_hints()
	for p in positions:
		var h := MeshInstance3D.new()
		h.mesh = _piece_mesh
		h.scale = Vector3.ONE * PIECE_SCALE
		h.position = grid_to_world(p)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := _transparent(Color(1, 1, 1, 0.4))
		h.material_override = m
		_hints_root.add_child(h)
		var t := h.create_tween().set_loops()
		t.tween_property(m, "albedo_color:a", 0.08, 0.5)
		t.tween_property(m, "albedo_color:a", 0.4, 0.5)


func clear_hints() -> void:
	if _hints_root:
		for c in _hints_root.get_children():
			c.queue_free()


# ---------------------------------------------------------------- Klikkflater

func _pick_body(col: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("col", col)
	return body


## Flytter klikkflaten til toppen av kolonnen. Full kolonne = ingen flate.
func _place_slot(col: Vector2i) -> void:
	var slot: StaticBody3D = _slots.get(col)
	if slot == null:
		return
	var h: int = _heights.get(col, 0)
	var full := h >= size
	slot.position = grid_to_world(Vector3i(col.x, col.y, h)) + Vector3(0, 0.03, 0)
	for c in slot.get_children():
		(c as CollisionShape3D).disabled = full


# ---------------------------------------------------------------- Input (mus og touch)

func pick_column(screen_pos: Vector2) -> Vector2i:
	if camera_rig == null or camera_rig.camera == null:
		return NO_COLUMN
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to, PICK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("col"):
		return NO_COLUMN
	return hit.collider.get_meta("col")


func _unhandled_input(event: InputEvent) -> void:
	if camera_rig == null:
		return

	# Flere fingre: knip for å zoome. Én finger håndteres som mus (Godot emulerer det).
	if event is InputEventScreenTouch:
		_last_touch_ms = Time.get_ticks_msec()
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			_dragging = true
			_pinch_distance = _touch_spread()
		return
	if event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _touch_spread()
			if _pinch_distance > 0.0 and d > 0.0:
				camera_rig.zoom(_pinch_distance / d)
			_pinch_distance = d
		return
	if event is InputEventMagnifyGesture:
		camera_rig.zoom(1.0 / event.factor)
		return
	if event is InputEventPanGesture:
		camera_rig.orbit(event.delta * 6.0)
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: camera_rig.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: camera_rig.zoom(1.1)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_pressing = true
					_dragging = event.button_index == MOUSE_BUTTON_RIGHT
					_press_pos = event.position
				else:
					var was_tap := _pressing and not _dragging and _touches.size() < 2
					_pressing = false
					_dragging = false
					if was_tap and input_enabled and event.button_index == MOUSE_BUTTON_LEFT:
						var col := pick_column(event.position)
						if col != NO_COLUMN:
							column_tapped.emit(col, _is_touch())
		return

	if event is InputEventMouseMotion:
		if _pressing:
			if not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
			if _dragging and _touches.size() < 2:
				camera_rig.orbit(event.relative)
		elif input_enabled and not _is_touch():
			_update_hover(event.position)


## Kameraet kan bevege seg uten at musen gjør det, så hover sjekkes også hver frame.
func _process(_delta: float) -> void:
	if input_enabled and not _pressing and not _is_touch() and camera_rig != null:
		_update_hover(get_viewport().get_mouse_position())


## Tvinger frem en ny hover-melding (f.eks. når det blir din tur igjen).
func refresh_hover() -> void:
	_hover_col = NO_COLUMN


func _update_hover(screen_pos: Vector2) -> void:
	var col := pick_column(screen_pos)
	if col != _hover_col:
		_hover_col = col
		column_hovered.emit(col)


func _is_touch() -> bool:
	return Time.get_ticks_msec() - _last_touch_ms < 800


func _touch_spread() -> float:
	var pts := _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1])


func _transparent(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	return m
