extends SceneTree
## Lager oppgavebanken til dagens oppgave (ai/daily_bank.gd): «Vinn på N trekk» (stille trekk er lov,
## entydig løsning) og «Finn beste trekk» (eneste trekk som redder deg). De er for tunge å lage på
## serveren, så de lages her, på forhånd (runde 17). Kjør på nytt for flere:
##   godot --headless --path . -s res://tools/make_daily_bank.gd -- 30
## Argument: antall av hver type. «Vinn på N trekk» der vinnerlinjen går på kryss og tvers (gjennom
## flere høyder) kommer først i banken. Skriver fremdriften underveis.

const OUT := "res://ai/daily_bank.gd"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 30
	var t0 := Time.get_ticks_msec()
	var wins := []
	var tried := 0
	while wins.size() < count:
		var n := 3 if tried % 3 != 2 else 4
		var p := Puzzle.make_win("win-%d" % tried, n)
		tried += 1
		if not p.is_empty():
			wins.append(p)
			print("Vinn på %d: %d (%d forsøk, %ds)%s" % [n, wins.size(), tried, (Time.get_ticks_msec() - t0) / 1000,
				" på kryss og tvers" if p.cross else ""])
	# Kryss og tvers først (de mest spennende), ellers i den rekkefølgen de ble funnet
	var cross := wins.filter(func(p: Dictionary) -> bool: return p.cross)
	var other := wins.filter(func(p: Dictionary) -> bool: return not p.cross)
	wins = cross + other
	var defends := []
	tried = 0
	while defends.size() < count:
		var k := 3 if tried % 2 == 0 else 2
		var p := Puzzle.make_defend("defend-%d" % tried, k)
		tried += 1
		if not p.is_empty():
			defends.append(p)
			print("Finn beste trekk: %d (%d forsøk, %ds)" % [defends.size(), tried, (Time.get_ticks_msec() - t0) / 1000])
	var lines: Array[String] = []
	for i in wins.size():
		var p: Dictionary = wins[i]
		p.erase("cross")
		p.id = "w-%02d" % (i + 1)
		lines.append("\t" + JSON.stringify(p) + ",")
	for i in defends.size():
		var p: Dictionary = defends[i]
		p.id = "d-%02d" % (i + 1)
		lines.append("\t" + JSON.stringify(p) + ",")
	var code := "class_name DailyBank\nextends RefCounted\n## Ferdige oppgaver til dagens oppgave av typene win og defend (se Puzzle), laget av\n"
	code += "## tools/make_daily_bank.gd. Ikke rediger for hånd.\n\nconst PUZZLES := [\n%s\n]\n" % "\n".join(lines)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("Skrev %d oppgaver til %s på %ds." % [lines.size(), OUT, (Time.get_ticks_msec() - t0) / 1000])
	quit()
