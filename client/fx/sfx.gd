extends Node
## Autoload «Sfx»: små lydeffekter som lages i kode (ingen lydfiler å laste ned).

const RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["drop"] = _make(_w_drop, 0.16)
	_streams["click"] = _make(_w_click, 0.05)
	_streams["error"] = _make(_w_error, 0.18)
	_streams["tick"] = _make(_w_tick, 0.04)
	_streams["win"] = _make(_w_win, 0.8)
	_streams["lose"] = _make(_w_lose, 0.7)
	_streams["boom"] = _make(_w_boom, 0.6)


func play(name: String, pitch := 1.0) -> void:
	if not Settings.sound or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


func _make(wave: Callable, length_s: float) -> AudioStreamWAV:
	var n := int(length_s * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var fade := minf(1.0, (n - i) / (RATE * 0.01))   # myk slutt, ingen klikk
		var v := clampf(wave.call(t) * fade, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


# ---- Bølgeformer: tid t i sekunder -> sample mellom -1 og 1

func _w_drop(t: float) -> float:
	return sin(TAU * (190.0 - 500.0 * t) * t) * exp(-t * 28.0) * 0.9


func _w_click(t: float) -> float:
	return sin(TAU * 1100.0 * t) * exp(-t * 90.0) * 0.4


func _w_error(t: float) -> float:
	return (1.0 if fmod(t * 120.0, 1.0) < 0.5 else -1.0) * exp(-t * 14.0) * 0.18


func _w_tick(t: float) -> float:
	return sin(TAU * 1600.0 * t) * exp(-t * 120.0) * 0.25


func _w_win(t: float) -> float:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var i := mini(int(t / 0.11), 3)
	var lt := t - i * 0.11
	return sin(TAU * notes[i] * t) * exp(-lt * 6.0) * 0.45


func _w_lose(t: float) -> float:
	return sin(TAU * (330.0 - 140.0 * t) * t) * exp(-t * 3.0) * 0.35


func _w_boom(t: float) -> float:
	return (randf() * 2.0 - 1.0) * exp(-t * 9.0) * 0.6 + sin(TAU * 55.0 * t) * exp(-t * 6.0) * 0.6
