extends SceneTree
## Lager oppgavebanken til dagens oppgave (ai/daily_bank.gd): «Vinn på N trekk» (stille trekk er lov,
## entydig løsning) og «Finn beste trekk» (eneste trekk som redder deg). De er for tunge å lage på
## serveren, så de lages her, på forhånd (runde 17). Kjør på nytt for flere:
##   godot --headless --path . -s res://tools/make_daily_bank.gd -- 30 7 60 120
## Argumenter: antall av hver type (30), prosesser som leter samtidig (1), høyst så mange minutter (0 =
## til det er nok), og antall «Tving frem seier» (120). Skriver fremdriften underveis.
##
## Runde 19:
##   - «Vinn på N trekk» må gå i flere plan (Puzzle.make_win). De fleste ender likevel med samme triks:
##     tre trekk i samme kolonne (stacked). Med en tidsfrist letes det til halvparten er uten trikset
##     (eller tiden er ute), og de to slagene veksles i banken. Hver prosess (worker) skriver det den
##     finner til en fil i DIR, og hovedprosessen samler dem.
##   - «Tving frem seier» ligger også her. Med kravet om flere plan tok det opptil 8 sekunder å lage dem
##     når dagen kom, og serveren (eller nettleseren uten nett) sto stille så lenge. Høyst MAX_SAME av
##     dem har vinnerlinjen i samme retning, og motstanderens svar skal ta under MAX_REPLY_MS.
##   - Det som allerede ligger i banken og passer, beholdes.

const OUT := "res://ai/daily_bank.gd"
const SEED := "r19"
const DIR := "user://daily_bank"
const MAX_SAME := 0.4
const MAX_REPLY_MS := 120


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3 and args[0] == "worker":
		_worker(int(args[1]), int(args[2]))
		quit()
		return
	var count := int(args[0]) if args.size() > 0 else 30
	var jobs := maxi(1, int(args[1]) if args.size() > 1 else 1)
	var minutes := int(args[2]) if args.size() > 2 else 0
	var forced_count := int(args[3]) if args.size() > 3 else 120
	var t0 := Time.get_ticks_msec()
	var wins := []
	var defends := []
	var forced := []
	for old: Dictionary in DailyBank.PUZZLES:
		var p := old.duplicate(true)
		p.erase("id")
		match str(p.kind):
			"defend": defends.append(p)
			"forced": forced.append(p)
			_:
				if Puzzle.is_3d(p):
					wins.append(p)
	print("Beholder %d «Vinn på N trekk», %d «Finn beste trekk» og %d «Tving frem seier» fra banken."
		% [wins.size(), defends.size(), forced.size()])
	wins = _pick(_search_wins(wins, count, jobs, minutes, t0), count)

	var tried := 0
	while defends.size() < count:
		var k := 3 if tried % 2 == 0 else 2
		var p := Puzzle.make_defend("%s-defend-%d" % [SEED, tried], k)
		tried += 1
		if not p.is_empty():
			defends.append(p)
			print("Finn beste trekk: %d (%d forsøk, %ds)" % [defends.size(), tried, (Time.get_ticks_msec() - t0) / 1000])

	var same := {}
	for p: Dictionary in forced:
		var k := str(Puzzle.shape(p).final)
		same[k] = int(same.get(k, 0)) + 1
	tried = 0
	while forced.size() < forced_count:
		var p := Puzzle.generate("%s-forced-%d" % [SEED, tried])
		tried += 1
		if p.is_empty():
			continue
		var k := str(Puzzle.shape(p).final)
		if int(same.get(k, 0)) >= forced_count * MAX_SAME or Puzzle.slowest_reply_ms(p) > MAX_REPLY_MS:
			continue
		same[k] = int(same.get(k, 0)) + 1
		p.erase("day")
		p.kind = "forced"
		forced.append(p)
		if forced.size() % 10 == 0:
			print("Tving frem seier: %d (%d forsøk, %ds) %s" % [forced.size(), tried, (Time.get_ticks_msec() - t0) / 1000, str(same)])

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
	for i in forced.size():
		var p: Dictionary = forced[i]
		p.id = "f-%03d" % (i + 1)
		lines.append("\t" + JSON.stringify(p) + ",")
	var code := "class_name DailyBank\nextends RefCounted\n## Ferdige oppgaver til dagens oppgave (se Puzzle): forced, win og defend, laget av\n"
	code += "## tools/make_daily_bank.gd. Ikke rediger for hånd.\n\nconst PUZZLES := [\n%s\n]\n" % "\n".join(lines)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("Skrev %d oppgaver til %s på %ds." % [lines.size(), OUT, (Time.get_ticks_msec() - t0) / 1000])
	quit()


