extends TestCase
## Tester for språk (client/i18n.gd).

## Filer med tekst som vises for spilleren
const SOURCES := ["res://client", "res://core/game_options.gd", "res://core/game_state.gd",
	"res://ai/bot_profile.gd", "res://net/net_client.gd", "res://server/lobby.gd", "res://server/accounts.gd",
	"res://server/tournaments.gd", "res://server/puzzles.gd"]

## Mønstre som fanger tekst som vises i UI-et
const PATTERNS := [
	"(?:tr|I18n\\.t|UI\\.label|UI\\.button|UI\\.section|UI\\.toggle_row|_show_status|_reject)\\(\"([^\"]+)\"",
	"UI\\.toggle_row\\(\"[^\"]*\", \"([^\"]+)\"",
	"UI\\.line_edit\\([^,]+, \"([^\"]+)\"",
	"\"name\": \"([^\"]+)\"",
	"_notice_room\\(room, \"([^\"]+)\"",
	"_error\\([^,]+, \"[^\"]+\", \"([^\"]+)\"",
	"MoveError\\.[A-Z_]+: return \"([^\"]+)\"",
	"\"error\": \"([^\"]+)\"",
	"_notify_all\\(t, \"([^\"]+)\"",
	"close_room\\.call\\([^,]+, \"([^\"]+)\"",
	"\\n\\s*return \"([A-ZÆØÅ][^\"]*\\.)\"",
	"\\.event\\(\"([^\"]+)\"",
	"announce\\.call\\(\"([^\"]+)\"",
]

var _old_locale := ""


func before_each() -> void:
	_old_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_old_locale)


func test_every_ui_text_has_english() -> void:
	var missing: Array[String] = []
	var found := 0
	for text in _ui_texts():
		found += 1
		if not I18n.EN.has(text):
			missing.append(text)
	check(found > 80, "fant for få tekster (%d), er mønstrene riktige?" % found)
	check(missing.is_empty(), "mangler engelsk for: %s" % ", ".join(missing))


func test_translation_follows_language() -> void:
	I18n.apply("en")
	check_eq(str(TranslationServer.translate("Spill mot AI")), "Play vs AI")
	check_eq(str(TranslationServer.translate("%s vant!")) % "Ada", "Ada won!")
	check_eq(I18n.server_text({ "text": "Ada ble med.", "key": "%s ble med.", "args": ["Ada"] }), "Ada joined.")
	check_eq(I18n.server_text({ "text": "Det er ikke din tur." }), "It's not your turn.")
	I18n.apply("nb")
	check_eq(str(TranslationServer.translate("Spill mot AI")), "Spill mot AI", "norsk skal ikke falle tilbake til engelsk:")
	check_eq(I18n.server_text({ "text": "Ada ble med.", "key": "%s ble med.", "args": ["Ada"] }), "Ada ble med.")


func test_english_texts_are_filled_in_and_keep_placeholders() -> void:
	for k in I18n.EN:
		var v: String = I18n.EN[k]
		check(v.strip_edges() != "", "tom oversettelse for «%s»" % k)
		check_eq(v.count("%s"), k.count("%s"), "plassholdere i «%s»:" % k)


func _ui_texts() -> Array[String]:
	var res: Array[String] = []
	var regexes: Array[RegEx] = []
	for p in PATTERNS:
		var r := RegEx.new()
		r.compile(p)
		regexes.append(r)
	for path in _files():
		# Hopp over kommentarer (de kan inneholde eksempler som tr("mønster %s"))
		var lines: Array[String] = []
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):
				lines.append(line)
		var src := "\n".join(lines)
		for r in regexes:
			for m in r.search_all(src):
				var text := m.get_string(1)
				if text != "" and not text in res:
					res.append(text)
	return res


func _files() -> Array[String]:
	var out: Array[String] = []
	for s in SOURCES:
		if s.ends_with(".gd"):
			out.append(s)
		else:
			_walk(s, out)
	return out


func _walk(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)
