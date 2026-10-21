class_name PiecePreview
extends SubViewportContainer
## Liten 3D-visning av brikken: hjemmedrakt og bortedrakt side om side, roterende.

var _viewport: SubViewport
var _pivot: Node3D
var _home: MeshInstance3D
var _away: MeshInstance3D
var _mesh: Mesh = preload("res://assets/models/piece.obj")


func _init(height := 150.0) -> void:
	custom_minimum_size = Vector2(0, height)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 30.0
	var eye := Vector3(0, 1.25, 2.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.2, 0) - eye, Vector3.UP), eye)
	_viewport.add_child(cam)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_home = _piece(Vector3(-0.42, 0, 0))
	_away = _piece(Vector3(0.42, 0, 0))


func _piece(at: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _mesh
	m.scale = Vector3.ONE * BoardView.PIECE_SCALE
	m.position = at
	_pivot.add_child(m)
	return m


func set_look(l: Dictionary) -> void:
	var home := l.duplicate()
	home.away = false
	var away := l.duplicate()
	away.away = true
	set_pair(home, away)


## To vilkårlige looks side om side (f.eks. deg og motstanderen).
func set_pair(left: Dictionary, right: Dictionary) -> void:
	_home.material_override = Skins.make_material(left)
	_away.material_override = Skins.make_material(right)


func _process(delta: float) -> void:
	_home.rotate_y(delta * 0.8)
	_away.rotate_y(delta * 0.8)
