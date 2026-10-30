class_name Progression
extends RefCounted
## XP, nivåer og opplåsing av skins og seiersanimasjoner (runde 17). Ligger i core/ fordi både klienten
## (innstillinger, profil, resultat) og serveren (XP etter partier, oppgaver og turneringer, og sjekk av
## utseendet andre ser) bruker det.
##
## XP får bare kontoer, og bare for det serveren selv kan sjekke:
##   parti mot en annen konto  seier 20–50 (mer jo sterkere motstanderen er), uavgjort 15, tap 8.
##                             Partiet må ha minst MIN_MOVES trekk, høyst SAME_OPPONENT_DAILY partier mot
##                             samme motstander per dag gir XP, og høyst DAILY_GAME_XP per dag fra partier
##                             (så to kontoer ikke kan «farme» hverandre).
##   dagens oppgave            25, pluss 5 per dag på rad (høyst +50): lange rekker lønner seg.
##   rangert turnering         etter plassering: vinner 150, finalist 75, semifinale 40, ellers 20.
## Partier mot boten gir ingenting: de spilles uten server og kan ikke sjekkes (og å slå Lett-boten
## skal ikke gi noe uansett).
##
## Nivå: 100 XP til nivå 2, og 50 mer for hvert nivå etter det (nivå 10 ved 2700 XP, nivå 20 ved 10 450).
## UNLOCKS: nivået som låser opp en ting, eller en prestasjon (vinn en rangert turnering, 7 dager på rad
## med dagens oppgave). Det som ikke står der, er åpent for alle, også gjester og uten nett.
## I tillegg kan en turnering ha en premie (prize) admin velger, og vinneren får den uansett nivå.
## Det en spiller brukte før XP fantes, beholder hen (unlocks på kontoen, se Store.normalize_user).
## progress (fra kontoen): { xp, unlocks: [ting], tournaments_won, best_puzzle_streak }. {} = gjest.

const MIN_MOVES := 10
const SAME_OPPONENT_DAILY := 3
const DAILY_GAME_XP := 400
const PUZZLE_XP := 25
const PUZZLE_STREAK_XP := 5
const PUZZLE_STREAK_MAX := 10
const TOURNAMENT_XP := { "winner": 150, "final": 75, "semi": 40, "played": 20 }
const TOURNAMENT := "tournament"   ## prestasjon: har vunnet en rangert turnering
const STREAK_7 := "streak7"        ## prestasjon: 7 dager på rad med dagens oppgave
const LEVEL_EVENTS := [5, 10, 15, 20, 25, 30]   ## nivåene som kunngjøres i den globale chatten

## Ting: "skin:<id>" og "fx:<id>" (Skins.ALL og Skins.WIN_FX).
const UNLOCKS := {
	"skin:gold": 2, "skin:ceramic": 3, "skin:violet": 4, "skin:copper": 5, "skin:racing": 6, "skin:carbon": 7,
	"skin:glass": 8, "skin:midnight": 9, "skin:lava": 10, "skin:mint": 11, "skin:rose": 12, "skin:aurora": 13,
	"skin:pixel": 14, "skin:damascus": 15, "skin:circuit": 16, "skin:opal": 17, "skin:code": 18,
	"skin:kintsugi": 20, "skin:toxic": 22, "skin:disco": 24, "skin:plasma": 26, "skin:blackhole": 30,
	"skin:champion": TOURNAMENT, "skin:dawn": STREAK_7,
	"fx:fireworks": 3, "fx:shockwave": 6, "fx:glitter": 9, "fx:lightning": 12, "fx:supernova": 16, "fx:chaos": 20,
}


## Samlet XP som trengs for et nivå (nivå 1 = 0).
static func xp_for_level(level: int) -> int:
	var l := maxi(level, 1) - 1
	return 100 * l + 25 * l * (l - 1)


static func level_for(xp: int) -> int:
	var level := 1
	while xp_for_level(level + 1) <= xp:
		level += 1
	return level


## Progresjonen fra en konto (eller det klienten har fått om den). {} gir en gjest uten noe låst opp.
static func progress_of(user: Dictionary) -> Dictionary:
	var stats: Dictionary = user.get("stats", {}) if user.get("stats") is Dictionary else {}
	return { "xp": int(user.get("xp", 0)), "unlocks": (user.get("unlocks", []) as Array).duplicate(),
		"tournaments_won": int(stats.get("tournaments_won", user.get("tournaments_won", 0))),
		"best_puzzle_streak": int(stats.get("best_puzzle_streak", user.get("best_puzzle_streak", 0))) }


