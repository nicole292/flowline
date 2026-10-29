shader_type canvas_item;
// Screen-edge speed streaks (only at high speed, never over the road ahead)
// and the warm Flow Drive edge glow.

uniform float speed = 0.0;     // 0..1 intensity
uniform float flow = 0.0;      // 0..1 Flow Drive intensity
uniform float time_s = 0.0;
uniform vec3 flow_color : source_color = vec3(1.0, 0.45, 0.15);

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5, 0.42);
	float r = length(uv * vec2(1.5, 1.0));
	float ang = atan(uv.y, uv.x);
	float cell = floor(ang * 70.0);
	float pick = hash(cell);
	float travel = fract(r * 1.6 - time_s * (2.2 + pick * 1.5) - pick * 7.0);
	float streak = step(0.9, pick) * smoothstep(0.0, 0.25, travel) * (1.0 - smoothstep(0.55, 0.8, travel));
	float edge = smoothstep(0.42, 0.8, r);
	float a = streak * edge * speed * 0.22;
	float glow = smoothstep(0.5, 1.0, r) * flow * (0.5 + 0.08 * sin(time_s * 5.0));
	vec3 col = mix(vec3(1.0), flow_color, clamp(glow * 3.0, 0.0, 1.0));
	COLOR = vec4(col, clamp(a + glow * 0.55, 0.0, 1.0));
}
