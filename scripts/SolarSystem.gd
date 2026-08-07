extends Node3D
## Builds the Sun, planets, dwarf planets, moons, asteroid belt, and comets
## from SolarSystemData and animates their orbits.
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
## Show floating name labels above each planet.
@export var show_labels: bool = true
## Build the asteroid belt.
@export var build_asteroids: bool = true
## Build comets with particle trails.
@export var build_comets: bool = true
## Build dwarf planets (Pluto, etc.).
@export var build_dwarf_planets: bool = true

# One entry per planet: { pivot, planet, orbit_speed, spin_speed, true_scale }.
var _orbits: Array[Dictionary] = []
# Moon entries: { pivot, moon, orbit_speed }.
var _moon_orbits: Array[Dictionary] = []

# 0 = enhanced (readable) sizes, 1 = true relative sizes.
var _scale_target: float = 0.0
var _scale_t: float = 0.0

# Asteroid belt rotation.
var _asteroid_pivot: Node3D = null
# Comet objects.
var _comets: Array[Dictionary] = []

signal time_scale_changed(new_scale: float)

func _ready() -> void:
	_build_sun()
	_build_planets()
	if build_dwarf_planets:
		_build_dwarf_planets()
	if build_asteroids:
		_build_asteroid_belt()
		_build_kuiper_belt()
		_build_oort_cloud()
	if build_comets:
		_build_comets_objects()
	_build_spacecraft()

func _process(delta: float) -> void:
	_animate_scale(delta)
	if not orbit_enabled:
		return
	var step := delta * time_scale
	for o in _orbits:
		o.pivot.rotate_y(deg_to_rad(o.orbit_speed) * step)
		# Spin about the planet's own (tilted) axis.
		o.planet.rotate_object_local(Vector3.UP, deg_to_rad(o.spin_speed) * step)
	# Animate moons orbiting their parent planets.
	for m in _moon_orbits:
		m.pivot.rotate_y(deg_to_rad(m.orbit_speed) * step)
	# Animate comets on elliptical orbits.
	_animate_comets(step)

## Switch planet sizes between enhanced (readable) and true relative scale.
func set_true_scale(enabled: bool) -> void:
	_scale_target = 1.0 if enabled else 0.0

func is_true_scale() -> bool:
	return _scale_target > 0.5

## Cycle through predefined time scales for orbit speed control.
func cycle_time_scale() -> void:
	var scales := [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]
	var current_idx := 0
	for i in scales.size():
		if absf(time_scale - scales[i]) < 0.01:
			current_idx = i
			break
	current_idx = (current_idx + 1) % scales.size()
	time_scale = scales[current_idx]
	orbit_enabled = time_scale > 0.001
	time_scale_changed.emit(time_scale)

func get_time_scale_label() -> String:
	if time_scale < 0.01:
		return "⏸ Paused"
	elif time_scale < 1.0:
		return "⏪ %.0f%%" % (time_scale * 100.0)
	elif is_equal_approx(time_scale, 1.0):
		return "▶ 1×"
	else:
		return "⏩ %.0f×" % time_scale

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

	# Solar flares — particle system erupting from the Sun's surface.
	_add_solar_flares(sun)

	# Sun label.
	if show_labels:
		_add_label(sun, "Sun", SolarSystemData.SUN.radius)

func _add_solar_flares(sun: Node3D) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "SolarFlares"
	particles.amount = 40
	particles.lifetime = 2.5
	particles.explosiveness = 0.3
	particles.randomness = 0.8
	particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	mat.color = Color(1.0, 0.6, 0.15, 0.7)

	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.8, 0.2, 0.9))
	grad.add_point(0.5, Color(1.0, 0.4, 0.1, 0.6))
	grad.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	particles.process_material = mat

	# The draw pass: a small sphere for each particle.
	var draw := SphereMesh.new()
	draw.radius = 0.08
	draw.height = 0.16
	draw.radial_segments = 8
	draw.rings = 4
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(1.0, 0.7, 0.2, 0.8)
	dmat.emission_enabled = true
	dmat.emission = Color(1.0, 0.5, 0.1)
	dmat.emission_energy_multiplier = 3.0
	draw.material = dmat
	particles.draw_pass_1 = draw

	sun.add_child(particles)

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

		# Earth cloud layer — a second transparent sphere.
		if data.get("has_clouds", false):
			_add_cloud_layer(planet, data.radius)

		# Build moons for this planet.
		if data.has("moon_data"):
			_build_moons(planet, data.moon_data)

		# Floating name label.
		if show_labels:
			_add_label(planet, data.name, data.radius)

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

