shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.2, 1.0);
uniform vec4 mantle_color : source_color = vec4(0.8, 0.3, 0.1, 1.0);
uniform vec4 crust_color : source_color = vec4(0.4, 0.3, 0.25, 1.0);

uniform float core_radius : hint_range(0.0, 1.0) = 0.35;
uniform float mantle_radius : hint_range(0.0, 1.0) = 0.85;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float dist = length(local_pos);
	vec4 final_color = crust_color;

	if (dist < core_radius) {
		float glow = 0.8 + 0.2 * sin(TIME * pulse_speed);
		final_color = core_color * glow;
	} else if (dist < mantle_radius) {
		final_color = mantle_color;
	}

	// Add ring/border highlights between layers
	float core_border = smoothstep(0.015, 0.0, abs(dist - core_radius));
	float mantle_border = smoothstep(0.015, 0.0, abs(dist - mantle_radius));

	final_color += vec4(1.0, 1.0, 1.0, 0.0) * (core_border * 0.6 + mantle_border * 0.4);

	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
}
