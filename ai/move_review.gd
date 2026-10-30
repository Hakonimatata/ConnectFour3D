class_name MoveReview
extends RefCounted
## AI-vurdering av et ferdig parti, trekk for trekk (runde 15, med søkeboten fra runde 17).
##
## Hver stilling i partiet vurderes én gang av søkeboten (SearchBot.begin_analysis, samme søk som
## Vanskelig og Ekspert spiller med): beste trekk og verdien for den som har tur. Verdien gjøres om til
## vinnersjanse (0–100 %), og et trekk koster det vinnersjansen falt fra stillingen før til stillingen
## etter, sett fra den som trakk. Slik analyserer sjakkprogrammer partier. Før (runde 15) så analysen
## bare ett trekk fram, og da fikk Ekspert-boten selv rundt 78 % treffsikkerhet.
##   accuracy  0–100 for trekket (100 = botens beste, eller like godt)
##   grade     best | good | inaccuracy | mistake | blunder | only (bare ett lovlig trekk, teller ikke)
##   reason    hvorfor et annet trekk var bedre (missed_win, missed_block, missed_force, allows_force,
##             under_own_threat, spent_threat, double, threat, hanging_three, block_three, better_spot)
##             – tom når trekket var best. under_own_threat og spent_threat handler om trekket som ble
##             spilt: det brukte opp en trussel (motstanderen bare blokkerer) uten å vinne noe på det
##   better    stedet (Vector3i) der brikken heller burde lagt (bare når trekket ikke var best).
##             Det er landingsplassen før trekket, i en annen kolonne enn trekket som ble spilt.
##   mate      missed_force: antall egne trekk til seieren som glapp. allows_force: til motstanderens
## evals[i] er vinnersjansen (%) til spiller 1 etter i trekk (stillingsmåleren i reprisen).
## summary() gir treffsikkerheten for hver spiller (snittet av trekkene), antall feil og tabber.
##
## Analysen gjøres litt etter litt: step() søker noen millisekunder om gangen og kalles hvert bilde til
## done() er sann. Da fryser ikke skjermen på telefon.
##
## Å bomme på en tvungen seier, eller gi motstanderen en, er «feil» (med tips), ikke «tabbe». Det skjer
## ofte i vanlige partier, og ellers ville nesten alt blitt rødt. Tabbe er å ikke vinne eller ikke
## blokkere når det står tre på rad (eller å miste mye av vinnersjansen på annen måte).
##
## Tre på rad er bare verdt noe så lenge motstanderen ikke kan blokkere den: en trussel som ikke kan
## spilles ennå, kan spares og brukes senere i en tvungen rekke. Søket gir derfor poeng for slike
## trusler, ikke for tre på rad som blokkeres med en gang (se SearchBot._eval og tempo_w).

const BEST := 98.0
const GOOD := 80.0
const INACCURACY := 50.0
const MISTAKE := 20.0
const MISSED_FORCE := 35.0    ## treffsikkerheten for et trekk som bommet på en tvungen seier
const ALLOWS_FORCE := 10.0    ## og for et som lot motstanderen få en
const DEPTH := 4              ## søkedybden (partall: se SearchBot.think)
const TIME_MS := 500          ## høyst så lenge per stilling (5×5×5 og trege telefoner)
const SLICE_USEC := 3000      ## så lenge ett step() søker
const SCALE := 120.0          ## poeng som gir ca. 73 % vinnersjanse (logistisk kurve)

var options: GameOptions
var first_player := 1
var moves: Array[Vector2i] = []
var results: Array = []         ## én Dictionary per trekk (se over)
var evals: Array[float] = []    ## vinnersjansen til spiller 1 etter i trekk
var depth := DEPTH
var time_ms := TIME_MS
var _scores: Array[int] = []    ## verdien for den som har tur, etter i trekk
var _info: Array = []           ## det som trengs om stillingen etter i trekk (se _position_info)
var _state: GameState           ## stillingen som vurderes nå (etter evals.size() trekk)
var _bot := SearchBot.new()
var _searching := false


