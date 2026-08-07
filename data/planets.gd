## Data table for the Sun, planets, dwarf planets, comets, spacecraft, and interstellar boundaries.
##
## Values are VISUAL (tuned for readability), not true-to-scale — real
## relative sizes/distances are far too extreme to view comfortably.

const SUN := {
	"name": "Sun",
	"radius": 2.0,
	"color": Color(1.0, 0.75, 0.2),
	"fact": "The star at the centre of the Solar System.",
	"texture": "res://assets/textures/2k_sun.jpg",
}

const PLANETS := [
	{"name": "Mercury", "radius": 0.15, "distance": 4.0, "orbit_speed": 24.0, "spin_speed": 20.0,
		"tilt": 0.0, "banded": false,
		"color": Color(0.55, 0.50, 0.48), "color2": Color(0.32, 0.29, 0.27),
		"fact": "Smallest planet and closest to the Sun.",
		"diameter_km": 4879, "sun_dist_mkm": 57.9, "year": "88 days", "day": "1408 h",
		"moons": 0, "gravity_g": 0.38,
		"atmosphere": Color(0.7, 0.7, 0.7), "atmo": 0.0,
		"texture": "res://assets/textures/2k_mercury.jpg"},
	{"name": "Venus", "radius": 0.28, "distance": 6.0, "orbit_speed": 18.0, "spin_speed": 15.0,
		"tilt": 3.0, "banded": false,
		"color": Color(0.85, 0.70, 0.45), "color2": Color(0.62, 0.48, 0.28),
		"fact": "Hottest planet, wrapped in a thick CO₂ atmosphere.",
		"diameter_km": 12104, "sun_dist_mkm": 108.2, "year": "225 days", "day": "5832 h",
		"moons": 0, "gravity_g": 0.90,
		"atmosphere": Color(0.95, 0.85, 0.55), "atmo": 0.9,
		"texture": "res://assets/textures/2k_venus_atmosphere.jpg"},
	{"name": "Earth", "radius": 0.30, "distance": 8.0, "orbit_speed": 15.0, "spin_speed": 40.0,
		"tilt": 23.4, "banded": false,
		"color": Color(0.20, 0.55, 0.30), "color2": Color(0.12, 0.32, 0.70),
		"fact": "The only known planet with life.",
		"diameter_km": 12742, "sun_dist_mkm": 149.6, "year": "365 days", "day": "24 h",
		"moons": 1, "gravity_g": 1.00,
		"atmosphere": Color(0.35, 0.6, 1.0), "atmo": 0.75, "ocean": true,
		"texture": "res://assets/textures/2k_earth_daymap.jpg",
		"has_clouds": true,
		"moon_data": [
			{"name": "Moon", "radius": 0.06, "orbit_dist": 0.7, "orbit_speed": 90.0,
			 "color": Color(0.7, 0.7, 0.7), "color2": Color(0.5, 0.5, 0.5),
			 "diameter_km": 3474, "fact": "Earth's only natural satellite."},
		]},
	{"name": "Mars", "radius": 0.20, "distance": 10.0, "orbit_speed": 12.0, "spin_speed": 38.0,
		"tilt": 25.0, "banded": false,
		"color": Color(0.80, 0.35, 0.20), "color2": Color(0.48, 0.20, 0.12),
		"fact": "The 'Red Planet', home to the tallest volcano.",
		"diameter_km": 6779, "sun_dist_mkm": 227.9, "year": "687 days", "day": "24.6 h",
		"moons": 2, "gravity_g": 0.38,
		"atmosphere": Color(0.85, 0.55, 0.4), "atmo": 0.25,
		"texture": "res://assets/textures/2k_mars.jpg",
		"moon_data": [
			{"name": "Phobos", "radius": 0.03, "orbit_dist": 0.45, "orbit_speed": 150.0,
			 "color": Color(0.5, 0.45, 0.4), "color2": Color(0.35, 0.30, 0.27),
			 "diameter_km": 22, "fact": "Mars' larger moon, slowly spiralling inward."},
			{"name": "Deimos", "radius": 0.02, "orbit_dist": 0.6, "orbit_speed": 80.0,
			 "color": Color(0.55, 0.50, 0.45), "color2": Color(0.38, 0.34, 0.30),
			 "diameter_km": 12, "fact": "Mars' smaller, outermost moon."},
		]},
	{"name": "Jupiter", "radius": 0.90, "distance": 14.0, "orbit_speed": 8.0, "spin_speed": 60.0,
		"tilt": 3.0, "banded": true,
		"color": Color(0.85, 0.72, 0.55), "color2": Color(0.60, 0.45, 0.35),
		"fact": "Largest planet; a gas giant with a Great Red Spot.",
		"diameter_km": 139820, "sun_dist_mkm": 778.5, "year": "11.9 years", "day": "9.9 h",
		"moons": 95, "gravity_g": 2.53,
		"atmosphere": Color(0.9, 0.78, 0.6), "atmo": 0.5, "spot": true,
		"texture": "res://assets/textures/2k_jupiter.jpg",
		"moon_data": [
			{"name": "Io", "radius": 0.06, "orbit_dist": 1.8, "orbit_speed": 120.0,
			 "color": Color(0.9, 0.8, 0.3), "color2": Color(0.8, 0.5, 0.2),
			 "diameter_km": 3643, "fact": "Most volcanically active body in the Solar System."},
			{"name": "Europa", "radius": 0.055, "orbit_dist": 2.2, "orbit_speed": 90.0,
			 "color": Color(0.75, 0.72, 0.65), "color2": Color(0.6, 0.55, 0.5),
			 "diameter_km": 3122, "fact": "May harbour an ocean beneath its icy surface."},
			{"name": "Ganymede", "radius": 0.07, "orbit_dist": 2.7, "orbit_speed": 60.0,
			 "color": Color(0.6, 0.55, 0.5), "color2": Color(0.45, 0.42, 0.38),
			 "diameter_km": 5268, "fact": "Largest moon in the Solar System."},
			{"name": "Callisto", "radius": 0.065, "orbit_dist": 3.2, "orbit_speed": 40.0,
			 "color": Color(0.4, 0.38, 0.35), "color2": Color(0.3, 0.28, 0.26),
			 "diameter_km": 4821, "fact": "Most heavily cratered body in the Solar System."},
		]},
	{"name": "Saturn", "radius": 0.80, "distance": 18.0, "orbit_speed": 6.0, "spin_speed": 55.0,
		"tilt": 27.0, "banded": true,
		"color": Color(0.88, 0.82, 0.62), "color2": Color(0.72, 0.64, 0.45),
		"fact": "Famous for its spectacular ring system.",
		"diameter_km": 116460, "sun_dist_mkm": 1434.0, "year": "29.5 years", "day": "10.7 h",
		"moons": 146, "gravity_g": 1.07,
		"atmosphere": Color(0.9, 0.85, 0.65), "atmo": 0.45,
		"texture": "res://assets/textures/2k_saturn.jpg",
		"moon_data": [
			{"name": "Titan", "radius": 0.07, "orbit_dist": 2.5, "orbit_speed": 50.0,
			 "color": Color(0.75, 0.65, 0.35), "color2": Color(0.6, 0.50, 0.25),
			 "diameter_km": 5150, "fact": "Only moon with a thick atmosphere; has lakes of methane.",
			 "atmosphere": Color(0.85, 0.7, 0.3), "atmo": 0.8},
		]},
	{"name": "Uranus", "radius": 0.50, "distance": 22.0, "orbit_speed": 4.0, "spin_speed": 45.0,
		"tilt": 98.0, "banded": true,
		"color": Color(0.60, 0.85, 0.85), "color2": Color(0.42, 0.70, 0.76),
		"fact": "An ice giant that rotates on its side.",
		"diameter_km": 50724, "sun_dist_mkm": 2871.0, "year": "84 years", "day": "17.2 h",
		"moons": 28, "gravity_g": 0.89,
		"atmosphere": Color(0.6, 0.9, 0.95), "atmo": 0.5,
		"texture": "res://assets/textures/2k_uranus.jpg"},
	{"name": "Neptune", "radius": 0.48, "distance": 26.0, "orbit_speed": 3.0, "spin_speed": 42.0,
		"tilt": 28.0, "banded": true,
		"color": Color(0.30, 0.45, 0.85), "color2": Color(0.16, 0.26, 0.68),
		"fact": "The windiest planet; farthest from the Sun.",
		"diameter_km": 49244, "sun_dist_mkm": 4495.0, "year": "165 years", "day": "16.1 h",
		"moons": 16, "gravity_g": 1.14,
		"atmosphere": Color(0.45, 0.55, 1.0), "atmo": 0.55,
		"texture": "res://assets/textures/2k_neptune.jpg"},
]

