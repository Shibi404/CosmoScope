## Data table for the Sun and planets.
##
## Values are VISUAL (tuned for readability), not true-to-scale — real
## relative sizes/distances are far too extreme to view comfortably.
##   radius      : sphere radius in metres
##   distance    : orbit radius from the Sun in metres
##   orbit_speed : degrees/second travelled around the Sun
##   spin_speed  : degrees/second of axial rotation
##   tilt        : axial tilt in degrees (roughly real; Uranus is famously ~98)
##   color       : primary surface tone (shader color_a)
##   color2      : secondary surface tone (shader color_b)
##   banded      : true for gas/ice giants -> latitude stripes
##   fact        : short blurb shown on selection
##   diameter_km : real equatorial diameter
##   sun_dist_mkm: real mean distance from the Sun, millions of km
##   year        : real orbital period (human-readable)
##   day         : real rotation period (human-readable)
##   moons       : real number of known moons
##   gravity_g   : real surface gravity relative to Earth

const SUN := {
	"name": "Sun",
	"radius": 2.0,
	"color": Color(1.0, 0.75, 0.2),
	"fact": "The star at the centre of the Solar System.",
}

const PLANETS := [
	{"name": "Mercury", "radius": 0.15, "distance": 4.0, "orbit_speed": 24.0, "spin_speed": 20.0,
		"tilt": 0.0, "banded": false,
		"color": Color(0.55, 0.50, 0.48), "color2": Color(0.32, 0.29, 0.27),
		"fact": "Smallest planet and closest to the Sun.",
		"diameter_km": 4879, "sun_dist_mkm": 57.9, "year": "88 days", "day": "1408 h",
		"moons": 0, "gravity_g": 0.38},
	{"name": "Venus", "radius": 0.28, "distance": 6.0, "orbit_speed": 18.0, "spin_speed": 15.0,
		"tilt": 3.0, "banded": false,
		"color": Color(0.85, 0.70, 0.45), "color2": Color(0.62, 0.48, 0.28),
		"fact": "Hottest planet, wrapped in a thick CO2 atmosphere.",
		"diameter_km": 12104, "sun_dist_mkm": 108.2, "year": "225 days", "day": "5832 h",
		"moons": 0, "gravity_g": 0.90},
	{"name": "Earth", "radius": 0.30, "distance": 8.0, "orbit_speed": 15.0, "spin_speed": 40.0,
		"tilt": 23.4, "banded": false,
		"color": Color(0.20, 0.55, 0.30), "color2": Color(0.12, 0.32, 0.70),
		"fact": "The only known planet with life.",
		"diameter_km": 12742, "sun_dist_mkm": 149.6, "year": "365 days", "day": "24 h",
		"moons": 1, "gravity_g": 1.00},
	{"name": "Mars", "radius": 0.20, "distance": 10.0, "orbit_speed": 12.0, "spin_speed": 38.0,
		"tilt": 25.0, "banded": false,
		"color": Color(0.80, 0.35, 0.20), "color2": Color(0.48, 0.20, 0.12),
		"fact": "The 'Red Planet', home to the tallest volcano.",
		"diameter_km": 6779, "sun_dist_mkm": 227.9, "year": "687 days", "day": "24.6 h",
		"moons": 2, "gravity_g": 0.38},
	{"name": "Jupiter", "radius": 0.90, "distance": 14.0, "orbit_speed": 8.0, "spin_speed": 60.0,
		"tilt": 3.0, "banded": true,
		"color": Color(0.85, 0.72, 0.55), "color2": Color(0.60, 0.45, 0.35),
		"fact": "Largest planet; a gas giant with a Great Red Spot.",
		"diameter_km": 139820, "sun_dist_mkm": 778.5, "year": "11.9 years", "day": "9.9 h",
		"moons": 95, "gravity_g": 2.53},
	{"name": "Saturn", "radius": 0.80, "distance": 18.0, "orbit_speed": 6.0, "spin_speed": 55.0,
		"tilt": 27.0, "banded": true,
		"color": Color(0.88, 0.82, 0.62), "color2": Color(0.72, 0.64, 0.45),
		"fact": "Famous for its spectacular ring system.",
		"diameter_km": 116460, "sun_dist_mkm": 1434.0, "year": "29.5 years", "day": "10.7 h",
		"moons": 146, "gravity_g": 1.07},
	{"name": "Uranus", "radius": 0.50, "distance": 22.0, "orbit_speed": 4.0, "spin_speed": 45.0,
		"tilt": 98.0, "banded": true,
		"color": Color(0.60, 0.85, 0.85), "color2": Color(0.42, 0.70, 0.76),
		"fact": "An ice giant that rotates on its side.",
		"diameter_km": 50724, "sun_dist_mkm": 2871.0, "year": "84 years", "day": "17.2 h",
		"moons": 28, "gravity_g": 0.89},
	{"name": "Neptune", "radius": 0.48, "distance": 26.0, "orbit_speed": 3.0, "spin_speed": 42.0,
		"tilt": 28.0, "banded": true,
		"color": Color(0.30, 0.45, 0.85), "color2": Color(0.16, 0.26, 0.68),
		"fact": "The windiest planet; farthest from the Sun.",
		"diameter_km": 49244, "sun_dist_mkm": 4495.0, "year": "165 years", "day": "16.1 h",
		"moons": 16, "gravity_g": 1.14},
]
