class_name Skins
extends RefCounted
## Brikkefarger («skins»). Nye legges bare til i listen.

const ALL: Array[Dictionary] = [
	{ "id": "ocean", "name": "Havblå", "color": Color(0.0, 0.51, 1.0) },
	{ "id": "ember", "name": "Glør", "color": Color(0.95, 0.22, 0.05) },
	{ "id": "lime", "name": "Lime", "color": Color(0.55, 0.9, 0.1) },
	{ "id": "gold", "name": "Gull", "color": Color(1.0, 0.75, 0.1) },
	{ "id": "violet", "name": "Fiol", "color": Color(0.6, 0.3, 1.0) },
	{ "id": "rose", "name": "Rosa", "color": Color(1.0, 0.35, 0.65) },
	{ "id": "mint", "name": "Mint", "color": Color(0.1, 0.9, 0.7) },
	{ "id": "snow", "name": "Snø", "color": Color(0.92, 0.94, 0.98) },
]

const DEFAULT_P1 := "ocean"
const DEFAULT_P2 := "ember"


static func get_skin(id: String) -> Dictionary:
	for s in ALL:
		if s.id == id:
			return s
	return ALL[0]


static func color_of(id: String) -> Color:
	return get_skin(id).color


static func is_valid(id: String) -> bool:
	return ALL.any(func(s: Dictionary) -> bool: return s.id == id)


## Velger farge for motstanderen. Ligner den for mye på vår, brukes en annen.
static func contrast_for(own_id: String, wanted_id: String) -> String:
	if _distance(color_of(own_id), color_of(wanted_id)) > 0.35:
		return wanted_id
	for candidate in [DEFAULT_P2, DEFAULT_P1, "gold", "mint", "violet"]:
		if _distance(color_of(own_id), color_of(candidate)) > 0.35:
			return candidate
	return DEFAULT_P2


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
