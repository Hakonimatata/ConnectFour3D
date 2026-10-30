class_name SearchBot
extends RefCounted
## Den sterke boten (runde 16): alfa-beta-søk med iterativ fordypning og transposisjonstabell,
## og en evaluering av hele brettet. Brukes av Bot når profilen har search_ms > 0 (Vanskelig og Ekspert).
##
## - Søket følger reglene («må blokkere», «ikke gi bort seier») akkurat som GameState.legal_moves().
## - Tvungne trekk (blokkering) teller ikke som dybde. Når dybden er brukt opp, søkes videre bare på
##   trekk som lager en trussel motstanderen må blokkere (som tvangssøket i Bot), så en tvungen seier
##   ikke gjemmer seg bak horisonten.
## - Evalueringen: åpne linjer (jo flere egne brikker, jo mer), trusler som ikke kan spilles ennå,
##   den laveste trusselen i en kolonne, to trusler over hverandre, og høyden truslene står på
##   (paritet: den som startet tjener på trusler på 1., 3., … høyde, den andre på 2., 4., …).
## - Egne, kompakte tabeller i stedet for GameState. Evalueringen og vinnerplassene oppdateres for
##   hvert trekk (bare linjene gjennom cellen), så hver node er billig.
##   Trekklistene ligger i én fast tabell (ingen nye lister per node), evalueringen ser bare på
##   kolonner som har trusler, og sene trekk som sjelden er best, søkes først grunnere (LMR).
## - Tenker i små biter: begin() og så think(µs) til den gir true. Da fryser ikke spillet
##   (web-eksporten har ikke tråder). choose() gjør alt på en gang (tester og verktøy).
## - begin_analysis() vurderer en stilling i stedet (AI-analysen, stillingsmåleren og treningen):
##   ingen snarveier eller tilfeldig åpning, og score() gir verdien for spilleren som har tur.

const WIN := 1_000_000
const INF := 2_000_000
const MATE := WIN - 1000        ## |score| over dette = tvungen seier eller tap
const MAX_PLY := 120
const Q_DEPTH := 6              ## hvor mange egne trusler på rad det taktiske søket prøver
const TT_BITS := 17
const TT_MASK := (1 << TT_BITS) - 1
const EXACT := 0
const LOWER := 1
const UPPER := 2
const WIN_NOW := -1             ## fra _gen: spilleren kan vinne med en gang
const LOST := -2                ## fra _gen: motstanderen har to vinnerplasser som kan spilles
const MAX_MOVES := 32           ## plass per ply i trekktabellen (5×5×5 har 25 kolonner)

# Evalueringen (poeng). Justert med tools/ai_arena.gd (variabler, så arenaen kan prøve andre verdier).
var threat_w := 60              ## en vinnerplass som ikke kan spilles ennå
var lowest_w := 40              ## … og den er den laveste trusselen i kolonnen
var stack_w := 250              ## … og spilleren har en trussel rett under (kan ikke blokkeres begge)
var parity_w := 30              ## … og den står på «riktig» høyde for spilleren
var line3_w := 30               ## åpen linje med én brikke igjen til seier (fire på rad: tre egne)
var line2_w := 10               ## … to igjen
var line1_w := 2                ## … tre igjen (lengre igjen: 1)
var vcf_depth := 0              ## sjekk motstanderens trusselrekker nederst i søket (0 = av: målt svakere, koster for mye tid)
var exact := false              ## eksakt søk (oppgavene): ingen forlengelser eller reduksjoner, så «seier om N» er den korteste innen dybden

var size := 0
var win_length := 0
var n_cols := 0
var n_cells := 0
var n_lines := 0
var must_block := true
var no_gift := true
var first := 1                  ## spilleren som startet partiet (for pariteten)
var side := 1                   ## spilleren som har tur i søket

