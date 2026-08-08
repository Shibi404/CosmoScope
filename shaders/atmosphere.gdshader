shader_type spatial;
render_mode cull_front, unshaded, blend_add;

uniform vec4 atmosphere_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float intensity : hint_range(0.1, 5.0) = 1.5;

varying vec3 v_normal;
varying vec3 v_view;

void vertex() {
	v_normal = normalize(NORMAL);
	v_view = normalize(-VERTEX);
}

void fragment() {
	float rim = 1.0 - clamp(dot(v_normal, v_view), 0.0, 1.0);
	float alpha = pow(rim, rim_power) * intensity;
	ALBEDO = atmosphere_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
