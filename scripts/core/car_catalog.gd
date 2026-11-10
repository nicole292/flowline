class_name CarCatalog
extends RefCounted
## Static data for player cars and traffic vehicles. Entries with
## "kind": "bike" are motorcycles: narrow, quick to turn and to accelerate.
## Lengths/widths match tools/blender/build_cars.py. Speeds in m/s.

const PLAYER_CARS := [
	{"id": "vanta", "name": "Vanta GT", "class": "Sport coupe", "price": 0,
	 "paint": Color(0.05, 0.17, 0.50), "length": 4.48, "width": 1.92,
	 "blurb": "Balanced and forgiving. The car that starts it all.",
	 "stats": {"top_speed": 56.0, "accel": 7.6, "brake_decel": 13.0,
			   "lat_max": 8.0, "steer_response": 10.4, "lat_grip": 30.0}},
	{"id": "kestrel", "name": "Kestrel RS", "class": "Hot hatch", "price": 12000,
	 "paint": Color(0.80, 0.10, 0.07), "length": 4.06, "width": 1.82,
	 "blurb": "Small, light and twitchy. Darts between lanes.",
	 "stats": {"top_speed": 58.0, "accel": 8.4, "brake_decel": 14.0,
			   "lat_max": 9.0, "steer_response": 12.4, "lat_grip": 33.0}},
	{"id": "meridian", "name": "Meridian S", "class": "Super saloon", "price": 26000,
	 "paint": Color(0.09, 0.09, 0.10), "length": 4.86, "width": 1.89,
	 "blurb": "Four doors, quad pipes and a lot more power than it shows.",
	 "stats": {"top_speed": 64.0, "accel": 8.8, "brake_decel": 14.0,
			   "lat_max": 8.0, "steer_response": 10.4, "lat_grip": 31.0}},
	{"id": "brute", "name": "Brute 8", "class": "Muscle", "price": 45000,
	 "paint": Color(0.88, 0.50, 0.04), "length": 4.78, "width": 1.96,
	 "blurb": "Huge straight-line speed. Heavy in the lane changes.",
	 "stats": {"top_speed": 70.0, "accel": 10.0, "brake_decel": 13.0,
			   "lat_max": 7.8, "steer_response": 9.6, "lat_grip": 29.0}},
	{"id": "halcyon", "name": "Halcyon GT", "class": "Grand tourer", "price": 80000,
	 "paint": Color(0.05, 0.22, 0.17), "length": 4.76, "width": 1.97,
	 "blurb": "A long-nosed fastback built for flat-out highway runs.",
	 "stats": {"top_speed": 74.0, "accel": 10.5, "brake_decel": 15.0,
			   "lat_max": 8.5, "steer_response": 11.2, "lat_grip": 33.0}},
	{"id": "solstice", "name": "Solstice", "class": "Supercar", "price": 140000,
	 "paint": Color(0.82, 0.82, 0.84), "length": 4.56, "width": 2.02,
	 "blurb": "Mid-engine, low and sharp. Changes lanes like a thought.",
	 "stats": {"top_speed": 80.0, "accel": 11.5, "brake_decel": 16.5,
			   "lat_max": 9.2, "steer_response": 12.8, "lat_grip": 36.0}},
	{"id": "vortex", "name": "Vortex", "class": "Hypercar", "price": 250000,
	 "paint": Color(0.95, 0.38, 0.05), "length": 4.72, "width": 2.08,
	 "blurb": "The wing is not for show. The fastest thing on the road.",
	 "stats": {"top_speed": 88.0, "accel": 13.0, "brake_decel": 18.0,
			   "lat_max": 9.7, "steer_response": 13.6, "lat_grip": 39.0}},
	# ---- motorcycles: after all the cars in the garage
	{"id": "nomad", "name": "Nomad 900", "class": "Roadster bike", "price": 18000, "kind": "bike",
	 "paint": Color(0.20, 0.22, 0.20), "length": 2.0, "width": 0.8,
	 "blurb": "Upright and light. Slips through gaps no car can.",
	 "stats": {"top_speed": 61.0, "accel": 9.4, "brake_decel": 13.5,
			   "lat_max": 9.7, "steer_response": 14.0, "lat_grip": 34.0}},
	{"id": "raptor", "name": "Raptor RR", "class": "Sport bike", "price": 110000, "kind": "bike",
	 "paint": Color(0.10, 0.45, 0.85), "length": 2.05, "width": 0.8,
	 "blurb": "Full fairing, tucked in, and a lot of revs. Lane splitting at speed.",
	 "stats": {"top_speed": 78.0, "accel": 12.0, "brake_decel": 15.5,
			   "lat_max": 10.1, "steer_response": 14.4, "lat_grip": 37.0}},
]

