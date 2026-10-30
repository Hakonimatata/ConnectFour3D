class_name Bot
extends RefCounted
## Regelbasert bot (portet fra den gamle Python-boten SimpleBot).
##
## Rekkefølge: 1) vinn hvis mulig, 2) blokker motstanderens seier,
## 3) ellers velg trekket med best evaluering etter ett trekks lookahead.
##
## Evalueringen ser på hver vinnerlinje gjennom cellen brikken lander i:
## åpne linjer, to og tre på rad, blokkering, «hengende tre» (en vinnerplass
## motstanderen ikke kan nå ennå), stablede trusler og tvungne angrepssekvenser.
##
## Boten endrer brettet midlertidig med place/unplace og setter det alltid tilbake.
##
## Vanskelig og Ekspert (profile.search_ms > 0) bruker i stedet SearchBot, som søker flere trekk
## fram. I spillet brukes begin_move/think/chosen_move, så tenkingen deles over flere bilder.
## Evalueringsfunksjonene her brukes fortsatt av AI-analysen (MoveReview) og oppgavene.

const W_OPEN_LINE := 1.0
const W_OPEN_TWO := 1.0
const W_BLOCK_LINE := 1.0
const W_BLOCK_TWO := 1.0
const W_HANGING_THREE := 100.0
const W_BLOCK_WIN := 50_000.0
const W_FORCE_WIN := 500_000.0
const W_WIN := 1_000_000.0
const FORCE_DEPTH := 8

var profile: BotProfile
var rng := RandomNumberGenerator.new()
var last_info: Dictionary = {}    ## For feilsøking: hvorfor trekket ble valgt
var _force_cache: Dictionary = {} ## Stilling + trekk -> resultat av can_force_win (tømmes per trekk)
var _searcher: SearchBot          ## Søket (lages første gang det trengs)
var _pending := Vector2i(-1, -1)  ## Trekket fra begin_move når boten ikke søker
var force_depth := FORCE_DEPTH    ## Hvor dypt tvangssøket går (analysen bruker mindre på 5×5×5, der det er tregt)


func _init(p_profile: BotProfile = null) -> void:
	profile = p_profile if p_profile != null else BotProfile.create(BotProfile.Level.HARD)
	rng.randomize()


## Starter tenkingen på et trekk. Kall think() hvert bilde til den gir true, og hent chosen_move().
func begin_move(state: GameState) -> void:
	if profile.search_ms > 0:
		_search_bot().begin(state, profile.search_ms, profile.search_depth)
	else:
		_pending = choose_move(state)


## Tenker høyst budget_usec mikrosekunder. Gir true når trekket er klart.
func think(budget_usec: int) -> bool:
	return _search_bot().think(budget_usec) if profile.search_ms > 0 else true


func chosen_move() -> Vector2i:
	return _search_bot().result() if profile.search_ms > 0 else _pending


func _search_bot() -> SearchBot:
	if _searcher == null:
		_searcher = SearchBot.new()
		_searcher.rng.seed = rng.seed
		for key in profile.search_tweaks:
			_searcher.set(key, profile.search_tweaks[key])
	return _searcher


## Velger et lovlig trekk for spilleren som har tur.
func choose_move(state: GameState) -> Vector2i:
	if profile.search_ms > 0:
		return _search_bot().choose(state, profile.search_ms, profile.search_depth)
	var me := state.current_player
	var opp := GameState.opponent(me)
	var legal := state.legal_moves()
	if legal.size() == 1:
		return _done(legal[0], "only_move")

	var wins := legal.filter(func(c: Vector2i) -> bool: return state.wins_by(c, me))
	if not wins.is_empty() and rng.randf() < profile.take_win_chance:
		return _done(_pick(wins), "immediate_win")

	var blocks := legal.filter(func(c: Vector2i) -> bool: return state.wins_by(c, opp))
	if not blocks.is_empty() and rng.randf() < profile.block_chance:
		return _done(_pick(blocks), "block_immediate_win")

	if not profile.use_evaluation:
		return _done(_pick(legal), "random")

	_force_cache.clear()

	var values := {}
	var best := -INF
	for col in legal:
		var v := evaluate_with_lookahead(state, col, me)
		values[col] = v
		best = maxf(best, v)
	var candidates := legal.filter(func(c: Vector2i) -> bool: return values[c] >= best - profile.random_margin)
	var choice: Vector2i = _pick(candidates)
	last_info = { "reason": "highest_evaluation", "value": values[choice], "values": values }
	return choice


## Verdien av et trekk minus det beste motstanderen kan svare med.
func evaluate_with_lookahead(state: GameState, col: Vector2i, piece: int) -> float:
	var own := evaluate(state, col, piece, profile.use_force_search)
	var opp := GameState.opponent(piece)
	var index := state.place(col, piece)
	if state.is_win_at(index, piece):
		state.unplace(col)
		return W_WIN
	var best_opp := 0.0
	for c in state.open_columns():
		best_opp = maxf(best_opp, evaluate(state, c, opp, profile.opponent_force_search))
	state.unplace(col)
	return own - best_opp