func _build_dwarf_planets() -> void:
	for data in SolarSystemData.DWARF_PLANETS:
		if show_orbits:
			_build_orbit_line(data.distance, Color(0.5, 0.4, 0.6, 0.2))

		var pivot := Node3D.new()
		pivot.name = "%sPivot" % data.name
		add_child(pivot)

		var planet := _make_sphere(data.radius, _planet_material(data))
		planet.name = data.name
		planet.position = Vector3(data.distance, 0.0, 0.0)
		planet.rotation.z = deg_to_rad(data.tilt)
		planet.set_meta("data", data)
		pivot.add_child(planet)

		# Moons for dwarf planets.
		if data.has("moon_data"):
			_build_moons(planet, data.moon_data)

		if show_labels:
			_add_label(planet, data.name, data.radius)

		pivot.rotate_y(randf() * TAU)

		_orbits.append({
			"pivot": pivot,
			"planet": planet,
			"orbit_speed": data.orbit_speed,
			"spin_speed": data.spin_speed,
			"true_scale": 1.0,
		})

func _build_moons(parent_planet: Node3D, moon_array: Array) -> void:
	for md in moon_array:
		# Moon pivot is a child of the planet, so it orbits around the planet.
		var moon_pivot := Node3D.new()
		moon_pivot.name = "%sPivot" % md.name
		parent_planet.add_child(moon_pivot)

		var moon_mat := StandardMaterial3D.new()
		moon_mat.albedo_color = md.color

		var moon := _make_sphere(md.radius, moon_mat)
		moon.name = md.name
		moon.position = Vector3(md.orbit_dist, 0.0, 0.0)
		moon.set_meta("data", md)

		# If the moon has an atmosphere (like Titan), add Fresnel glow.
		if md.has("atmosphere") and md.get("atmo", 0.0) > 0.0:
			var moon_shader_mat := _planet_material(md)
			moon.material_override = moon_shader_mat

		moon_pivot.add_child(moon)

		# Small label for the moon.
		if show_labels:
			_add_label(moon, md.name, md.radius, 16, true)

		moon_pivot.rotate_y(randf() * TAU)

		_moon_orbits.append({
			"pivot": moon_pivot,
			"moon": moon,
			"orbit_speed": md.orbit_speed,
		})

func _add_cloud_layer(planet: Node3D, planet_radius: float) -> void:
	## Adds a semi-transparent cloud sphere slightly larger than the planet,
	## rotating at a different speed to simulate atmospheric motion.
	var cloud_radius := planet_radius * 1.015
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = cloud_radius
	cloud_mesh.height = cloud_radius * 2.0
	cloud_mesh.radial_segments = 48
	cloud_mesh.rings = 24

	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # only draw the far side
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	cloud_mat.no_depth_test = false

	# Use the noise texture for cloud-like patterns.
	var noise_tex := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.015
	noise.fractal_octaves = 5
	noise_tex.noise = noise
	noise_tex.width = 512
	noise_tex.height = 256
	cloud_mat.albedo_texture = noise_tex

	var clouds := MeshInstance3D.new()
	clouds.name = "Clouds"
	clouds.mesh = cloud_mesh
	clouds.material_override = cloud_mat
	planet.add_child(clouds)

	# The cloud layer spins slightly faster than the planet itself,
	# creating a visible atmospheric drift effect.
	clouds.set_meta("cloud_spin", 12.0)  # deg/sec extra rotation

