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


func test_players_choose_their_own_kit() -> void:
	var a := Skins.look("gold", "none", "classic", true)
	var pair := Skins.resolve_pair(a, Skins.look("gold"))
	check_eq(pair[0].away, true, "valgt bortedrakt beholdes:")
	check_eq(pair[1].away, false, "ulik drakt: ingen bytte:")
	pair = Skins.resolve_pair(a, Skins.look("gold", "none", "classic", true))
	check_eq(pair[1].away, false, "samme skin og drakt: gjesten bytter:")
	pair = Skins.resolve_pair(Skins.look("ocean"), Skins.look("ember", "none", "classic", true))
	check_eq(pair[1].away, true, "ulike skins: drakten man valgte:")


func test_every_skin_pair_is_distinguishable() -> void:
	for a in Skins.ALL:
		for b in Skins.ALL:
			var pair := Skins.resolve_pair(Skins.look(a.id), Skins.look(b.id))
			var d := Skins._distance(Skins.ui_color(pair[0]), Skins.ui_color(pair[1]))
			check(d >= Skins.SIMILAR, "%s mot %s er for like (%.2f)" % [a.id, b.id, d])
			check(not Skins.too_similar(pair[0], pair[1]), "%s mot %s ligner for mye" % [a.id, b.id])
	# Ganske like skins (før ble bare nesten like oppdaget): gjesten får bortedrakten
	for p in [["ember", "copper"], ["ice", "opal"], ["oak", "copper"], ["lime", "toxic"]]:
		check(Skins.resolve_pair(Skins.look(p[0]), Skins.look(p[1]))[1] != Skins.look(p[1]), "%s mot %s byttes" % p)


func test_boards_and_decal_colors() -> void:
	var ids: Array[String] = []
	for b in Skins.BOARDS:
		check(not b.id in ids, "dobbelt brett: %s" % b.id)
		ids.append(b.id)
		check(b.base is Color and b.line is Color and b.side is Color, "brettet %s mangler farger" % b.id)
	check_eq(Skins.get_board("finnes-ikke").id, Skins.BOARDS[0].id)
	check_eq(Skins.look("ocean", "crown", "supernova", false, "gold").decal_color, "gold")
	check_eq(Skins.look("ocean", "crown", "supernova", false, "tull").decal_color, "auto")
	var gold := Skins.make_material(Skins.look("ocean", "crown", "classic", false, "gold"))
	check_eq(gold.shader, Skins.shader_for(Skins.Style.SMOOTH, Skins.decal_index("crown")))
	check_eq(Color(gold.get_shader_parameter("decal_color")).to_html(false), "e8c35a")
	var kit := Skins.look("ember", "moon", "classic", true, "kit")
	check_eq(Skins.decal_color_of(kit), Skins.ui_color(kit), "draktfarge følger bortedrakten:")


func test_elo_tiers_and_badges() -> void:
	check_eq(EloBadge.tier(0).id, "bronze")
	check_eq(EloBadge.tier(1200).id, "silver", "startverdien 1200 er sølv:")
	check_eq(EloBadge.tier(1250).id, "gold")
	check_eq(EloBadge.tier(1849).id, "master")
	check_eq(EloBadge.tier(2400).id, "grandmaster")
	check_eq(EloBadge.next_tier(1200).id, "gold")
	check(EloBadge.next_tier(1900).is_empty(), "ingen nivå over stormester")
	var last := -1
	for t in EloBadge.TIERS:
		check(int(t.min) > last, "nivåene skal stige: %s" % t.id)
		last = int(t.min)
		var tex := EloBadge.icon(int(t.min), 20)
		check_eq(tex.get_width(), 40, "tegnes i dobbel oppløsning:")
		var img := tex.get_image()
		check(img.get_pixel(20, 20).a > 0.9, "%s: midten skal være dekket" % t.id)
		check(img.get_pixel(0, 0).a < 0.1, "%s: hjørnet skal være gjennomsiktig" % t.id)
	check(EloBadge.icon(1300, 20) == EloBadge.icon(1340, 20), "samme nivå bruker samme bilde")
	var r := EloBadge.make(-1)
	check(not r.visible, "gjester får ikke merke")
	EloBadge.set_elo(r, 1560)
	check(r.visible and r.tooltip_text.contains("1560"))
	r.free()


func test_look_sanitizes_and_material_gets_parameters() -> void:
	var l := Skins.look("finnes-ikke", "tull", "tull")
	check_eq(l.skin, Skins.DEFAULT_P1)
	check_eq(l.decal, "none")
	check_eq(l.win_fx, "classic")
	var m := Skins.make_material(Skins.look("lava", "star", "confetti", true))
	check_eq(m.shader, Skins.shader_for(Skins.Style.LAVA, Skins.decal_index("star")), "spesialisert shader:")
	check(m.shader.code.contains("#define STYLE %d" % Skins.Style.LAVA), "stilen settes inn i koden")
	check_eq(m.get_shader_parameter("color_a"), Skins.get_skin("lava").away.a)
	check(Skins.swatch("gold").get_width() == 30)
