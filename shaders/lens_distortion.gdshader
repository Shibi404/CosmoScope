shader_type canvas_item;

// Barrel distortion for Google Cardboard-style lenses. Each eye's view is
// pre-warped so the lens's pincushion magnification cancels out. Applied to a
// TextureRect whose texture is that eye's rendered viewport.
uniform float k1 = 0.22;
uniform float k2 = 0.24;
uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0;   // -1..1, centred on the lens
	float r2 = dot(c, c);
	vec2 d = c * (1.0 + k1 * r2 + k2 * r2 * r2);
	vec2 uv = d * 0.5 + vec2(0.5);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = fill_color;
	} else {
		COLOR = texture(TEXTURE, uv);
	}
}
