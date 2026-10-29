extends SceneTree
## Headless test runner. Runs every test_* method in tests/test_*.gd.
##   godot --headless --path . -s res://tests/run_tests.gd

var failures: Array[String] = []
var current := ""


func _initialize() -> void:
	var total := 0
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var inst = script.new()
			inst.set("t", self)
			current = "%s::%s" % [f.get_basename(), name]
			var before := failures.size()
			inst.call(name)
			total += 1
			print(("  ok   " if failures.size() == before else "  FAIL ") + current)
	print("\n%d tests, %d failures" % [total, failures.size()])
	for f in failures:
		print("  - " + f)
	quit(1 if failures.size() > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (got %f, want %f)" % [msg, a, b])
