class_name BoardView
extends Node3D
## 3D-visningen av brettet. Bygges i kode ut fra størrelsen (4×4×4, 5×5×5, ...).
## Vet ingenting om regler. Den viser brikker og sier fra når en kolonne trykkes.
##
## Koordinater: regelmotoren bruker (x, y) = kolonne og z = høyde.
## Godot har Y opp, så grid_to_world() oversetter (x, y, z) -> (X, Y=z, Z=y).

signal column_tapped(col: Vector2i, from_touch: bool)
signal column_hovered(col: Vector2i)   ## (-1, -1) = ingen

const NO_COLUMN := Vector2i(-1, -1)
const SPACING := 1.0          ## Avstand mellom kolonner
const LAYER := 0.52           ## Høyde per brikke
const PIECE_SCALE := 4.0      ## piece.obj er 0,17 bred, 0,126 høy
const DRAG_THRESHOLD := 10.0  ## Piksler før et trykk regnes som dra (roter)
const PICK_LAYER := 2

var size := 4
var camera_rig: CameraRig
var input_enabled := false
var colors := { 1: Skins.color_of(Skins.DEFAULT_P1), 2: Skins.color_of(Skins.DEFAULT_P2) }

var _piece_mesh: Mesh = preload("res://assets/models/piece.obj")
var _toon: Shader = preload("res://assets/shaders/toon.gdshader")
var _static_root: Node3D
var _pieces_root: Node3D
var _hints_root: Node3D
var _pieces: Dictionary = {}    ## Vector3i -> MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_col := NO_COLUMN
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
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.material_override = gm
	add_child(_ghost)


# ---------------------------------------------------------------- Oppsett

func setup(p_size: int) -> void:
	size = p_size
	clear_pieces()
	for c in _static_root.get_children():
		c.queue_free()

	var width := size * SPACING + 0.5
	var height := size * LAYER

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(width, 0.22, width)
	base.mesh = base_mesh
	base.position.y = -0.11
	base.material_override = _material(Color("2a3040"), 0.2, 0.55)
	_static_root.add_child(base)

	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(width + 0.16, 0.08, width + 0.16)
	rim.mesh = rim_mesh
	rim.position.y = -0.2
	rim.material_override = _material(Color("4c8dff"), 0.0, 0.4, 0.6)
	_static_root.add_child(rim)

	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.05
	rod_mesh.bottom_radius = 0.05
	rod_mesh.height = height + 0.12
	rod_mesh.radial_segments = 12
	var rod_mat := _material(Color("8e9ab5"), 0.6, 0.35)

	var pick_shape := CylinderShape3D.new()
	pick_shape.radius = SPACING * 0.45
	pick_shape.height = height + 0.5

	for x in size:
		for y in size:
			var floor_pos := grid_to_world(Vector3i(x, y, 0))
			var rod := MeshInstance3D.new()
			rod.mesh = rod_mesh
			rod.material_override = rod_mat
			rod.position = floor_pos + Vector3(0, rod_mesh.height / 2.0, 0)
			_static_root.add_child(rod)

			var body := StaticBody3D.new()
			body.collision_layer = PICK_LAYER
			body.collision_mask = 0
			body.set_meta("col", Vector2i(x, y))
			body.position = floor_pos + Vector3(0, pick_shape.height / 2.0, 0)
			var shape := CollisionShape3D.new()
			shape.shape = pick_shape
			body.add_child(shape)
			_static_root.add_child(body)

	if camera_rig:
		camera_rig.frame_board(width, height)


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
	clear_hints()
	hide_ghost()


## Legger til en brikke. Med animate faller den ned og spretter.
func add_piece(pos: Vector3i, player: int, animate := true) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = _piece_mesh
	piece.scale = Vector3.ONE * PIECE_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = _toon
	mat.set_shader_parameter("base_color", colors[player])
	piece.material_override = mat
	piece.set_meta("player", player)
	_pieces_root.add_child(piece)
	_pieces[pos] = piece

	var target := grid_to_world(pos)
	if not animate:
		piece.position = target
		return
	piece.position = target + Vector3(0, size * LAYER + 1.2 - pos.z * LAYER * 0.5, 0)
	var t := piece.create_tween()
	t.tween_property(piece, "position", target, 0.42).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


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


# ---------------------------------------------------------------- Hint og spøkelsesbrikke

func show_ghost(pos: Vector3i, player: int, col: Vector2i) -> void:
	_ghost_col = col
	_ghost.visible = true
	_ghost.position = grid_to_world(pos)
	var mat: StandardMaterial3D = _ghost.material_override
	mat.albedo_color = Color(colors[player], 0.38)


func hide_ghost() -> void:
	_ghost_col = NO_COLUMN
	if _ghost:
		_ghost.visible = false


func ghost_column() -> Vector2i:
	return _ghost_col


## Viser pulserende hvite plasser (f.eks. der man må blokkere).
func show_hints(positions: Array) -> void:
	clear_hints()
	for p in positions:
		var h := MeshInstance3D.new()
		h.mesh = _piece_mesh
		h.scale = Vector3.ONE * PIECE_SCALE
		h.position = grid_to_world(p)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.5)
		h.material_override = m
		_hints_root.add_child(h)
		var t := h.create_tween().set_loops()
		t.tween_property(m, "albedo_color:a", 0.1, 0.4)
		t.tween_property(m, "albedo_color:a", 0.55, 0.4)


func clear_hints() -> void:
	if _hints_root:
		for c in _hints_root.get_children():
			c.queue_free()


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
			var col := pick_column(event.position)
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


func _material(color: Color, metallic: float, roughness: float, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m