func _build_asteroid_belt() -> void:
	var belt := SolarSystemData.ASTEROID_BELT
	_asteroid_pivot = Node3D.new()
	_asteroid_pivot.name = "AsteroidBelt"
	add_child(_asteroid_pivot)

	# MultiMeshInstance3D for efficient instanced rendering of many small rocks.
	var multi := MultiMeshInstance3D.new()
	multi.name = "AsteroidInstances"

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = belt.count

	# Small irregular-ish mesh: an icosphere stands in for rocks.
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = belt.color
	rock_mat.roughness = 1.0
	rock_mesh.material = rock_mat
	mm.mesh = rock_mesh

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in belt.count:
		var angle := rng.randf() * TAU
		var r := rng.randf_range(belt.inner_radius, belt.outer_radius)
		var y := rng.randf_range(-belt.height_spread, belt.height_spread)
		var sz := rng.randf_range(belt.min_size, belt.max_size)

		var t := Transform3D()
		t = t.scaled(Vector3.ONE * sz)
		# Random rotation so asteroids look irregular.
		t = t.rotated(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU)
		t.origin = Vector3(cos(angle) * r, y, sin(angle) * r)
		mm.set_instance_transform(i, t)

		# Slight color variation.
		var cv := rng.randf_range(0.8, 1.2)
		mm.set_instance_color(i, belt.color * cv)

	multi.multimesh = mm
	_asteroid_pivot.add_child(multi)

	if show_orbits:
		# Faint belt boundaries.
		_build_orbit_line(belt.inner_radius, Color(0.4, 0.35, 0.3, 0.12))
		_build_orbit_line(belt.outer_radius, Color(0.4, 0.35, 0.3, 0.12))

func _build_kuiper_belt() -> void:
	var belt: Dictionary = SolarSystemData.KUIPER_BELT
	var pivot := Node3D.new()
	pivot.name = "KuiperBelt"
	add_child(pivot)

	var multi := MultiMeshInstance3D.new()
	multi.name = "KuiperInstances"

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = belt.count

	var ice_mesh := SphereMesh.new()
	ice_mesh.radius = 1.0
	ice_mesh.height = 2.0
	ice_mesh.radial_segments = 4
	ice_mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = belt.color
	mat.roughness = 0.8
	ice_mesh.material = mat
	mm.mesh = ice_mesh

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in belt.count:
		var angle: float = rng.randf() * TAU
		var r: float = rng.randf_range(belt.inner_radius, belt.outer_radius)
		var y: float = rng.randf_range(-belt.height_spread, belt.height_spread)
		var sz: float = rng.randf_range(belt.min_size, belt.max_size)

		var t := Transform3D()
		t = t.scaled(Vector3.ONE * sz)
		t.origin = Vector3(cos(angle) * r, y, sin(angle) * r)
		mm.set_instance_transform(i, t)
		var cv: float = rng.randf_range(0.7, 1.3)
		mm.set_instance_color(i, belt.color * cv)

	multi.multimesh = mm
	pivot.add_child(multi)

func _build_oort_cloud() -> void:
	var cloud: Dictionary = SolarSystemData.OORT_CLOUD
	var pivot := Node3D.new()
	pivot.name = "OortCloud"
	add_child(pivot)

	var multi := MultiMeshInstance3D.new()
	multi.name = "OortInstances"

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = cloud.count

	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.5
	star_mesh.height = 1.0
	star_mesh.radial_segments = 4
	star_mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = cloud.color
	star_mesh.material = mat
	mm.mesh = star_mesh

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in cloud.count:
		var u: float = rng.randf()
		var v: float = rng.randf()
		var theta: float = u * TAU
		var phi: float = acos(2.0 * v - 1.0)
		var r: float = cloud.radius * rng.randf_range(0.9, 1.1)

		var pos := Vector3(
			r * sin(phi) * cos(theta),
			r * sin(phi) * sin(theta),
			r * cos(phi)
		)

		var t := Transform3D()
		t = t.scaled(Vector3.ONE * rng.randf_range(cloud.min_size, cloud.max_size))
		t.origin = pos
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(cloud.color.r, cloud.color.g, cloud.color.b, rng.randf_range(0.2, 0.6)))

	multi.multimesh = mm
	pivot.add_child(multi)

