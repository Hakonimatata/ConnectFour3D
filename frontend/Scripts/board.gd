extends Node3D

class_name Board

# Connect game logic functions

var logic: GameLogic

@export var cell_hitbox_scene: PackedScene
@export var piece_scene: PackedScene
@export var grid_size := 4
@export var horizontal_spacing := 0.25
@export var vertical_spacing := 0.12
@export var cell_size := 0.2

@onready var pieces_root: Node3D = $Pieces
@onready var cells_root: Node3D = $Cells
@onready var highlighted_spots_root: Node3D = $HighlightedSpots

var piece_nodes: Dictionary = {} # Vector3i -> Node3D
var cell_nodes: Dictionary = {} # Vector2i -> CellHitbox

var game_over := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_spawn_hitboxes()

func set_game_logic(gl: GameLogic) -> void:
	logic = gl
	# Connect signals from the game logic that we need to reflect
	logic.piece_placed.connect(_on_piece_placed)
	logic.invalid_move.connect(_on_invalid_move)
	logic.game_won.connect(_on_game_won)
	logic.forced_moves.connect(_on_forced_move)
	


func grid_to_world(coord: Vector3i) -> Vector3:
	var half := (grid_size - 1) * horizontal_spacing * 0.5
	return Vector3(
		coord.x * horizontal_spacing - half,  # X
		coord.z * vertical_spacing,           # Y (høyde)
		coord.y * horizontal_spacing - half   # Z
	)
	
func _spawn_hitboxes() -> void:
	
	for x in range(grid_size):
		for y in range(grid_size):
			var cell_hitbox := cell_hitbox_scene.instantiate() as CellHitbox
			var coord = Vector2i(x, y)
			cell_hitbox.cell_coordinate = coord
			cell_hitbox.cell_size = cell_size
			
			# Set initital position
			cell_hitbox.position = grid_to_world(Vector3i(
				cell_hitbox.cell_coordinate.x,
				cell_hitbox.cell_coordinate.y,
				0 # At z=0
			))
			
			# Save reference
			cell_nodes[coord] = cell_hitbox
			
			# Add to scene
			cells_root.add_child(cell_hitbox)
			
			# Connect clicked signal to a function call
			cell_hitbox.clicked.connect(_on_cell_clicked)
	
	
func _on_cell_clicked(coordinate: Vector2i) -> void:
	if game_over: return
	# Do a request, signals handle the rest
	logic.request_move(coordinate, logic.current_player_id)
	print("Clicked cell:", coordinate)
	
func _on_piece_placed(pos: Vector3i, player_id: int) -> void:
	var piece := piece_scene.instantiate() as Piece
	pieces_root.add_child(piece)
	piece.position = grid_to_world(pos)
	piece.set_player(player_id)
	piece_nodes[pos] = piece
	
	# Move cell up a step
	var cell_coord := Vector2i(pos.x, pos.y)
	if cell_nodes.has(cell_coord):
		var cell: CellHitbox = cell_nodes[cell_coord]
		cell.position.y += vertical_spacing
	
	_remove_highlighted_spots()

	
func _on_invalid_move(reason: String) -> void:
	print(reason)
	
func _on_forced_move(positions: Array[Vector3i]) -> void:
	"""Get forced positions from game logic and highlight"""
	_remove_highlighted_spots()
	for pos in positions:
		_highlight_spot(pos)

	
func _on_game_won(player_id: int, win_positions: Array[Vector3i]) -> void:
	print("WIN! For player ", player_id)
	game_over = true
	_highlight_pieces(win_positions)
	

func _highlight_pieces(positions: Array[Vector3i]) -> void:
	"""Highlights pieces if they exist at position"""
	
	for pos in positions:
		if piece_nodes.has(pos):
			var piece: Piece = piece_nodes[pos]
			piece.set_highlight()
	
func _highlight_spot(pos: Vector3i) -> void:
	"""Instanciates a highlighted spot on the game board"""
	var piece := piece_scene.instantiate() as Piece
	highlighted_spots_root.add_child(piece)
	piece.position = grid_to_world(pos)
	piece.set_transparent_highlight()
	
	
func _remove_highlighted_spots() -> void:
	for child in highlighted_spots_root.get_children():
		child.queue_free()
