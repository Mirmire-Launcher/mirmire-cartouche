// SPDX-License-Identifier: GPL-3.0-or-later
// Mirmire Cartouche's home: clear glass, as the heart's ball. Nearly clear where it faces the camera, bright towards its
// edges (Fresnel), with a sharp highlight from the lights: the shape reads as glass without hiding what is inside.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.88, 0.94, 1.0);
uniform float clear_alpha : hint_range(0.0, 1.0) = 0.03;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.65;
uniform float edge_power : hint_range(0.5, 8.0) = 2.6;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - facing, edge_power);
	ALBEDO = tint;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	EMISSION = tint * edge * 0.35;
	ALPHA = mix(clear_alpha, edge_alpha, edge);
}
