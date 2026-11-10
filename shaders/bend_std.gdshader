shader_type spatial;
render_mode cull_back;
// A plain material for long things that follow the curved highway (barriers,
// rails, posts, lamp columns, tunnels). See bend.gdshaderinc.
#include "res://shaders/bend.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_tex = false;     // world-space (triplanar) texture, like the concrete
uniform sampler2D albedo_tex : source_color, hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_scale = 0.5;
uniform float roughness_v = 0.8;
uniform float metallic_v = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float dash_period = 0.0;  // > 0: emission only on part of every period along z (light rows)
uniform float dash_fill = 0.5;
// Two world-z ranges (from, to with from > to) where whole instances are
// hidden, e.g. lamp columns inside a tunnel. Decided per instance origin.
uniform vec4 hide = vec4(-1e9, 1e9, -1e9, 1e9);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float oz = MODEL_MATRIX[3].z;
	if ((oz <= hide.x && oz >= hide.y) || (oz <= hide.z && oz >= hide.w)) {
		VERTEX = vec3(0.0);
	} else {
		bend_vertex(wpos.z, VERTEX, NORMAL);
	}
}

void fragment() {
	vec3 col = albedo.rgb;
	if (use_tex) {
		vec3 w = abs(wnrm);
		w /= (w.x + w.y + w.z);
		vec3 p = wpos * tex_scale;
		col *= texture(albedo_tex, p.zy).rgb * w.x + texture(albedo_tex, p.xz).rgb * w.y
				+ texture(albedo_tex, p.xy).rgb * w.z;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	float e = emission_energy;
	if (dash_period > 0.0) {
		e *= step(fract(wpos.z / dash_period), dash_fill);
	}
	EMISSION = emission_color.rgb * e;
}