func _init(p_options: GameOptions, p_first: int, p_moves: Array) -> void:
	options = p_options
	first_player = p_first
	# Bare trekk som er lovlige (en ødelagt trekkliste stopper analysen der den blir ugyldig)
	var s := GameState.new(options, first_player)
	for m in p_moves:
		var col: Vector2i = m if m is Vector2i else Vector2i(int(m[0]), int(m[1]))
		if s.is_over() or not col in s.legal_moves():
			break
		s.play(col, false)
		moves.append(col)
	_state = GameState.new(options, first_player)


func done() -> bool:
	return evals.size() > moves.size()


## Hvor langt analysen har kommet (0–1).
func progress() -> float:
	return float(evals.size()) / (moves.size() + 1)


## Hele partiet med en gang (testene og verktøy). I spillet brukes step() fra _process.
func run() -> MoveReview:
	while not done():
		step()
	return self


## Søker litt på stillingen som vurderes nå. Når den er ferdig, lagres verdien, trekket før den
## vurderes, og neste stilling står for tur.
func step() -> void:
	if done():
		return
	if _state.is_over():
		var mover_won := _state.result != GameState.Result.DRAW   # den som hadde tur nå, tapte
		_record(-SearchBot.WIN if mover_won else 0, Vector2i(-1, -1))
		return
	if not _searching:
		_bot.begin_analysis(_state, depth, time_ms)
		_searching = true
	if _bot.think(SLICE_USEC):
		_searching = false
		_record(_bot.score(), _bot.result())


## Spilleren som har tur etter i trekk (de bytter på).
func side(i: int) -> int:
	return first_player if i % 2 == 0 else GameState.opponent(first_player)


## Vinnersjansen (%) for den som har tur, ut fra søkets verdi.
static func win_percent(score: int) -> float:
	if score > SearchBot.MATE:
		return 100.0
	if score < -SearchBot.MATE:
		return 0.0
	return 100.0 / (1.0 + exp(-score / SCALE))


## Treffsikkerheten for et trekk som mistet så mange prosentpoeng vinnersjanse (samme kurve som
## Lichess: 0 → 100, 5 → 81, 15 → 51, 30 → 24).
static func accuracy_for_drop(drop: float) -> float:
	return 100.0 if drop <= 0.0 else clampf(103.1668 * exp(-0.04354 * drop) - 3.1669, 0.0, 100.0)


static func grade_of(acc: float) -> String:
	if acc >= BEST:
		return "best"
	if acc >= GOOD:
		return "good"
	if acc >= INACCURACY:
		return "inaccuracy"
	if acc >= MISTAKE:
		return "mistake"
	return "blunder"


## Hva et trekk gjør (til tipsene): double (to trusler), hanging_three (tre på rad som ikke kan
## blokkeres ennå), threat (motstanderen må blokkere), block_three (tar plassen motstanderen trenger
## for tre på rad som ikke kan blokkeres ennå), ellers better_spot. Brettet endres bare midlertidig.
static func explain(s: GameState, col: Vector2i, me: int) -> String:
	var opp := GameState.opponent(me)
	var n := s.n_lines
	var L := s.win_length
	var index := s.place(col, me)
	var threats := 0
	for c in s.open_columns():
		if s.wins_by(c, me):
			threats += 1
	var hanging := false
	var block_three := false
	for li in s.lines.cell_lines[index]:
		var mine := s.counts[me * n + li]
		var theirs := s.counts[opp * n + li]
		if theirs == 0 and mine == L - 1:
			for x in s.lines.cells[li]:
				if s.cells[x] == 0:
					var p := s.lines.pos_of(x)
					hanging = hanging or s.column_height(Vector2i(p.x, p.y)) != p.z
		elif mine == 1 and theirs == L - 2:
			# Bare verdt å nevne hvis motstanderens tre på rad her ikke kunne vært blokkert med en gang
			for x in s.lines.cells[li]:
				if s.cells[x] == 0:
					var p := s.lines.pos_of(x)
					block_three = block_three or s.column_height(Vector2i(p.x, p.y)) != p.z
	s.unplace(col)
	if threats >= 2:
		return "double"
	if hanging:
		return "hanging_three"   # det som varer: trusselen motstanderen må blokkere nå, er brukt opp etterpå
	if threats == 1:
		return "threat"
	if block_three:
		return "block_three"
	return "better_spot"


