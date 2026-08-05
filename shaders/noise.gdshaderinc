// Shared value-noise / fBm helpers for CosmoScope shaders.
// Included via: #include "res://shaders/noise.gdshaderinc"

float _hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float _vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(_hash(i + vec3(0.0, 0.0, 0.0)), _hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(_hash(i + vec3(0.0, 1.0, 0.0)), _hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(_hash(i + vec3(0.0, 0.0, 1.0)), _hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(_hash(i + vec3(0.0, 1.0, 1.0)), _hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * _vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}
