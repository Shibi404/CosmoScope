shader_type spatial;

#include "res://shaders/noise.gdshaderinc"

// Two-tone procedural surface. `banded` gives gas giants their latitude
// stripes; otherwise the tones are mixed by fractal noise (terrain/clouds).
uniform vec3 color_a : source_color = vec3(0.4, 0.4, 0.4);
uniform vec3 color_b : source_color = vec3(0.2, 0.2, 0.2);
uniform float noise_scale = 3.0;
uniform bool banded = false;
uniform float band_frequency = 12.0;
uniform float surface_roughness = 0.9;

// Atmospheric rim glow (Fresnel halo at the planet's edge).
uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmosphere_strength = 0.0;
uniform float atmosphere_power = 3.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = normalize(v_local);
	float n;
	if (banded) {
		// Warp the latitude so the stripes ripple instead of being perfectly flat.
		float warp = fbm(p * noise_scale) * 0.35;
		n = clamp(0.5 + 0.5 * sin((p.y + warp) * band_frequency), 0.0, 1.0);
	} else {
		n = clamp(fbm(p * noise_scale), 0.0, 1.0);
	}
	ALBEDO = mix(color_a, color_b, n);
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;

	// Fresnel: ~0 facing the camera, ~1 at the silhouette -> a soft atmosphere halo.
	float fres = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), atmosphere_power);
	EMISSION = atmosphere_color * fres * atmosphere_strength;
}
