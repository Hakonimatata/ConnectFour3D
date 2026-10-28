class_name RoomScreen
extends Screen
## Venterom: romkode, spillere, brikkene slik de blir i partiet, innstillinger, «klar»-knapp og chat.
## Når begge er klare starter serveren partiet (game_start).
## Er kontrasten mellom brikkene dårlig, kan du bytte skin her (motstanderen ser det med en gang).

var _room: Dictionary
var _code_label: Label
var _desc_label: Label
var _players_box: VBoxContainer
var _ready_button: Button
var _options_button: Button
var _chat: ChatPanel
var _is_ready := false
var _hint_label: Label
var _invite_button: Button
var _friends_button: Button
var _friend_list: VBoxContainer
var _preview: PiecePreview
var _preview_names: Label
var _skin_picker: HFlowContainer
var _skin_button: Button
var _leave_button: Button
var _walkover_end_ms := 0     ## turneringskamp der motstanderen ikke har kommet: når du vinner på walkover
var _tournament_hint := ""


func _init(p_app: ClientRoot, room_state: Dictionary) -> void:
	super(p_app)
	_room = room_state


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 520)
	v.add_child(UI.label("Rom", "Muted"))
	_code_label = UI.label("", "Title")
	v.add_child(_code_label)
	_hint_label = UI.label("Gi koden til en venn, så kan de bli med.", "Muted", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_hint_label)
	_invite_button = UI.button("Del invitasjon", func() -> void:
		_hint_label.text = app.share_link("rom", str(_room.get("code", "")), tr("Bli med i rommet mitt!"))
	)
	v.add_child(_invite_button)
	# Venner som er online kan inviteres rett inn i rommet (de får et banner med «Bli med»)
	_friends_button = UI.button("Inviter en venn", func() -> void:
		_friend_list.visible = not _friend_list.visible
		if _friend_list.visible:
			show_invite_list(Net.friends)
			Net.send({ "t": Protocol.FRIEND, "action": "list" })
	)
	v.add_child(_friends_button)
	_friend_list = UI.vbox(6)
	_friend_list.visible = false
	v.add_child(_friend_list)
	_desc_label = UI.label("", "", HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_desc_label)

	v.add_child(UI.section("Spillere"))
	_players_box = UI.vbox(8)
	v.add_child(_players_box)

	# Brikkene slik de blir i partiet (sete 1 til venstre), og bytte av egen skin
	_preview = PiecePreview.new(110)
	v.add_child(_preview)
	_preview_names = UI.label("", "Muted", HORIZONTAL_ALIGNMENT_CENTER, true)
	_preview_names.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(_preview_names)
	_skin_button = UI.button("Bytt skin", func() -> void: _skin_picker.visible = not _skin_picker.visible)
	v.add_child(_skin_button)
	_skin_picker = HFlowContainer.new()
	_skin_picker.add_theme_constant_override("h_separation", 6)
	_skin_picker.add_theme_constant_override("v_separation", 6)
	_skin_picker.visible = false
	var group := ButtonGroup.new()
	for skin in Skins.ALL:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = skin.id == Settings.skin_id
		b.theme_type_variation = "ChoiceButton"
		b.icon = Skins.swatch(skin.id, 26)
		b.tooltip_text = skin.name
		b.custom_minimum_size = Vector2(44, 40)
		b.pressed.connect(_pick_skin.bind(str(skin.id)))
		_skin_picker.add_child(b)
	var kit := UI.button("Bytt drakt", func() -> void:
		Sfx.play("click")
		Settings.kit_away = not Settings.kit_away
		Settings.save()
		Net.send_look()
	)
	kit.custom_minimum_size = Vector2(0, 40)
	_skin_picker.add_child(kit)
	v.add_child(_skin_picker)

	var row := UI.hbox(10)
	_ready_button = UI.button("Klar!", _toggle_ready, "PrimaryButton")
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_button = UI.button("Endre regler", _edit_options)
	row.add_child(_ready_button)
	row.add_child(_options_button)
	v.add_child(row)

	v.add_child(UI.section("Chat"))
	_chat = ChatPanel.new()
	_chat.custom_minimum_size.y = 220
	_chat.send_requested.connect(func(t: String) -> void: Net.send({ "t": Protocol.CHAT, "text": t }))
	v.add_child(_chat)

	_leave_button = UI.button("Forlat rommet", _on_back)
	v.add_child(_leave_button)

	Net.message.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)
	_show(_room)


