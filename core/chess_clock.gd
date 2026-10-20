class_name ChessClock
extends RefCounted
## Sjakkur: hver spiller har sin egen tidsbank, og bare den som har tur bruker av sin.
## Etter hvert trekk legges tillegget (increment) til.
## Klokken får tiden utenfra (now_ms), slik at den er lett å teste og kan
## brukes likt på klient og server.

var enabled: bool = false
var increment_ms: int = 0
var remaining_ms: PackedInt64Array = [0, 0, 0]   ## indeks 1 og 2 = spillerne
var running_player: int = 0                      ## 0 = stoppet
var _turn_started_ms: int = 0


func _init(options: GameOptions = null) -> void:
	if options == null or not options.has_clock():
		return
	enabled = true
	increment_ms = options.time_increment_s * 1000
	remaining_ms[1] = options.time_base_s * 1000
	remaining_ms[2] = options.time_base_s * 1000


func start(player: int, now_ms: int) -> void:
	running_player = player
	_turn_started_ms = now_ms


## Kalles når `running_player` har gjort et trekk. Starter motstanderens tid.
func switch(now_ms: int) -> void:
	if running_player == 0:
		return
	var p := running_player
	remaining_ms[p] = max(0, remaining_ms[p] - (now_ms - _turn_started_ms)) + increment_ms
	start(3 - p, now_ms)


func stop(now_ms: int) -> void:
	if running_player != 0:
		remaining_ms[running_player] = max(0, remaining_ms[running_player] - (now_ms - _turn_started_ms))
	running_player = 0


func time_left(player: int, now_ms: int) -> int:
	if player == running_player:
		return max(0, remaining_ms[player] - (now_ms - _turn_started_ms))
	return remaining_ms[player]


## Spilleren som har gått tom for tid, eller 0.
func flagged(now_ms: int) -> int:
	if enabled and running_player != 0 and time_left(running_player, now_ms) <= 0:
		return running_player
	return 0


## Setter tidene direkte (klienten bruker dette når serveren sender tider).
func sync(p1_ms: int, p2_ms: int, running: int, now_ms: int) -> void:
	remaining_ms[1] = p1_ms
	remaining_ms[2] = p2_ms
	start(running, now_ms)


static func format_ms(ms: int) -> String:
	var total_s := int(ceil(ms / 1000.0))
	if ms < 10_000 and ms > 0:
		return "%.1f" % (ms / 1000.0)
	return "%d:%02d" % [total_s / 60, total_s % 60]
