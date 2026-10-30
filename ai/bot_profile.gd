class_name BotProfile
extends RefCounted
## Vanskelighetsgrad for boten. Lett og Middels er den regelbaserte boten med ulike parametere.
## Vanskelig og Ekspert søker (SearchBot) i search_ms millisekunder; Ekspert får tenke lenger.

enum Level { EASY, MEDIUM, HARD, EXPERT }

var level: Level = Level.HARD
var display_name := "Vanskelig"
var take_win_chance := 1.0        ## Sjanse for å ta en direkte seier
var block_chance := 1.0           ## Sjanse for å blokkere en direkte trussel
var use_evaluation := true        ## Av = tilfeldig trekk (etter seier/blokk)
var use_force_search := true      ## Søk etter tvungne seire (dyrt, men sterkt)
var use_stacked := true           ## Se etter to vinnerplasser over hverandre
var opponent_force_search := true ## Vurder også om motstanderen kan tvinge seier
var random_margin := 0.0          ## Velg tilfeldig blant trekk innenfor denne marginen fra det beste
var think_time_s := 0.6           ## Kunstig tenketid, så det føles naturlig (minst så lenge)
var search_ms := 0                ## > 0: bruk søket (SearchBot) og tenk så lenge per trekk
var search_depth := 64            ## Høyeste søkedybde
var search_tweaks := {}           ## Andre vekter i søkets evaluering (bare for tools/ai_arena.gd), f.eks. { "parity_w": 0 }


static func create(p_level: Level) -> BotProfile:
	var p := BotProfile.new()
	p.level = p_level
	match p_level:
		Level.EASY:
			p.display_name = "Lett"
			p.take_win_chance = 0.7
			p.block_chance = 0.35
			p.use_evaluation = false
		Level.MEDIUM:
			p.display_name = "Middels"
			p.block_chance = 0.9
			p.use_force_search = false
			p.use_stacked = false
			p.opponent_force_search = false
			p.random_margin = 3.0
		Level.HARD:
			p.search_ms = 1000
		Level.EXPERT:
			p.display_name = "Ekspert"
			p.search_ms = 2500
			p.think_time_s = 0.3
	return p


## Den gamle vanskelige boten (før runde 16), uten søk. Brukes til å måle at den nye er bedre.
static func legacy_hard() -> BotProfile:
	return create(Level.HARD).with_search(0)


func with_search(ms: int) -> BotProfile:
	search_ms = ms
	return self


static func level_names() -> Array[String]:
	return ["Lett", "Middels", "Vanskelig", "Ekspert"]