var _line_cells: Array[PackedInt32Array] = []
var _cell_lines: Array[PackedInt32Array] = []
var _cells := PackedByteArray()
var _heights := PackedByteArray()
var _counts := PackedInt32Array()   ## [spiller * n_lines + linje] = brikker i linjen
var _wins := PackedInt32Array()     ## [spiller * n_cells + celle] = linjer cellen ville fullført
var _line_w := PackedInt32Array()   ## verdien av en åpen linje med k egne brikker
var _line_score := 0                ## sum av linjeverdiene, spiller 1 minus spiller 2
var _filled := 0
var _static := PackedInt32Array()   ## celle -> antall linjer gjennom den (midten og hjørnene først)
var _zobrist := PackedInt64Array()
var _hash := 0
var _tt_key := PackedInt64Array()
var _tt_val := PackedInt32Array()
var _tt_meta := PackedInt32Array()  ## dybde << 8 | flagg << 6 | kolonne
var _history := PackedInt32Array()  ## [spiller * n_cols + kolonne] = hvor ofte trekket ga kutt
var _killers := PackedInt32Array()  ## to «drapstrekk» per ply
var _mv := PackedInt32Array()       ## trekklistene: ply * MAX_MOVES + i
var _sc := PackedInt32Array()       ## sorteringsverdiene til trekkene
var _col_threats := PackedInt32Array()  ## kolonne -> antall (spiller, celle) med vinnerplass (også fylte)
var _threat_cells := PackedInt32Array() ## spiller -> antall celler med vinnerplass (også fylte)
var _open2 := PackedInt32Array()    ## spiller -> linjer med win_length - 2 egne og ingen andre
var _vcf_cache := {}            ## (hash, dybde, spiller) -> om spilleren har en tvungen trusselrekke (tømmes per trekk)
var _win_col := -1
var _deadline := 0
var _aborted := false
var nodes := 0
var rng := RandomNumberGenerator.new()

# Tenkingen (iterativ fordypning, kan fortsette over flere bilder)
var max_depth := 64
var _root := PackedInt32Array()
var _root_scores := PackedInt32Array()
var _depth := 0
var _index := 0
var _alpha := 0
var _best := -1
var _best_score := 0
var _iter_best := -1
var _iter_score := 0
var _trusted := -1              ## beste trekk fra siste ferdige partallsdybde (se think)
var _trusted_score := 0
var _result_score := 0
var _analysis := false          ## begin_analysis: vurder stillingen, ikke bare velg et trekk
var _limit := 0
var _done := true
var _result := -1
var depth_reached := 0          ## dybden som ble søkt ferdig (til feilsøking og målinger)


func _init() -> void:
	rng.randomize()


## Velger et trekk på en gang (tester og verktøy). time_ms = hvor lenge den får tenke.
func choose(state: GameState, time_ms: int, depth_limit := 64) -> Vector2i:
	begin(state, time_ms, depth_limit)
	while not think(1_000_000):
		pass
	return result()


func result() -> Vector2i:
	return Vector2i(_result % size, _result / size)


## Verdien av stillingen for spilleren som hadde tur (etter begin_analysis): over MATE er tvungen
## seier, under -MATE tvunget tap (se mate_in). Ellers poeng fra evalueringen.
func score() -> int:
	return _result_score


## Antall egne trekk til tvungen seier (positivt) eller tap (negativt) for en poengsum, ellers 0.
## WIN - k betyr at spilleren som har tur vinner k ply ut i søket (k = 0: vinner med dette trekket).
static func mate_in(s: int) -> int:
	if s > MATE:
		return (WIN - s) / 2 + 1
	if s < -MATE:
		return -((WIN + s + 1) / 2)
	return 0


func is_done() -> bool:
	return _done


## Starter tenkingen på stillingen. Enkle tilfeller (bare ett trekk, vinn, blokker, første trekk)
## avgjøres med en gang.
func begin(state: GameState, time_ms: int, depth_limit := 64) -> void:
	_begin(state, time_ms, depth_limit, false)


## Vurderer stillingen: søker til depth_limit (bruk et partall) eller til tiden er ute, og gir beste
## trekk (result) og verdien (score). Kall think() til den gir true. Partiet kan ikke være ferdig.
func begin_analysis(state: GameState, depth_limit: int, time_ms: int) -> void:
	_begin(state, time_ms, depth_limit, true)


