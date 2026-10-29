class_name SaveData
extends RefCounted
## Persistent player progress stored as JSON in user://.
## Writes go to a temp file first, then replace the save, so a crash or
## kill mid-write can never leave a corrupted save behind.

const VERSION := 2
const STARTER := "vanta"
const MODES := ["endless", "twoway", "time"]

var path := "user://save.json"
var best_score := 0
var best_distance := 0.0
var best_by_mode := {"endless": 0, "twoway": 0, "time": 0}
var cash := 0
var xp := 0
var total_distance := 0.0
var total_near_misses := 0
var total_overtakes := 0
var runs := 0
var selected_car := STARTER
var owned_cars: Array[String] = [STARTER]
var upgrades := {}   # car id -> {speed, accel, handling, brakes}
var paints := {}     # car id -> paint index
var rims := {}       # car id -> rim colour index
var owned_paints := {}  # car id -> [indices]
var owned_rims := {}    # car id -> [indices]
var missions: Array = []
var mission_seq := 0
var last_daily := ""
var daily_streak := 0
var last_mode := "endless"
var last_env := "day"
var settings := {"music": 0.8, "sfx": 1.0, "engine": 1.0, "steer_sensitivity": 1.0,
		"controls": "buttons", "camera": "near", "quality": "high", "units": "kmh", "crashes": "keep"}


func to_dict() -> Dictionary:
	return {
		"version": VERSION, "best_score": best_score, "best_distance": best_distance,
		"best_by_mode": best_by_mode, "cash": cash, "xp": xp, "total_distance": total_distance,
		"total_near_misses": total_near_misses, "total_overtakes": total_overtakes, "runs": runs,
		"selected_car": selected_car, "owned_cars": owned_cars, "upgrades": upgrades,
		"paints": paints, "rims": rims, "owned_paints": owned_paints, "owned_rims": owned_rims,
		"missions": missions, "mission_seq": mission_seq, "last_daily": last_daily,
		"daily_streak": daily_streak, "last_mode": last_mode, "last_env": last_env, "settings": settings,
	}


func from_dict(d: Dictionary) -> void:
	best_score = int(d.get("best_score", 0))
	best_distance = float(d.get("best_distance", 0.0))
	var bm: Variant = d.get("best_by_mode", {})
	if bm is Dictionary:
		for m in MODES:
			best_by_mode[m] = int((bm as Dictionary).get(m, 0))
	best_by_mode["endless"] = maxi(best_by_mode["endless"], best_score)
	cash = maxi(0, int(d.get("cash", 0)))
	xp = maxi(0, int(d.get("xp", 0)))
	total_distance = float(d.get("total_distance", 0.0))
	total_near_misses = int(d.get("total_near_misses", 0))
	total_overtakes = int(d.get("total_overtakes", 0))
	runs = int(d.get("runs", 0))
	selected_car = str(d.get("selected_car", STARTER))
	owned_cars.clear()
	for c in d.get("owned_cars", [STARTER]):
		if CarCatalog.has_player_car(str(c)):
			owned_cars.append(str(c))
	if not owned_cars.has(STARTER):
		owned_cars.append(STARTER)
	if not owned_cars.has(selected_car):
		selected_car = STARTER
	for key in ["upgrades", "paints", "rims", "owned_paints", "owned_rims"]:
		var v: Variant = d.get(key, {})
		if v is Dictionary:
			set(key, (v as Dictionary).duplicate(true))
	for car in upgrades.keys():
		for cat in Progression.UPGRADES:
			upgrades[car][cat] = clampi(int(upgrades[car].get(cat, 0)), 0, Progression.MAX_LEVEL)
	var ms: Variant = d.get("missions", [])
	missions = (ms as Array).duplicate(true) if ms is Array else []
	mission_seq = int(d.get("mission_seq", 0))
	last_daily = str(d.get("last_daily", ""))
	daily_streak = int(d.get("daily_streak", 0))
	last_mode = str(d.get("last_mode", "endless"))
	if not MODES.has(last_mode):
		last_mode = "endless"
	last_env = str(d.get("last_env", "day"))
	var s: Variant = d.get("settings", {})
	if s is Dictionary:
		for k in settings:
			if (s as Dictionary).has(k):
				settings[k] = s[k] if settings[k] is String else float(s[k])
	ensure_missions()