## Turneringskamp: «Motstanderen har ikke kommet. Du vinner på walkover om 3:12.»
func _update_walkover() -> void:
	if _walkover_end_ms == 0:
		return
	var players: Array = _room.get("players", [])
	var both := players.size() >= 2 and players[0] is Dictionary and players[1] is Dictionary
	if both:
		_hint_label.text = _tournament_hint
		return
	var left := maxi(0, _walkover_end_ms - Time.get_ticks_msec()) / 1000
	var clock := "%d:%02d" % [left / 60, left % 60]
	if int(_room.get("you", 0)) == 0:
		_hint_label.text = _tournament_hint + "
" + tr("Kommer ikke begge innen %s, avgjøres kampen på walkover.") % clock
	else:
		_hint_label.text = _tournament_hint + "
" + tr("Motstanderen har ikke kommet ennå. Kommer hen ikke innen %s, vinner du på walkover.") % clock


func _process(_delta: float) -> void:
	if _walkover_end_ms != 0 and Engine.get_process_frames() % 15 == 0:
		_update_walkover()


func _on_disconnected() -> void:
	_chat.add_system("Mistet forbindelsen. Kobler til igjen…")


func _show(room: Dictionary) -> void:
	_room = room
	_code_label.text = str(room.get("code", ""))
	var opts = room.get("options", {})
	_desc_label.text = GameOptions.from_dict(opts if opts is Dictionary else {}).describe()
	var you := int(room.get("you", 1))
	var tournament = room.get("tournament")
	var is_tournament: bool = tournament is Dictionary
	_options_button.visible = you == 1 and not is_tournament
	_ready_button.visible = not is_tournament
	_invite_button.visible = not is_tournament
	_walkover_end_ms = 0
	if is_tournament:
		_tournament_hint = tr("Turneringskamp i «%s». Kampen starter når begge er her.") % tournament.name
		if not bool(tournament.get("ranked", true)):
			_tournament_hint += " " + tr("Uranket: Elo endres ikke.")
		_hint_label.text = _tournament_hint
		var left := int(tournament.get("walkover_in", 0))
		if left > 0:
			_walkover_end_ms = Time.get_ticks_msec() + left * 1000
			_update_walkover()
	var spectator := you == 0
	_skin_button.visible = not spectator
	_options_button.visible = _options_button.visible and not spectator
	_ready_button.visible = _ready_button.visible and not spectator
	_leave_button.text = tr("Slutt å se på") if spectator else tr("Forlat rommet")
	if spectator:
		_hint_label.text = tr("Du ser på som tilskuer. Partiet vises når begge spillerne er her.")
	for c in _players_box.get_children():
		c.queue_free()
	var players: Array = room.get("players", [])
	var both := true
	for i in 2:
		var info = players[i] if i < players.size() else null
		var row := UI.hbox(10)
		if info == null:
			both = false
			row.add_child(UI.dot(UI.BORDER))
			row.add_child(UI.label("Venter på motstander…", "Muted"))
		else:
			var avatar := AvatarView.new(34)
			avatar.set_avatar(str(info.get("avatar", "")), str(info.name), Skins.color_of(str(info.skin)))
			row.add_child(avatar)
			if info.get("elo") != null:
				row.add_child(EloBadge.make(int(info.elo), 22))
			var shown := tr("%s (deg)") % str(info.name) if int(info.seat) == you else str(info.name)
			if info.get("elo") != null:
				shown += "  ·  Elo %d" % int(info.elo)
			var name_label := UI.label(shown)
			name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var state_text := "klar" if bool(info.ready) else "ikke klar"
			if not bool(info.connected):
				state_text = "frakoblet"
			var s := UI.label(state_text, "Muted")
			if bool(info.ready):
				s.add_theme_color_override("font_color", UI.SUCCESS)
			row.add_child(s)
			if int(info.seat) == you:
				_is_ready = bool(info.ready)
		_players_box.add_child(row)
	_ready_button.text = "Ikke klar likevel" if _is_ready else "Klar!"
	_ready_button.disabled = not both
	# Venner kan inviteres så lenge det er en ledig plass (ikke i turneringer eller som tilskuer)
	_friends_button.visible = not both and not is_tournament and not spectator and Net.is_logged_in()
	if not _friends_button.visible:
		_friend_list.visible = false
	_show_matchup(players, you)


