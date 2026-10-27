class_name MainMenu
extends Screen
## Hovedmenyen. I bakgrunnen spilles det siste partiet på serveren av, med spillerne og hvordan
## det endte. Uten nett (eller før noen har spilt) spiller to boter mot hverandre.
## Menyen tar en kort «titt» på serveren (uten å mase hvis den ikke svarer), og viser
## aktive turneringer, den globale chatten (med hvor mange som er online) og Elo-merket ditt.

const MAX_TOURNAMENTS := 3

var _demo: GameState
var _replay: Dictionary = {}    ## partiet som spilles av (fra serveren). Tom = bot-demo
var _replay_i := 0
var _replay_pause := 0
var _replay_title := ""         ## «Siste parti: Ada – Bob» eller «Nylig parti: …»
var _replay_last: Dictionary = {}   ## forrige parti som ble spilt av (neste blir et annet)
var _caption_box: PanelContainer
var _caption: Label
var _avatar: AvatarView
const REPLAY_PAUSE_STEPS := 5  ## hvor lenge sluttstillingen blir stående (i demo-steg)
var _demo_bot := Bot.new(BotProfile.create(BotProfile.Level.MEDIUM))
var _panel: Control
var _vbox: VBoxContainer
var _offline_button: Button
var _offline_clip: Control           ## klipper panelet under «Spill offline» mens det folder seg ut
var _offline_drawer: PanelContainer  ## «Mot AI» og «To spillere»
var _offline_open := false
var _offline_tween: Tween
const DRAWER_BG := Color("252b38")
const DRAWER_GAP := 6   ## luft mellom knappene og panelet (fanen strekkes ned over den)
static var _chevrons := {}
var _tour_box: VBoxContainer
var _tour_list: VBoxContainer
var _badge: TextureRect
var _chat: GlobalChat
var _who_name: Label
var _account_button: Button
var _admin_button: Button               ## bare for admin
var _friends_button: Button             ## bare innlogget («Venner (2)» når noen er online)
var _champion: PanelContainer           ## siste turneringsvinner
var _champion_trophy: TrophyView
var _champion_name: Label
var _champion_sub: Label
var _champion_id := 0
const CHAMPION_GOLD := Color("ffd76a")
var _last_portrait := true
var _layout_queued := false
var _last_list: Array = []   ## sist viste turneringsliste