static func is_unlocked(item: String, progress: Dictionary) -> bool:
	if not UNLOCKS.has(item) or item in progress.get("unlocks", []):
		return true
	var need = UNLOCKS[item]
	if need is int:
		return level_for(int(progress.get("xp", 0))) >= need
	if need == TOURNAMENT:
		return int(progress.get("tournaments_won", 0)) > 0
	if need == STREAK_7:
		return int(progress.get("best_puzzle_streak", 0)) >= 7
	return false


## Hva som trengs for å låse opp («Nivå 5», «Vinn en rangert turnering» …), eller "" hvis åpen.
static func requirement_text(item: String) -> String:
	if not UNLOCKS.has(item):
		return ""
	var need = UNLOCKS[item]
	if need is int:
		return I18n.t("Nivå %d") % need
	if need == TOURNAMENT:
		return I18n.t("Vinn en rangert turnering")
	return I18n.t("Løs dagens oppgave 7 dager på rad")


## Kort versjon til knapper («Nivå 10», «Turnering», «7 på rad»).
static func requirement_short(item: String) -> String:
	var need = UNLOCKS.get(item, 0)
	if need is int:
		return I18n.t("Nivå %d") % need if need > 0 else ""
	return I18n.t("Turnering") if need == TOURNAMENT else I18n.t("7 på rad")


## Sorteringsnøkkel: det som er låst opp først (i vanlig rekkefølge), så etter nivået som trengs, og
## prestasjonene sist.
static func sort_key(item: String, progress: Dictionary, index: int) -> int:
	if is_unlocked(item, progress):
		return index
	var need = UNLOCKS.get(item, 0)
	return 10_000 + (int(need) * 100 if need is int else 90_000) + index


## Skins i rekkefølgen velgerne viser dem (se sort_key).
static func sorted_skins(progress: Dictionary) -> Array:
	var keyed := []
	for i in Skins.ALL.size():
		keyed.append([sort_key("skin:" + str(Skins.ALL[i].id), progress, i), Skins.ALL[i]])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return keyed.map(func(e: Array) -> Dictionary: return e[1])


## Alle ting som kan låses opp (skins og seiersanimasjoner), i rekkefølge.
static func items() -> Array[String]:
	var out: Array[String] = []
	for s in Skins.ALL:
		out.append("skin:" + str(s.id))
	for f in Skins.WIN_FX:
		out.append("fx:" + str(f.id))
	return out


## Det som ble låst opp mellom to progresjoner (til «Låst opp: Lava» etter et parti).
static func newly_unlocked(before: Dictionary, after: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for item in items():
		if UNLOCKS.has(item) and is_unlocked(item, after) and not is_unlocked(item, before):
			out.append(item)
	return out


## Navnet på en ting («Lava», «Fyrverkeri»).
static func item_name(item: String) -> String:
	var id := item.get_slice(":", 1)
	if item.begins_with("skin:"):
		return I18n.t(str(Skins.get_skin(id).name))
	for f in Skins.WIN_FX:
		if f.id == id:
			return I18n.t(str(f.name))
	return id


## Utseendet med låste ting byttet ut (skin: standard, seiersanimasjon: klassisk). Merker låses av Elo
## (EloTiers), ikke her.
static func allowed_look(look: Dictionary, progress: Dictionary, default_skin := Skins.DEFAULT_P1) -> Dictionary:
	var out := look.duplicate()
	if not is_unlocked("skin:" + str(look.get("skin", "")), progress):
		out.skin = default_skin
	if not is_unlocked("fx:" + str(look.get("win_fx", "")), progress):
		out.win_fx = "classic"
	return out


## XP for et parti mot en annen konto: score 1 = seier, 0.5 = uavgjort, 0 = tap. Seier gir mer mot en
## sterkere motstander (20 mot en mye svakere, 35 mot en like god, 50 mot en mye sterkere).
static func game_xp(score: float, my_elo: int, opp_elo: int) -> int:
	if score >= 1.0:
		var expected := 1.0 / (1.0 + pow(10.0, (opp_elo - my_elo) / 400.0))
		return roundi(20.0 + 30.0 * (1.0 - expected))
	return 15 if score > 0.0 else 8


## XP for dagens oppgave med denne rekken (dager på rad, i dag medregnet).
static func puzzle_xp(streak: int) -> int:
	return PUZZLE_XP + PUZZLE_STREAK_XP * clampi(streak - 1, 0, PUZZLE_STREAK_MAX)


## XP til eksisterende kontoer da XP kom (runde 17), ut fra statistikken, så aktive spillere ikke
## begynner på nivå 1.
static func backfill_xp(stats: Dictionary) -> int:
	return int(stats.get("wins", 0)) * 30 + int(stats.get("draws", 0)) * 15 + int(stats.get("losses", 0)) * 8 \
		+ int(stats.get("puzzles_solved", 0)) * PUZZLE_XP + int(stats.get("tournaments_won", 0)) * TOURNAMENT_XP.winner
