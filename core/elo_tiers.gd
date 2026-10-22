class_name EloTiers
extends RefCounted
## Elo-nivåene (Bronse → Stormester) og hvilke merker på brikken de låser opp.
## Ligger i core/ fordi både klienten (merker og innstillinger) og serveren (sjekk av merker) bruker dem.
## Utseendet på nivå-merkene (farge og form) brukes av client/ui/elo_badge.gd.

const TIERS: Array[Dictionary] = [
	{ "id": "bronze", "name": "Bronse", "min": 0, "color": Color("c8814a"), "shape": "shield", "marks": 1 },
	{ "id": "silver", "name": "Sølv", "min": 1100, "color": Color("c3cad3"), "shape": "shield", "marks": 2 },
	{ "id": "gold", "name": "Gull", "min": 1250, "color": Color("f2c14e"), "shape": "shield", "marks": 3 },
	{ "id": "platinum", "name": "Platina", "min": 1400, "color": Color("4fd8c4"), "shape": "hexagon", "marks": 0 },
	{ "id": "diamond", "name": "Diamant", "min": 1550, "color": Color("6fb4ff"), "shape": "gem", "marks": 0 },
	{ "id": "master", "name": "Mester", "min": 1700, "color": Color("b67cff"), "shape": "crown", "marks": 0 },
	{ "id": "grandmaster", "name": "Stormester", "min": 1850, "color": Color("ff5470"), "shape": "seal", "marks": 0 },
]

## Merker på brikken som må låses opp (nivå-id). Resten kan alle bruke, også gjester.
## Startverdien 1200 er sølv, så en ny konto får sølv-merkene med en gang.
const DECAL_TIERS := {
	"diamond": "silver",
	"chevron": "silver",
	"hexagon": "gold",
	"moon": "gold",
	"bolt": "platinum",
	"crown": "diamond",
	"flame": "master",
	"laurel": "grandmaster",
}


## Nivået for en Elo-verdi.
static func tier(elo: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if elo >= int(t.min):
			out = t
	return out


## Neste nivå over denne Elo-verdien, eller {} på toppen.
static func next_tier(elo: int) -> Dictionary:
	for t in TIERS:
		if int(t.min) > elo:
			return t
	return {}


static func get_tier(id: String) -> Dictionary:
	for t in TIERS:
		if t.id == id:
			return t
	return {}


## Nivået som trengs for et merke, eller {} hvis det er åpent for alle.
static func required_tier(decal: String) -> Dictionary:
	return get_tier(str(DECAL_TIERS.get(decal, "")))


## Kan en spiller med denne Elo-en bruke merket? elo < 0 = gjest (bare de åpne merkene).
static func decal_unlocked(decal: String, elo: int) -> bool:
	var need := required_tier(decal)
	return need.is_empty() or (elo >= 0 and elo >= int(need.min))
