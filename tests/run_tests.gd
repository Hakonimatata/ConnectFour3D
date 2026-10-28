extends Node
## Testløper (scenen tests/run_tests.tscn). Kjør fra roten av prosjektet:
##   godot --headless res://tests/run_tests.tscn
## Valgfritt filter:  godot --headless res://tests/run_tests.tscn -- rules
## (Som scene, ikke -s, slik at autoloads som Settings og Net er lastet.)
## Avslutter med kode 1 hvis noen test feiler (så CI blir rød).
## Skriptfeil (f.eks. kall på null) under en test teller også som feil.


class ErrorCounter extends Logger:
	var count := 0
	var first := ""
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		if first == "":
			first = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]
		_mutex.unlock()

	func reset() -> void:
		_mutex.lock()
		count = 0
		first = ""
		_mutex.unlock()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]

	Settings.persist = false   # testene skal aldri overskrive spillerens innstillinger
	# Ingen nedtelling før partiene, så testene kan spille med en gang (testene av nedtellingen slår den på)
	Lobby.countdown_ms = 0
	MatchController.countdown_ms = 0
	var errors := ErrorCounter.new()
	OS.add_logger(errors)

	var files := DirAccess.get_files_at("res://tests")
	var passed := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()

	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if filter != "" and not file.contains(filter):
			continue
		print("\n%s" % file)
		errors.reset()
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate() or errors.count > 0:
			failed += 1
			print("  FEIL  kunne ikke laste filen: " + errors.first)
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.tree = get_tree()
			t.root = self
			errors.reset()
			t.before_each()
			var started := Time.get_ticks_msec()
			await t.call(name)
			t.after_each()
			var ms := Time.get_ticks_msec() - started
			if errors.count > 0:
				t.failures.append("%d skriptfeil, første: %s" % [errors.count, errors.first])
			if t.failures.is_empty():
				passed += 1
				print("  ok    %s (%d ms)" % [name, ms])
			else:
				failed += 1
				print("  FEIL  %s" % name)
				for f in t.failures:
					print("        - " + f)

	OS.remove_logger(errors)
	print("\n%d ok, %d feilet (%.1f s)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if failed > 0 else 0)
