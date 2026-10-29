class_name SaveData
extends RefCounted
## Persistent player progress stored as JSON in user://.
## Writes go to a temp file first, then replace the save, so a crash or
## kill mid-write can never leave a corrupted save behind.

const VERSION := 1

var path := "user://save.json"
var best_score := 0
var best_distance := 0.0
var cash := 0
var total_distance := 0.0
var total_near_misses := 0
var runs := 0
var selected_car := "kestrel"
var owned_cars: Array[String] = ["kestrel"]
var settings := {"music": 0.8, "sfx": 1.0, "engine": 1.0, "steer_sensitivity": 1.0}


func to_dict() -> Dictionary:
	return {
		"version": VERSION, "best_score": best_score, "best_distance": best_distance,
		"cash": cash, "total_distance": total_distance, "total_near_misses": total_near_misses,
		"runs": runs, "selected_car": selected_car, "owned_cars": owned_cars, "settings": settings,
	}


func from_dict(d: Dictionary) -> void:
	best_score = int(d.get("best_score", 0))
	best_distance = float(d.get("best_distance", 0.0))
	cash = maxi(0, int(d.get("cash", 0)))
	total_distance = float(d.get("total_distance", 0.0))
	total_near_misses = int(d.get("total_near_misses", 0))
	runs = int(d.get("runs", 0))
	selected_car = str(d.get("selected_car", "kestrel"))
	owned_cars.clear()
	for c in d.get("owned_cars", ["kestrel"]):
		owned_cars.append(str(c))
	if not owned_cars.has("kestrel"):
		owned_cars.append("kestrel")
	if not owned_cars.has(selected_car):
		selected_car = "kestrel"
	var s: Variant = d.get("settings", {})
	if s is Dictionary:
		for k in settings:
			if (s as Dictionary).has(k):
				settings[k] = float(s[k])


func load_from_disk() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_warning("Save file unreadable, starting fresh")
		return false
	from_dict(data)
	return true


func save_to_disk() -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	return dir.rename(tmp.get_file(), path.get_file()) == OK


## Records a finished run. Returns true if it set a new best score.
func record_run(score: int, distance: float, near_misses: int, earned: int) -> bool:
	runs += 1
	cash += earned
	total_distance += distance
	total_near_misses += near_misses
	best_distance = maxf(best_distance, distance)
	if score > best_score:
		best_score = score
		return true
	return false