func _ready() -> void:
	app.camera.auto_rotate = true
	app.board.input_enabled = false
	app.board.setup(4)
	var pair := Skins.resolve_pair(Settings.look(), Skins.look(Skins.DEFAULT_P2))
	app.board.set_looks(pair[0], pair[1])
	_demo_bot.profile.think_time_s = 0.0

	_panel = MarginContainer.new()
	add_child(_panel)
	var card := PanelContainer.new()
	_panel.add_child(card)
	var v := UI.vbox(12)
	_vbox = v
	card.add_child(v)

	v.add_child(UI.label("Fire på rad", "Title"))
	v.add_child(UI.label("i 3D · mot AI, lokalt eller online", "Muted"))
	v.add_child(UI.spacer(8))
	# To hovedvalg side om side. «Spill offline» er en fane som folder ut et panel under seg
	# (mot AI / to spillere på samme enhet). Fanen og panelet har samme farge og kant, så de blir én form.
	var play := UI.vbox(DRAWER_GAP)
	_offline_button = UI.button("Spill offline", _toggle_offline)
	_offline_button.icon = _chevron(false)
	_offline_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_offline_button.z_index = 1   # tegnes over panelets øvre kant, så overgangen blir sømløs
	play.add_child(_row([UI.button("Spill online", func() -> void: app.show_online(), "PrimaryButton"), _offline_button]))
	_offline_clip = Control.new()
	_offline_clip.clip_contents = true
	_offline_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offline_clip.visible = false
	_offline_drawer = PanelContainer.new()
	var drawer_style := UI._box(DRAWER_BG, 10, UI.ACCENT, 8, 8)
	drawer_style.corner_radius_top_right = 0
	_offline_drawer.add_theme_stylebox_override("panel", drawer_style)
	_offline_drawer.add_child(_row([
		UI.button("Mot AI", func() -> void: app.show_setup("ai")),
		UI.button("To spillere", func() -> void: app.show_setup("local")),
	]))
	_offline_clip.add_child(_offline_drawer)
	_offline_clip.resized.connect(func() -> void: _offline_drawer.size.x = _offline_clip.size.x)
	play.add_child(_offline_clip)
	v.add_child(play)
	var solved := Settings.puzzle_day == Time.get_date_string_from_system()
	var puzzle := UI.button("Dagens oppgave", func() -> void: app.show_puzzle())
	if solved:
		# Et lite grønt merke i hjørnet i stedet for «· løst» i teksten (som ble kuttet på mobil)
		puzzle.add_child(_solved_badge())
		puzzle.tooltip_text = tr("Løst i dag")
	v.add_child(_row([puzzle, UI.button("Innstillinger", func() -> void: app.show_settings())]))

	# Siste turneringsvinner: et eget kort med pokalen, som åpner turneringen (treet og pokalen)
	v.add_child(_build_champion_card())

	# Aktive turneringer (vises bare når serveren svarer og noe er åpent eller pågår)
	_tour_box = UI.vbox(6)
	_tour_box.visible = false
	_tour_box.add_child(UI.spacer(2))
	_tour_box.add_child(UI.section("Aktive turneringer"))
	_tour_list = UI.vbox(6)
	_tour_box.add_child(_tour_list)
	v.add_child(_tour_box)
	v.add_child(UI.spacer(4))

	var who := UI.hbox(8)
	_avatar = AvatarView.new(30)
	who.add_child(_avatar)
	_on_profile_synced()
	Net.profile_synced.connect(_on_profile_synced)
	_badge = EloBadge.make(-1, 20)
	who.add_child(_badge)
	_who_name = UI.label(Settings.display_name(), "Muted")
	_who_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_who_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_who_name.clip_text = true
	_who_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(_who_name)
	# Logg inn (gjest) eller Min profil (innlogget), rett ved profilbildet
	_account_button = UI.button("Logg inn", _on_account_pressed, "GhostButton")
	_account_button.custom_minimum_size.y = 36
	_admin_button = UI.button("Admin", func() -> void: app.show_admin(), "GhostButton")
	_admin_button.custom_minimum_size.y = 36
	_admin_button.visible = false
	who.add_child(_admin_button)
	_friends_button = UI.button("Venner", func() -> void: app.show_friends(true), "GhostButton")
	_friends_button.custom_minimum_size.y = 36
	_friends_button.visible = false
	_friends_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(_friends_button)
	who.add_child(_account_button)
	v.add_child(who)

	Net.message.connect(_on_net_message)
	Net.connected.connect(_on_net_connected)
	Net.account_changed.connect(_update_badge)
	var tour_timer := Timer.new()
	tour_timer.wait_time = 20.0
	tour_timer.autostart = true
	tour_timer.timeout.connect(_ask_tournaments)
	add_child(tour_timer)
	if Net.status == Net.Status.OFFLINE:
		Net.connect_to_server("", false)
	else:
		_ask_tournaments()
	_update_badge()

	# Teksten over brettet: hvem som spilte det siste partiet, og hvordan det endte
	_caption_box = PanelContainer.new()
	_caption_box.add_theme_stylebox_override("panel", UI._box(UI.PANEL, 10, UI.BORDER, 10, 5))
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.visible = false
	_caption = UI.label("", "", HORIZONTAL_ALIGNMENT_CENTER)
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_caption.add_theme_font_size_override("font_size", 13)
	_caption_box.add_child(_caption)
	add_child(_caption_box)

	_chat = GlobalChat.new()
	_chat.toggled.connect(func(_open: bool) -> void: _layout())
	_chat.profile_requested.connect(func(username: String) -> void: app.show_profile(username, true))
	add_child(_chat)
	# Når man begynner/slutter å skrive, legges chatten om (tastaturet på mobil)
	_chat._input.focus_entered.connect(_layout)
	_chat._input.focus_exited.connect(_layout)

	resized.connect(_layout)
	_layout.call_deferred()
	# Endrer innholdet i kortet høyde (turneringer, vinner, admin-knapp), legges menyen om.
	_vbox.minimum_size_changed.connect(_queue_layout)

	var timer := Timer.new()
	timer.wait_time = 0.9
	timer.autostart = true
	timer.timeout.connect(_demo_step)
	add_child(timer)
	_demo = GameState.new()


