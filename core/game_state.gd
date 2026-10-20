class_name GameState
extends RefCounted
## Regelmotoren: brettet, hvem som har tur, lovlige trekk og resultat.
## Ren logikk, ingen noder og ingen grafikk, så den brukes likt av
## klient, AI, server og tester. Reglene er beskrevet i Plan.md, seksjon 2.
##
## Et trekk er en kolonne (x, y). Brikken faller ned til laveste ledige z.
## Spillerne heter 1 og 2. Tom celle er 0.

enum Result { PLAYING, P1_WON, P2_WON, DRAW }
enum EndReason { NONE, LINE, BOARD_FULL, TIMEOUT, RESIGN, DISCONNECT }
enum MoveError { OK, GAME_OVER, OUT_OF_BOUNDS, COLUMN_FULL, MUST_BLOCK, GIVES_WIN }

var options: GameOptions
var lines: Lines
var size: int
var win_length: int

var cells: PackedByteArray        ## celle-indeks -> 0, 1 eller 2
var heights: PackedByteArray      ## kolonne-indeks (x + N·y) -> antall brikker
var counts: PackedByteArray       ## counts[spiller · n_lines + linje] = spillerens brikker i linjen
var n_lines: int

var first_player: int = 1
var current_player: int = 1
var result: Result = Result.PLAYING
var end_reason: EndReason = EndReason.NONE
var winning_line: Array[Vector3i] = []
var history: Array[Vector2i] = []


func _init(p_options: GameOptions = null, p_first_player: int = 1) -> void:
	options = p_options if p_options != null else GameOptions.new()
	size = options.size
	win_length = options.win_length
	lines = Lines.get_for(size, win_length)
	cells.resize(size * size * size)
	heights.resize(size * size)
	n_lines = lines.count()
	counts.resize(3 * n_lines)
	first_player = p_first_player
	current_player = p_first_player


## Lager et parti ut fra en trekkliste (brukes ved gjenkobling og replays).
static func from_moves(p_options: GameOptions, p_first_player: int, moves: Array) -> GameState:
	var s := GameState.new(p_options, p_first_player)
	for m in moves:
		var col: Vector2i = m if m is Vector2i else Vector2i(int(m[0]), int(m[1]))
		s.play(col, false)
	return s


# ---------------------------------------------------------------- Spørringer

func is_over() -> bool:
	return result != Result.PLAYING


func winner() -> int:
	match result:
		Result.P1_WON: return 1
		Result.P2_WON: return 2
	return 0


static func opponent(player: int) -> int:
	return 3 - player


func get_cell(pos: Vector3i) -> int:
	return cells[lines.index_of(pos)]


func is_inside_column(col: Vector2i) -> bool:
	return col.x >= 0 and col.x < size and col.y >= 0 and col.y < size


func column_height(col: Vector2i) -> int:
	return heights[col.x + size * col.y]


func is_column_open(col: Vector2i) -> bool:
	return is_inside_column(col) and column_height(col) < size


## Hvor en brikke vil lande i kolonnen (kolonnen må være åpen).
func landing_pos(col: Vector2i) -> Vector3i:
	return Vector3i(col.x, col.y, column_height(col))


func open_columns() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size:
		for x in size:
			if heights[x + size * y] < size:
				out.append(Vector2i(x, y))
	return out


## Ville en brikke fra `player` i den (tomme) cellen gitt fire på rad?
func is_winning_cell(index: int, player: int) -> bool:
	var own := player * n_lines
	var opp := opponent(player) * n_lines
	for li in lines.cell_lines[index]:
		if counts[own + li] == win_length - 1 and counts[opp + li] == 0:
			return true
	return false


## Vinner `player` ved å legge i kolonnen nå?
func wins_by(col: Vector2i, player: int) -> bool:
	return is_winning_cell(lines.index_of(landing_pos(col)), player)


