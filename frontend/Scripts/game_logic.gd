extends Node
class_name GameLogic

signal piece_placed(pos: Vector3i, player_id: int)
signal game_won(player_id: int, win_positions: Array[Vector3i])
signal invalid_move(reason: String)
signal forced_moves(positions: Array[Vector3i])

class MoveInfo:
	var is_winning_move: bool = false
	var win_positions: Array[Vector3i] = []
	var causes_opponent_to_win: bool = false
	var opponent_win_positions: Array[Vector3i] = []
	var is_missing_blocking_move: bool = false

var grid_size: int = 4
var win_length: int = 4
var p1_id: int = 1
var p2_id: int = 2
@export var p2_starts: bool = false

@export_group("Game Rules")
@export var must_block: bool = true
@export var must_not_give_victory: bool = true

var current_player_id: int

# grid[x][y][z] -> int (0 = tom, ellers spiller-id)
var grid: Array
var actions: Array[Vector2i] = []

# 13 retninger for 3D 4-på-rad (uten duplikater)
var directions: Array[Vector3i] = [
	Vector3i( 1,  0,  0), Vector3i( 0,  1,  0), Vector3i( 0,  0,  1),
	Vector3i( 1,  1,  0), Vector3i( 1,  0,  1), Vector3i( 0,  1,  1),
	Vector3i( 1, -1,  0), Vector3i( 1,  0, -1), Vector3i( 0,  1, -1),
	Vector3i( 1,  1,  1), Vector3i( 1, -1, -1), Vector3i(-1,  1, -1),
	Vector3i(-1, -1,  1),
]

func _ready() -> void:
	_build_actions()
	reset_board(p2_starts)

func _build_actions() -> void:
	actions.clear()
	for x in range(grid_size):
		for y in range(grid_size):
			actions.append(Vector2i(x, y))

func reset_board(p2_start: bool = false) -> void:
	# grid[x][y][z]
	grid = []
	for x in range(grid_size):
		grid.append([])
		for y in range(grid_size):
			grid[x].append([])
			for z in range(grid_size):
				grid[x][y].append(0)

	current_player_id = p2_id if p2_start else p1_id

# ---------------- Public API ----------------

func request_move(action: Vector2i, player_id: int) -> void:
	if not _is_move_possible(action, player_id, true, true):
		return

	var position := _action_to_position(action)
	var info := _get_move_info(position, player_id)
	
	# Check game rules 
	if info.is_missing_blocking_move and must_block:
		invalid_move.emit("Du må blokkere! Motstander kan vinne på: %s" % str(info.opponent_win_positions))
		forced_moves.emit(info.opponent_win_positions)
		return
	if info.causes_opponent_to_win and must_not_give_victory:
		invalid_move.emit("Ugyldig trekk: dette gir motstander en vinnemulighet på toppen.")
		return
	
	_set_id_at_position(position, player_id)
	piece_placed.emit(position, player_id)
	
	if info.is_winning_move:
		game_won.emit(player_id, info.win_positions)
		return
	
	_switch_player()

func get_id_at_position(pos: Vector3i) -> int:
	return grid[pos.x][pos.y][pos.z]

# ---------------- Internals ----------------

func _set_id_at_position(pos: Vector3i, id: int) -> void:
	grid[pos.x][pos.y][pos.z] = id

func _get_move_info(position: Vector3i, player_id: int) -> MoveInfo:
	var info := MoveInfo.new()
	var opponent_id := _get_opponent_id(player_id)
	
	# 1) Er dette et vinn-trekk for oss? (vi kan sjekke uten simulering ved å simulere lokalt)
	if _would_be_winning_move(position, player_id, info):
		return info
	
	# 2) Må vi blokkere? (sjekk om motstander har et vinn-trekk på sin neste "drop")
	info.opponent_win_positions = _get_opponent_winning_drops(opponent_id)
	
	if info.opponent_win_positions.size() > 0:
		# hvis vårt trekk er på en av blokk-posisjonene, ok
		if position in info.opponent_win_positions:
			return info
		info.is_missing_blocking_move = true
		return info

	# 3) "På toppen"-regelen (korrekt): etter at vi legger her, blir feltet over spillbart.
	# Hvis motstander kan vinne ved å legge på feltet over, er trekket ugyldig.
	if _gives_opponent_win_on_top(position, player_id, opponent_id):
		info.causes_opponent_to_win = true
		return info
	
	return info

