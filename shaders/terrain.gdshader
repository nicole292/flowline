shader_type spatial;
// Roadside grass in world space with a gravel verge next to the barriers.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 grass_a : source_color = vec3(0.20, 0.28, 0.10);
uniform vec3 grass_b : source_color = vec3(0.32, 0.36, 0.16);
uniform vec3 verge : source_color = vec3(0.34, 0.32, 0.28);
uniform float verge_from = 9.0;
uniform float verge_to = 11.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.0125).r;
	float n2 = texture(noise_tex, p * 0.13).r;
	float n3 = texture(noise_tex, p * 1.1).r;
	vec3 g = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
	g *= 0.8 + 0.25 * n2 + 0.12 * n3;
	float v = 1.0 - smoothstep(verge_from, verge_to + n2 * 1.5, abs(p.x));
	vec3 col = mix(g, verge * (0.85 + 0.3 * n3), v);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