## Viser brikkene som de blir i partiet. Sete 1 har hjemmedrakt; gjesten får bortedrakt
## (eller en annen skin) ved lik farge, akkurat som i OnlineMatch.
func _show_matchup(players: Array, you: int) -> void:
	var looks := {}
	var names := {}
	for info in players:
		if not info is Dictionary:
			continue
		var seat := int(info.seat)
		looks[seat] = Skins.look(str(info.get("skin", "")), str(info.get("decal", "none")),
			str(info.get("win_fx", "classic")), bool(info.get("away", false)), str(info.get("decal_color", "auto")))
		names[seat] = tr("Deg") if seat == you else str(info.name)
	if looks.size() < 2:
		_preview.set_look(looks.get(you, Settings.look()))
		_preview_names.text = tr("Hjemme- og bortedrakten din")
		return
	var pair := Skins.resolve_pair(looks[1], looks[2])
	_preview.set_pair(pair[0], pair[1])
	_preview_names.text = "%s   ·   %s" % [names[1], names[2]]


func _pick_skin(id: String) -> void:
	Sfx.play("click")
	Settings.skin_id = id
	Settings.save()
	Net.send_look()
	_skin_picker.visible = false


func _toggle_ready() -> void:
	Net.send({ "t": Protocol.READY, "ready": not _is_ready })


func _edit_options() -> void:
	var current := GameOptions.from_dict(_room.get("options", {}))
	Settings.last_options = current.to_dict()
	# Callbackene tilhører app (ClientRoot), som lever videre når denne skjermen slettes.
	app.show_setup("online", app.online_set_options.bind(_room), app.show_room.bind(_room))


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		Protocol.ROOM_STATE:
			_show(msg)
		Protocol.CHAT_MSG:
			var seat := int(msg.get("seat", 0))
			var players: Array = _room.get("players", [])
			var color := UI.ACCENT
			if seat >= 1 and seat <= players.size() and players[seat - 1] != null:
				color = Skins.color_of(str(players[seat - 1].skin))
			_chat.add_message(str(msg.get("from", "")), str(msg.get("text", "")), color)
		Protocol.NOTICE, Protocol.ERROR:
			_chat.add_system(I18n.server_text(msg))
		Protocol.FRIENDS:
			if _friend_list.visible:
				show_invite_list(msg)
		Protocol.GAME_START, Protocol.GAME_SYNC:
			app.start_match(OnlineMatch.new(msg))


## Venner som er online og ikke spiller, med «Inviter».
func show_invite_list(data: Dictionary) -> void:
	for c in _friend_list.get_children():
		_friend_list.remove_child(c)
		c.queue_free()
	var free := (data.get("friends", []) as Array).filter(func(f: Dictionary) -> bool:
		return f.get("online", false) and not f.get("playing", false))
	if free.is_empty():
		_friend_list.add_child(UI.label("Ingen venner er ledige akkurat nå. Legg til venner under «Spill online» → «Venner».",
			"Muted", HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for f in free:
		var row := UI.hbox(8)
		row.add_child(EloBadge.make(int(f.get("elo", -1)), 20))
		var name := str(f.username)
		var l := UI.label(name)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.button("Inviter", func() -> void:
			Net.send({ "t": Protocol.FRIEND, "action": "invite", "username": name })
		, "PrimaryButton"))
		_friend_list.add_child(row)


func _on_back() -> void:
	Net.send({ "t": Protocol.LEAVE_ROOM })
	var tournament = _room.get("tournament")
	if int(_room.get("you", 1)) == 0 and tournament is Dictionary:
		app.show_tournament(int(tournament.id))
	else:
		app.show_online()
