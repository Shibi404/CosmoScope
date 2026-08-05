## Data table for the Sun and planets.
##
## Values are VISUAL (tuned for readability), not true-to-scale — real
## relative sizes/distances are far too extreme to view comfortably.
##   radius      : sphere radius in metres
##   distance    : orbit radius from the Sun in metres
##   orbit_speed : degrees/second travelled around the Sun
##   spin_speed  : degrees/second of axial rotation
##   color       : placeholder albedo until real textures are added
##   fact        : short blurb shown on selection

const SUN := {
	"name": "Sun",
	"radius": 2.0,
	"color": Color(1.0, 0.75, 0.2),
	"fact": "The star at the centre of the Solar System.",
}

const PLANETS := [
	{"name": "Mercury", "radius": 0.15, "distance": 4.0, "orbit_speed": 24.0, "spin_speed": 20.0,
		"color": Color(0.55, 0.50, 0.48), "fact": "Smallest planet and closest to the Sun."},
	{"name": "Venus", "radius": 0.28, "distance": 6.0, "orbit_speed": 18.0, "spin_speed": 15.0,
		"color": Color(0.85, 0.70, 0.45), "fact": "Hottest planet, wrapped in a thick CO2 atmosphere."},
	{"name": "Earth", "radius": 0.30, "distance": 8.0, "orbit_speed": 15.0, "spin_speed": 40.0,
		"color": Color(0.25, 0.50, 0.85), "fact": "The only known planet with life."},
	{"name": "Mars", "radius": 0.20, "distance": 10.0, "orbit_speed": 12.0, "spin_speed": 38.0,
		"color": Color(0.80, 0.35, 0.20), "fact": "The 'Red Planet', home to the tallest volcano."},
	{"name": "Jupiter", "radius": 0.90, "distance": 14.0, "orbit_speed": 8.0, "spin_speed": 60.0,
		"color": Color(0.80, 0.65, 0.50), "fact": "Largest planet; a gas giant with a Great Red Spot."},
	{"name": "Saturn", "radius": 0.80, "distance": 18.0, "orbit_speed": 6.0, "spin_speed": 55.0,
		"color": Color(0.85, 0.80, 0.60), "fact": "Famous for its spectacular ring system."},
	{"name": "Uranus", "radius": 0.50, "distance": 22.0, "orbit_speed": 4.0, "spin_speed": 45.0,
		"color": Color(0.60, 0.85, 0.85), "fact": "An ice giant that rotates on its side."},
	{"name": "Neptune", "radius": 0.48, "distance": 26.0, "orbit_speed": 3.0, "spin_speed": 42.0,
		"color": Color(0.30, 0.40, 0.85), "fact": "The windiest planet; farthest from the Sun."},
]
