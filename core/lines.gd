class_name Lines
extends RefCounted
## Alle mulige vinnerlinjer for en brettstørrelse, regnet ut én gang.
##
## En celle har indeks i = x + N·y + N²·z (z er høyden).
## En linje er win_length celler etter hverandre i én av de 13 retningene.
## 4×4×4 med fire på rad gir 76 linjer, 5×5×5 gir 302.

## 13 unike retninger: 3 akser, 6 flatediagonaler, 4 romdiagonaler.
const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1),
	Vector3i(1, 1, 0), Vector3i(1, -1, 0),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1),
	Vector3i(0, 1, 1), Vector3i(0, 1, -1),
	Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(1, -1, 1), Vector3i(1, -1, -1),
]

var size: int
var win_length: int
var cells: Array[PackedInt32Array] = []       ## linje-indeks -> celle-indekser
var cell_lines: Array[PackedInt32Array] = []  ## celle-indeks -> linje-indekser

static var _cache: Dictionary = {}


## Henter (og lager ved første kall) linjene for en størrelse.
static func get_for(p_size: int, p_win_length: int) -> Lines:
	var key := Vector2i(p_size, p_win_length)
	if not _cache.has(key):
		_cache[key] = Lines.new(p_size, p_win_length)
	return _cache[key]


func _init(p_size: int, p_win_length: int) -> void:
	size = p_size
	win_length = p_win_length
	var n_cells := size * size * size
	for i in n_cells:
		cell_lines.append(PackedInt32Array())

	for d in DIRECTIONS:
		for x in size:
			for y in size:
				for z in size:
					var start := Vector3i(x, y, z)
					var end := start + d * (win_length - 1)
					if not _inside(end):
						continue
					var line := PackedInt32Array()
					for k in win_length:
						line.append(index_of(start + d * k))
					var line_index := cells.size()
					cells.append(line)
					for c in line:
						cell_lines[c].append(line_index)


func count() -> int:
	return cells.size()


func index_of(p: Vector3i) -> int:
	return p.x + size * p.y + size * size * p.z


func pos_of(i: int) -> Vector3i:
	return Vector3i(i % size, (i / size) % size, i / (size * size))


func _inside(p: Vector3i) -> bool:
	return p.x >= 0 and p.x < size and p.y >= 0 and p.y < size and p.z >= 0 and p.z < size