func _begin(state: GameState, time_ms: int, depth_limit: int, analysis: bool) -> void:
	_analysis = analysis
	_setup(state)
	if _filled <= 2:
		_tt_key.fill(0)   # nytt parti (kanskje med en annen som startet): glem gamle stillinger
	max_depth = depth_limit
	_vcf_cache.clear()
	_done = false
	_root = PackedInt32Array()
	for col in state.legal_moves():
		_root.append(col.x + size * col.y)
	var p := side
	var pc := p * n_cells
	var oc := (3 - p) * n_cells
	for c in _root:
		if _wins[pc + _landing(c)] > 0:
			_finish(c, WIN)
			return
	if _root.size() == 1 and not analysis:
		_finish(_root[0])
		return
	for c in _root:
		if analysis:
			break   # analysen trenger verdien, så blokkeringen søkes som alle andre trekk
		if _wins[oc + _landing(c)] > 0:
			_finish(c)   # må blokkere (har motstanderen to, er partiet tapt uansett)
			return
	# Første trekk for hver spiller: tilfeldig blant de beste plassene, så boten ikke er forutsigbar
	if _filled < 2 and not analysis:
		var top := 0
		for c in _root:
			top = maxi(top, _static[_landing(c)])
		var options := Array(_root).filter(func(c: int) -> bool: return _static[_landing(c)] == top)
		_finish(options[rng.randi() % options.size()])
		return
	for i in _history.size():
		_history[i] >>= 2   # gammel kunnskap teller mindre
	# Rotrekkene sorteres som i søket (historikk og plasser med mange linjer)
	var n := _root.size()
	for i in n:
		_mv[i] = _root[i]
	_order(0, n, p, -1, -1, -1)
	for i in n:
		_root[i] = _mv[i]
	_root_scores.resize(n)
	_root_scores.fill(0)
	_depth = 1
	_index = 0
	_alpha = -INF
	_best = _root[0]
	_best_score = 0
	_iter_best = -1
	_iter_score = -INF
	depth_reached = 0
	_trusted = -1
	_trusted_score = 0
	_limit = Time.get_ticks_usec() + time_ms * 1000


## Tenker høyst budget_usec mikrosekunder. Gir true når trekket er valgt (se result()).
func think(budget_usec: int) -> bool:
	if _done:
		return true
	var p := side
	_deadline = mini(Time.get_ticks_usec() + budget_usec, _limit)
	while true:
		if _index >= _root.size():
			# Dybden er søkt ferdig. Bare partallsdybder (2, 4, …) brukes til å velge trekket: ved
			# oddetall har motstanderen tur nederst, og da overses våre egne trusselrekker (målt med
			# tools/ai_arena.gd: dybde 2 og 4 slo den gamle boten 96 % og 75 %, dybde 3 bare 19–34 %).
			# Oddetallsdybdene sorterer trekkene for neste dybde. Tvungen seier eller tap er sikkert uansett.
			_best = _iter_best
			_best_score = _iter_score
			depth_reached = _depth
			if _depth % 2 == 0 or absi(_best_score) > MATE:
				_trusted = _iter_best
				_trusted_score = _iter_score
			_sort_root()
			if absi(_best_score) > MATE or _depth >= max_depth or _depth >= n_cells - _filled:
				return _finish(_best, _best_score)
			_depth += 1
			_index = 0
			_alpha = -INF
			_iter_best = -1
			_iter_score = -INF
			continue
		if Time.get_ticks_usec() >= _limit:
			return _timeout_finish()
		var c := _root[_index]
		_aborted = false
		_place(c, p)
		side = 3 - p
		var v := -_search(_depth - 1, -INF, -_alpha, 1, Q_DEPTH)
		side = p
		_unplace(c, p)
		if _aborted:
			if Time.get_ticks_usec() >= _limit:
				return _timeout_finish()
			return false   # tiden for dette bildet er brukt; fortsett neste gang (tabellen husker det som er gjort)
		_root_scores[_index] = v
		if v > _iter_score:
			_iter_score = v
			_iter_best = c
		_alpha = maxi(_alpha, v)
		_index += 1
		if Time.get_ticks_usec() >= _deadline:
			return false
	return false


## Tiden er ute midt i en dybde. Er det en partallsdybde, og det første trekket (det beste fra forrige
## dybde) er søkt ferdig, er det beste av de ferdige trekkene minst like godt. Ellers: siste partallsdybde.
func _timeout_finish() -> bool:
	if _depth % 2 == 0 and _index > 0 and _iter_best >= 0:
		return _finish(_iter_best, _iter_score)   # en partallsdybde er delvis søkt: det beste av de ferdige trekkene
	if _trusted >= 0:
		return _finish(_trusted, _trusted_score)
	return _finish(_best, _best_score)


