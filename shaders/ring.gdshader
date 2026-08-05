shader_type spatial;
render_mode cull_disabled, blend_mix, specular_disabled;

#include "res://shaders/noise.gdshaderinc"

// Flat planar ring: a quad in the planet's equatorial plane, carved into a
// banded annulus by the distance from centre (in UV space, 0..1 -> -1..1).
uniform vec3 ring_color : source_color = vec3(0.82, 0.76, 0.60);
uniform float inner_radius = 0.55;
uniform float outer_radius = 0.98;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r < inner_radius || r > outer_radius) {
		discard;
	}
	float bands = 0.5 + 0.5 * sin(r * 140.0);
	float grain = fbm(vec3(r * 40.0, 0.0, 0.0));
	float a = (0.35 + 0.65 * bands) * (0.6 + 0.4 * grain);
	// Soften the inner and outer edges.
	a *= smoothstep(inner_radius, inner_radius + 0.03, r);
	a *= smoothstep(outer_radius, outer_radius - 0.03, r);
	ALBEDO = ring_color * (0.7 + 0.3 * bands);
	ALPHA = clamp(a, 0.0, 1.0);
}