## Garage paint palette: [name, colour].
const PAINTS := [
	["Pacific Blue", Color(0.05, 0.17, 0.50)], ["Rosso", Color(0.70, 0.04, 0.04)],
	["Arctic White", Color(0.88, 0.89, 0.90)], ["Obsidian", Color(0.035, 0.035, 0.04)],
	["Liquid Silver", Color(0.62, 0.63, 0.66)], ["Nardo Grey", Color(0.38, 0.39, 0.40)],
	["British Racing", Color(0.04, 0.20, 0.12)], ["Signal Orange", Color(0.95, 0.38, 0.05)],
	["Solar Yellow", Color(0.95, 0.72, 0.05)], ["Lime Rush", Color(0.45, 0.80, 0.08)],
	["Ultraviolet", Color(0.28, 0.10, 0.55)], ["Midnight Purple", Color(0.12, 0.05, 0.20)],
	["Teal Pearl", Color(0.03, 0.42, 0.45)], ["Copper", Color(0.55, 0.25, 0.12)],
]

const RIMS := [
	["Silver", Color(0.66, 0.67, 0.70), 1.0, 0.28], ["Gloss Black", Color(0.03, 0.03, 0.035), 0.4, 0.12],
	["Gunmetal", Color(0.22, 0.23, 0.25), 1.0, 0.32], ["Bronze", Color(0.55, 0.37, 0.17), 1.0, 0.3],
	["White", Color(0.9, 0.9, 0.9), 0.2, 0.3],
]

const TRAFFIC := [
	{"id": "t_sedan", "length": 4.65, "width": 1.80, "weight": 3.0, "speed_mul": 1.0},
	{"id": "t_hatch", "length": 3.95, "width": 1.74, "weight": 2.5, "speed_mul": 0.98},
	{"id": "t_suv", "length": 4.75, "width": 1.93, "weight": 2.2, "speed_mul": 1.0},
	{"id": "t_van", "length": 5.25, "width": 2.00, "weight": 1.2, "speed_mul": 0.93},
	{"id": "t_pickup", "length": 5.35, "width": 1.96, "weight": 1.1, "speed_mul": 0.97},
	{"id": "t_truck", "length": 7.60, "width": 2.30, "weight": 0.9, "speed_mul": 0.84},
	{"id": "t_bus", "length": 12.0, "width": 2.50, "weight": 0.35, "speed_mul": 0.82},
	{"id": "t_moto", "length": 2.0, "width": 0.80, "weight": 0.6, "speed_mul": 1.04},
	# Only ever parked at crash sites (weight 0: never picked for traffic).
	{"id": "t_police", "length": 4.65, "width": 1.80, "weight": 0.0, "speed_mul": 1.0},
	{"id": "meridian", "length": 4.86, "width": 1.89, "weight": 0.4, "speed_mul": 1.05},
	{"id": "kestrel", "length": 4.06, "width": 1.82, "weight": 0.3, "speed_mul": 1.05},
]

## Traffic paint: bright, cheerful colours (playtest: grey cars all looked
## the same and vanished in the haze), with a few whites and blacks.
const TRAFFIC_PAINTS := [
	[Color(1.0, 0.76, 0.04), 1.2],   # racing yellow
	[Color(1.0, 0.40, 0.04), 1.2],   # orange
	[Color(0.86, 0.06, 0.05), 1.2],  # red
	[Color(0.95, 0.16, 0.52), 0.9],  # hot pink
	[Color(0.48, 0.16, 0.80), 0.9],  # purple
	[Color(0.06, 0.36, 0.98), 1.2],  # electric blue
	[Color(0.30, 0.66, 0.98), 0.9],  # sky blue
	[Color(0.0, 0.68, 0.62), 0.9],   # teal
	[Color(0.42, 0.86, 0.12), 1.0],  # lime
	[Color(0.55, 0.92, 0.72), 0.6],  # mint
	[Color(0.92, 0.92, 0.90), 1.0],  # white
	[Color(0.05, 0.05, 0.055), 0.5], # black
]


static func has_player_car(id: String) -> bool:
	for c in PLAYER_CARS:
		if c["id"] == id:
			return true
	return false


static func player_car(id: String) -> Dictionary:
	for c in PLAYER_CARS:
		if c["id"] == id:
			return c
	return PLAYER_CARS[0]


static func is_bike(id: String) -> bool:
	return player_car(id).get("kind", "car") == "bike"


static func index_of(id: String) -> int:
	for i in PLAYER_CARS.size():
		if PLAYER_CARS[i]["id"] == id:
			return i
	return 0


static func paint_for(id: String, index: int) -> Color:
	if index >= 0 and index < PAINTS.size():
		return PAINTS[index][1]
	return player_car(id)["paint"]


static func model_path(id: String) -> String:
	return "res://assets/vehicles/%s.glb" % id


## A traffic colour, re-picked if it is one of `avoid` (the last few
## used), so neighbouring cars never share a colour.
static func random_paint(rng: RandomNumberGenerator, avoid: Array = []) -> Color:
	var c := _weighted_paint(rng)
	for i in 8:
		if not avoid.has(c):
			break
		c = _weighted_paint(rng)
	return c


static func _weighted_paint(rng: RandomNumberGenerator) -> Color:
	var total := 0.0
	for p in TRAFFIC_PAINTS:
		total += float(p[1])
	var r := rng.randf() * total
	for p in TRAFFIC_PAINTS:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return TRAFFIC_PAINTS[0][0]
