class_name BotProfile
extends RefCounted
## Vanskelighetsgrad for boten. Nivåene er bare ulike parametere for samme bot.

enum Level { EASY, MEDIUM, HARD }

var level: Level = Level.HARD
var display_name := "Vanskelig"
var take_win_chance := 1.0        ## Sjanse for å ta en direkte seier
var block_chance := 1.0           ## Sjanse for å blokkere en direkte trussel
var use_evaluation := true        ## Av = tilfeldig trekk (etter seier/blokk)
var use_force_search := true      ## Søk etter tvungne seire (dyrt, men sterkt)
var use_stacked := true           ## Se etter to vinnerplasser over hverandre
var opponent_force_search := true ## Vurder også om motstanderen kan tvinge seier
var random_margin := 0.0          ## Velg tilfeldig blant trekk innenfor denne marginen fra det beste
var think_time_s := 0.6           ## Kunstig tenketid, så det føles naturlig


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
			pass
	return p


static func level_names() -> Array[String]:
	return ["Lett", "Middels", "Vanskelig"]
