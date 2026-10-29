class_name CarCatalog
extends RefCounted
## Static data for player cars and traffic vehicles.
## Lengths/widths match tools/blender/build_cars.py.

const PLAYER_CARS := [
	{"id": "kestrel", "name": "Kestrel", "class": "Hot hatch", "price": 0,
	 "paint": Color(0.80, 0.10, 0.07), "length": 4.06, "width": 1.80,
	 "stats": {"top_speed": 52.0, "accel": 7.0, "brake_decel": 12.0,
			   "lat_max": 6.6, "steer_response": 4.6, "lat_grip": 14.0}},
	{"id": "vanta", "name": "Vanta GT", "class": "Sport coupe", "price": 18000,
	 "paint": Color(0.05, 0.17, 0.50), "length": 4.48, "width": 1.90,
	 "stats": {"top_speed": 60.0, "accel": 8.0, "brake_decel": 13.0,
			   "lat_max": 7.0, "steer_response": 5.2, "lat_grip": 15.0}},
	{"id": "meridian", "name": "Meridian", "class": "Executive sedan", "price": 32000,
	 "paint": Color(0.09, 0.09, 0.10), "length": 4.86, "width": 1.87,
	 "stats": {"top_speed": 64.0, "accel": 7.8, "brake_decel": 13.5,
			   "lat_max": 6.8, "steer_response": 4.8, "lat_grip": 14.5}},
	{"id": "brute", "name": "Brute 8", "class": "Muscle", "price": 48000,
	 "paint": Color(0.88, 0.50, 0.04), "length": 4.78, "width": 1.94,
	 "stats": {"top_speed": 68.0, "accel": 9.2, "brake_decel": 12.0,
			   "lat_max": 6.6, "steer_response": 4.4, "lat_grip": 13.0}},
	{"id": "solstice", "name": "Solstice", "class": "Supercar", "price": 120000,
	 "paint": Color(0.82, 0.82, 0.84), "length": 4.56, "width": 2.00,
	 "stats": {"top_speed": 80.0, "accel": 10.5, "brake_decel": 15.0,
			   "lat_max": 7.8, "steer_response": 6.0, "lat_grip": 17.0}},
]

const TRAFFIC := [
	{"id": "t_sedan", "length": 4.65, "width": 1.80, "weight": 3.0, "speed_mul": 1.0},
	{"id": "t_hatch", "length": 3.95, "width": 1.74, "weight": 2.5, "speed_mul": 0.98},
	{"id": "t_suv", "length": 4.75, "width": 1.93, "weight": 2.2, "speed_mul": 1.0},
	{"id": "t_van", "length": 5.25, "width": 2.00, "weight": 1.2, "speed_mul": 0.93},
	{"id": "t_pickup", "length": 5.35, "width": 1.96, "weight": 1.1, "speed_mul": 0.97},
	{"id": "t_truck", "length": 7.60, "width": 2.30, "weight": 0.9, "speed_mul": 0.84},
	{"id": "meridian", "length": 4.86, "width": 1.87, "weight": 0.5, "speed_mul": 1.05},
	{"id": "vanta", "length": 4.48, "width": 1.90, "weight": 0.3, "speed_mul": 1.08},
]

## Realistic traffic paint distribution: mostly greyscale, a few colours.
const TRAFFIC_PAINTS := [
	[Color(0.85, 0.85, 0.84), 5.0], [Color(0.05, 0.05, 0.055), 4.0],
	[Color(0.55, 0.56, 0.58), 4.0], [Color(0.30, 0.31, 0.33), 3.0],
	[Color(0.08, 0.14, 0.32), 1.6], [Color(0.48, 0.05, 0.05), 1.3],
	[Color(0.20, 0.28, 0.24), 0.7], [Color(0.55, 0.45, 0.32), 0.6],
	[Color(0.78, 0.62, 0.10), 0.3], [Color(0.25, 0.42, 0.62), 0.6],
]


static func player_car(id: String) -> Dictionary:
	for c in PLAYER_CARS:
		if c["id"] == id:
			return c
	return PLAYER_CARS[0]


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