func ensure_missions() -> void:
	while missions.size() < 3:
		missions.append(Progression.make_mission(mission_seq))
		mission_seq += 1


func load_from_disk() -> bool:
	if not FileAccess.file_exists(path):
		ensure_missions()
		return false
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_warning("Save file unreadable, starting fresh")
		ensure_missions()
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


# ------------------------------------------------------------------ helpers

func level() -> int:
	return int(Progression.level_info(xp)["level"])


func car_levels(id: String) -> Dictionary:
	if not upgrades.has(id):
		upgrades[id] = {"speed": 0, "accel": 0, "handling": 0, "brakes": 0}
	return upgrades[id]


func paint_index(id: String) -> int:
	return int(paints.get(id, -1))


func rim_index(id: String) -> int:
	return int(rims.get(id, 0))


func spend(amount: int) -> bool:
	if amount < 0 or cash < amount:
		return false
	cash -= amount
	return true


func buy_car(id: String) -> bool:
	if owned_cars.has(id) or not CarCatalog.has_player_car(id):
		return false
	if not spend(int(CarCatalog.player_car(id)["price"])):
		return false
	owned_cars.append(id)
	return true


func buy_upgrade(id: String, cat: String) -> bool:
	if not owned_cars.has(id) or not Progression.UPGRADES.has(cat):
		return false
	var lv := car_levels(id)
	var next := int(lv[cat]) + 1
	if next > Progression.MAX_LEVEL:
		return false
	if not spend(Progression.upgrade_cost(CarCatalog.player_car(id), next)):
		return false
	lv[cat] = next
	return true


## Paint and rim colours: buy once per car, then switch freely.
func choose_paint(id: String, index: int) -> bool:
	var owned: Array = owned_paints.get(id, [])
	if index >= 0 and not owned.has(index):
		if not spend(Progression.PAINT_COST):
			return false
		owned.append(index)
		owned_paints[id] = owned
	paints[id] = index
	return true


func choose_rim(id: String, index: int) -> bool:
	var owned: Array = owned_rims.get(id, [0])
	if not owned.has(index):
		if not spend(Progression.RIM_COST):
			return false
		owned.append(index)
		owned_rims[id] = owned
	rims[id] = index
	return true


## Records a finished run. Returns a summary of everything it unlocked.
func record_run(mode: String, score: int, distance: float, near_misses: int, earned: int,
		gained_xp := 0, overtakes := 0) -> Dictionary:
	runs += 1
	var before := level()
	cash += earned
	xp += gained_xp
	total_distance += distance
	total_near_misses += near_misses
	total_overtakes += overtakes
	best_distance = maxf(best_distance, distance)
	var best := false
	if score > int(best_by_mode.get(mode, 0)):
		best_by_mode[mode] = score
		best = true
	best_score = maxi(best_score, score)
	var after := level()
	var bonus := 0
	for l in range(before + 1, after + 1):
		bonus += Progression.level_up_reward(l)
	cash += bonus
	return {"best": best, "level_before": before, "level_after": after, "level_bonus": bonus}


## Applies run stats to missions, pays completed ones and refills the list.
func apply_missions(run: Dictionary) -> Array:
	var done := Progression.apply_run(missions, run)
	for m in done:
		cash += int(m["reward"])
	if not done.is_empty():
		missions = missions.filter(func(m): return int(m["progress"]) < int(m["target"]))
		ensure_missions()
	return done


func claim_daily(today: String) -> int:
	var st := Progression.daily_state(last_daily, daily_streak, today)
	if not st["available"]:
		return 0
	last_daily = today
	daily_streak = int(st["streak"])
	cash += int(st["reward"])
	return int(st["reward"])
