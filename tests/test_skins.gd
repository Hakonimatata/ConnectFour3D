extends TestCase
## Tester for skins, drakter, merker og seiersanimasjoner.


func test_home_and_away_are_clearly_different() -> void:
	var ids: Array[String] = []
	for s in Skins.ALL:
		check(not s.id in ids, "dobbel id: %s" % s.id)
		ids.append(s.id)
		var d := Skins._distance(s.home.ui, s.away.ui)
		check(d >= Skins.SIMILAR, "%s: hjemme og borte er for like (%.2f)" % [s.id, d])


func test_same_skin_gives_away_kit_to_player_two() -> void:
	var pair := Skins.resolve_pair(Skins.look("gold"), Skins.look("gold"))
	check_eq(pair[0].away, false)
	check_eq(pair[1].away, true)
	check_eq(pair[1].skin, "gold", "beholder skin, bytter drakt:")
	var different := Skins.resolve_pair(Skins.look("ocean"), Skins.look("ember"))
	check_eq(different[1].away, false, "ulike skins trenger ikke bortedrakt:")


func test_every_skin_pair_is_distinguishable() -> void:
	for a in Skins.ALL:
		for b in Skins.ALL:
			var pair := Skins.resolve_pair(Skins.look(a.id), Skins.look(b.id))
			var d := Skins._distance(Skins.ui_color(pair[0]), Skins.ui_color(pair[1]))
			check(d >= Skins.SIMILAR, "%s mot %s er for like (%.2f)" % [a.id, b.id, d])


func test_look_sanitizes_and_material_gets_parameters() -> void:
	var l := Skins.look("finnes-ikke", "tull", "tull")
	check_eq(l.skin, Skins.DEFAULT_P1)
	check_eq(l.decal, "none")
	check_eq(l.win_fx, "classic")
	var m := Skins.make_material(Skins.look("lava", "star", "confetti", true))
	check_eq(m.get_shader_parameter("style"), int(Skins.Style.LAVA))
	check_eq(m.get_shader_parameter("decal"), Skins.decal_index("star"))
	check_eq(m.get_shader_parameter("color_a"), Skins.get_skin("lava").away.a)
	check(Skins.swatch("gold").get_width() == 30)
