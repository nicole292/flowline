shader_type spatial;
// Roadside ground: photo grass (ambientCG Grass004, CC0) with large-scale
// colour variation, and a gravel verge (Gravel023) next to the road.
// All periods divide the 1200 m rebase distance.

#include "res://shaders/bend.gdshaderinc"

uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_nrm : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_nrm : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float verge_in = 9.0;   // |x| where gravel starts (inner edge)
uniform float verge_out = 11.5; // |x| where grass takes over
uniform float verge_center = 0.0;
uniform float verge_in2 = -1.0; // optional second verge (other carriageway)
uniform float verge_out2 = -1.0;
uniform float verge_center2 = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bend_vertex(wpos.z, VERTEX, NORMAL);
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.0125).r;
	float n2 = texture(noise_tex, p * 0.1).r;
	vec3 g = texture(grass_tex, p / 2.0).rgb;
	vec3 g2 = texture(grass_tex, p / 7.5 + vec2(0.4, 0.1)).rgb;
	g = mix(g, g2, 0.35);
	// dry / lush patches, like real verges in late summer
	vec3 dry = g * vec3(1.25, 1.1, 0.7);
	g = mix(g * 0.85, dry, smoothstep(0.45, 0.75, n1)) * (0.85 + 0.25 * n2);
	vec3 gr = texture(gravel_tex, p / 1.5).rgb * 0.5;
	float d1 = abs(p.x - verge_center);
	float v = 1.0 - smoothstep(verge_in, verge_out + n2 * 1.5, d1);
	if (verge_in2 > 0.0) {
		float d2 = abs(p.x - verge_center2);
		v = max(v, 1.0 - smoothstep(verge_in2, verge_out2 + n2 * 1.5, d2));
	}
	ALBEDO = mix(g, gr, v);
	NORMAL_MAP = mix(texture(grass_nrm, p / 2.0).rgb, texture(gravel_nrm, p / 1.5).rgb, v);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