## Bruker trekket opp en trussel? "under_own_threat": brikken legges rett under en egen vinnerplass,
## så motstanderen kan blokkere den. "spent_threat": ny tre på rad der den siste plassen kan spilles
## med en gang. Ellers "" (også ved seier eller to trusler, da brukes ingenting opp).
static func spent_threat(s: GameState, col: Vector2i, me: int) -> String:
	var pos := s.landing_pos(col)
	var above := pos + Vector3i(0, 0, 1)
	var saved := above.z < s.size and s.is_winning_cell(s.lines.index_of(above), me)
	var index := s.place(col, me)
	var threats := 0
	if not s.is_win_at(index, me):
		for c in s.open_columns():
			if s.wins_by(c, me):
				threats += 1
	s.unplace(col)
	if threats != 1:
		return ""
	return "under_own_threat" if saved else "spent_threat"


## Treffsikkerhet per spiller: { 1: { accuracy, moves, best, mistakes, blunders }, 2: … }.
## Trekk der det bare fantes ett lovlig, teller ikke.
func summary() -> Dictionary:
	var out := {}
	for p in [1, 2]:
		var counted := results.filter(func(r: Dictionary) -> bool: return r.player == p and r.grade != "only")
		var sum := 0.0
		for r in counted:
			sum += float(r.accuracy)
		out[p] = {
			"accuracy": roundi(sum / counted.size()) if not counted.is_empty() else 100,
			"moves": counted.size(),
			"best": counted.filter(func(r: Dictionary) -> bool: return r.grade == "best").size(),
			"mistakes": counted.filter(func(r: Dictionary) -> bool: return r.grade == "mistake").size(),
			"blunders": counted.filter(func(r: Dictionary) -> bool: return r.grade == "blunder").size(),
		}
	return out


## Kort tekst om trekket (til repriser).
static func describe(r: Dictionary) -> String:
	match str(r.get("grade", "")):
		"only": return I18n.t("Eneste lovlige trekk.")
		"best": return I18n.t("Beste trekk.")
	var grade: String = {
		"good": I18n.t("Bra trekk."), "inaccuracy": I18n.t("Unøyaktig."),
		"mistake": I18n.t("Feil."), "blunder": I18n.t("Tabbe!"),
	}.get(str(r.grade), "")
	return "%s %s" % [grade, tip(str(r.reason), int(r.get("mate", 0)))]


## Tipset for en grunn (se explain og øverst), med den grønne markøren som viser det bedre trekket.
static func tip(reason: String, mate := 0) -> String:
	match reason:
		"missed_win": return I18n.t("Du kunne vunnet med en gang der den grønne markøren står.")
		"missed_block": return I18n.t("Motstanderen hadde tre på rad. Du måtte blokkere der den grønne markøren står.")
		"missed_force":
			return I18n.t("Herfra kunne du tvunget frem seier på %d trekk. Første trekk: den grønne markøren.") % mate
		"allows_force":
			return I18n.t("Trekket lar motstanderen tvinge frem seier på %d trekk. Bedre: den grønne markøren.") % mate
		"under_own_threat":
			return I18n.t("Du la rett under din egen trussel, så motstanderen kunne blokkere den. Spar slike trusler til de gir deg seier. Bedre: den grønne markøren.")
		"spent_threat":
			return I18n.t("Tre på rad som kan blokkeres med en gang, gir deg ingenting: trusselen er brukt opp. Bedre: den grønne markøren.")
		"double": return I18n.t("Bedre: den grønne markøren gir to trusler samtidig.")
		"threat": return I18n.t("Bedre: den grønne markøren tvinger motstanderen til å blokkere, og det gir deg en bedre stilling.")
		"hanging_three":
			return I18n.t("Bedre: den grønne markøren gir tre på rad som motstanderen ikke kan blokkere ennå. Spar den til den gir deg seier.")
		"block_three":
			return I18n.t("Bedre: den grønne markøren tar plassen motstanderen trenger for tre på rad som du ikke kan blokkere ennå.")
		"better_spot": return I18n.t("Den grønne markøren viser en bedre plass.")
	return ""


## Stillingsmålerens tekst for stillingen etter i trekk, og hvem som leder (0 = jevnt). Se eval_label.
func eval_text(i: int) -> Array:
	if i >= _scores.size():
		return ["", 0]
	if i == moves.size() and _state.is_over():
		return final_label(_state).slice(1)
	return eval_label(_scores[i], side(i)).slice(1)


