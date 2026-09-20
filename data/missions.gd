## Per-planet ship activities. Each one is a different mini-game built around a
## real property of that planet (see scripts/PlanetActivities.gd for the rules).
##
## kind:
##   thermal — Mercury: cross between the sunlit and night side without over/under-heating
##   descent — Venus:   dive into the atmosphere, watch pressure + hull heat, pull up in time
##   orbit   — Earth:   reach a stable orbit, deploy a satellite, observe from orbit
##   rover   — Mars:    land at a site, drive a rover to rock targets, scan, collect a sample
##   storm   — Jupiter: hold station in the Great Red Spot's winds and measure the storm
##   rings   — Saturn:  fly the Cassini Division gap through the ring particles
##   tilt    — Uranus:  line up with the spin axis / equator and scan from three angles
##   winds   — Neptune: dive into a storm, log wind speed, escape before control is lost
##
## learned    — fact card shown on completion
## discovery  — one-liner recorded in the mission log

const MISSIONS := {
	"Mercury": {
		"kind": "thermal", "title": "Temperature Survival", "score": 200,
		"brief": "Mercury has almost no atmosphere, so heat is not spread around. Survive the swing between day and night.",
		"objective": "Cross between the sunlit and night side 3 times, within 3 u of the surface. Keep the hull between -90 and +170 °C.",
		"learned": "Mercury has almost no atmosphere to trap or move heat. The sunlit side reaches about 430 °C while the night side falls to about -180 °C, one of the biggest temperature swings of any planet.",
		"discovery": "Mercury: ~430 °C by day, ~-180 °C at night. No atmosphere to hold heat.",
	},
	"Venus": {
		"kind": "descent", "title": "Pressure & Heat Descent", "score": 250,
		"brief": "Venus' thick CO₂ atmosphere makes it the hottest planet. Dive for a sample without cooking or crushing the probe.",
		"objective": "Gravity pulls you down. Hold below 0.9 u altitude for 5 s of sampling; keep pressure under 85 bar and hull under 360 °C.",
		"learned": "Venus has a runaway greenhouse effect. Its CO₂ atmosphere is about 90 times denser than Earth's and holds the surface at roughly 465 °C, hot enough to melt lead, even hotter than Mercury.",
		"discovery": "Venus: 92 bar and ~465 °C at the surface. A runaway greenhouse effect.",
	},
	"Earth": {
		"kind": "orbit", "title": "Atmosphere & Satellite", "score": 250,
		"brief": "Satellites stay up because they fall around the planet as fast as they fall toward it.",
		"objective": "Reach a stable circular orbit (follow the cyan ring), press G to deploy the satellite, then observe the atmosphere, an ocean and a continent with G.",
		"learned": "A satellite stays in orbit by moving sideways fast enough that it keeps missing the ground. Earth's thin atmosphere, its oceans (about 71% of the surface) and its continents are all visible from orbit.",
		"discovery": "Earth: stable orbit needs the right speed for the altitude. 71% of the surface is ocean.",
	},
	"Mars": {
		"kind": "rover", "title": "Rover Exploration", "score": 350,
		"brief": "Mars is a cold desert with thin air, dust and one-third of Earth's gravity, with clues that liquid water once flowed.",
		"objective": "Land on the marked site (descend slowly), then drive the rover (W/S drive, A/D turn) to each target and press G to scan, then collect a sample.",
		"learned": "Mars' red colour comes from iron-oxide dust. Rounded pebbles and clay minerals show liquid water once flowed there. Gravity is only 0.38 g and the thin CO₂ air drives global dust storms.",
		"discovery": "Mars: iron-oxide dust, ancient riverbed rocks, 0.38 g gravity. Water flowed here long ago.",
	},
	"Jupiter": {
		"kind": "storm", "title": "Great Red Spot", "score": 350,
		"brief": "Jupiter is a gas giant with no surface. The Great Red Spot is a storm wider than Earth that has raged for centuries.",
		"objective": "Fly to the Great Red Spot and hold station inside the marked zone for 6 s while the winds push you around.",
		"learned": "Jupiter is a gas giant with no solid surface. The Great Red Spot is an anticyclone about 1.3 times Earth's width, with winds near 430 km/h at its rim and a calmer centre. It has lasted for hundreds of years.",
		"discovery": "Jupiter: gas giant. The Great Red Spot is a 1.3× Earth-wide storm, winds ~430 km/h.",
	},
	"Saturn": {
		"kind": "rings", "title": "Ring Navigation", "score": 400,
		"brief": "Saturn's rings are billions of separate ice and rock particles orbiting in a very thin sheet.",
		"objective": "Fly the Cassini Division gap through all 3 checkpoints in order. Ring particles damage the hull, so stay inside the gap.",
		"learned": "Saturn's rings are not solid. They are billions of particles, from dust grains to house-sized chunks, made mostly of water ice with some rock. They span 280,000 km but are often only about 10 m thick.",
		"discovery": "Saturn: rings are ~99% water-ice and rock particles, ~10 m thick, gaps kept clear by moons.",
	},
	"Uranus": {
		"kind": "tilt", "title": "Axial Tilt Survey", "score": 300,
		"brief": "Uranus is tipped over by about 98°, so it rolls around the Sun on its side and its poles take turns facing the Sun.",
		"objective": "Use the cyan spin-axis line. Scan the North pole (view along the axis), the equator (side-on) and the South pole. Aim at the planet and press G.",
		"learned": "Uranus' spin axis is tilted about 98°, so it orbits on its side. Each pole gets about 42 years of continuous sunlight followed by 42 years of darkness, giving the most extreme seasons in the Solar System.",
		"discovery": "Uranus: 98° axial tilt. Poles get ~42 years of sun, then ~42 years of dark.",
	},
	"Neptune": {
		"kind": "winds", "title": "Extreme Winds", "score": 400,
		"brief": "Neptune has the fastest winds in the Solar System, powered by internal heat rather than sunlight.",
		"objective": "Dive into the storm, press G in the shear layer and again in the core to log wind speed, then escape before you lose control.",
		"learned": "Neptune's winds reach about 2,100 km/h, the fastest in the Solar System, even though sunlight there is 900 times weaker than at Earth. Its internal heat drives the storms, including the Great Dark Spot.",
		"discovery": "Neptune: winds up to ~2,100 km/h, the fastest known. Driven by internal heat.",
	},
}