## Kolonner der `player` vinner med neste brikke.
func winning_columns(player: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for col in open_columns():
		if wins_by(col, player):
			out.append(col)
	return out


## Blir feltet rett over landingsplassen en vinnerplass for motstanderen?
## (Vår brikke kan ikke ligge i noen linje gjennom feltet over som motstanderen
## nesten har fullført, så det holder å sjekke dagens stilling.)
func gives_win_above(col: Vector2i, player: int) -> bool:
	var z := column_height(col)
	if z + 1 >= size:
		return false
	return is_winning_cell(lines.index_of(Vector3i(col.x, col.y, z + 1)), opponent(player))


## Lovlige trekk for spilleren som har tur, etter prioriteten i Plan.md 2.3:
## 1) alle åpne kolonner, 2) vinnertrekk er alltid lov, 3) må blokkere,
## 4) ikke gi bort seier, 5) et filter som ville fjernet alle trekk hoppes over.
func legal_moves() -> Array[Vector2i]:
	if is_over():
		return []
	var me := current_player
	var wins: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for col in open_columns():
		if wins_by(col, me):
			wins.append(col)
		else:
			rest.append(col)

	if options.must_block:
		var blocks := rest.filter(func(c: Vector2i) -> bool: return wins_by(c, opponent(me)))
		if not blocks.is_empty():
			rest.assign(blocks)

	if options.no_gift:
		var safe := rest.filter(func(c: Vector2i) -> bool: return not gives_win_above(c, me))
		if not safe.is_empty() or not wins.is_empty():
			rest.assign(safe)

	wins.append_array(rest)
	return wins


## Sjekker et trekk for spilleren som har tur. Gir MoveError.OK hvis lovlig.
func check_move(col: Vector2i) -> MoveError:
	if is_over():
		return MoveError.GAME_OVER
	if not is_inside_column(col):
		return MoveError.OUT_OF_BOUNDS
	if not is_column_open(col):
		return MoveError.COLUMN_FULL
	if col in legal_moves():
		return MoveError.OK
	# Ulovlig på grunn av en regel. Finn hvilken.
	if options.must_block and not winning_columns(opponent(current_player)).is_empty() \
			and not wins_by(col, opponent(current_player)):
		return MoveError.MUST_BLOCK
	return MoveError.GIVES_WIN


## Celler motstanderen kan vinne på nå (vises som hint ved «må blokkere»).
func threat_positions(player: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for col in winning_columns(opponent(player)):
		out.append(landing_pos(col))
	return out


static func error_text(err: MoveError) -> String:
	match err:
		MoveError.GAME_OVER: return "Partiet er ferdig."
		MoveError.OUT_OF_BOUNDS: return "Utenfor brettet."
		MoveError.COLUMN_FULL: return "Kolonnen er full."
		MoveError.MUST_BLOCK: return "Du må blokkere!"
		MoveError.GIVES_WIN: return "Det trekket gir bort seieren."
	return ""


# ---------------------------------------------------------------- Endringer

## Spiller et trekk for spilleren som har tur.
## Gir en Dictionary: { ok, error, pos, player, won, draw }.
func play(col: Vector2i, validate: bool = true) -> Dictionary:
	var err: MoveError = check_move(col) if validate else MoveError.OK
	if err != MoveError.OK:
		return { "ok": false, "error": err }
	var player := current_player
	var index := place(col, player)
	history.append(col)

	var line := _completed_line(index, player)
	if not line.is_empty():
		result = Result.P1_WON if player == 1 else Result.P2_WON
		end_reason = EndReason.LINE
		for c in line:
			winning_line.append(lines.pos_of(c))
	elif history.size() == size * size * size:
		result = Result.DRAW
		end_reason = EndReason.BOARD_FULL
	else:
		current_player = opponent(player)

	return {
		"ok": true, "error": MoveError.OK, "pos": lines.pos_of(index), "player": player,
		"won": result != Result.PLAYING and result != Result.DRAW, "draw": result == Result.DRAW,
	}


## Angrer siste trekk.
func undo() -> void:
	if history.is_empty():
		return
	var col: Vector2i = history.pop_back()
	var index := lines.index_of(Vector3i(col.x, col.y, column_height(col) - 1))
	var player := cells[index]
	unplace(col)
	current_player = player
	result = Result.PLAYING
	end_reason = EndReason.NONE
	winning_line.clear()


## Avslutter partiet utenfor brettet (tid ute, gi opp, frakobling).
func end_with_loss(loser: int, reason: EndReason) -> void:
	if is_over():
		return
	result = Result.P2_WON if loser == 1 else Result.P1_WON
	end_reason = reason


# ------------------------------------------- Rå plassering (for AI og intern bruk)
# Disse endrer bare brettet og linjetellerne, ikke tur, historikk eller resultat.

func place(col: Vector2i, player: int) -> int:
	var ci := col.x + size * col.y
	var index := lines.index_of(Vector3i(col.x, col.y, heights[ci]))
	heights[ci] += 1
	cells[index] = player
	var off := player * n_lines
	for li in lines.cell_lines[index]:
		counts[off + li] += 1
	return index


func unplace(col: Vector2i) -> void:
	var ci := col.x + size * col.y
	heights[ci] -= 1
	var index := lines.index_of(Vector3i(col.x, col.y, heights[ci]))
	var player := cells[index]
	cells[index] = 0
	var off := player * n_lines
	for li in lines.cell_lines[index]:
		counts[off + li] -= 1


## Har brikken i cellen fullført en linje? (cellen må være spilt)
func is_win_at(index: int, player: int) -> bool:
	var off := player * n_lines
	for li in lines.cell_lines[index]:
		if counts[off + li] == win_length:
			return true
	return false


func _completed_line(index: int, player: int) -> PackedInt32Array:
	var off := player * n_lines
	for li in lines.cell_lines[index]:
		if counts[off + li] == win_length:
			return lines.cells[li]
	return PackedInt32Array()
