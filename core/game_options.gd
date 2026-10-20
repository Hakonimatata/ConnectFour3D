class_name GameOptions
extends RefCounted
## Innstillinger for ett parti. Delt av klient, AI og server.
## Se Plan.md, seksjon 2.4.

const SIZES: Array[int] = [4, 5]
const STARTERS: Array[String] = ["p1", "p2", "random", "alternate"]

var size: int = 4                 ## Brettet er size × size × size
var win_length: int = 4           ## Antall på rad som trengs for å vinne
var must_block: bool = false      ## «Må blokkere»
var no_gift: bool = false         ## «Ikke gi bort seier»
var time_base_s: int = 0          ## 0 = uten klokke
var time_increment_s: int = 0     ## Sekunder lagt til etter hvert trekk
var starter: String = "p1"        ## Hvem starter: p1, p2, random, alternate


func has_clock() -> bool:
	return time_base_s > 0


## Hvem starter parti nummer `number` (1, 2, 3, ...)? Spiller 1 er verten / «jeg».
func first_player(number: int, rng: RandomNumberGenerator) -> int:
	match starter:
		"p2": return 2
		"random": return 1 + rng.randi() % 2
		"alternate": return 1 if number % 2 == 1 else 2
	return 1


func duplicate_options() -> GameOptions:
	return GameOptions.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"size": size,
		"win_length": win_length,
		"must_block": must_block,
		"no_gift": no_gift,
		"time_base_s": time_base_s,
		"time_increment_s": time_increment_s,
		"starter": starter,
	}


## Lager innstillinger fra en Dictionary (f.eks. fra nettverket).
## Ugyldige eller manglende verdier erstattes med standardverdier.
static func from_dict(d: Dictionary) -> GameOptions:
	var o := GameOptions.new()
	var s := int(d.get("size", o.size))
	o.size = s if s in SIZES else 4
	o.win_length = clampi(int(d.get("win_length", o.win_length)), 3, o.size)
	o.must_block = bool(d.get("must_block", o.must_block))
	o.no_gift = bool(d.get("no_gift", o.no_gift))
	o.time_base_s = clampi(int(d.get("time_base_s", o.time_base_s)), 0, 3600)
	o.time_increment_s = clampi(int(d.get("time_increment_s", o.time_increment_s)), 0, 60)
	var st := str(d.get("starter", o.starter))
	o.starter = st if st in STARTERS else "p1"
	return o


## Kort tekst for visning, f.eks. «4×4×4 · Må blokkere · 3+2».
func describe() -> String:
	var parts: Array[String] = ["%d×%d×%d" % [size, size, size]]
	if must_block:
		parts.append(tr("Må blokkere"))
	if no_gift:
		parts.append(tr("Ikke gi bort seier"))
	if has_clock():
		parts.append("%d+%d" % [time_base_s / 60, time_increment_s] if time_base_s % 60 == 0 \
			else "%ds+%d" % [time_base_s, time_increment_s])
	else:
		parts.append(tr("Uten klokke"))
	return " · ".join(parts)