func _build_spacecraft() -> void:
	for data in SolarSystemData.SPACECRAFT:
		var pivot := Node3D.new()
		pivot.name = "%sPivot" % data.name.replace(" ", "")
		add_child(pivot)

		var craft_mat := StandardMaterial3D.new()
		craft_mat.albedo_color = data.color
		craft_mat.metallic = 0.9
		craft_mat.roughness = 0.2

		var craft := _make_sphere(data.radius, craft_mat)
		craft.name = data.name.replace(" ", "")
		craft.position = Vector3(data.distance, 0.0, 0.0)
		craft.set_meta("data", data)
		pivot.add_child(craft)

		if show_labels:
			_add_label(craft, data.get("name_full", data.name), data.radius, 16)

		pivot.rotate_y(randf() * TAU)
		_orbits.append({
			"pivot": pivot,
			"planet": craft,
			"orbit_speed": data.orbit_speed,
			"spin_speed": 10.0,
			"true_scale": 1.0,
		})

func _build_comets_objects() -> void:
	for data in SolarSystemData.COMETS:
		var comet_node := Node3D.new()
		comet_node.name = data.name.replace("'", "").replace(" ", "")
		add_child(comet_node)

		# Comet nucleus (small icy body).
		var nucleus := _make_sphere(data.radius, _comet_material(data))
		nucleus.name = "Nucleus"
		nucleus.set_meta("data", data)
		comet_node.add_child(nucleus)

		# Particle tail — always points away from the Sun.
		var tail := GPUParticles3D.new()
		tail.name = "Tail"
		tail.amount = 80
		tail.lifetime = 2.0
		tail.explosiveness = 0.0
		tail.randomness = 0.4
		tail.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

		var tmat := ParticleProcessMaterial.new()
		tmat.direction = Vector3(0, 0, 1)  # will be overridden each frame
		tmat.spread = 25.0
		tmat.initial_velocity_min = 1.0
		tmat.initial_velocity_max = 3.0
		tmat.gravity = Vector3.ZERO
		tmat.damping_min = 0.5
		tmat.damping_max = 1.5
		tmat.scale_min = 0.02
		tmat.scale_max = 0.06

		var tail_grad := GradientTexture1D.new()
		var tg := Gradient.new()
		tg.set_color(0, data.tail_color)
		tg.set_color(1, Color(data.tail_color.r, data.tail_color.g, data.tail_color.b, 0.0))
		tail_grad.gradient = tg
		tmat.color_ramp = tail_grad

		tail.process_material = tmat

		# Draw pass.
		var tdraw := SphereMesh.new()
		tdraw.radius = 0.03
		tdraw.height = 0.06
		tdraw.radial_segments = 6
		tdraw.rings = 3
		var td_mat := StandardMaterial3D.new()
		td_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		td_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		td_mat.albedo_color = data.tail_color
		td_mat.emission_enabled = true
		td_mat.emission = Color(data.tail_color.r, data.tail_color.g, data.tail_color.b)
		td_mat.emission_energy_multiplier = 2.0
		tdraw.material = td_mat
		tail.draw_pass_1 = tdraw

		comet_node.add_child(tail)

		if show_labels:
			_add_label(nucleus, data.name, data.radius, 18)

		# Store comet state for elliptical orbit animation.
		_comets.append({
			"node": comet_node,
			"nucleus": nucleus,
			"tail": tail,
			"data": data,
			"angle": randf() * TAU,
		})