func _queue_layout() -> void:
	if not _layout_queued:
		_layout_queued = true
		(func() -> void:
			_layout_queued = false
			_layout()
		).call_deferred()


## Bred skjerm: kortet til venstre. Smal (mobil): kortet nederst.
func _layout() -> void:
	var portrait := size.y > size.x
	# Tastaturet på mobil krymper skjermen. Ikke bytt oppsett mens man skriver i chatten.
	var typing := _chat.is_typing()
	if typing:
		portrait = _last_portrait
	_last_portrait = portrait
	_panel.visible = not (typing and portrait)   # på mobil dekker chatten menyen mens man skriver
	var w := minf(400.0, size.x - 32.0)
	_panel.custom_minimum_size.x = w
	# Flytt brettet bort fra kortet: opp på mobil, til høyre på PC.
	if portrait:
		# Mobil: menyen midtstilt nederst og litt tettere, chatten som en smal linje øverst,
		# og brettet midt i plassen mellom dem (og litt lenger unna, så det får plass).
		w = minf(400.0, size.x - 20.0)
		_panel.custom_minimum_size.x = w
		_vbox.add_theme_constant_override("separation", 8)
		var h := _panel.get_combined_minimum_size().y
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -w * 0.5
		_panel.offset_right = w * 0.5
		_panel.offset_top = -h - 10.0
		_panel.offset_bottom = -10.0
		var card_top := size.y - h - 10.0
		_chat.compact = true
		_chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_chat.offset_left = 10
		_chat.offset_right = -10
		_chat.offset_top = 10
		var chat_bottom := 10.0 + _chat.get_combined_minimum_size().y
		if typing:
			_chat.open = true
			_chat._apply_compact()
			_chat.offset_bottom = maxf(10 + 180.0, size.y - 10.0)   # hele plassen over tastaturet
		else:
			_chat.offset_bottom = maxf(10 + 180.0, card_top - 10.0) if _chat.open else chat_bottom
		_caption_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		_caption_box.offset_top = chat_bottom + 8.0
		_caption_box.offset_bottom = _caption_box.offset_top + _caption_box.get_combined_minimum_size().y
		app.camera.dist_target = app.camera.max_distance * 0.78
		var px_per_unit := size.x / 10.5
		app.camera.view_offset = Vector2(0, ((chat_bottom + card_top) * 0.5 - size.y * 0.5) / px_per_unit)
	else:
		_vbox.add_theme_constant_override("separation", 12)
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 48)
		app.camera.view_offset = Vector2(-1.2, -0.5)
		# Chatten nede til høyre
		_chat.compact = false
		# Teksten øverst, over brettet (til høyre for menyen)
		_caption_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
		var shift := size.x * 0.17
		_caption_box.offset_left += shift
		_caption_box.offset_right += shift
		var cw := minf(380.0, size.x * 0.3)
		var ch := minf(360.0, size.y * 0.48)
		_chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_chat.offset_left = -cw - 16
		_chat.offset_right = -16
		_chat.offset_top = -ch - 16
		_chat.offset_bottom = -16


func _toggle_offline() -> void:
	set_offline_open(not _offline_open)


## Folder panelet under «Spill offline» ut eller inn. Mens det er åpent, ser knappen ut som en fane
## i samme farge som panelet. Når det lukkes, blir knappen vanlig igjen først når panelet er borte.
func set_offline_open(open: bool, animate := true) -> void:
	_offline_open = open
	_offline_button.icon = _chevron(open)
	if open:
		_set_tab_style(true)
	var h := _offline_drawer.get_combined_minimum_size().y if open else 0.0
	_offline_drawer.size = Vector2(_offline_clip.size.x, _offline_drawer.get_combined_minimum_size().y)
	if _offline_tween:
		_offline_tween.kill()
	if not animate:
		_set_drawer_height(h)
		_offline_drawer.modulate.a = 1.0
		_set_tab_style(open)
		return
	_offline_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_offline_tween.tween_method(_set_drawer_height, _offline_clip.custom_minimum_size.y, h, 0.22)
	_offline_tween.tween_property(_offline_drawer, "modulate:a", 1.0 if open else 0.0, 0.18)
	if not open:
		_offline_tween.chain().tween_callback(_set_tab_style.bind(false))


