extends Node3D
## Builds the Sun and planets from SolarSystemData and animates their orbits.
##
## This is the SHARED content core: both the AR and VR scenes instance this
## same node, so the solar system is defined in exactly one place. The two
## modes differ only in their camera and interaction, never in content.

const SolarSystemData := preload("res://data/planets.gd")
const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const SUN_SHADER := preload("res://shaders/sun.gdshader")
const RING_SHADER := preload("res://shaders/ring.gdshader")
const CORONA_SHADER := preload("res://shaders/corona.gdshader")

## Toggle orbital motion (e.g. pause for inspection).
@export var orbit_enabled: bool = true
## Global multiplier on orbit + spin speed.
@export var time_scale: float = 1.0
## Draw faint circular orbit paths in the ecliptic plane.
@export var show_orbits: bool = true
## Animation speed for the enhanced<->true relative-size morph.
@export var scale_morph_speed: float = 2.0

# One entry per planet: { pivot, planet, orbit_speed, spin_speed, true_scale }.
var _orbits: Array[Dictionary] = []

# 0 = enhanced (readable) sizes, 1 = true relative sizes.
var _scale_target: float = 0.0
var _scale_t: float = 0.0

func _ready() -> void:
	_build_sun()
	_build_planets()

func _process(delta: float) -> void:
	_animate_scale(delta)
	if not orbit_enabled:
		return
	var step := delta * time_scale
	for o in _orbits:
		o.pivot.rotate_y(deg_to_rad(o.orbit_speed) * step)
		# Spin about the planet's own (tilted) axis.
		o.planet.rotate_object_local(Vector3.UP, deg_to_rad(o.spin_speed) * step)

## Switch planet sizes between enhanced (readable) and true relative scale.
func set_true_scale(enabled: bool) -> void:
	_scale_target = 1.0 if enabled else 0.0

func is_true_scale() -> bool:
	return _scale_target > 0.5

func _animate_scale(delta: float) -> void:
	if is_equal_approx(_scale_t, _scale_target):
		return
	_scale_t = move_toward(_scale_t, _scale_target, scale_morph_speed * delta)
	for o in _orbits:
		var s := lerpf(1.0, o.true_scale, _scale_t)
		o.planet.scale = Vector3.ONE * s

func _build_sun() -> void:
	var sun := _make_sphere(SolarSystemData.SUN.radius, _sun_material())
	sun.name = "Sun"
	add_child(sun)

	# The Sun lights the rest of the system.
	var light := OmniLight3D.new()
	light.omni_range = 200.0
	light.light_energy = 2.0
	sun.add_child(light)

	# Additive, camera-facing corona so the Sun glows as a radiant star.
	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SolarSystemData.SUN.radius * 5.0
	corona.mesh = quad
	var cmat := ShaderMaterial.new()
	cmat.shader = CORONA_SHADER
	corona.material_override = cmat
	sun.add_child(corona)

func _build_planets() -> void:
	# Anchor true scale on the largest planet so it keeps its size and the
	# others shrink to their real proportions relative to it.
	var ref_diam := 0.0
	var ref_radius := 1.0
	for d in SolarSystemData.PLANETS:
		if float(d.diameter_km) > ref_diam:
			ref_diam = float(d.diameter_km)
			ref_radius = d.radius

	for data in SolarSystemData.PLANETS:
		if show_orbits:
			_build_orbit_line(data.distance)

		# A pivot at the Sun; rotating it sweeps the planet around its orbit.
		var pivot := Node3D.new()
		pivot.name = "%sPivot" % data.name
		add_child(pivot)

		var planet := _make_sphere(data.radius, _planet_material(data))
		planet.name = data.name
		planet.position = Vector3(data.distance, 0.0, 0.0)
		planet.rotation.z = deg_to_rad(data.tilt)  # axial tilt
		planet.set_meta("data", data)
		pivot.add_child(planet)

		if data.name == "Saturn":
			_add_rings(planet, data.radius)

		# Randomise start angle so the planets aren't lined up.
		pivot.rotate_y(randf() * TAU)

		var true_radius := ref_radius * (float(data.diameter_km) / ref_diam)
		_orbits.append({
			"pivot": pivot,
			"planet": planet,
			"orbit_speed": data.orbit_speed,
			"spin_speed": data.spin_speed,
			"true_scale": true_radius / data.radius,
		})

## Planet body nodes, for gaze/selection by the VR and AR modes.
func get_planet_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for o in _orbits:
		bodies.append(o.planet)
	return bodies

func _add_rings(planet: Node3D, planet_radius: float) -> void:
	# A flat quad in the planet's equatorial plane; the ring shader carves it
	# into a banded annulus. Parented to the planet so it inherits the tilt.
	var size := planet_radius * 6.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER

	var rings := MeshInstance3D.new()
	rings.name = "Rings"
	rings.mesh = plane
	rings.material_override = mat
	planet.add_child(rings)

func _build_orbit_line(radius: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.45, 0.6, 0.25)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var segments := 128
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		im.surface_add_vertex(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	im.surface_end()

	var line := MeshInstance3D.new()
	line.name = "Orbit%d" % int(radius)
	line.mesh = im
	add_child(line)

func _planet_material(data: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter("color_a", data.color)
	mat.set_shader_parameter("color_b", data.color2)
	mat.set_shader_parameter("banded", data.banded)
	mat.set_shader_parameter("atmosphere_color", data.atmosphere)
	mat.set_shader_parameter("atmosphere_strength", data.atmo)
	mat.set_shader_parameter("has_spot", data.get("spot", false))
	mat.set_shader_parameter("water", data.get("ocean", false))

	# Use a photographic map when one is provided; otherwise stay procedural.
	var tex_path: String = data.get("texture", "")
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_texture", load(tex_path))
		mat.set_shader_parameter("use_texture", true)
	return mat

func _sun_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SUN_SHADER
	mat.set_shader_parameter("hot", SolarSystemData.SUN.color)
	return mat

func _make_sphere(radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi
