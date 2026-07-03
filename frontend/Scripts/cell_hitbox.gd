extends StaticBody3D
class_name CellHitbox

signal clicked(coordinate: Vector2i)

@export var cell_coordinate: Vector2i
@export var cell_size := 0.25
@export var cell_height := 0.02

@export var ring_segments := 24
@export var vertical_lines := 8
@export var line_color := Color(1, 1, 1, 1)

@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var hover_outline: MeshInstance3D = $HoverOutline

func _ready() -> void:
	input_ray_pickable = true
	_apply_size()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Bygg "outline-only" linjer inn i HoverOutline
	hover_outline.mesh = _build_outline_mesh()
	hover_outline.visible = false

	# Unshaded linjemateriale
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = line_color
	mat.emission_enabled = true
	mat.emission = line_color
	mat.emission_energy_multiplier = 1.2
	hover_outline.material_override = mat

	# litt opp for å unngå z-fighting
	hover_outline.position.y = (cell_height / 2.0) + 0.002


func _input_event(camera: Camera3D, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(cell_coordinate)

func _on_mouse_entered() -> void:
	hover_outline.visible = true

func _on_mouse_exited() -> void:
	hover_outline.visible = false

func _apply_size() -> void:
	var shape := col_shape.shape as CylinderShape3D
	shape.height = cell_height
	shape.radius = cell_size / 2.0


func _build_outline_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var r := (cell_size / 2.0) * 1.05
	var y := 0.0  # vi legger den flatt som en ring (du flytter hele hover_outline opp)

	# Ring (flat sirkel)
	for i in range(ring_segments):
		var t0 := TAU * float(i) / float(ring_segments)
		var t1 := TAU * float(i + 1) / float(ring_segments)
		var p0 := Vector3(cos(t0) * r, y, sin(t0) * r)
		var p1 := Vector3(cos(t1) * r, y, sin(t1) * r)
		mesh.surface_add_vertex(p0)
		mesh.surface_add_vertex(p1)

	# “Kryss/vertikale” (egentlig radielle streker i ringen) – valgfritt
	for j in range(vertical_lines):
		var t := TAU * float(j) / float(vertical_lines)
		var p_in := Vector3(cos(t) * (r * 0.6), y, sin(t) * (r * 0.6))
		var p_out := Vector3(cos(t) * r, y, sin(t) * r)
		mesh.surface_add_vertex(p_in)
		mesh.surface_add_vertex(p_out)

	mesh.surface_end()
	return mesh
