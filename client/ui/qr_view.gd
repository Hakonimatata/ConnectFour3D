class_name QrView
extends Control
## Tegner en QR-kode (QrCode) kvadratisk i kontrollen, svart på hvitt med 4 moduler lys kant rundt,
## så den kan skannes fra en skjerm på avstand.

var _modules := PackedByteArray()
var _n := 0


func set_text(text: String) -> void:
	_modules = QrCode.encode(text)
	_n = QrCode.size_of(_modules)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	draw_rect(Rect2(origin, Vector2(side, side)), Color.WHITE)
	if _n == 0:
		return
	var cell := side / (_n + 8)
	for y in _n:
		for x in _n:
			if _modules[y * _n + x] == 1:
				# Litt overlapp, så det ikke blir hårfine lyse streker mellom modulene
				draw_rect(Rect2(origin + Vector2(x + 4, y + 4) * cell, Vector2(cell + 0.6, cell + 0.6)), Color.BLACK)
