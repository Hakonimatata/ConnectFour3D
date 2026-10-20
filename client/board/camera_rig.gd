class_name CameraRig
extends Node3D
## Orbit-kamera rundt brettet: myk rotasjon og zoom, pluss kamerarist («trauma»).
## Selve input (mus/touch) håndteres i BoardView, som kaller orbit() og zoom().

@export var rotate_sensitivity := 0.008
@export var min_pitch_deg := -80.0
@export var max_pitch_deg := -12.0
@export var smooth := 10.0

var camera: Camera3D
var yaw_target := deg_to_rad(35.0)
var pitch_target := deg_to_rad(-38.0)
var dist_target := 7.0
var min_distance := 4.0
var max_distance := 14.0
var auto_rotate := false         ## Brukes i menyen (sakte rotasjon)
var view_offset := Vector2.ZERO  ## Flytter bildet sideveis/opp (f.eks. bort fra menykortet)
var target := Vector3.ZERO

var _yaw := yaw_target
var _pitch := pitch_target
var _dist := dist_target
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.current = true
	add_child(camera)
	_noise.frequency = 0.9
	_apply(0.0)


## Plasserer kameraet riktig for en brettstørrelse (brettet er sentrert i origo).
func frame_board(board_width: float, board_height: float) -> void:
	target = Vector3(0, board_height * 0.42, 0)
	var radius := Vector2(board_width, board_height).length() * 0.62
	min_distance = radius * 1.3
	max_distance = radius * 3.6
	dist_target = radius * 2.25
	dist_target = clampf(dist_target, min_distance, max_distance)


func orbit(delta_px: Vector2) -> void:
	yaw_target -= delta_px.x * rotate_sensitivity
	pitch_target = clampf(pitch_target - delta_px.y * rotate_sensitivity,
		deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


## factor < 1 zoomer inn, > 1 zoomer ut.
func zoom(factor: float) -> void:
	dist_target = clampf(dist_target * factor, min_distance, max_distance)


## Kamerarist. amount 0..1 legges til, og risten klinger ut av seg selv.
func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _process(delta: float) -> void:
	# Bruk ekte tid for risten, så den virker også i sakte film.
	var real_delta := delta / maxf(Engine.time_scale, 0.05)
	_time += real_delta
	if auto_rotate:
		yaw_target += delta * 0.15
	_trauma = maxf(0.0, _trauma - real_delta * 1.1)
	# Stående skjerm (mobil): la synsfeltet følge bredden, så brettet ikke kuttes på sidene.
	var vp := get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if vp.y > vp.x else Camera3D.KEEP_HEIGHT
	camera.fov = 52.0 if vp.y > vp.x else 50.0
	_apply(real_delta)


func _apply(delta: float) -> void:
	var t := 1.0 - exp(-smooth * delta) if delta > 0.0 else 1.0
	_yaw = lerpf(_yaw, yaw_target, t)
	_pitch = lerpf(_pitch, pitch_target, t)
	_dist = lerpf(_dist, dist_target, t)

	var shake := _trauma * _trauma
	var sx := _noise.get_noise_2d(_time * 40.0, 0.0) * shake
	var sy := _noise.get_noise_2d(0.0, _time * 40.0) * shake
	var sr := _noise.get_noise_2d(_time * 40.0, 100.0) * shake

	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var offset := basis * Vector3(0, 0, _dist)
	global_position = target + offset
	look_at(target, Vector3.UP)
	camera.position = Vector3(sx * 0.6, sy * 0.6, 0)
	camera.rotation = Vector3(0, 0, sr * 0.12)
	camera.h_offset = lerpf(camera.h_offset, view_offset.x, t)
	camera.v_offset = lerpf(camera.v_offset, view_offset.y, t)