## Dwarf planets rendered beyond Neptune's orbit.
const DWARF_PLANETS := [
	{"name": "Pluto", "radius": 0.10, "distance": 30.0, "orbit_speed": 1.5, "spin_speed": 15.0,
		"tilt": 57.0, "banded": false,
		"color": Color(0.72, 0.65, 0.55), "color2": Color(0.50, 0.44, 0.38),
		"fact": "Reclassified as a dwarf planet in 2006, with a heart-shaped feature.",
		"diameter_km": 2377, "sun_dist_mkm": 5906.0, "year": "248 years", "day": "153 h",
		"moons": 5, "gravity_g": 0.06,
		"atmosphere": Color(0.6, 0.55, 0.5), "atmo": 0.1,
		"moon_data": [
			{"name": "Charon", "radius": 0.055, "orbit_dist": 0.4, "orbit_speed": 55.0,
			 "color": Color(0.55, 0.52, 0.50), "color2": Color(0.40, 0.38, 0.36),
			 "diameter_km": 1212, "fact": "So large relative to Pluto they are sometimes called a double dwarf planet."},
		]},
]

## Comets: highly elliptical orbits, rendered with a particle tail.
const COMETS := [
	{"name": "Halley's Comet", "radius": 0.04,
		"semi_major": 20.0, "eccentricity": 0.85, "orbit_speed": 5.0,
		"color": Color(0.8, 0.85, 0.9), "color2": Color(0.5, 0.55, 0.65),
		"tail_color": Color(0.7, 0.85, 1.0, 0.6),
		"fact": "Visible from Earth every 75-79 years; last seen in 1986.",
		"diameter_km": 11, "sun_dist_mkm": 2667.0, "year": "75.3 years", "day": "52.8 h",
		"moons": 0, "gravity_g": 0.0,
		"tilt": 15.0},
]

