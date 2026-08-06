shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// A camera-facing additive glow quad placed at the Sun, giving it an extended
// corona so it reads as a radiant star rather than a flat disc.
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.2);
uniform float falloff = 2.5;
uniform float intensity = 1.6;

void vertex() {
	// Billboard: strip rotation from the model-view matrix, keep scale.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mv[0] = vec4(sx, 0.0, 0.0, 0.0);
	mv[1] = vec4(0.0, sy, 0.0, 0.0);
	mv[2] = vec4(0.0, 0.0, 1.0, 0.0);
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;      // -1..1 across the quad
	float r = length(uv);
	float a = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	ALBEDO = color * intensity;
	ALPHA = a;
}