func _set_drawer_height(h: float) -> void:
	_offline_clip.custom_minimum_size.y = h
	_offline_clip.visible = h > 0.5
	_layout()


## Fanen: samme farge og kant som panelet, uten kant og runde hjørner nederst. Den strekkes ned
## over luken (expand_margin) og dekker panelets øvre kant der de møtes.
func _set_tab_style(on: bool) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_offline_button.remove_theme_stylebox_override(state)
	if not on:
		return
	var tab := UI._box(DRAWER_BG, 10, UI.ACCENT, 14, 10)
	tab.border_width_bottom = 0
	tab.corner_radius_bottom_left = 0
	tab.corner_radius_bottom_right = 0
	tab.expand_margin_bottom = DRAWER_GAP + 1
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_offline_button.add_theme_stylebox_override(state, tab)
	_offline_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## En liten pil (ned = lukket, opp = åpen), tegnet i kode.
static func _chevron(up: bool) -> Texture2D:
	if _chevrons.has(up):
		return _chevrons[up]
	var px := 32
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var mid := Vector2(16, 12 if up else 20)
	var ends := [Vector2(7, 20 if up else 12), Vector2(25, 20 if up else 12)]
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := 99.0
			for e: Vector2 in ends:
				d = minf(d, Geometry2D.get_closest_point_to_segment(p, mid, e).distance_to(p))
			img.set_pixel(x, y, Color(UI.TEXT, clampf(2.6 - d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(16, 16))
	_chevrons[up] = tex
	return tex


## Grønt merke med hake øverst til høyre på en knapp.
static func _solved_badge() -> TextureRect:
	var px := 36
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	var a := Vector2(10, 18.5)
	var b := Vector2(15.5, 24)
	var e := Vector2(26, 12.5)
	for y in px:
		for x in px:
			var p := Vector2(x + 0.5, y + 0.5)
			var disc := clampf(px * 0.5 - 0.5 - p.distance_to(c), 0.0, 1.0)
			var d := minf(Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p),
				Geometry2D.get_closest_point_to_segment(p, b, e).distance_to(p))
			var tick := clampf(2.6 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(UI.SUCCESS.lerp(Color.WHITE, tick), disc))
	var badge := TextureRect.new()
	badge.texture = ImageTexture.create_from_image(img)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -15
	badge.offset_right = 3
	badge.offset_top = -5
	badge.offset_bottom = 13
	return badge


## Knapper side om side med lik bredde.
static func _row(buttons: Array) -> HBoxContainer:
	var row := UI.hbox(8)
	for b: Button in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(b)
	return row


func _on_net_connected(_resumed: bool) -> void:
	_ask_tournaments()


func _ask_tournaments() -> void:
	if Net.is_online():
		Net.send({ "t": Protocol.LIST_TOURNAMENTS })


func _on_net_message(msg: Dictionary) -> void:
	if msg.t == Protocol.TOURNAMENT_LIST:
		show_tournaments(msg.get("tournaments", []))
	elif msg.t == Protocol.TOURNAMENT_STATE:
		_ask_tournaments()   # meldte seg på fra menyen: oppdater kortet («Påmeldt»)
	elif msg.t == Protocol.FRIENDS:
		_update_friends_button()


func _on_account_pressed() -> void:
	Sfx.play("click")
	if Net.is_logged_in():
		app.show_profile("", true)
	else:
		app.show_account(true)


func _update_badge() -> void:
	_who_name.text = Settings.display_name()
	_account_button.text = tr("Min profil") if Net.is_logged_in() else tr("Logg inn")
	_admin_button.visible = bool(Net.user.get("admin", false))
	_friends_button.visible = Net.is_logged_in()
	_update_friends_button()
	if Net.is_logged_in() and Net.is_online():
		Net.send({ "t": Protocol.FRIEND, "action": "list" })


## «Venner», med hvor mange som er online og en prikk ved nye forespørsler.
## Profilbildet (og fargen fra skinnet) ved navnet. Oppdateres når kontoens profil kommer ved innlogging.
func _on_profile_synced() -> void:
	_avatar.set_avatar(Settings.avatar, Settings.display_name(), Skins.color_of(Settings.skin_id))


func _update_friends_button() -> void:
	var online := (Net.friends.get("friends", []) as Array).filter(func(f: Dictionary) -> bool: return f.get("online", false))
	var text := tr("Venner")
	if not online.is_empty():
		text += " (%d)" % online.size()
	if not (Net.friends.get("requests", []) as Array).is_empty():
		text += "  •"
	_friends_button.text = text
	EloBadge.set_elo(_badge, int(Net.user.get("elo", -1)) if Net.is_logged_in() else -1, 20)


## Kortet for siste turneringsvinner: pokalen (med glød), «Siste turneringsvinner», navnet i gull
## og turneringen. Hele kortet er en knapp som åpner turneringen.
func _build_champion_card() -> PanelContainer:
	_champion = PanelContainer.new()
	_champion.add_theme_stylebox_override("panel", UI._box(Color("2a2617"), 12, Color("b8913a"), 10, 6, 3))
	_champion.visible = false
	var row := UI.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champion_trophy = TrophyView.new({}, 64, true)
	row.add_child(_champion_trophy)
	var texts := UI.vbox(0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UI.label("Siste turneringsvinner", "Muted")
	title.add_theme_color_override("font_color", Color(CHAMPION_GOLD, 0.75))
	texts.add_child(title)
	_champion_name = UI.label("", "Heading")
	_champion_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_champion_name.add_theme_color_override("font_color", CHAMPION_GOLD)
	_champion_name.clip_text = true
	_champion_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_champion_name)
	_champion_sub = UI.label("", "Muted")
	_champion_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_champion_sub.clip_text = true
	_champion_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_champion_sub)
	row.add_child(texts)
	var see := UI.label("Se ›", "Muted")
	see.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(see)
	_champion.add_child(row)
	# Usynlig knapp over hele kortet (gir også en svak lysning ved hover)
	var button := Button.new()
	button.theme_type_variation = "GhostButton"
	button.pressed.connect(func() -> void:
		Sfx.play("click")
		Net.ensure_connected()
		app.show_tournament(_champion_id, true)
	)
	_champion.add_child(button)
	return _champion