## Verdien av å legge `piece` i kolonnen, sett fra `piece` sin side.
func evaluate(state: GameState, col: Vector2i, piece: int, force_search: bool) -> float:
	var opp := GameState.opponent(piece)
	var n := state.n_lines
	var L := state.win_length
	var index := state.lines.index_of(state.landing_pos(col))
	var value := 0.0
	var creates_three := false

	for li in state.lines.cell_lines[index]:
		var mine := state.counts[piece * n + li]
		var theirs := state.counts[opp * n + li]
		if theirs == 0:   # linjen er fortsatt åpen for oss
			value += W_OPEN_LINE
			if mine == L - 3:
				value += W_OPEN_TWO
			elif mine == L - 2:
				creates_three = true
			elif mine >= L - 1:
				value += W_WIN
		if mine == 0:     # linjen er åpen for motstanderen, vi blokkerer den
			if theirs == L - 3:
				value += W_BLOCK_LINE
			elif theirs == L - 2:
				value += W_BLOCK_TWO
			elif theirs >= L - 1:
				value += W_BLOCK_WIN

	if creates_three and creates_hanging_three(state, col, piece):
		value += W_HANGING_THREE
	if force_search and can_force_win(state, col, piece, force_depth):
		value += W_FORCE_WIN
	if profile.use_stacked and creates_stacked_threat(state, col, piece):
		value += W_FORCE_WIN
	return value


## Gir trekket tre på rad der den siste plassen ikke kan spilles ennå?
## Da kan ikke motstanderen blokkere den med en gang.
func creates_hanging_three(state: GameState, col: Vector2i, piece: int) -> bool:
	var opp := GameState.opponent(piece)
	var n := state.n_lines
	var index := state.place(col, piece)
	var found := false
	for li in state.lines.cell_lines[index]:
		if state.counts[piece * n + li] != state.win_length - 1 or state.counts[opp * n + li] != 0:
			continue
		for c in state.lines.cells[li]:
			if state.cells[c] == 0:
				var p := state.lines.pos_of(c)
				if state.column_height(Vector2i(p.x, p.y)) != p.z:
					found = true
				break
		if found:
			break
	state.unplace(col)
	return found


## Kan `piece` tvinge frem seier ved å starte med dette trekket?
## Hvert angrep må lage nøyaktig én trussel (motstanderen tvinges til å blokkere),
## helt til et trekk lager to trusler samtidig eller vinner direkte.
func can_force_win(state: GameState, col: Vector2i, piece: int, depth: int) -> bool:
	if not _may_create_threat(state, col, piece):
		return false
	var key: int = hash(state.cells) * 4099 + (col.x + 8 * col.y) * 64 + piece * 16 + depth
	if _force_cache.has(key):
		return _force_cache[key]
	var opp := GameState.opponent(piece)
	var index := state.place(col, piece)
	var result := false
	if state.is_win_at(index, piece):
		result = true
	elif _count_winning_columns(state, opp, 1) > 0:
		result = false   # motstanderen vinner heller enn å blokkere
	else:
		var threat := _count_winning_columns(state, piece, 2)
		if threat >= 2:
			result = true
		elif threat == 1 and depth > 0:
			var block := _first_winning_column(state, piece)
			var block_index := state.place(block, opp)
			if not state.is_win_at(block_index, opp):
				for next in state.open_columns():
					if can_force_win(state, next, piece, depth - 1):
						result = true
						break
			state.unplace(block)
	state.unplace(col)
	_force_cache[key] = result
	return result


## Rask sjekk før søket: et trekk kan bare lage en trussel hvis det vinner,
## gir tre på rad i en åpen linje, eller gjør en vinnerplass rett over spillbar.
func _may_create_threat(state: GameState, col: Vector2i, piece: int) -> bool:
	var n := state.n_lines
	var opp_off := GameState.opponent(piece) * n
	var own_off := piece * n
	var pos := state.landing_pos(col)
	var index := state.lines.index_of(pos)
	for li in state.lines.cell_lines[index]:
		if state.counts[opp_off + li] == 0 and state.counts[own_off + li] >= state.win_length - 2:
			return true
	if pos.z + 1 < state.size:
		return state.is_winning_cell(index + state.size * state.size, piece)
	return false


## Antall kolonner der `player` vinner nå, men slutter å telle ved `limit`.
func _count_winning_columns(state: GameState, player: int, limit: int) -> int:
	var found := 0
	for col in state.open_columns():
		if state.wins_by(col, player):
			found += 1
			if found >= limit:
				break
	return found


func _first_winning_column(state: GameState, player: int) -> Vector2i:
	for col in state.open_columns():
		if state.wins_by(col, player):
			return col
	return Vector2i(-1, -1)


## Gir trekket to vinnerplasser rett over hverandre i en kolonne?
## Da vinner vi uansett hva motstanderen gjør der.
func creates_stacked_threat(state: GameState, col: Vector2i, piece: int) -> bool:
	state.place(col, piece)
	var found := false
	var size := state.size
	for c in state.open_columns():
		var z := state.column_height(c)
		if z + 2 >= size:
			continue
		var upper := state.lines.index_of(Vector3i(c.x, c.y, z + 1))
		var over := state.lines.index_of(Vector3i(c.x, c.y, z + 2))
		if state.is_winning_cell(upper, piece) and state.is_winning_cell(over, piece):
			found = true
			break
	state.unplace(col)
	return found


func _pick(options: Array) -> Vector2i:
	return options[rng.randi() % options.size()]


func _done(col: Vector2i, reason: String) -> Vector2i:
	last_info = { "reason": reason }
	return col
