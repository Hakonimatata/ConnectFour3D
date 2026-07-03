extends Node3D
class_name Piece

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var outline: MeshInstance3D = $Outline

@export var toon_shader: Shader = preload("res://Shaders/toon.gdshader")
@export var outline_shader: Shader = preload("res://Shaders/outline.gdshader")

@export var player_1_color: Color = Color(0.0, 0.51, 1.0, 1.0)
@export var player_2_color: Color = Color(0.848, 0.164, 0.0, 1.0)
@export var default_color: Color = Color.GRAY
@export var idle_emission_energy := 0.1

@export var transparent_highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var outline_color: Color = Color.BLACK
@export var outline_width: float = 0.01

# Kun highlight-glød
@export var highlight_emission_energy: float = 2.0

var _toon_mat: ShaderMaterial
var _outline_mat: ShaderMaterial

var _last_player_id: int = 0
var _is_highlighted: bool = false

func _ready() -> void:
	position = Vector3.ZERO
	scale = Vector3(0.01, 0.01, 0.01)
	rotate_x(deg_to_rad(-90))

	if mesh == null:
		push_error("Piece.gd: Mangler MeshInstance3D")
		return

	_init_toon()
	# _init_outline() # valgfritt
	set_default()

# ---------- Init ----------
func _init_toon() -> void:
	_toon_mat = ShaderMaterial.new()
	_toon_mat.shader = toon_shader
	mesh.material_override = _toon_mat

	# default params
	_toon_mat.set_shader_parameter("steps", 3.0)
	_toon_mat.set_shader_parameter("shadow_floor", 0.18)
	_toon_mat.set_shader_parameter("rim_strength", 0.22)
	_set_emission(0.0)

func _init_outline() -> void:
	if outline == null:
		return

	outline.mesh = mesh.mesh
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = outline_shader
	outline.material_override = _outline_mat

	var w : float = outline_width / max(scale.x, 0.00001)
	set_outline(outline_color, w)

# ---------- Public API ----------
func set_outline(color: Color, width: float = 0.02) -> void:
	if _outline_mat == null:
		return
	_outline_mat.set_shader_parameter("outline_color", Color(color.r, color.g, color.b, 1.0))
	_outline_mat.set_shader_parameter("width", width)

func set_default() -> void:
	_last_player_id = 0
	_is_highlighted = false
	_apply_color(default_color)
	_set_emission(0.0)

func set_player(player_id: int) -> void:
	_last_player_id = player_id
	_is_highlighted = false

	if player_id == 1:
		_apply_color(player_1_color)
	elif player_id == 2:
		_apply_color(player_2_color)
	else:
		_apply_color(default_color)

	_set_emission(idle_emission_energy)

# Kun glød, beholder egen farge
func set_highlight() -> void:
	_is_highlighted = true
	_set_emission(highlight_emission_energy)

func clear_highlight() -> void:
	_is_highlighted = false
	_set_emission(0.0)

func set_transparent_highlight(alpha := 0.4) -> void:
	# Dette endrer base_color (valgfritt), men glød er fortsatt av/på separat
	_toon_mat.set_shader_parameter(
		"base_color",
		Color(
			transparent_highlight_color.r,
			transparent_highlight_color.g,
			transparent_highlight_color.b,
			alpha
		)
	)
	_set_emission(10.0)

# ---------- Internals ----------
func _apply_color(color: Color) -> void:
	if _toon_mat == null:
		return
	_toon_mat.set_shader_parameter("base_color", Color(color.r, color.g, color.b, color.a))

func _set_emission(energy: float) -> void:
	if _toon_mat == null:
		return
	_toon_mat.set_shader_parameter("emission_energy", energy)