func _animate_comets(step: float) -> void:
	for c in _comets:
		var data: Dictionary = c.data
		var a: float = data.semi_major
		var e: float = data.eccentricity
		var c_node: Node3D = c.node
		var c_angle: float = c.angle
		c_angle += deg_to_rad(float(data.orbit_speed)) * step
		c.angle = c_angle

		# Elliptical orbit: r = a(1 - e²) / (1 + e·cos(θ))
		var r: float = a * (1.0 - e * e) / (1.0 + e * cos(c_angle))
		var tilt_rad: float = deg_to_rad(float(data.get("tilt", 0.0)))
		var x: float = cos(c_angle) * r
		var z: float = sin(c_angle) * r
		var y: float = sin(c_angle) * sin(tilt_rad) * r * 0.1

		c_node.position = Vector3(x, y, z)

		# Point the tail away from the Sun (origin).
		var away: Vector3 = c_node.position.normalized()
		if away.length() > 0.01:
			var tail_node: GPUParticles3D = c.tail
			var pmat: ParticleProcessMaterial = tail_node.process_material
			pmat.direction = away

## Planet body nodes, for gaze/selection by the VR and AR modes.
func get_planet_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for o in _orbits:
		bodies.append(o.planet)
	# Also include comet nuclei as selectable.
	for c in _comets:
		bodies.append(c.nucleus)
	return bodies

func _add_label(parent: Node3D, text: String, obj_radius: float, font_size: int = 24, is_moon: bool = false) -> void:
	var label := Label3D.new()
	label.name = "%sLabel" % text.replace(" ", "").replace("'", "")
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.004 if not is_moon else 0.003
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = Color(1.0, 1.0, 1.0, 0.75) if not is_moon else Color(0.85, 0.85, 0.9, 0.55)
	label.position = Vector3(0.0, obj_radius + 0.15 if not is_moon else obj_radius + 0.06, 0.0)
	parent.add_child(label)

func _add_rings(planet: Node3D, planet_radius: float) -> void:
	# A flat quad in the planet's equatorial plane; the ring shader carves it
	# into a banded annulus. Parented to the planet so it inherits the tilt.
	var size := planet_radius * 6.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	var ring_tex := "res://assets/textures/2k_saturn_ring_alpha.png"
	if ResourceLoader.exists(ring_tex):
		mat.set_shader_parameter("ring_texture", load(ring_tex))
		mat.set_shader_parameter("use_texture", true)

	var rings := MeshInstance3D.new()
	rings.name = "Rings"
	rings.mesh = plane
	rings.material_override = mat
	planet.add_child(rings)

func _build_orbit_line(radius: float, line_color: Color = Color(0.4, 0.45, 0.6, 0.25)) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = line_color

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

func _build_elliptical_orbit_line(semi_major: float, eccentricity: float, tilt_deg: float, line_color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = line_color

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var segments := 180
	var tilt_rad: float = deg_to_rad(tilt_deg)
	for i in segments + 1:
		var a: float = TAU * float(i) / float(segments)
		var r: float = semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(a))
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		var y: float = sin(a) * sin(tilt_rad) * r * 0.1
		im.surface_add_vertex(Vector3(x, y, z))
	im.surface_end()

	var line := MeshInstance3D.new()
	line.name = "EllipticalOrbit"
	line.mesh = im
	add_child(line)

func _planet_material(data: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter("color_a", data.color)
	mat.set_shader_parameter("color_b", data.color2)
	mat.set_shader_parameter("banded", data.get("banded", false))
	mat.set_shader_parameter("atmosphere_color", data.get("atmosphere", Color(0.5, 0.5, 0.5)))
	mat.set_shader_parameter("atmosphere_strength", data.get("atmo", 0.0))
	mat.set_shader_parameter("has_spot", data.get("spot", false))
	mat.set_shader_parameter("water", data.get("ocean", false))

	# Use a photographic map when one is provided; otherwise stay procedural.
	var tex_path: String = data.get("texture", "")
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_texture", load(tex_path))
		mat.set_shader_parameter("use_texture", true)
	return mat

func _comet_material(data: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.color
	mat.emission_enabled = true
	mat.emission = Color(data.color.r * 0.5, data.color.g * 0.5, data.color.b * 0.5)
	mat.emission_energy_multiplier = 1.5
	return mat

func _sun_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SUN_SHADER
	mat.set_shader_parameter("hot", SolarSystemData.SUN.color)
	var tex_path: String = SolarSystemData.SUN.get("texture", "")
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("sun_texture", load(tex_path))
		mat.set_shader_parameter("use_texture", true)
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