func _finish(c: int, s := 0) -> bool:
	_result = c
	_result_score = s
	_done = true
	return true


func _sort_root() -> void:
	# Beste først, så resten etter forrige poengsum (enkel innsettingssortering, høyst 25 trekk)
	for i in range(1, _root.size()):
		var m := _root[i]
		var s := _root_scores[i] + (INF if m == _best else 0)
		var j := i - 1
		while j >= 0 and _root_scores[j] + (INF if _root[j] == _best else 0) < s:
			_root[j + 1] = _root[j]
			_root_scores[j + 1] = _root_scores[j]
			j -= 1
		_root[j + 1] = m
		_root_scores[j + 1] = s - (INF if m == _best else 0)


# ---------------------------------------------------------------- Søket

func _search(depth: int, alpha: int, beta: int, ply: int, q: int) -> int:
	nodes += 1
	if (nodes & 255) == 0 and Time.get_ticks_usec() > _deadline:
		_aborted = true
	if _aborted:
		return 0
	if ply >= MAX_PLY + 30:
		return _eval(side)   # svært lang tvungen rekke: stopp her
	var p := side
	var base := ply * MAX_MOVES
	var n := _gen(p, base)
	if n == WIN_NOW:
		return WIN - ply
	if n == LOST:
		return -(WIN - ply - 1)
	if n == 0:
		return 0   # brettet er fullt: uavgjort
	if n == 1 and ply < MAX_PLY and not exact:
		# Tvunget trekk: teller ikke som dybde
		return _child(_mv[base], p, depth, alpha, beta, ply, q)
	if depth <= 0 or ply >= MAX_PLY:
		if exact:
			return _eval(p)
		return _quiesce(base, n, alpha, beta, ply, q)

	var slot := _hash & TT_MASK
	var tt_move := -1
	if _tt_key[slot] == _hash:
		var meta := _tt_meta[slot]
		tt_move = meta & 63
		if (meta >> 8) >= depth:
			var v := _tt_val[slot]
			if v > MATE:
				v -= ply
			elif v < -MATE:
				v += ply
			var flag := (meta >> 6) & 3
			if flag == EXACT or (flag == LOWER and v >= beta) or (flag == UPPER and v <= alpha):
				return v
	var k1 := _killers[ply * 2]
	var k2 := _killers[ply * 2 + 1]
	_order(base, n, p, tt_move, k1, k2)
	var a0 := alpha
	var best := -INF
	var best_move := _mv[base]
	for i in n:
		var c := _mv[base + i]
		var v: int
		if i == 0:
			v = _child(c, p, depth - 1, alpha, beta, ply, q)
		else:
			# Sene trekk (ikke fra tabellen eller drapstrekk) søkes først grunnere; så smalt vindu
			# (de fleste trekk er dårligere enn det første); søk på nytt om det ikke holdt
			var reduce := 1 if i >= 3 and depth >= 3 and c != k1 and c != k2 and not exact else 0
			v = _child(c, p, depth - 1 - reduce, alpha, alpha + 1, ply, q)
			if reduce > 0 and v > alpha and not _aborted:
				v = _child(c, p, depth - 1, alpha, alpha + 1, ply, q)
			if v > alpha and v < beta and not _aborted:
				v = _child(c, p, depth - 1, alpha, beta, ply, q)
		if _aborted:
			return 0
		if v > best:
			best = v
			best_move = c
		if v > alpha:
			alpha = v
		if alpha >= beta:
			_history[p * n_cols + c] += depth * depth
			if k1 != c:
				_killers[ply * 2 + 1] = k1
				_killers[ply * 2] = c
			break
	var flag := UPPER if best <= a0 else (LOWER if best >= beta else EXACT)
	var stored := best + ply if best > MATE else (best - ply if best < -MATE else best)
	_tt_key[slot] = _hash
	_tt_val[slot] = stored
	_tt_meta[slot] = (depth << 8) | (flag << 6) | best_move
	return best


## Legger trekket, søker fra motstanderens side, og tar det bort igjen. Gir verdien for p.
func _child(c: int, p: int, depth: int, alpha: int, beta: int, ply: int, q: int) -> int:
	_place(c, p)
	side = 3 - p
	var v := -_search(depth, -beta, -alpha, ply + 1, q)
	side = p
	_unplace(c, p)
	return v


