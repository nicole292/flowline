// Curved highway: the world is simulated straight and bent here. `bend` is
// RoadCurve.bend_table(): the road's sideways offset every BEND_STEP metres
// from BEND_D0 metres ahead of the camera (negative = behind). Keep these
// constants equal to RoadCurve.TABLE_*. Meshes using this must have no
// rotation or scale (only a translation), so a world-x shift is a local one.
uniform float bend[44];
uniform float bend_cam_z = 0.0;
const float BEND_D0 = -160.0;
const float BEND_STEP = 20.0;

float bend_at(float d) {
	float f = clamp((d - BEND_D0) / BEND_STEP, 0.0, 42.999);
	int i = int(f);
	return mix(bend[i], bend[i + 1], f - float(i));
}

// x: sideways shift for world z, y: slope (sideways metres per metre ahead).
vec2 bend_world(float wz) {
	float d = bend_cam_z - wz;
	return vec2(bend_at(d), (bend_at(d + 2.0) - bend_at(d - 2.0)) * 0.25);
}

// Bends a model-space vertex and its normal (the surface turns with the road).
void bend_vertex(float wz, inout vec3 v, inout vec3 n) {
	vec2 b = bend_world(wz);
	v.x += b.x;
	n = normalize(vec3(n.x, n.y, n.z + b.y * n.x));
}
