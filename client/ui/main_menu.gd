class_name MainMenu
extends Screen
## Hovedmenyen. I bakgrunnen spiller to boter mot hverandre mens kameraet roterer.

var _demo: GameState
var _demo_bot := Bot.new(BotProfile.create(BotProfile.Level.MEDIUM))
var _panel: Control


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
	card.add_child(v)

	v.add_child(UI.label("Fire på rad", "Title"))
	v.add_child(UI.label("i 3D · mot AI, lokalt eller online", "Muted"))
	v.add_child(UI.spacer(8))
	v.add_child(UI.button("Spill mot AI", func() -> void: app.show_setup("ai"), "PrimaryButton"))
	v.add_child(UI.button("To spillere på samme enhet", func() -> void: app.show_setup("local")))
	v.add_child(UI.button("Spill online", func() -> void: app.show_online()))
	v.add_child(UI.button("Innstillinger", func() -> void: app.show_settings()))
	v.add_child(UI.spacer(4))

	var who := UI.hbox(8)
	var avatar := AvatarView.new(30)
	avatar.set_avatar(Settings.avatar, Settings.player_name, Skins.color_of(Settings.skin_id))
	who.add_child(avatar)
	who.add_child(UI.label(Settings.player_name, "Muted"))
	v.add_child(who)

	resized.connect(_layout)
	_layout.call_deferred()

	var timer := Timer.new()
	timer.wait_time = 0.9
	timer.autostart = true
	timer.timeout.connect(_demo_step)
	add_child(timer)
	_demo = GameState.new()


## Bred skjerm: kortet til venstre. Smal (mobil): kortet nederst.
func _layout() -> void:
	var portrait := size.y > size.x
	var w := minf(400.0, size.x - 32.0)
	_panel.custom_minimum_size.x = w
	# Flytt brettet bort fra kortet: opp på mobil, til høyre på PC.
	if portrait:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
		app.camera.view_offset = Vector2(0, -1.4)
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 48)
		app.camera.view_offset = Vector2(-1.8, 0)


func _demo_step() -> void:
	if _demo.is_over():
		_demo = GameState.new()
		app.board.clear_pieces()
		return
	var player := _demo.current_player
	var r := _demo.play(_demo_bot.choose_move(_demo))
	app.board.add_piece(r.pos, player)
	if _demo.is_over() and not _demo.winning_line.is_empty():
		app.board.highlight(_demo.winning_line)
