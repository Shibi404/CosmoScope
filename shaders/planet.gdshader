shader_type spatial;

#include "res://shaders/noise.gdshaderinc"

// Two-tone procedural surface. `banded` gives gas giants turbulent latitude
// stripes; otherwise the tones are mixed by fractal noise (terrain/clouds).
uniform vec3 color_a : source_color = vec3(0.4, 0.4, 0.4);
uniform vec3 color_b : source_color = vec3(0.2, 0.2, 0.2);
uniform float noise_scale = 3.0;
uniform bool banded = false;
uniform float band_frequency = 12.0;
uniform float surface_roughness = 0.9;

// Great Red Spot / storm feature (gas giants).
uniform bool has_spot = false;
uniform vec3 spot_color : source_color = vec3(0.72, 0.26, 0.16);
uniform float spot_lon = 0.6;
uniform float spot_lat = -0.3;
uniform float spot_size = 0.5;

// Ocean specular (rocky worlds with water).
uniform bool water = false;

// Atmospheric rim glow (Fresnel halo at the planet's edge).
uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmosphere_strength = 0.0;
uniform float atmosphere_power = 3.0;

varying vec3 v_local;

// Ridged/turbulent fractal for swirling storm bands.
float turbulence(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * abs(_vnoise(p) * 2.0 - 1.0);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = normalize(v_local);

	float n;
	if (banded) {
		// Turbulence warps the stripes into swirling storm belts.
		float warp = turbulence(p * noise_scale) * 0.5;
		n = clamp(0.5 + 0.5 * sin(p.y * band_frequency + warp * 4.0), 0.0, 1.0);
	} else {
		n = clamp(fbm(p * noise_scale), 0.0, 1.0);
	}
	vec3 col = mix(color_a, color_b, n);

	// Great Red Spot: a coloured oval at a fixed latitude/longitude.
	if (has_spot) {
		vec3 sdir = normalize(vec3(
			cos(spot_lon) * cos(spot_lat),
			sin(spot_lat),
			sin(spot_lon) * cos(spot_lat)));
		float d = distance(p, sdir);
		float s = smoothstep(spot_size, spot_size * 0.3, d);
		col = mix(col, spot_color, s);
	}

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = surface_roughness;

	// Oceans (where the blend favours the water tone) catch a specular sheen.
	if (water) {
		float ocean = smoothstep(0.45, 0.62, n);
		ROUGHNESS = mix(surface_roughness, 0.2, ocean);
		METALLIC = mix(0.0, 0.15, ocean);
	}

	// Fresnel: ~0 facing the camera, ~1 at the silhouette -> a soft atmosphere halo.
	float fres = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), atmosphere_power);
	EMISSION = atmosphere_color * fres * atmosphere_strength;
}
