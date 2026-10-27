class_name SetupScreen
extends Screen
## Spilloppsett: brett, regler, klokke og hvem som starter.
## Brukes for «mot AI», «lokalt» og «opprett online-rom» (samme skjema).

const CLOCKS := [[0, 0], [60, 0], [180, 2], [300, 0], [600, 5]]
const CLOCK_NAMES := ["Av", "1+0", "3+2", "5+0", "10+5"]
const SIZES := [4, 5]
const STARTERS := ["p1", "p2", "random", "alternate"]

var mode: String             ## "ai", "local" eller "online"
var on_confirm: Callable     ## Kun online: kalles med (options, private)
var on_cancel: Callable      ## Kun online: hva «Tilbake» gjør
var options: GameOptions
var _private := false


func _init(p_app: ClientRoot, p_mode: String, p_on_confirm := Callable(), p_on_cancel := Callable()) -> void:
	super(p_app)
	mode = p_mode
	on_confirm = p_on_confirm
	on_cancel = p_on_cancel
	options = GameOptions.from_dict(Settings.last_options)


func _ready() -> void:
	app.camera.auto_rotate = true
	var v := UI.centered_card(self, 480)
	var titles := { "ai": "Spill mot AI", "local": "To spillere", "online": "Nytt rom" }
	v.add_child(UI.label(titles[mode], "Heading"))

	if mode == "ai":
		v.add_child(UI.section("Vanskelighetsgrad"))
		v.add_child(UI.choice(BotProfile.level_names(), Settings.ai_level, func(i: int) -> void: Settings.ai_level = i))

	add_option_fields(v, options)

	v.add_child(UI.section("Hvem starter"))
	var starter_names := ["Jeg", "Motstander", "Tilfeldig", "Annenhver"]
	if mode == "local":
		starter_names = ["Spiller 1", "Spiller 2", "Tilfeldig", "Annenhver"]
	elif mode == "online":
		starter_names = ["Verten", "Gjesten", "Tilfeldig", "Annenhver"]
	v.add_child(UI.choice(starter_names, maxi(0, STARTERS.find(options.starter)),
		func(i: int) -> void: options.starter = STARTERS[i]))

	if mode == "online" and not on_cancel.is_valid():
		v.add_child(UI.section("Synlighet"))
		v.add_child(UI.toggle_row("Privat rom", "Vises ikke i listen. Venner blir med med koden.",
			_private, func(on: bool) -> void: _private = on))

	var buttons := UI.hbox(10)
	var back := UI.button("Tilbake", _on_back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var start_text := "Start"
	if mode == "online":
		start_text = "Lagre" if on_cancel.is_valid() else "Opprett rom"
	var start := UI.button(start_text, _on_start, "PrimaryButton")
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	buttons.add_child(start)
	UI.card_footer(v).add_child(buttons)


## Brett, regler og klokke. Brukes også av turneringsskjemaet.
static func add_option_fields(v: VBoxContainer, opts: GameOptions) -> void:
	v.add_child(UI.section("Brett"))
	v.add_child(UI.choice(["4×4×4", "5×5×5"], SIZES.find(opts.size), func(i: int) -> void: opts.size = SIZES[i]))

	v.add_child(UI.section("Regler"))
	v.add_child(UI.toggle_row("Må blokkere", "Kan motstanderen vinne på neste trekk, må du stoppe det.",
		opts.must_block, func(on: bool) -> void: opts.must_block = on))
	v.add_child(UI.toggle_row("Ikke gi bort seier", "Du kan ikke legge slik at motstanderen kan vinne rett over.",
		opts.no_gift, func(on: bool) -> void: opts.no_gift = on))

	v.add_child(UI.section("Klokke (minutter + sekunder per trekk)"))
	# Faste valg, eller «Egen»: velg minutter og ekstra sekunder per trekk selv.
	var clock_index := CLOCKS.size()
	for i in CLOCKS.size():
		if CLOCKS[i][0] == opts.time_base_s and CLOCKS[i][1] == opts.time_increment_s:
			clock_index = i
	var custom := UI.hbox(8)
	var minutes := _spin(1, 60, maxi(1, opts.time_base_s / 60) if opts.time_base_s > 0 else 5)
	var extra := _spin(0, 60, opts.time_increment_s)
	custom.add_child(minutes)
	custom.add_child(UI.label("min", "Muted"))
	custom.add_child(UI.spacer(0))
	custom.add_child(extra)
	custom.add_child(UI.label("sek per trekk", "Muted"))
	custom.visible = clock_index == CLOCKS.size()
	minutes.value_changed.connect(func(value: float) -> void: opts.time_base_s = int(value) * 60)
	extra.value_changed.connect(func(value: float) -> void: opts.time_increment_s = int(value))
	var names: Array = CLOCK_NAMES.duplicate()
	names.append("Egen")
	v.add_child(UI.choice(names, clock_index, func(i: int) -> void:
		custom.visible = i == CLOCKS.size()
		if custom.visible:
			opts.time_base_s = int(minutes.value) * 60
			opts.time_increment_s = int(extra.value)
		else:
			opts.time_base_s = CLOCKS[i][0]
			opts.time_increment_s = CLOCKS[i][1]
	))
	v.add_child(custom)


static func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.rounded = true
	s.value = clampi(value, lo, hi)
	s.custom_minimum_size = Vector2(110, 0)
	s.select_all_on_focus = true
	return s


func _on_start() -> void:
	Settings.last_options = options.to_dict()
	Settings.save()
	match mode:
		"ai":
			app.start_match(OfflineMatch.new(options, BotProfile.create(Settings.ai_level)))
		"local":
			app.start_match(OfflineMatch.new(options))
		"online":
			on_confirm.call(options, _private)


func _on_back() -> void:
	if on_cancel.is_valid():
		on_cancel.call()
	elif mode == "online":
		app.show_online()
	else:
		app.show_menu()
