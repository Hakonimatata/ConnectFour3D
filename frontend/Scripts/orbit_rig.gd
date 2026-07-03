extends Node3D

# Input / mål
@export var distance := 6.0
@export var min_distance := 1.5
@export var max_distance := 25.0
@export var rotate_sensitivity := 0.01
@export var zoom_step := 0.8
@export var min_pitch_deg := -80.0
@export var max_pitch_deg := -5.0
@export var height_offset := 0.5

# Smooth-innstillinger
@export var orbit_smooth := 12.0
@export var zoom_smooth := 12.0
@export var follow_smooth := 10.0

@onready var yaw_node: Node3D = $Yaw
@onready var pitch_node: Node3D = $Yaw/Pitch
@onready var cam: Camera3D = $Yaw/Pitch/Camera3D

@export var target_position: Vector3 = Vector3(0, 0.2, 0)

var yaw_target := 0.0
var pitch_target := deg_to_rad(-45.0)
var dist_target := 6.0
var pivot_target := Vector3.ZERO

var yaw := yaw_target
var pitch := pitch_target
var dist := dist_target
var pivot := Vector3.ZERO

func _ready() -> void:
	dist_target = clamp(distance, min_distance, max_distance)
	dist = dist_target
	
	pivot_target = target_position
	pivot = target_position
	
	_apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	# Rotér med RMB
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw_target -= event.relative.x * rotate_sensitivity
		pitch_target -= event.relative.y * rotate_sensitivity
		pitch_target = clamp(
			pitch_target,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)

	# Zoom med scroll
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_target = max(min_distance, dist_target - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_target = min(max_distance, dist_target + zoom_step)

func _process(delta: float) -> void:
	# Følg target fullstendig (ingen pan-offset)
	pivot_target = target_position

	yaw = _smooth(yaw, yaw_target, orbit_smooth, delta)
	pitch = _smooth(pitch, pitch_target, orbit_smooth, delta)
	dist = _smooth(dist, dist_target, zoom_smooth, delta)
	pivot = pivot.lerp(pivot_target, 1.0 - exp(-follow_smooth * delta))

	global_position = pivot
	_apply_camera()

func _apply_camera() -> void:
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	cam.position = Vector3(0, 0, dist)
	cam.look_at(global_position, Vector3.UP)

func _smooth(current: float, target_val: float, speed: float, delta: float) -> float:
	var t := 1.0 - exp(-speed * delta)
	return lerp(current, target_val, t)
