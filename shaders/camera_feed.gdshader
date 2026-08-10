shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Draws the live device camera feed as a full-screen backdrop for AR mode.
// Handles both RGB feeds and the YCbCr (two-plane) feeds most phones provide.
uniform sampler2D plane0 : source_color, hint_default_black;  // RGBA or Y
uniform sampler2D plane1 : source_color, hint_default_black;  // CbCr (YCbCr feeds)
uniform bool ycbcr = false;
uniform bool flip_y = true;

void fragment() {
	vec2 uv = UV;
	if (flip_y) {
		uv.y = 1.0 - uv.y;
	}
	vec3 rgb;
	if (ycbcr) {
		float y = texture(plane0, uv).r;
		vec2 c = texture(plane1, uv).rg - vec2(0.5);
		rgb = vec3(
			y + 1.402 * c.y,
			y - 0.344 * c.x - 0.714 * c.y,
			y + 1.772 * c.x);
	} else {
		rgb = texture(plane0, uv).rgb;
	}
	ALBEDO = rgb;
}
