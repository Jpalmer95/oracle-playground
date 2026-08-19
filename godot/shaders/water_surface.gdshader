shader_type spatial;
// HermesForge water surface — keep in lockstep with water_body.gd
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.10, 0.35, 0.40, 0.55);
uniform vec4 deep_color : source_color = vec4(0.03, 0.16, 0.28, 0.90);
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_height : hint_range(0.0, 2.0) = 0.25;
uniform float wave_scale : hint_range(0.01, 10.0) = 0.6;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform int wave_count : hint_range(1, 4) = 3;

float wave(vec2 pos, vec2 dir, float freq, float t) {
	return sin(dot(pos, dir) * freq + t);
}

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz * wave_scale;
	float h = 0.0;
	h += wave(p, normalize(vec2(1.0, 0.3)), 1.0, t) * 0.5;
	if (wave_count >= 2) { h += wave(p, normalize(vec2(-0.7, 1.0)), 1.7, t * 1.3) * 0.3; }
	if (wave_count >= 3) { h += wave(p, normalize(vec2(0.4, -1.0)), 2.6, t * 1.7) * 0.2; }
	if (wave_count >= 4) { h += wave(p, normalize(vec2(-1.0, -0.5)), 3.9, t * 2.1) * 0.1; }
	VERTEX.y += h * wave_height;
	NORMAL = normalize(vec3(-h * 0.5, 1.0, -h * 0.5));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 view = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), fresnel_power);
	vec4 col = mix(deep_color, shallow_color, fres);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
}