## Leter etter flere «Vinn på N trekk» med jobs prosesser, til det er count (med en tidsfrist: til
## halvparten er uten stablet slutt, eller tiden er ute). Gir det som er funnet, også de gamle.
func _search_wins(wins: Array, count: int, jobs: int, minutes: int, t0: int) -> Array:
	var plain := func(list: Array) -> int:
		return list.filter(func(p: Dictionary) -> bool: return not Puzzle.shape(p).stacked).size()
	if wins.size() >= count and (minutes == 0 or plain.call(wins) * 2 >= count):
		return wins
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	var pids: Array[int] = []
	for i in jobs:
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "-s", "res://tools/make_daily_bank.gd", "--", "worker", str(i), str(jobs)]))
	var found := []
	var shown := -1
	while true:
		OS.delay_msec(5000)
		found = wins + _collect()
		var n: int = plain.call(found)
		var late := minutes > 0 and Time.get_ticks_msec() - t0 > minutes * 60_000
		if found.size() != shown:
			shown = found.size()
			print("%ds: %d funnet, %d uten stablet slutt" % [(Time.get_ticks_msec() - t0) / 1000, found.size(), n])
		if found.size() >= count and (minutes == 0 or n * 2 >= count or late):
			break
	FileAccess.open(DIR.path_join("stop"), FileAccess.WRITE).close()
	for pid in pids:
		while OS.is_process_running(pid):
			OS.delay_msec(200)
	return wins + _collect()


## En prosess som leter: frø nummer index, index + jobs, … til hovedprosessen sier stopp.
func _worker(index: int, jobs: int) -> void:
	var path := DIR.path_join("win_%d.jsonl" % index)
	var tried := index
	while not FileAccess.file_exists(DIR.path_join("stop")):
		var n := 3 if tried % 3 != 2 else 4
		var p := Puzzle.make_win("%s-win-%d" % [SEED, tried], n)
		tried += jobs
		if p.is_empty():
			continue
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		f.seek_end()
		f.store_line(JSON.stringify(p))
		f.close()


func _collect() -> Array:
	var out := []
	for name in DirAccess.get_files_at(DIR):
		if name.ends_with(".jsonl"):
			for line in FileAccess.get_file_as_string(DIR.path_join(name)).split("\n", false):
				var p: Variant = JSON.parse_string(line)
				if p is Dictionary:
					out.append(_ints(p))
	return out


## JSON gir tall som float. Oppgavene i banken skal ha heltall, som før.
static func _ints(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		return (v as Array).map(_ints)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _ints(v[k])
		return d
	return v


## Velger count oppgaver: alle uten stablet slutt først (høyst halvparten), så fylles det opp med de
## stablede. I banken veksler de, og de med vinnerlinjen på kryss og tvers kommer tidlig i hver gruppe.
static func _pick(found: Array, count: int) -> Array:
	var by_cross := func(a: Dictionary, b: Dictionary) -> bool:
		return _cross(a) and not _cross(b)
	var plain := found.filter(func(p: Dictionary) -> bool: return not Puzzle.shape(p).stacked)
	var stacked := found.filter(func(p: Dictionary) -> bool: return Puzzle.shape(p).stacked)
	plain.sort_custom(by_cross)
	stacked.sort_custom(by_cross)
	plain = plain.slice(0, maxi(count / 2, count - stacked.size()))
	stacked = stacked.slice(0, count - plain.size())
	var out := []
	while not plain.is_empty() or not stacked.is_empty():
		if not plain.is_empty():
			out.append(plain.pop_front())
		if not stacked.is_empty():
			out.append(stacked.pop_front())
	return out


static func _cross(p: Dictionary) -> bool:
	return Puzzle.shape(p).final in ["slant", "space"]