## Den siste ferdige turneringen med en vinner (nyeste først), eller {}.
static func latest_champion(list: Array) -> Dictionary:
	var done := list.filter(func(t: Dictionary) -> bool:
		return t.get("status") == "finished" and str(t.get("winner", "")) != "")
	if done.is_empty():
		return {}
	var when := func(t: Dictionary) -> int:
		return int(t.get("finished_at", 0)) if int(t.get("finished_at", 0)) > 0 else int(t.get("start_time", 0))
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return when.call(a) > when.call(b))
	return done[0]


## Viser turneringer som pågår eller er åpne for påmelding (pågående først), og siste vinner.
func show_tournaments(list: Array) -> void:
	if list == _last_list and _tour_list.get_child_count() > 0:
		return   # listen hentes hvert 20. sekund: ikke bygg alt på nytt når ingenting er endret
	_last_list = list.duplicate(true)
	var champ := latest_champion(list)
	_champion.visible = not champ.is_empty()
	if not champ.is_empty():
		_champion_id = int(champ.id)
		_champion_trophy.set_design(champ.get("trophy", {}))
		_champion_name.text = str(champ.winner)
		_champion_sub.text = str(champ.name)
	# Fjern de gamle med en gang. Med bare queue_free ble de med i høyden _layout regnet ut,
	# og menyen ble for høy med tomrom nederst.
	for c in _tour_list.get_children():
		_tour_list.remove_child(c)
		c.queue_free()
	var active := list.filter(func(t: Dictionary) -> bool: return t.get("status") in ["running", "open"])
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return TournamentScreen.status_order(a.status) < TournamentScreen.status_order(b.status) \
			or (a.status == b.status and a.start_time < b.start_time)
	)
	_tour_box.visible = not active.is_empty()
	# Den neste turneringen med åpen påmelding reklameres med et eget kort øverst
	var promo := next_signup(list)
	if not promo.is_empty():
		_tour_list.add_child(_promo_card(promo))
		active.erase(promo)
	for t in active.slice(0, MAX_TOURNAMENTS - (0 if promo.is_empty() else 1)):
		_tour_list.add_child(_tournament_button(t))
	if active.size() > MAX_TOURNAMENTS:
		_tour_list.add_child(UI.button(tr("Alle turneringer (%d)") % active.size(), func() -> void:
			Net.ensure_connected()
			app.show_tournaments()
		, "GhostButton"))
	_layout.call_deferred()


