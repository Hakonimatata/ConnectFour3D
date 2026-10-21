class_name GameAnalysis
extends RefCounted
## Analyserer et ferdig parti (trekklisten) for statistikk:
##   forced         trekk som ga motstanderen en trussel de *måtte* blokkere
##                  (du har en vinnerplass de kan nå, og de kan ikke vinne selv først)
##   double_threats trekk som laget to eller flere vinnerplasser samtidig
##   longest_streak flest tvungne trekk på rad
##   winning_streak tvungne trekk på rad rett før vinnertrekket («seier med N tvungne trekk»)
## Se Plan.md, seksjon 13.4.


static func analyze(options: GameOptions, first_player: int, moves: Array) -> Dictionary:
	var out := { 1: _empty(), 2: _empty() }
	var streak := { 1: 0, 2: 0 }
	var s := GameState.new(options, first_player)
	for m in moves:
		var col: Vector2i = m if m is Vector2i else Vector2i(int(m[0]), int(m[1]))
		var player := s.current_player
		var r := s.play(col, false)
		if not r.ok:
			break
		var stats: Dictionary = out[player]
		if r.won:
			stats.winning_streak = streak[player]
			break
		if s.is_over():
			break
		var opp := GameState.opponent(player)
		var threats := s.winning_columns(player).size()
		var opponent_can_win := not s.winning_columns(opp).is_empty()
		if threats > 0 and not opponent_can_win:
			stats.forced += 1
			streak[player] += 1
			stats.longest_streak = maxi(stats.longest_streak, streak[player])
			if threats >= 2:
				stats.double_threats += 1
		else:
			streak[player] = 0
	return out


static func _empty() -> Dictionary:
	return { "forced": 0, "double_threats": 0, "longest_streak": 0, "winning_streak": 0 }
