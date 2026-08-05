extends Node3D
## Builds the Sun and planets from SolarSystemData and animates their orbits.
##
## This is the SHARED content core: both the AR and VR scenes instance this
## same node, so the solar system is defined in exactly one place. The two
## modes differ only in their camera and interaction, never in content.

const SolarSystemData := preload("res://data/planets.gd")

## Toggle orbital motion (e.g. pause for inspection).
@export var orbit_enabled: bool = true
## Global multiplier on orbit + spin speed.
@export var time_scale: float = 1.0

# One entry per planet: { pivot, planet, orbit_speed, spin_speed }.
var _orbits: Array[Dictionary] = []

func _ready() -> void:
	_build_sun()
	_build_planets()

func _process(delta: float) -> void:
	if not orbit_enabled:
		return
	var step := delta * time_scale
	for o in _orbits:
		o.pivot.rotate_y(deg_to_rad(o.orbit_speed) * step)
		o.planet.rotate_y(deg_to_rad(o.spin_speed) * step)

func _build_sun() -> void:
	var sun := _make_sphere(SolarSystemData.SUN.radius, SolarSystemData.SUN.color, true)
	sun.name = "Sun"
	add_child(sun)

	# The Sun lights the rest of the system.
	var light := OmniLight3D.new()
	light.omni_range = 200.0
	light.light_energy = 2.0
	sun.add_child(light)

func _build_planets() -> void:
	for data in SolarSystemData.PLANETS:
		# A pivot at the Sun; rotating it sweeps the planet around its orbit.
		var pivot := Node3D.new()
		pivot.name = "%sPivot" % data.name
		add_child(pivot)

		var planet := _make_sphere(data.radius, data.color, false)
		planet.name = data.name
		planet.position = Vector3(data.distance, 0.0, 0.0)
		planet.set_meta("fact", data.fact)
		pivot.add_child(planet)

		# Randomise start angle so the planets aren't lined up.
		pivot.rotate_y(randf() * TAU)

		_orbits.append({
			"pivot": pivot,
			"planet": planet,
			"orbit_speed": data.orbit_speed,
			"spin_speed": data.spin_speed,
		})

func _make_sphere(radius: float, color: Color, emissive: bool) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi
