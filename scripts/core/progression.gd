class_name Progression
extends RefCounted
## Economy and long-term progression rules (pure logic, no nodes):
## upgrades and their effect on handling, prices, XP/levels, run rewards,
## missions and the daily reward.

const UPGRADES := ["speed", "accel", "handling", "brakes"]
const UPGRADE_NAMES := {"speed": "Top speed", "accel": "Acceleration",
		"handling": "Handling", "brakes": "Brakes"}
const MAX_LEVEL := 5
const PAINT_COST := 1500
const RIM_COST := 800


## Handling stats for a car with the given upgrade levels {cat: level}.
## Each level is felt on the road: +4% top speed, +7% acceleration,
## +5% lateral speed/grip and +7% steering response, +8% braking.
static func stats_for(car: Dictionary, levels: Dictionary) -> Dictionary:
	var base: Dictionary = car["stats"]
	var s := base.duplicate()
	var sp := int(levels.get("speed", 0))
	var ac := int(levels.get("accel", 0))
	var ha := int(levels.get("handling", 0))
	var br := int(levels.get("brakes", 0))
	s["top_speed"] = float(base["top_speed"]) * (1.0 + 0.04 * sp)
	s["accel"] = float(base["accel"]) * (1.0 + 0.07 * ac)
	s["lat_max"] = float(base["lat_max"]) * (1.0 + 0.05 * ha)
	s["lat_grip"] = float(base["lat_grip"]) * (1.0 + 0.05 * ha)
	s["steer_response"] = float(base["steer_response"]) * (1.0 + 0.07 * ha)
	s["brake_decel"] = float(base["brake_decel"]) * (1.0 + 0.08 * br)
	return s


## 0..1 ratings for the garage bars, against the best possible car.
static func ratings(stats: Dictionary) -> Dictionary:
	return {
		"speed": clampf((float(stats["top_speed"]) - 40.0) / 70.0, 0.05, 1.0),
		"accel": clampf((float(stats["accel"]) - 5.0) / 12.0, 0.05, 1.0),
		"handling": clampf((float(stats["lat_max"]) * float(stats["steer_response"]) - 25.0) / 55.0, 0.05, 1.0),
		"brakes": clampf((float(stats["brake_decel"]) - 9.0) / 18.0, 0.05, 1.0),
	}


## Price of buying `level` (1..MAX_LEVEL) of an upgrade for a car.
static func upgrade_cost(car: Dictionary, level: int) -> int:
	var base := 1200 + int(car["price"]) / 25
	return int(round(base * pow(1.55, level - 1) / 50.0)) * 50


static func xp_to_next(level: int) -> int:
	return 1500 + 900 * (level - 1)


## Returns {level, into, need} for a total XP amount.
static func level_info(xp: int) -> Dictionary:
	var level := 1
	var left := xp
	while left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return {"level": level, "into": left, "need": xp_to_next(level)}


const CLEAN_BONUS := 0.3   ## extra cash for a run of 1 km or more without a crash


## Cash and XP for a finished run. Two-way pays more, as in the genre, and a
## crash-free run pays a bonus on top.
static func run_rewards(score: float, distance_m: float, near_misses: int, mode: String,
		crashes := 0) -> Dictionary:
	var mult: float = {"endless": 1.0, "twoway": 1.35, "time": 1.15}.get(mode, 1.0)
	var cash := int((score / 12.0 + near_misses * 6 + distance_m / 1000.0 * 30.0) * mult)
	var clean := 0
	if crashes == 0 and distance_m >= 1000.0:
		clean = int(cash * CLEAN_BONUS)
	var xp := int(score / 8.0 + distance_m / 10.0)
	return {"cash": cash + clean, "clean_bonus": clean, "xp": xp}


static func level_up_reward(level: int) -> int:
	return 1000 + 500 * level


# ------------------------------------------------------------------ daily reward

## Day number from a "YYYY-MM-DD" string (days since 2000-01-01, UTC dates).
static func day_number(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return -1
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]),
			"day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	return int(unix / 86400)


## {available, streak, reward} for today given the last claim and streak.
static func daily_state(last_claim: String, streak: int, today: String) -> Dictionary:
	var d_today := day_number(today)
	var d_last := day_number(last_claim)
	if d_last == d_today:
		return {"available": false, "streak": streak, "reward": 0}
	var new_streak := streak + 1 if d_last == d_today - 1 else 1
	return {"available": true, "streak": new_streak, "reward": 500 * mini(new_streak, 7)}


# ------------------------------------------------------------------ missions

## Mission templates. `stat` names a per-run or lifetime counter; `scale`
## grows the target with the mission number so they get harder over time.
const MISSIONS := [
	{"stat": "near_misses", "text": "Get %d near misses in one run", "base": 8, "step": 4, "per_run": true},
	{"stat": "distance_km", "text": "Drive %d km in one run", "base": 2, "step": 1, "per_run": true},
	{"stat": "top_kmh", "text": "Reach %d km/h", "base": 170, "step": 10, "per_run": true},
	{"stat": "flow_drives", "text": "Trigger Flow Drive %d times in one run", "base": 1, "step": 1, "per_run": true},
	{"stat": "overtakes_total", "text": "Overtake %d cars in total", "base": 60, "step": 40, "per_run": false},
	{"stat": "twoway_m", "text": "Drive %d m against traffic in Two-Way", "base": 500, "step": 500, "per_run": false},
	{"stat": "checkpoints", "text": "Reach %d checkpoints in one Time Trial", "base": 3, "step": 1, "per_run": true},
	{"stat": "best_streak", "text": "Chain a x%d near-miss streak", "base": 4, "step": 1, "per_run": true},
]


static func make_mission(seq: int) -> Dictionary:
	var tpl: Dictionary = MISSIONS[(seq * 3) % MISSIONS.size()]
	var tier := seq / MISSIONS.size()
	var target := int(tpl["base"]) + int(tpl["step"]) * tier
	var text := String(tpl["text"]) % target
	if target == 1:
		text = text.replace(" 1 times", " once")
	return {"id": seq, "stat": tpl["stat"], "text": text, "target": target,
			"progress": 0, "per_run": tpl["per_run"], "reward": 1500 + 600 * tier + 250 * (seq % 3)}


## Applies one run's stats to the active missions. Lifetime missions add up,
## per-run missions keep their best. Returns the missions completed now.
static func apply_run(missions: Array, run: Dictionary) -> Array:
	var done := []
	for m in missions:
		if int(m["progress"]) >= int(m["target"]):
			continue
		var v := int(run.get(m["stat"], 0))
		if m["per_run"]:
			m["progress"] = maxi(int(m["progress"]), v)
		else:
			m["progress"] = int(m["progress"]) + v
		if int(m["progress"]) >= int(m["target"]):
			m["progress"] = int(m["target"])
			done.append(m)
	return done
