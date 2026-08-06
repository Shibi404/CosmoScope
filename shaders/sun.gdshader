shader_type spatial;
render_mode unshaded;

#include "res://shaders/noise.gdshaderinc"

// Animated, self-lit surface: two noise layers drift in opposite directions
// to fake churning plasma, coloured between a cool and a hot tone.
uniform vec3 hot : source_color = vec3(1.0, 0.9, 0.45);
uniform vec3 cool : source_color = vec3(0.9, 0.32, 0.06);
uniform float flow_speed = 0.06;
uniform float noise_scale = 3.0;
uniform float emission_strength = 2.2;

// Optional photographic sun map, modulated by the animated shimmer.
uniform sampler2D sun_texture : source_color, hint_default_white;
uniform bool use_texture = false;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = normalize(v_local) * noise_scale;
	float n1 = fbm(p + vec3(TIME * flow_speed));
	float n2 = fbm(p * 2.0 - vec3(TIME * flow_speed * 0.5));
	float m = clamp(n1 * 0.6 + n2 * 0.6, 0.0, 1.0);

	vec3 col;
	if (use_texture) {
		// Keep the churn by brightening/darkening the real surface over time.
		col = texture(sun_texture, UV).rgb * (0.75 + 0.5 * m);
	} else {
		col = mix(cool, hot, m);
	}
	ALBEDO = col;
	EMISSION = col * emission_strength;
}