## Dybden er brukt opp: stillingens verdi, men prøv også trekk som lager en trussel motstanderen
## må blokkere (så langt q rekker). Slik finnes tvungne seire som går dypere enn søket.
func _quiesce(base: int, n: int, alpha: int, beta: int, ply: int, q: int) -> int:
	var p := side
	if q == Q_DEPTH and ply < MAX_PLY and vcf_depth > 0 and _has_vcf(3 - p, vcf_depth):
		# Motstanderen kan tvinge frem seier med trusler hvis vi står stille: søk ett trekk til, så vi
		# ser om noe stopper det (den gamle boten sjekket alltid dette, så uten det tapte søket av og til)
		var best_reply := -INF
		for i in n:
			var v := _child(_mv[base + i], p, 0, alpha, beta, ply, q - 1)
			if _aborted:
				return 0
			if v > best_reply:
				best_reply = v
				if v > alpha:
					alpha = v
					if alpha >= beta:
						break
		return best_reply
	var best := _eval(p)
	if best >= beta or q <= 0:
		return best
	if _open2[p] == 0 and _threat_cells[p] == 0:
		return best   # ingen trekk kan lage en trussel
	alpha = maxi(alpha, best)
	for i in n:
		var c := _mv[base + i]
		if not _makes_threat(c, p):
			continue
		var v := _child(c, p, 0, alpha, beta, ply, q - 1)
		if _aborted:
			return 0
		if v > best:
			best = v
			if v > alpha:
				alpha = v
				if alpha >= beta:
					break
	return best


## Lovlige trekk for p i _mv fra base (som GameState.legal_moves()). Gir antallet, WIN_NOW hvis p kan
## vinne med en gang (kolonnen i _win_col), eller LOST hvis motstanderen har to vinnerplasser som kan
## spilles. Når motstanderen har én, er blokkeringen eneste trekk (alt annet taper uansett).
func _gen(p: int, base: int) -> int:
	var pc := p * n_cells
	var oc := (3 - p) * n_cells
	var blocks := 0
	var block := -1
	for c in n_cols:
		var z := _heights[c]
		if z >= size:
			continue
		var cell := c + n_cols * z
		if _wins[pc + cell] > 0:
			_win_col = c
			return WIN_NOW
		if _wins[oc + cell] > 0:
			blocks += 1
			block = c
	if blocks >= 2:
		return LOST
	if blocks == 1:
		_mv[base] = block
		return 1
	var n := 0
	for c in n_cols:
		var z := _heights[c]
		if z >= size:
			continue
		if no_gift and z + 1 < size and _wins[oc + c + n_cols * (z + 1)] > 0:
			continue   # ikke gi bort seier: motstanderen vinner i cellen over
		_mv[base + n] = c
		n += 1
	if n == 0:
		for c in n_cols:
			if _heights[c] < size:
				_mv[base + n] = c
				n += 1
	return n


## Kan player tvinge frem seier med trusler alene (hver trussel må blokkeres, til den får to på en
## gang)? Som Bot.can_force_win, men på søkets tabeller. Brukes for motstanderen nederst i søket.
func _has_vcf(player: int, d: int) -> bool:
	if d <= 0 or (_open2[player] == 0 and _threat_cells[player] == 0):
		return false
	var key := (_hash * 8 + d) * 4 + player
	if _vcf_cache.has(key):
		return _vcf_cache[key]
	var result := _find_vcf(player, d)
	_vcf_cache[key] = result
	return result


func _find_vcf(player: int, d: int) -> bool:
	var opp := 3 - player
	var pc := player * n_cells
	var oc := opp * n_cells
	for c in n_cols:
		var z := _heights[c]
		if z >= size:
			continue
		if no_gift and z + 1 < size and _wins[oc + c + n_cols * (z + 1)] > 0:
			continue
		if not _makes_threat(c, player):
			continue
		_place(c, player)
		var threats := 0
		var block := -1
		var opp_wins := false
		for k in n_cols:
			var h := _heights[k]
			if h >= size:
				continue
			var cell := k + n_cols * h
			if _wins[oc + cell] > 0:
				opp_wins = true
				break
			if _wins[pc + cell] > 0:
				threats += 1
				block = k
		var found := false
		if not opp_wins:
			if threats >= 2:
				found = true
			elif threats == 1:
				_place(block, opp)   # motstanderen må blokkere
				found = _has_vcf(player, d - 1)
				_unplace(block, opp)
		_unplace(c, player)
		if found:
			return true
	return false