# --- Regel-hjelpere ---

func _would_be_winning_move(position: Vector3i, player_id: int, info: MoveInfo) -> bool:
	# Simuler, sjekk, angre
	_set_id_at_position(position, player_id)
	
	for d in directions:
		var connected := _get_connected_pieces(position, d, player_id, true)
		if connected.size() >= win_length:
			info.is_winning_move = true
			info.win_positions = connected
			_set_id_at_position(position, 0)
			return true
	
	_set_id_at_position(position, 0)
	return false

func _get_opponent_winning_drops(opponent_id: int) -> Array[Vector3i]:
	var wins: Array[Vector3i] = []
	
	for action in _get_possible_actions():
		var pos := _action_to_position(action)
	
		# Simuler motstander-drop, sjekk win, angre
		_set_id_at_position(pos, opponent_id)
		if _is_winning_position(pos, opponent_id):
			wins.append(pos)
		_set_id_at_position(pos, 0)
	
	return wins

func _gives_opponent_win_on_top(position: Vector3i, player_id: int, opponent_id: int) -> bool:
	var above: Variant = _spot_above(position)
	if above == null:
		return false
	
	# Simuler vårt trekk (det er dette som gjør 'above' spillbar neste tur)
	_set_id_at_position(position, player_id)
	var causes := _is_winning_position(above, opponent_id)
	_set_id_at_position(position, 0)
	
	return causes

# --- Win-checker ---

func _is_winning_position(position: Vector3i, player_id: int) -> bool:
	for d in directions:
		var connected := _get_connected_pieces(position, d, player_id, true)
		if connected.size() >= win_length:
			return true
	return false

func _get_connected_pieces(
	position: Vector3i,
	direction: Vector3i,
	player_id: int,
	count_initial_pos: bool = true
) -> Array[Vector3i]:
	var dx := direction.x
	var dy := direction.y
	var dz := direction.z
	
	var connection: Array[Vector3i] = []
	if count_initial_pos:
		connection.append(position)
	
	# positiv retning
	var p := position
	for _i in range(grid_size):
		p = Vector3i(p.x + dx, p.y + dy, p.z + dz)
		if not _is_inside_grid(p):
			break
		if get_id_at_position(p) != player_id:
			break
		connection.append(p)
	
	# negativ retning
	p = position
	for _i in range(grid_size):
		p = Vector3i(p.x - dx, p.y - dy, p.z - dz)
		if not _is_inside_grid(p):
			break
		if get_id_at_position(p) != player_id:
			break
		connection.append(p)
	
	return connection

# --- Move validity / actions ---

func _is_move_possible(action: Vector2i, player_id: int, check_turn: bool = true, emit_errors: bool = true) -> bool:
	var x := action.x
	var y := action.y
	
	# Sjekk tur
	if check_turn and player_id != -1:
		if player_id != current_player_id:
			if emit_errors:
				invalid_move.emit("Det er spiller %d sin tur." % current_player_id)
			return false

	# Inside bounds?
	if x < 0 or x >= grid_size or y < 0 or y >= grid_size:
		if emit_errors:
			invalid_move.emit("Action %s er utenfor brettet." % str(action))
		return false

	# Full kolonne?
	if grid[x][y][grid_size - 1] != 0:
		if emit_errors:
			invalid_move.emit("Kan ikke bygge høyere enn %d." % grid_size)
		return false

	return true

func _get_possible_actions() -> Array[Vector2i]:
	var possible: Array[Vector2i] = []
	for action in actions:
		if _is_move_possible(action, -1, false, false):
			possible.append(action)
	return possible

func _is_inside_grid(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size and pos.z >= 0 and pos.z < grid_size

func _action_to_position(action: Vector2i) -> Vector3i:
	var z := _get_z(action)
	return Vector3i(action.x, action.y, z)

func _get_z(action: Vector2i) -> int:
	var x := action.x
	var y := action.y
	var z := 0
	while z < grid_size and grid[x][y][z] != 0:
		z += 1
	return z

func _spot_above(pos: Vector3i) -> Variant:
	if pos.z < grid_size - 1:
		return Vector3i(pos.x, pos.y, pos.z + 1)
	return null

func _switch_player() -> void:
	current_player_id = p2_id if current_player_id == p1_id else p1_id

func _get_opponent_id(player_id: int) -> int:
	return p1_id if player_id != p1_id else p2_id
