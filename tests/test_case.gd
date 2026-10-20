class_name TestCase
extends RefCounted
## Base for tester. Lag en fil tests/test_*.gd som arver TestCase, og skriv
## metoder som starter med test_. Kjøres av tests/run_tests.tscn.

var failures: Array[String] = []
var tree: SceneTree   ## satt av testløperen, for tester som trenger frames
var root: Node        ## testløper-noden: legg midlertidige noder her


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(cond: bool, msg: String = "forventet true") -> void:
	if not cond:
		failures.append(msg)


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s forventet <%s>, fikk <%s>" % [msg, str(expected), str(actual)])


## Spiller en liste med trekk [[x, y], ...] og feiler hvis et trekk er ulovlig.
func play_all(state: GameState, moves: Array) -> void:
	for m in moves:
		var r := state.play(Vector2i(m[0], m[1]))
		if not r.ok:
			failures.append("trekk %s var ulovlig (%s)" % [str(m), GameState.error_text(r.error)])
			return


## Venter til cond() er sann, eller gir opp etter timeout_s. Gir true hvis den ble sann.
func wait_until(cond: Callable, timeout_s := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()