## Stillingsmåleren for en verdi fra søket (for spilleren me som har tur): «Seier om 3» ved tvungen
## seier, ellers vinnersjansen til den som leder («62 %»).
## Gir [vinnersjansen til spiller 1, teksten, hvem som leder (0 = jevnt)].
static func eval_label(score: int, me: int) -> Array:
	var p := win_percent(score)
	var p1 := p if me == 1 else 100.0 - p
	var m := SearchBot.mate_in(score)
	if m != 0:
		return [p1, I18n.t("Seier om %d") % absi(m), me if m > 0 else GameState.opponent(me)]
	if absf(p1 - 50.0) < 2.0:
		return [p1, "50 %", 0]
	return [p1, "%d %%" % roundi(maxf(p1, 100.0 - p1)), 1 if p1 > 50.0 else 2]


## Stillingsmåleren når partiet er slutt.
static func final_label(s: GameState) -> Array:
	if s.result == GameState.Result.DRAW or s.winner() == 0:
		return [50.0, I18n.t("Uavgjort"), 0]
	return [100.0 if s.winner() == 1 else 0.0, I18n.t("Vunnet"), s.winner()]


## Hvorfor botens beste trekk er best (treningen: «Vis beste trekk»). info fra position_info, score
## fra søket (for den som har tur).
static func best_text(info: Dictionary, score: int) -> String:
	var m := SearchBot.mate_in(score)
	if not info.get("wins", []).is_empty():
		return I18n.t("Du kan vinne med en gang!")
	if int(info.get("blocks", 0)) == 1:
		return I18n.t("Blokker: motstanderen har tre på rad.")
	if m > 1:
		return I18n.t("Herfra kan du tvinge frem seier på %d trekk.") % m
	if m < 0:
		return I18n.t("Motstanderen kan tvinge frem seier uansett. Dette trekket holder lengst.")
	match str(info.get("why", "")):
		"double": return I18n.t("Gir to trusler samtidig. Motstanderen kan bare blokkere én.")
		"threat": return I18n.t("Tvinger motstanderen til å blokkere, og det gir deg en bedre stilling.")
		"hanging_three": return I18n.t("Gir tre på rad som motstanderen ikke kan blokkere ennå. Spar den til den gir deg seier.")
		"block_three": return I18n.t("Tar plassen motstanderen trenger for tre på rad som du ikke kan blokkere ennå.")
	return I18n.t("Gir flest muligheter videre (åpne linjer og trusler).")


# ---------------------------------------------------------------- Intern

## Lagrer vurderingen av stillingen etter i = evals.size() trekk, vurderer trekket før, og går videre.
func _record(score: int, best: Vector2i) -> void:
	var i := evals.size()
	_scores.append(score)
	var p := win_percent(score)
	evals.append(p if side(i) == 1 else 100.0 - p)
	_info.append(position_info(_state, best))
	if i > 0:
		results.append(judge(_info[i - 1], moves[i - 1], side(i - 1), _scores[i - 1], -score))
	if i < moves.size():
		_state.play(moves[i], false)
	else:
		_blame_hidden_losses()


## Søket ser ikke alltid en lang tvungen seier med en gang. Da ser det først tapet når taperen bare
## har tvungne trekk igjen (blokkeringer, som ikke teller), og trekket som faktisk tapte, slapp unna.
## Når en spiller står til tvunget tap (eller har tapt), får derfor spillerens siste frie trekk skylden
## (allows_force), hvis stillingen før det ikke allerede var tapt.
func _blame_hidden_losses() -> void:
	for k in range(2, _scores.size()):
		if _scores[k] > -SearchBot.MATE or _scores[k - 2] < -SearchBot.MATE:
			continue   # ikke tapt her, eller tapet ble sett allerede ved forrige trekk
		var j := k - 2   # spillerens trekk før denne stillingen (de bytter på)
		while j >= 0 and results[j].grade == "only":
			j -= 2
		if j < 0 or _scores[j] < -SearchBot.MATE:
			continue
		var r: Dictionary = results[j]
		var b: Dictionary = _info[j]
		if r.reason in ["allows_force", "missed_win", "missed_block"] or moves[j] == b.best:
			continue   # allerede en tabbe, eller boten ville spilt det samme (tapet lå enda tidligere)
		r.mate = (k - j) / 2 + maxi(0, -SearchBot.mate_in(_scores[k]))
		r.reason = "allows_force"
		r.accuracy = minf(float(r.accuracy), ALLOWS_FORCE)
		r.grade = grade_of(r.accuracy)
		r.drop = maxf(float(r.drop), win_percent(_scores[j]))
		r.better = b.best_pos