## Gir trekket p en vinnerplass som kan spilles straks (så motstanderen må blokkere)?
func _makes_threat(c: int, p: int) -> bool:
	var z := _heights[c]
	var cell := c + n_cols * z
	if z + 1 < size and _wins[p * n_cells + cell + n_cols] > 0:
		return true   # egen trussel rett over blir spillbar
	var po := p * n_lines
	var oo := (3 - p) * n_lines
	var two := win_length - 2
	for li in _cell_lines[cell]:
		if _counts[po + li] != two or _counts[oo + li] != 0:
			continue
		for x in _line_cells[li]:
			if x == cell or _cells[x] != 0:
				continue
			var col := x % n_cols
			var xz := x / n_cols
			if xz == _heights[col] or (col == c and xz == z + 1):
				return true
	return false


## Beste trekk først: trekket fra tabellen, drapstrekk, så historikk og plasser med mange linjer.
func _order(base: int, n: int, p: int, tt_move: int, k1: int, k2: int) -> void:
	var hp := p * n_cols
	for i in n:
		var c := _mv[base + i]
		var s := _history[hp + c] + _static[c + n_cols * _heights[c]] * 8
		if c == tt_move:
			s += 1 << 28
		elif c == k1 or c == k2:
			s += 1 << 24
		_sc[base + i] = s
	for i in range(1, n):
		var m := _mv[base + i]
		var s := _sc[base + i]
		var j := i - 1
		while j >= 0 and _sc[base + j] < s:
			_mv[base + j + 1] = _mv[base + j]
			_sc[base + j + 1] = _sc[base + j]
			j -= 1
		_mv[base + j + 1] = m
		_sc[base + j + 1] = s


# ---------------------------------------------------------------- Evaluering

## Verdien av stillingen for p (p har tur, ingen vinnerplass kan spilles).
func _eval(p: int) -> int:
	var s := _line_score
	var o1 := n_cells
	var o2 := 2 * n_cells
	for c in n_cols:
		if _col_threats[c] == 0:
			continue
		var lowest := true
		var below1 := false
		var below2 := false
		for z in range(_heights[c], size):
			var cell := c + n_cols * z
			var w1 := _wins[o1 + cell] > 0
			var w2 := _wins[o2 + cell] > 0
			if w1 or w2:
				var odd := (z & 1) == 0   # 1., 3., … høyde
				if w1:
					s += threat_w + (lowest_w if lowest else 0) + (stack_w if below1 else 0) \
						+ (parity_w if odd == (first == 1) else 0)
				if w2:
					s -= threat_w + (lowest_w if lowest else 0) + (stack_w if below2 else 0) \
						+ (parity_w if odd == (first == 2) else 0)
				lowest = false
			below1 = w1
			below2 = w2
	return s if p == 1 else -s


# ---------------------------------------------------------------- Brettet

func _landing(c: int) -> int:
	return c + n_cols * _heights[c]


## Legger p sin brikke i kolonnen og oppdaterer linjene, vinnerplassene, linjeverdien og hashen.
func _place(c: int, p: int) -> void:
	var z := _heights[c]
	var cell := c + n_cols * z
	_cells[cell] = p
	_heights[c] = z + 1
	_filled += 1
	_hash ^= _zobrist[p * n_cells + cell]
	var o := 3 - p
	var po := p * n_lines
	var oo := o * n_lines
	var two := win_length - 2
	var delta := 0
	for li in _cell_lines[cell]:
		var a := _counts[po + li]
		var b := _counts[oo + li]
		if b == 0:
			delta += _line_w[a + 1] - _line_w[a]
			if a == two:
				_open2[p] -= 1
				for x in _line_cells[li]:   # ny vinnerplass for p: den tomme cellen i linjen
					if _cells[x] == 0:
						_add_win(p, x, 1)
						break
			elif a + 1 == two:
				_open2[p] += 1
		if a == 0:
			delta += _line_w[b]   # linjen var åpen for motstanderen; nå er den stengt
			if b == two:
				_open2[o] -= 1
			elif b == win_length - 1:
				_add_win(o, cell, -1)
		_counts[po + li] = a + 1
	_line_score += delta if p == 1 else -delta


