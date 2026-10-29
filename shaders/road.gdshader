shader_type spatial;
// Procedural asphalt + markings in world space, so the road mesh can follow
// the player while markings stay fixed. Rebase distances must be a multiple
// of DASH_PERIOD and of the noise tile period.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float lane_width = 3.6;
uniform int lanes = 4;
uniform float dash_period = 12.0;
uniform float dash_length = 3.0;
uniform float wetness = 0.0;

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
	float n1 = texture(noise_tex, p * 0.045).r;
	float n2 = texture(noise_tex, p * 0.75).r;
	float n3 = texture(noise_tex, p * vec2(0.5, 0.02)).r;
	float half_road = lane_width * float(lanes) * 0.5;

	vec3 asphalt = vec3(0.115, 0.118, 0.124) * (0.78 + 0.32 * n1 + 0.16 * n2);
	// Polished, darker tyre tracks in each lane.
	float lx = mod(p.x + half_road, lane_width) - lane_width * 0.5;
	float track = smoothstep(0.42, 0.0, abs(abs(lx) - 0.86)) * step(abs(p.x), half_road);
	asphalt *= 1.0 - 0.22 * track * (0.55 + 0.45 * n3);
	float rough = 0.82 - 0.16 * track;

	float paint = 0.0;
	paint = max(paint, line_mask(p.x + half_road - 0.25, 0.08));
	paint = max(paint, line_mask(p.x - half_road + 0.25, 0.08));
	float zz = mod(p.y, dash_period);
	float fwz = max(fwidth(p.y), 0.001);
	float dash = smoothstep(0.0, fwz, zz) * (1.0 - smoothstep(dash_length - fwz, dash_length + fwz, zz));
	for (int k = 1; k < lanes; k++) {
		float x0 = -half_road + float(k) * lane_width;
		paint = max(paint, line_mask(p.x - x0, 0.065) * dash);
	}
	paint *= 0.78 + 0.22 * n2;

	vec3 col = mix(asphalt, vec3(0.80, 0.80, 0.78), paint);
	float shoulder = smoothstep(half_road - 0.1, half_road + 0.05, abs(p.x));
	col *= mix(1.0, 1.1, shoulder);
	ALBEDO = col;
	ROUGHNESS = mix(mix(rough, 0.55, paint), 0.12, wetness);
	SPECULAR = 0.4;
}