## Det vi må vite om stillingen før et trekk for å vurdere det (regnes mens stillingen står på
## brettet): vinnertrekk, hva som må blokkeres, botens beste trekk (best) med landingsplass og grunn,
## og trekkene som ville brukt opp en trussel (spends: kolonne -> spent_threat).
static func position_info(s: GameState, best: Vector2i) -> Dictionary:
	if s.is_over():
		return {}
	var me := s.current_player
	var opp := GameState.opponent(me)
	var legal := s.legal_moves()
	var info := { "only": legal.size() == 1, "win": Vector2i(-1, -1), "wins": [], "block": Vector2i(-1, -1), "blocks": 0,
		"best": best, "best_pos": Vector3i(-1, -1, -1), "why": "", "spends": {} }
	for c in legal:
		if s.wins_by(c, me):
			info.win = c
			info.wins.append(c)
		var spent := spent_threat(s, c, me)
		if spent != "":
			info.spends[c] = spent   # trekk som bruker opp en trussel (se spent_threat)
	for c in s.open_columns():
		if s.wins_by(c, opp):
			info.blocks += 1
			info.block = c
	if best.x >= 0 and s.is_column_open(best):
		info.best_pos = s.landing_pos(best)
		info.why = explain(s, best, me)
	if info.win.x >= 0:
		info.win_pos = s.landing_pos(info.win)
	if info.blocks > 0:
		info.block_pos = s.landing_pos(info.block)
	return info


## Vurderingen av et trekk: b = position_info før trekket, before = søkets verdi før trekket og
## after = verdien etter, begge for spilleren som trakk (after er motstanderens verdi med motsatt fortegn).
static func judge(b: Dictionary, col: Vector2i, player: int, before: int, after: int) -> Dictionary:
	var r := { "player": player, "col": col, "accuracy": 100.0, "grade": "best", "reason": "",
		"better": Vector3i(-1, -1, -1), "mate": 0, "drop": 0.0 }
	if b.is_empty() or b.only or (b.blocks >= 2 and b.win.x < 0):
		r.grade = "only"   # bare ett lovlig trekk, eller tapt uansett: teller ikke
		return r
	if b.win.x >= 0:
		if col in b.wins:
			return r
		return _miss(r, "missed_win", b.win_pos)
	if b.blocks == 1 and col != b.block:
		return _miss(r, "missed_block", b.block_pos)
	if col == b.best:
		return r
	var drop := maxf(0.0, win_percent(before) - win_percent(after))
	r.drop = drop
	var acc := accuracy_for_drop(drop)
	var reason := ""
	if acc < BEST:
		if SearchBot.mate_in(before) > 0 and SearchBot.mate_in(after) <= 0:
			reason = "missed_force"
			r.mate = SearchBot.mate_in(before)
			acc = maxf(acc, MISSED_FORCE)
		elif SearchBot.mate_in(after) < 0 and SearchBot.mate_in(before) >= 0:
			reason = "allows_force"
			r.mate = -SearchBot.mate_in(after)
			acc = maxf(acc, ALLOWS_FORCE)
		else:
			reason = str(b.why)
			# Brukte trekket opp en trussel (og det beste trekket gjorde ikke det samme), er det tipset
			var spent := str(b.get("spends", {}).get(col, ""))
			if spent != "" and not reason in ["double", "threat"]:
				reason = spent
	r.accuracy = acc
	r.grade = grade_of(acc)
	if r.grade != "best" and b.best_pos.x >= 0:
		r.reason = reason
		r.better = b.best_pos
	return r


static func _miss(r: Dictionary, reason: String, pos: Vector3i) -> Dictionary:
	r.accuracy = 0.0
	r.grade = "blunder"
	r.reason = reason
	r.better = pos
	r.drop = 100.0
	return r
