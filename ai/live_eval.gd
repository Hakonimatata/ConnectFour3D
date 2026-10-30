class_name LiveEval
extends RefCounted
## Vurderer stillingen i et parti som pågår (runde 17): stillingsmåleren for tilskuere og treningen
## («Vis beste trekk», og vurderingen av trekket du nettopp gjorde). Samme søk som AI-analysen
## (MoveReview), bare dypere, siden det bare er én stilling om gangen. Søker litt hvert bilde (step),
## så spillet ikke fryser. Husker vurderingen av hver stilling, så angre og gjenta ikke søker på nytt.

const DEPTH := 6
const TIME_MS := 1500

var depth := DEPTH
var time_ms := TIME_MS
## Stillingene som er vurdert: nøkkel (trekkene) -> { score, best, side, info, p1, text, leader }.
## score er for den som har tur (side), info fra MoveReview.position_info.
var known := {}
var _bot := SearchBot.new()
var _state: GameState
var _key := 0
var _busy := false


static func key_of(s: GameState) -> int:
	return s.history.hash()


## Stillingen er endret: begynn å vurdere den, om den ikke er vurdert før.
func update(s: GameState) -> void:
	_key = key_of(s)
	_busy = false
	if known.has(_key):
		return
	_state = GameState.from_moves(s.options, s.first_player, s.history)   # egen kopi: partiet går videre
	if _state.is_over():
		var label := MoveReview.final_label(_state)
		known[_key] = { "score": -SearchBot.WIN if _state.winner() != 0 else 0, "best": Vector2i(-1, -1),
			"side": _state.current_player, "info": {}, "p1": label[0], "text": label[1], "leader": label[2] }
		return
	_bot.begin_analysis(_state, depth, time_ms)
	_busy = true


## Søker høyst budget_usec mikrosekunder. Gir true når stillingen er ferdig vurdert.
func step(budget_usec: int) -> bool:
	if not _busy:
		return false
	if not _bot.think(budget_usec):
		return false
	_busy = false
	var score := _bot.score()
	var best := _bot.result()
	var label := MoveReview.eval_label(score, _state.current_player)
	known[_key] = { "score": score, "best": best, "side": _state.current_player,
		"info": MoveReview.position_info(_state, best), "p1": label[0], "text": label[1], "leader": label[2] }
	return true


func is_busy() -> bool:
	return _busy


## Vurderingen av stillingen, eller {} hvis den ikke er ferdig ennå.
func get_eval(s: GameState) -> Dictionary:
	return known.get(key_of(s), {})


## Vurderingen av det siste trekket i s (treningen), når både stillingen før og etter er vurdert.
## Gir {} ellers (f.eks. hvis trekket ble gjort før stillingen var ferdig vurdert).
func judge_last(s: GameState) -> Dictionary:
	if s.history.is_empty():
		return {}
	var after: Dictionary = get_eval(s)
	var prev := GameState.from_moves(s.options, s.first_player, s.history.slice(0, s.history.size() - 1))
	var before: Dictionary = get_eval(prev)
	if after.is_empty() or before.is_empty():
		return {}
	var col: Vector2i = s.history[-1]
	return MoveReview.judge(before.info, col, int(before.side), int(before.score), -int(after.score))