## Den neste turneringen som er åpen for påmelding (starter først), eller {}.
static func next_signup(list: Array) -> Dictionary:
	var open := list.filter(func(t: Dictionary) -> bool: return t.get("status") == "open")
	if open.is_empty():
		return {}
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start_time) < int(b.start_time))
	return open[0]


## Reklame for påmelding: pokalen det spilles om, navnet, når den starter og hvor mange som er med,
## og «Meld meg på» rett fra menyen. Hele kortet åpner turneringen.
func _promo_card(t: Dictionary) -> PanelContainer:
	var id := int(t.id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI._box(Color("1d2a42"), 12, UI.ACCENT_HOVER, 10, 8, 4))
	var open_page := Button.new()   # under innholdet: trykk hvor som helst på kortet
	open_page.theme_type_variation = "GhostButton"
	open_page.pressed.connect(func() -> void:
		Sfx.play("click")
		Net.ensure_connected()
		app.show_tournament(id, true)
	)
	card.add_child(open_page)
	var row := UI.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(TrophyView.new(t.get("trophy", {}), 62, true))
	var texts := UI.vbox(0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kicker := UI.label("Turnering – meld deg på!", "Muted")
	kicker.add_theme_color_override("font_color", Color("a9c1f2"))
	texts.add_child(kicker)
	var name := UI.label(str(t.name))
	name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name.add_theme_font_size_override("font_size", 19)
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(name)
	var when := "%s · %d/%d" % [UI.format_when(int(t.start_time)), int(t.players), int(t.max_players)]
	var sub := UI.label(when, "Muted")
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(sub)
	row.add_child(texts)
	if bool(t.get("joined", false)):
		var joined := UI.label("Påmeldt", "Muted")
		joined.add_theme_color_override("font_color", UI.SUCCESS)
		joined.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(joined)
	else:
		var join := UI.button("Meld meg på", func() -> void: _quick_join(id), "PrimaryButton")
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(join)
	card.add_child(row)
	# Kortet pulserer svakt, så det synes
	var tw := card.create_tween().set_loops()
	tw.tween_property(card, "self_modulate", Color(1.1, 1.1, 1.18), 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card, "self_modulate", Color.WHITE, 1.1).set_trans(Tween.TRANS_SINE)
	return card


## «Meld meg på» fra menyen. Uten konto åpnes innloggingen først.
func _quick_join(id: int) -> void:
	if not Net.is_logged_in():
		app.show_account(true)
		return
	Net.ensure_connected()
	Net.send({ "t": Protocol.TOURNAMENT_JOIN, "id": id })


func _tournament_button(t: Dictionary) -> Button:
	var running: bool = t.status == "running"
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.custom_minimum_size.y = 58
	b.icon = _dot_icon(UI.SUCCESS if running else UI.ACCENT)
	var when := tr("Pågår nå") if running else tr("Påmelding åpen") + " · " + tr("starter %s") % UI.format_time(int(t.start_time))
	b.text = "%s\n%s · %d/%d" % [t.name, when, int(t.players), int(t.max_players)]
	var id := int(t.id)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		Net.ensure_connected()
		app.show_tournament(id, true)
	)
	if running:
		# Pågående turnering pulserer svakt, så den synes på forsiden
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "self_modulate", Color(1.12, 1.12, 1.12), 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return b


static func _dot_icon(color: Color) -> Texture2D:
	var px := 28
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - px / 2.0, y + 0.5 - px / 2.0).length()
			var a := clampf(px * 0.3 - d + 0.5, 0.0, 1.0)
			var ring := clampf(px * 0.48 - d + 0.5, 0.0, 1.0) * 0.25
			img.set_pixel(x, y, Color(color, maxf(a, ring)))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(14, 14))
	return tex


