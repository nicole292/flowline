class_name ScoreModel
extends RefCounted
## Scoring, near-miss streaks and the Flow meter.
##
## Flow: near misses fill the meter. When full, Flow Drive doubles every
## point until the meter drains or the player bumps into something.
##
## Damage: every crash dents the car (harder hits more). At 100% the car is
## wrecked and the run is over. Starting a Flow Drive repairs some of it.

const NEAR_GAP := 1.25         ## metres of side clearance that still counts
const TIER_GAPS := [0.35, 0.75] ## below these: INSANE, CLOSE; else NEAR
const TIER_NAMES := ["NEAR MISS", "CLOSE CALL", "INSANE"]
const TIER_POINTS := [100, 180, 300]
const TIER_FLOW := [0.20, 0.28, 0.38]
const STREAK_WINDOW := 3.5
const FLOW_GRACE := 4.0        ## seconds after a near miss before decay
const FLOW_DECAY := 0.03       ## per second while building
const FLOW_DRAIN := 0.085      ## per second during Flow Drive
const OVERTAKE_POINTS := 20
const DIST_POINTS := 0.5       ## points per metre before the speed bonus
const FLOW_REPAIR := 0.25      ## damage repaired each time Flow Drive starts

var score := 0.0
var distance := 0.0
var time := 0.0
var near_misses := 0
var overtakes := 0
var best_streak := 0
var top_speed := 0.0
var flow := 0.0
var flow_active := false
var flow_activations := 0
var streak := 0
var streak_timer := 0.0
var _grace := 0.0
## Extra multiplier from where you drive (x2 in the oncoming lanes in Two-Way).
var lane_bonus := 1.0
var oncoming_distance := 0.0
var damage := 0.0              ## 0..1, 1 = wrecked


func multiplier() -> float:
	return (2.0 if flow_active else 1.0) * lane_bonus


## Speed bonus for distance points: 1x at 80 km/h, 2x at 160 km/h, 3x at 240.
static func speed_factor(speed_ms: float) -> float:
	return 1.0 + maxf(0.0, speed_ms * 3.6 - 80.0) / 80.0


func tick(dt: float, speed_ms: float) -> void:
	time += dt
	var d := speed_ms * dt
	distance += d
	top_speed = maxf(top_speed, speed_ms)
	score += d * DIST_POINTS * speed_factor(speed_ms) * multiplier()
	if lane_bonus > 1.0:
		oncoming_distance += d
	streak_timer = maxf(0.0, streak_timer - dt)
	if streak_timer <= 0.0:
		streak = 0
	_grace = maxf(0.0, _grace - dt)
	if flow_active:
		flow -= FLOW_DRAIN * dt
		if flow <= 0.0:
			flow = 0.0
			flow_active = false
	elif _grace <= 0.0:
		flow = maxf(0.0, flow - FLOW_DECAY * dt)


static func tier_for_gap(gap: float) -> int:
	if gap < 0.0 or gap > NEAR_GAP:
		return -1
	if gap < TIER_GAPS[0]:
		return 2
	if gap < TIER_GAPS[1]:
		return 1
	return 0


## Called when the player passes a car. Returns {} for a plain overtake, or
## {tier, name, points, streak, flow_started} for a near miss.
func on_pass(gap: float, speed_ms: float) -> Dictionary:
	overtakes += 1
	score += OVERTAKE_POINTS * multiplier()
	var tier := tier_for_gap(gap)
	if tier < 0:
		return {}
	near_misses += 1
	streak = streak + 1 if streak_timer > 0.0 else 1
	streak_timer = STREAK_WINDOW
	best_streak = maxi(best_streak, streak)
	var speed_mul := clampf(speed_ms * 3.6 / 120.0, 0.6, 2.5)
	var streak_mul := minf(1.0 + 0.25 * (streak - 1), 3.0)
	var pts := int(round(TIER_POINTS[tier] * speed_mul * streak_mul * multiplier()))
	score += pts
	_grace = FLOW_GRACE
	var started := false
	flow = minf(1.0, flow + TIER_FLOW[tier])
	if not flow_active and flow >= 1.0:
		flow_active = true
		flow_activations += 1
		started = true
	var repaired := 0.0
	if started:
		repaired = minf(damage, FLOW_REPAIR)
		damage -= repaired
	return {"tier": tier, "name": TIER_NAMES[tier], "points": pts,
			"streak": streak, "flow_started": started, "repaired": repaired}


var crashes := 0


## Damage from one crash at this closing speed (m/s): a light tap is about
## a quarter of the car, a head-on in Two-Way most of it.
static func crash_damage(impact_speed: float) -> float:
	return clampf(0.2 + 0.01 * absf(impact_speed), 0.25, 0.65)


## True if a crash at this closing speed would wreck the car.
func would_wreck(impact_speed: float) -> bool:
	return damage + crash_damage(impact_speed) >= 0.999


## A crash you keep driving through: costs points (more at higher impact
## speed, never more than you have), damages the car, ends Flow and the streak.
func on_crash(impact_speed: float) -> int:
	crashes += 1
	damage = minf(1.0, damage + crash_damage(impact_speed))
	var penalty := mini(int(score), int(400.0 + 12.0 * absf(impact_speed)))
	score -= penalty
	on_bump()
	return penalty


## Scraping a barrier or another light contact ends Flow and the streak.
func on_bump() -> void:
	flow = 0.0
	flow_active = false
	streak = 0
	streak_timer = 0.0


## Currency earned at the end of a run.
func cash_earned() -> int:
	return int(score / 40.0) + near_misses * 2