## Docking at these bodies refuels the ship (gas-giant scooping / Earth station).
const REFUEL_PLANETS := ["Earth", "Jupiter", "Saturn"]

## Rocky planets the pilot can walk on in VR (first-person surface exploration).
## gravity / temp / info are shown on the wrist HUD; the rest describes the local environment.
const WALKABLE := {
	"Mercury": {
		"gravity": 0.38, "temp": "430 °C by day, -180 °C at night", "freq": 0.03, "amp": 1.6,
		"info": "Cratered, airless and black-skied. Dust and rock, no weather.",
		"ground": Color(0.42, 0.39, 0.37), "rock": Color(0.3, 0.28, 0.27),
		"sky_top": Color(0.0, 0.0, 0.0), "sky_horizon": Color(0.03, 0.03, 0.04),
		"sun": 2.8, "ambient": 0.15, "fog": 0.0, "rocks": 90,
		"samples": [
			{"name": "Regolith sample", "fact": "Mercury's surface is a layer of pulverised rock (regolith) made by billions of years of meteorite impacts."},
			{"name": "Crater-rim rock", "fact": "Mercury is covered in craters. With no air or water to erode them, some are billions of years old."},
			{"name": "Ice-shadow sample", "fact": "Despite the heat, permanently shadowed craters near Mercury's poles hold water ice."},
		],
	},
	"Venus": {
		"gravity": 0.90, "temp": "465 °C, 92 bar (simulated in a safe suit)", "freq": 0.015, "amp": 2.4,
		"info": "Orange haze, crushing air, plains of volcanic rock.",
		"ground": Color(0.55, 0.38, 0.2), "rock": Color(0.36, 0.26, 0.16),
		"sky_top": Color(0.7, 0.42, 0.16), "sky_horizon": Color(0.9, 0.62, 0.3),
		"sun": 0.5, "sun_color": Color(1.0, 0.75, 0.45), "ambient": 0.9, "fog": 0.02, "rocks": 80,
		"samples": [
			{"name": "Basalt plate", "fact": "Venus' surface is mostly young volcanic basalt plains, resurfaced by lava a few hundred million years ago."},
			{"name": "Sulphur-crusted rock", "fact": "Venus' clouds are sulphuric acid, and sulphur compounds in the air react with surface rocks."},
			{"name": "Wind-worn stone", "fact": "Slow winds on the surface still move fine dust, in air almost 90 times denser than Earth's."},
		],
	},
	"Earth": {
		"gravity": 1.00, "temp": "about 15 °C average", "freq": 0.012, "amp": 3.0,
		"info": "Blue sky, breathable air, liquid water. Nothing else we know of compares.",
		"ground": Color(0.32, 0.45, 0.24), "rock": Color(0.4, 0.38, 0.34),
		"sky_top": Color(0.25, 0.45, 0.85), "sky_horizon": Color(0.7, 0.82, 0.95),
		"sun": 1.1, "ambient": 0.9, "fog": 0.0008, "rocks": 110,
		"samples": [
			{"name": "Granite pebble", "fact": "Earth's continents are made of light granite; the ocean floor is denser basalt."},
			{"name": "Fossil-bearing stone", "fact": "Earth's rocks hold fossils, records of over 3.5 billion years of life."},
			{"name": "Soil sample", "fact": "Soil, a mix of rock, water, air and living things, is unique to Earth and supports almost all land life."},
		],
	},
	"Mars": {
		"gravity": 0.38, "temp": "about -60 °C average", "freq": 0.02, "amp": 2.6,
		"info": "Rusty desert under a butterscotch sky, with thin CO₂ air.",
		"ground": Color(0.62, 0.32, 0.18), "rock": Color(0.42, 0.22, 0.14),
		"sky_top": Color(0.55, 0.4, 0.3), "sky_horizon": Color(0.88, 0.62, 0.45),
		"sun": 0.9, "sun_color": Color(1.0, 0.88, 0.75), "ambient": 0.8, "fog": 0.004, "rocks": 130,
		"samples": [
			{"name": "Hematite spherule", "fact": "Small hematite 'blueberries' formed in water, one of the first strong signs that Mars once had liquid water."},
			{"name": "Basalt cobble", "fact": "Most Martian rock is basalt, from volcanoes such as Olympus Mons, the tallest in the Solar System."},
			{"name": "Clay-rich rock", "fact": "Clay minerals only form in liquid water, so this rock records a warmer, wetter Mars."},
		],
	},
}