func _demo_step() -> void:
	# De siste partiene på serveren vinner over bot-demoen
	if _replay.is_empty():
		var next := next_replay()
		if not next.is_empty():
			_start_replay(next)
			return
	if not _replay.is_empty():
		_replay_step()
		return
	if _demo.is_over():
		_demo = GameState.new()
		app.board.clear_pieces()
		return
	var player := _demo.current_player
	var r := _demo.play(_demo_bot.choose_move(_demo))
	app.board.add_piece(r.pos, player)
	if _demo.is_over() and not _demo.winning_line.is_empty():
		app.board.highlight(_demo.winning_line)


# ---------------------------------------------------------------- Siste parti

## Et tilfeldig av de tre siste partiene, men ikke det samme som sist (så de går på rundgang).
func next_replay() -> Dictionary:
	var games: Array = Net.last_games if not Net.last_games.is_empty() \
		else ([Net.last_game] if not Net.last_game.is_empty() else [])
	var choices := games.filter(func(g: Dictionary) -> bool: return g != _replay_last)
	if choices.is_empty():
		choices = games
	return choices.pick_random() if not choices.is_empty() else {}


func _start_replay(rec: Dictionary) -> void:
	_replay = rec
	_replay_last = rec
	_replay_i = 0
	_replay_pause = 0
	var opts := GameOptions.from_dict(rec.get("options", {}) if rec.get("options") is Dictionary else {})
	_demo = GameState.new(opts, int(rec.get("first", 1)))
	if app.board.size != opts.size:
		app.board.setup(opts.size)
		_layout()
	app.board.clear_pieces()
	var recs: Array = rec.get("players", [])
	var looks := []
	for i in 2:
		var p: Dictionary = recs[i] if i < recs.size() and recs[i] is Dictionary else {}
		looks.append(Skins.look(str(p.get("skin", Skins.DEFAULT_P1 if i == 0 else Skins.DEFAULT_P2)),
			str(p.get("decal", "none")), "classic", bool(p.get("away", false)), str(p.get("decal_color", "auto"))))
	var pair := Skins.resolve_pair(looks[0], looks[1])
	app.board.set_looks(pair[0], pair[1])
	var newest: bool = Net.last_games.is_empty() or rec == Net.last_games[0]
	_replay_title = (tr("Siste parti: %s") if newest else tr("Nylig parti: %s")) % _names(rec)
	_caption.text = _replay_title
	_caption_box.visible = true


func _replay_step() -> void:
	var moves: Array = _replay.get("moves", [])
	if _replay_i < moves.size():
		var m = moves[_replay_i]
		_replay_i += 1
		var player := _demo.current_player
		var r := _demo.play(Vector2i(int(m[0]), int(m[1])), false)
		if r.get("ok", false):
			app.board.add_piece(r.pos, player)
		if _replay_i == moves.size():
			if not _demo.winning_line.is_empty():
				app.board.highlight(_demo.winning_line)
			_caption.text = _replay_title + "\n" + result_text(_replay)
		return
	# Sluttstillingen står en stund, så kommer et av de andre siste partiene
	_replay_pause += 1
	if _replay_pause >= REPLAY_PAUSE_STEPS:
		_replay = {}


static func _names(rec: Dictionary) -> String:
	var recs: Array = rec.get("players", [])
	var names := []
	for i in 2:
		names.append(str(recs[i].get("name", "?")) if i < recs.size() and recs[i] is Dictionary else "?")
	return "%s – %s" % names


## «Ada vant på tid», «Uavgjort – fullt brett» osv.
static func result_text(rec: Dictionary) -> String:
	var recs: Array = rec.get("players", [])
	var result := int(rec.get("result", 0))
	if result == GameState.Result.DRAW:
		return str(TranslationServer.translate("Uavgjort – fullt brett"))
	var seat := 1 if result == GameState.Result.P1_WON else 2
	var winner := str(recs[seat - 1].get("name", "?")) if seat - 1 < recs.size() and recs[seat - 1] is Dictionary else "?"
	var key := "%s vant med fire på rad"
	match int(rec.get("reason", 0)):
		GameState.EndReason.TIMEOUT: key = "%s vant på tid"
		GameState.EndReason.RESIGN: key = "%s vant – motstanderen ga opp"
		GameState.EndReason.DISCONNECT: key = "%s vant – motstanderen forlot partiet"
	return str(TranslationServer.translate(key)) % winner
