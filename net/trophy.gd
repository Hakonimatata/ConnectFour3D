class_name Trophy
extends RefCounted
## Pokaler: utseendet er en liten ordbok som lages fra et frø (seed), så hver turnering kan få
## sin egen unike pokal. Serveren lagrer ordboken (i tournaments.json og på brukeren i users.json),
## og klienten tegner den (TrophyView). Felt som mangler eller er ukjente, fylles ut fra frøet,
## så en pokal kan også skrives for hånd i JSON-filene.
##
##   { seed, shape, metal, handles, emblem, base }

const SHAPES := ["cup", "chalice", "star", "orb", "obelisk", "crown"]
const METALS := ["gold", "silver", "bronze", "platinum", "rose", "crystal", "ruby", "emerald", "sapphire",
	"obsidian", "aurora"]
const HANDLES := ["loop", "wing", "angular", "none"]
const EMBLEMS := ["four", "star", "crown", "bolt", "one", "none"]
const BASES := ["marble", "onyx", "wood", "granite", "jade"]
const MAX_NAME := 40
const DEFAULT_NAME := "Pokal"
const MAX_PER_USER := 100

## Metallfarger: lys, middels og mørk tone.
const METAL_COLORS := {
	"gold": ["fff1a8", "f2c94c", "a77a14"],
	"silver": ["ffffff", "c9d1dc", "7d8796"],
	"bronze": ["ffd2a1", "d08a4c", "7a4521"],
	"platinum": ["f4fbff", "b9cad8", "6f8193"],
	"rose": ["ffe0dc", "e7a59c", "9c5d55"],
	"crystal": ["ffffff", "b9ecff", "5aa9d6"],
	"ruby": ["ffb3bf", "e8445f", "7d1428"],
	"emerald": ["b6ffd9", "2fc77f", "0f6b40"],
	"sapphire": ["c2dcff", "3f7fe8", "17306f"],
	"obsidian": ["9a8cc0", "3b3650", "15121f"],
	"aurora": ["ffffff", "c7b6ff", "5f7fd6"],   # tegnes med regnbuetoner
}
const BASE_COLORS := {
	"marble": ["f1f1ee", "c9c9c4"],
	"onyx": ["3a3d46", "17181d"],
	"wood": ["9a6a43", "5d3c22"],
	"granite": ["8e9198", "55585f"],
	"jade": ["6fbf9a", "2f6e55"],
}
## Metaller som glitrer (små stjerner rundt pokalen).
const SPARKLY := ["platinum", "crystal", "ruby", "emerald", "sapphire", "aurora", "gold"]


## En ny tilfeldig pokal fra et frø. Samme frø gir alltid samme pokal.
static func generate(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return {
		"seed": seed,
		"shape": SHAPES[rng.randi() % SHAPES.size()],
		"metal": METALS[rng.randi() % METALS.size()],
		"handles": HANDLES[rng.randi() % HANDLES.size()],
		"emblem": EMBLEMS[rng.randi() % EMBLEMS.size()],
		"base": BASES[rng.randi() % BASES.size()],
	}


## Gjør en pokal fra JSON eller klienten gyldig: ukjente verdier byttes med de frøet gir.
static func normalize(d: Variant) -> Dictionary:
	var src: Dictionary = d if d is Dictionary else {}
	var out := generate(int(src.get("seed", 0)))
	for pair in [["shape", SHAPES], ["metal", METALS], ["handles", HANDLES], ["emblem", EMBLEMS], ["base", BASES]]:
		var v := str(src.get(pair[0], ""))
		if v in pair[1]:
			out[pair[0]] = v
	return out


## En pokal på en bruker: navnet som er gravert inn, utseendet, turneringen (0 = gitt av admin) og datoen.
static func entry(name: String, design: Variant, tournament_id: int, date: String) -> Dictionary:
	var n := name.strip_edges().substr(0, MAX_NAME)
	return { "name": n if n != "" else DEFAULT_NAME, "design": normalize(design), "tournament": tournament_id,
		"date": date.substr(0, 10) }


static func normalize_entry(e: Variant) -> Dictionary:
	if not e is Dictionary:
		return {}
	return entry(str(e.get("name", "")), e.get("design", {}), int(e.get("tournament", 0)), str(e.get("date", "")))
