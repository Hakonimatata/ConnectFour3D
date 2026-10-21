class_name MatchController
extends Node
## Felles grensesnitt mellom spillskjermen og «motstanderen».
## Spillskjermen vet ikke om det er lokalt, mot bot eller online.
## Implementasjoner: OfflineMatch (lokalt + AI) og OnlineMatch (server).

signal started                                               ## Nytt parti (også rematch)
signal move_applied(col: Vector2i, pos: Vector3i, player: int)
signal move_rejected(text: String, hints: Array)
signal turn_changed(player: int)
signal finished(result: int, reason: int, line: Array)
signal chat_received(from_name: String, text: String)
signal info(text: String)                                    ## Statusmeldinger til spilleren
signal players_changed

var mode := "local"           ## "local", "ai" eller "online"
var options := GameOptions.new()
var state: GameState
var clock := ChessClock.new()
var game_number := 0
## Spillerne: name, skin, decal, win_fx, away (se Skins.look), avatar (base64, kan være ""),
## local (styres fra denne enheten), subtitle, elo (-1 = ingen konto)
var players := {
	1: { "name": "Spiller 1", "skin": Skins.DEFAULT_P1, "local": true, "subtitle": "" },
	2: { "name": "Spiller 2", "skin": Skins.DEFAULT_P2, "local": true, "subtitle": "" },
}


# ---- Overstyres av implementasjonene

func start_game() -> void:
	pass


func submit_move(_col: Vector2i) -> void:
	pass


func resign() -> void:
	pass


func request_rematch() -> void:
	pass


func send_chat(_text: String) -> void:
	pass


func leave() -> void:
	pass


func supports_chat() -> bool:
	return false


## Setet til spilleren på denne enheten (0 = begge, som i lokalt spill).
func my_seat() -> int:
	return 0


# ---- Felles

func is_local_turn() -> bool:
	return state != null and not state.is_over() and players[state.current_player].local


func time_left_ms(player: int) -> int:
	return clock.time_left(player, Time.get_ticks_msec())


func color_of(player: int) -> Color:
	return Skins.ui_color(players[player])


func look_of(player: int) -> Dictionary:
	var p: Dictionary = players[player]
	return Skins.look(str(p.get("skin", "")), str(p.get("decal", "none")), str(p.get("win_fx", "classic")),
		bool(p.get("away", false)), str(p.get("decal_color", "auto")))


## Gjør spillernes utseende lett å skille (bortedrakt for spiller 2 ved lik skin).
func resolve_looks() -> void:
	var pair := Skins.resolve_pair(look_of(1), look_of(2))
	for i in 2:
		(players[i + 1] as Dictionary).merge(pair[i], true)