## Spacecraft & Space Probes.
const SPACECRAFT := [
	{"name": "Voyager 1", "radius": 0.05, "distance": 36.0, "orbit_speed": 0.8,
		"color": Color(0.9, 0.85, 0.6), "fact": "Launched in 1977, now exploring interstellar space beyond the heliosphere."},
	{"name": "JWST", "name_full": "James Webb Telescope", "radius": 0.04, "distance": 8.4, "orbit_speed": 14.5,
		"color": Color(1.0, 0.8, 0.2), "fact": "NASA's premier space observatory stationed at Earth's L2 point."},
]

## Asteroid belt parameters.
const ASTEROID_BELT := {
	"inner_radius": 11.5,
	"outer_radius": 13.0,
	"count": 600,
	"min_size": 0.015,
	"max_size": 0.06,
	"color": Color(0.45, 0.42, 0.38),
	"height_spread": 0.4,
}

## Kuiper Belt parameters.
const KUIPER_BELT := {
	"inner_radius": 28.0,
	"outer_radius": 36.0,
	"count": 800,
	"min_size": 0.01,
	"max_size": 0.04,
	"color": Color(0.55, 0.6, 0.7),
	"height_spread": 0.8,
}

## Oort Cloud shell parameters.
const OORT_CLOUD := {
	"radius": 45.0,
	"count": 500,
	"min_size": 0.01,
	"max_size": 0.03,
	"color": Color(0.7, 0.8, 0.95),
}
