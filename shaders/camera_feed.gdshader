shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Live device camera feed as a full-screen AR backdrop. Android feeds are
// usually two-plane YCbCr and often need rotation/flip to display upright,
// so those are adjustable at runtime.
uniform sampler2D plane0 : source_color, hint_default_black;  // RGBA or Y
uniform sampler2D plane1 : source_color, hint_default_black;  // CbCr (YCbCr feeds)
uniform bool ycbcr = true;
uniform int rotation = 0;      // 0,1,2,3 => 0/90/180/270 degrees
uniform bool flip_h = false;
uniform bool flip_v = false;

vec2 orient_uv(vec2 uv) {
	vec2 r = uv;
	if (rotation == 1) {
		r = vec2(uv.y, 1.0 - uv.x);
	} else if (rotation == 2) {
		r = vec2(1.0 - uv.x, 1.0 - uv.y);
	} else if (rotation == 3) {
		r = vec2(1.0 - uv.y, uv.x);
	}
	if (flip_h) {
		r.x = 1.0 - r.x;
	}
	if (flip_v) {
		r.y = 1.0 - r.y;
	}
	return r;
}

void fragment() {
	vec2 uv = orient_uv(UV);
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
