shader_type spatial;
// Photo-scanned asphalt (ambientCG Asphalt031, CC0) + procedural markings in
// world space, so the road mesh can follow the player while everything on it
// stays put. Every texture period divides the 1200 m rebase distance.

uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float tile = 3.0;
uniform float lane_width = 3.6;
uniform int lanes = 4;
uniform float center_x = 0.0;
uniform float dash_period = 12.0;
uniform float dash_length = 3.0;
uniform float darkness = 0.36;
uniform float wetness = 0.0;
uniform bool two_way = false;        // solid double centre line between lanes 2 and 3
uniform float lamps = 0.0;           // night: warm light pools under the median lamps
uniform float lamp_x = -6.25;
uniform float lamp_x2 = -11.75;
uniform float lamp_period = 60.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float d, float half_w) {
	float fw = max(fwidth(d), 0.0005);
	return 1.0 - smoothstep(half_w - fw, half_w + fw, abs(d));
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv = p / tile;
	vec3 a1 = texture(albedo_tex, uv).rgb;
	vec3 a2 = texture(albedo_tex, uv * 0.37 + vec2(0.31, 0.17)).rgb;
	float big = texture(noise_tex, p * 0.02).r;
	float mid = texture(noise_tex, p * 0.15).r;
	vec3 asphalt = mix(a1, a2, 0.4) * darkness * (0.78 + 0.38 * big) * (0.92 + 0.12 * mid);
	asphalt *= vec3(0.98, 0.99, 1.02);

	float lx_road = p.x - center_x;
	float half_road = lane_width * float(lanes) * 0.5;
	// Repair patches: darker, smoother rectangles of newer asphalt.
	float patch_n = texture(noise_tex, vec2(floor(lx_road / lane_width) * 0.37, floor(p.y / 20.0) * 0.25)).r;
	float patch = step(0.72, patch_n) * step(abs(lx_road), half_road);
	asphalt = mix(asphalt, asphalt * 0.72, patch);
	// Polished, darker tyre tracks and an oily centre stripe in each lane.
	float lx = mod(lx_road + half_road, lane_width) - lane_width * 0.5;
	float in_road = step(abs(lx_road), half_road);
	float track = smoothstep(0.45, 0.0, abs(abs(lx) - 0.86)) * in_road;
	float oil = smoothstep(0.35, 0.0, abs(lx)) * in_road;
	asphalt *= 1.0 - 0.16 * track - 0.08 * oil * mid;
	float rough = texture(rough_tex, uv).r * 0.25 + 0.68 - 0.12 * track - 0.06 * patch;

	float paint = 0.0;
	paint = max(paint, line_mask(lx_road + half_road - 0.25, 0.09));
	paint = max(paint, line_mask(lx_road - half_road + 0.25, 0.09));
	float zz = mod(p.y, dash_period);
	float fwz = max(fwidth(p.y), 0.001);
	float dash = smoothstep(0.0, fwz, zz) * (1.0 - smoothstep(dash_length - fwz, dash_length + fwz, zz));
	for (int k = 1; k < lanes; k++) {
		float x0 = -half_road + float(k) * lane_width;
		if (two_way && k == lanes / 2) {
			paint = max(paint, line_mask(lx_road - x0 - 0.17, 0.065));
			paint = max(paint, line_mask(lx_road - x0 + 0.17, 0.065));
		} else {
			paint = max(paint, line_mask(lx_road - x0, 0.075) * dash);
		}
	}
	// Worn paint: aggregate shows through.
	paint *= smoothstep(0.15, 0.55, a1.r * 0.8 + mid * 0.5);

	vec3 col = mix(asphalt, vec3(0.78, 0.78, 0.75), paint);
	float shoulder = smoothstep(half_road - 0.1, half_road + 0.05, abs(lx_road));
	col *= mix(1.0, 1.08, shoulder);
	ALBEDO = col;
	if (lamps > 0.0) {
		float dz = mod(p.y + lamp_period * 0.5, lamp_period) - lamp_period * 0.5;
		float pool = exp(-pow((p.x - lamp_x) / 4.2, 2.0) - pow(dz / 11.0, 2.0));
		pool += exp(-pow((p.x - lamp_x2) / 4.2, 2.0) - pow(dz / 11.0, 2.0));
		EMISSION = col * pool * lamps * vec3(1.0, 0.72, 0.42) * 4.5;
	}
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.3, paint);
	ROUGHNESS = mix(mix(rough, 0.55, paint), 0.1, wetness);
	SPECULAR = 0.45;
}