func _unplace(c: int, p: int) -> void:
	var z := _heights[c] - 1
	var cell := c + n_cols * z
	var o := 3 - p
	var po := p * n_lines
	var oo := o * n_lines
	var two := win_length - 2
	var delta := 0
	for li in _cell_lines[cell]:
		var a := _counts[po + li] - 1
		var b := _counts[oo + li]
		if b == 0:
			delta += _line_w[a + 1] - _line_w[a]
			if a == two:
				_open2[p] += 1
				for x in _line_cells[li]:
					if _cells[x] == 0:
						_add_win(p, x, -1)
						break
			elif a + 1 == two:
				_open2[p] -= 1
		if a == 0:
			delta += _line_w[b]
			if b == two:
				_open2[o] += 1
			elif b == win_length - 1:
				_add_win(o, cell, 1)
		_counts[po + li] = a
	_line_score -= delta if p == 1 else -delta
	_cells[cell] = 0
	_heights[c] = z
	_filled -= 1
	_hash ^= _zobrist[p * n_cells + cell]


## En linje gjør cellen til vinnerplass for p (d = 1), eller ikke lenger (d = -1). Holder tellerne
## per kolonne og spiller oppdatert, så evalueringen og det taktiske søket kan hoppe over det som er tomt.
func _add_win(p: int, cell: int, d: int) -> void:
	var i := p * n_cells + cell
	var before := _wins[i]
	_wins[i] = before + d
	if before == 0:
		_col_threats[cell % n_cols] += 1
		_threat_cells[p] += 1
	elif before + d == 0:
		_col_threats[cell % n_cols] -= 1
		_threat_cells[p] -= 1


## Bygger tabellene for stillingen (og for brettstørrelsen første gang).
func _setup(state: GameState) -> void:
	if state.size != size or state.win_length != win_length:
		size = state.size
		win_length = state.win_length
		n_cols = size * size
		n_cells = n_cols * size
		n_lines = state.lines.count()
		_line_cells = state.lines.cells
		_cell_lines = state.lines.cell_lines
		_cells.resize(n_cells)
		_heights.resize(n_cols)
		_counts.resize(3 * n_lines)
		_wins.resize(3 * n_cells)
		_static.resize(n_cells)
		for i in n_cells:
			_static[i] = _cell_lines[i].size()
		var z := RandomNumberGenerator.new()
		z.seed = 4099
		_zobrist.resize(3 * n_cells)
		for i in _zobrist.size():
			_zobrist[i] = (int(z.randi()) << 31) ^ int(z.randi())
		_tt_key.resize(1 << TT_BITS)
		_tt_key.fill(0)
		_tt_val.resize(1 << TT_BITS)
		_tt_meta.resize(1 << TT_BITS)
		_history.resize(3 * n_cols)
		_history.fill(0)
		_killers.resize(2 * (MAX_PLY + 1))
		_mv.resize((MAX_PLY + 40) * MAX_MOVES)
		_sc.resize(_mv.size())
		_col_threats.resize(n_cols)
		_threat_cells.resize(3)
		_open2.resize(3)
	# Åpne linjer: line1_w, line2_w, line3_w poeng for 1, 2, 3 egne brikker (fire på rad). Vinnerplassene telles i _eval.
	_line_w.resize(win_length + 1)
	_line_w.fill(1)
	_line_w[0] = 0
	_line_w[win_length] = 0
	if win_length >= 2:
		_line_w[win_length - 1] = line3_w
	if win_length >= 3:
		_line_w[win_length - 2] = line2_w
	if win_length >= 4:
		_line_w[win_length - 3] = line1_w
	_killers.fill(-1)
	_cells.fill(0)
	_heights.fill(0)
	_counts.fill(0)
	_wins.fill(0)
	_col_threats.fill(0)
	_threat_cells.fill(0)
	_open2.fill(0)
	_line_score = 0
	_filled = 0
	_hash = 0
	must_block = state.options.must_block
	no_gift = state.options.no_gift
	first = state.first_player
	for z in size:
		for c in n_cols:
			var v := state.cells[c + n_cols * z]
			if v != 0:
				_place(c, v)
	side = state.current_player
