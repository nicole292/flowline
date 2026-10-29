class_name CarCatalog
extends RefCounted
## Static data for player cars and traffic vehicles.
## Lengths/widths match tools/blender/build_cars.py. Speeds in m/s.

const PLAYER_CARS := [
	{"id": "vanta", "name": "Vanta GT", "class": "Sport coupe", "price": 0,
	 "paint": Color(0.05, 0.17, 0.50), "length": 4.48, "width": 1.92,
	 "blurb": "Balanced and forgiving. The car that starts it all.",
	 "stats": {"top_speed": 56.0, "accel": 7.6, "brake_decel": 13.0,
			   "lat_max": 7.0, "steer_response": 5.2, "lat_grip": 15.0}},
	{"id": "kestrel", "name": "Kestrel RS", "class": "Hot hatch", "price": 12000,
	 "paint": Color(0.80, 0.10, 0.07), "length": 4.06, "width": 1.82,
	 "blurb": "Small, light and twitchy. Darts between lanes.",
	 "stats": {"top_speed": 58.0, "accel": 8.4, "brake_decel": 14.0,
			   "lat_max": 7.8, "steer_response": 6.2, "lat_grip": 16.5}},
	{"id": "meridian", "name": "Meridian S", "class": "Super saloon", "price": 26000,
	 "paint": Color(0.09, 0.09, 0.10), "length": 4.86, "width": 1.89,
	 "blurb": "Four doors, quad pipes and a lot more power than it shows.",
	 "stats": {"top_speed": 64.0, "accel": 8.8, "brake_decel": 14.0,
			   "lat_max": 7.0, "steer_response": 5.2, "lat_grip": 15.5}},
	{"id": "brute", "name": "Brute 8", "class": "Muscle", "price": 45000,
	 "paint": Color(0.88, 0.50, 0.04), "length": 4.78, "width": 1.96,
	 "blurb": "Huge straight-line speed. Heavy in the lane changes.",
	 "stats": {"top_speed": 70.0, "accel": 10.0, "brake_decel": 13.0,
			   "lat_max": 6.8, "steer_response": 4.8, "lat_grip": 14.5}},
	{"id": "halcyon", "name": "Halcyon GT", "class": "Grand tourer", "price": 80000,
	 "paint": Color(0.05, 0.22, 0.17), "length": 4.76, "width": 1.97,
	 "blurb": "A long-nosed fastback built for flat-out highway runs.",
	 "stats": {"top_speed": 74.0, "accel": 10.5, "brake_decel": 15.0,
			   "lat_max": 7.4, "steer_response": 5.6, "lat_grip": 16.5}},
	{"id": "solstice", "name": "Solstice", "class": "Supercar", "price": 140000,
	 "paint": Color(0.82, 0.82, 0.84), "length": 4.56, "width": 2.02,
	 "blurb": "Mid-engine, low and sharp. Changes lanes like a thought.",
	 "stats": {"top_speed": 80.0, "accel": 11.5, "brake_decel": 16.5,
			   "lat_max": 8.0, "steer_response": 6.4, "lat_grip": 18.0}},
	{"id": "vortex", "name": "Vortex", "class": "Hypercar", "price": 250000,
	 "paint": Color(0.95, 0.38, 0.05), "length": 4.72, "width": 2.08,
	 "blurb": "The wing is not for show. The fastest thing on the road.",
	 "stats": {"top_speed": 88.0, "accel": 13.0, "brake_decel": 18.0,
			   "lat_max": 8.4, "steer_response": 6.8, "lat_grip": 19.5}},
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
	{"id": "meridian", "length": 4.86, "width": 1.89, "weight": 0.4, "speed_mul": 1.05},
	{"id": "kestrel", "length": 4.06, "width": 1.82, "weight": 0.3, "speed_mul": 1.05},
]

## Realistic traffic paint distribution: mostly greyscale, a few colours.
const TRAFFIC_PAINTS := [
	[Color(0.85, 0.85, 0.84), 5.0], [Color(0.05, 0.05, 0.055), 4.0],
	[Color(0.55, 0.56, 0.58), 4.0], [Color(0.30, 0.31, 0.33), 3.0],
	[Color(0.08, 0.14, 0.32), 1.6], [Color(0.48, 0.05, 0.05), 1.3],
	[Color(0.20, 0.28, 0.24), 0.7], [Color(0.55, 0.45, 0.32), 0.6],
	[Color(0.78, 0.62, 0.10), 0.3], [Color(0.25, 0.42, 0.62), 0.6],
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


static func random_paint(rng: RandomNumberGenerator) -> Color:
	var total := 0.0
	for p in TRAFFIC_PAINTS:
		total += float(p[1])
	var r := rng.randf() * total
	for p in TRAFFIC_PAINTS:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return TRAFFIC_PAINTS[0][0]
