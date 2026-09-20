extends Node3D
## 🛡️ Asteroid Impact & Planetary Defense — Educational Simulation
##
## Independent scenario, self-contained like SandboxController.gd — it never
## touches the main Solar System scene, so that scene is always intact when
## the user backs out (there is nothing to "restore": nothing here is shared
## global state).
##
## The asteroid itself is the primary interaction object:
##   - Click/tap it to select it (ring + indicator + live velocity readout).
##   - Drag it: a small move just repositions it; a bigger move arms a launch
##     vector (drag direction = launch direction, drag distance = speed) and
##     releasing it launches — same "grab and fling" idea as
##     SandboxController's click-drag launch, just direct-direction instead
##     of pull-back, per this scenario's spec.
##   - Click any planet to make it the target (no dropdown).
##   - While flying, arm 🛡️ Defend Planet then drag the asteroid again for a
##     small course-correction nudge; the pre-deflection path is kept as a
##     ghost line for comparison.
## Physics reuses the same Newtonian point-mass integrator and G_CONST as
## SandboxController.gd/the VR impact simulator — generalized so the
## gravity center is whichever planet is currently targeted, instead of a
## fixed body. Outcome (safe miss / close fly-by / deflection / temporary
## orbit / collision / escape) is derived from the simulated trajectory
## (closest approach + how much the path bent), never randomly chosen.
##
## Scope note: this pass implements the interactive desktop/touch core
## (sections 1-23, 26-27 of the spec). AR placement and a VR gaze-driven
## control scheme are intentionally not built here — see the chat summary.
## No real-world impact-damage/casualty physics is modeled anywhere.

const SolarSystemData := preload("res://data/planets.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")
const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const RING_SHADER := preload("res://shaders/ring.gdshader")

const G_CONST: float = 8.0 # Same tuned visual gravity constant as SandboxController
const ASTEROID_VISUAL_RADIUS: float = 0.32
const MIN_LAUNCH_DRAG: float = 0.3
const SPEED_SCALE: float = 1.1
const MAX_VELOCITY: float = 16.0
const DEFLECT_SCALE: float = 0.6
const MAX_DEFLECT_DRAG: float = 6.0
const ESCAPE_RADIUS: float = 26.0
const MAX_SIM_TIME: float = 40.0
const TRAIL_MAX_POINTS: int = 900
const CLOSE_APPROACH_MULT: float = 4.0
const SAFE_MISS_ANGLE_DEG: float = 15.0
const SAFE_MISS_DIST_MULT: float = 8.0
const ATTEMPT_HISTORY_MAX: int = 12
const EVENT_LOG_MAX: int = 40

const PLANET_ROW_Z: float = -10.0
const PLANET_SPACING: float = 3.2
const ASTEROID_DEFAULT_POS := Vector3(0.0, 0.0, 6.0)

## Hand-tuned *visual* masses per SolarSystemData.PLANETS index — tuned for
## interesting gameplay/deflection behaviour, not real relative planet mass
## (matches SandboxController's Earth=100/Jupiter=300 visual-gravity tuning).
const TARGET_MASSES: Array[float] = [40.0, 70.0, 100.0, 60.0, 320.0, 260.0, 150.0, 170.0]

enum SimState { READY, FLYING, RESOLVED }
enum Outcome { NONE, SAFE_MISS, CLOSE_FLYBY, DEFLECTED, TEMP_ORBIT, COLLISION, ESCAPE_TRAJECTORY }

const OUTCOME_INFO := {
	Outcome.SAFE_MISS: {"title": "🟢 SAFE MISS", "desc": "The launch direction sent the asteroid outside %s's collision region — gravity barely touched its course."},
	Outcome.CLOSE_FLYBY: {"title": "🟡 CLOSE FLY-BY", "desc": "The asteroid passed close to %s without colliding — a near thing, but it kept enough speed and clearance to continue on."},
	Outcome.DEFLECTED: {"title": "🔵 GRAVITATIONAL DEFLECTION", "desc": "The asteroid passed through %s's gravitational influence, which bent its trajectory substantially before it escaped."},
	Outcome.TEMP_ORBIT: {"title": "🟣 TEMPORARY ORBIT", "desc": "The asteroid was briefly captured, looping around %s, before eventually breaking free (or the simulation time limit was reached)."},
	Outcome.COLLISION: {"title": "🔴 COLLISION", "desc": "The asteroid's trajectory intersected %s directly. Impact event detected in the educational simulation."},
	Outcome.ESCAPE_TRAJECTORY: {"title": "⚪ ESCAPE TRAJECTORY", "desc": "%s's gravity measurably curved the path, but the asteroid never came close enough to be a fly-by before escaping."},
}

var _camera: Camera3D
var _orbit_pivot: Vector3 = Vector3(0.0, 0.5, -1.0)
var _yaw: float = 0.0
var _pitch: float = 0.24
var _cam_dist: float = 19.0
var _dragging_cam: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _camera_tween: Tween

var _planet_nodes: Array[Dictionary] = [] # {mesh, radius, data, idx}
var _target_idx: int = 2 # Default Earth (selectable anytime in READY)
var _active_target_idx: int = 2 # Locked in for the current/last flight
var _target_ring: MeshInstance3D
var _target_label: Label3D

var _asteroid_mesh: MeshInstance3D
var _asteroid_ring: MeshInstance3D
var _debris_trail: GPUParticles3D
var _selected: String = "" # "" | "asteroid"

var _dragging: bool = false
var _drag_mode: String = "" # "aim" | "deflect"
var _drag_anchor: Vector3 = Vector3.ZERO
var _drag_vector: Vector3 = Vector3.ZERO
var _defend_armed: bool = false

var _state: SimState = SimState.READY
var _paused: bool = false
var _sim_speed: float = 1.0
var _outcome: Outcome = Outcome.NONE

var _ast_pos: Vector3 = ASTEROID_DEFAULT_POS
var _ast_vel: Vector3 = Vector3.ZERO
var _sim_time: float = 0.0
var _min_dist: float = INF
var _min_dist_speed: float = 0.0
var _min_dist_point: Vector3 = Vector3.ZERO
var _angle_swept_rad: float = 0.0
var _prev_angle: float = 0.0
var _last_impact_speed: float = 0.0
var _impact_point: Vector3 = Vector3.ZERO
var _warning_level: String = "STANDBY"

var _last_launch_pos: Vector3 = ASTEROID_DEFAULT_POS
var _last_launch_vel: Vector3 = Vector3.ZERO
var _deflection_applied: bool = false

var _arrow_mesh_inst: MeshInstance3D
var _arrow_mesh: ImmediateMesh
var _preview_mesh_inst: MeshInstance3D
var _preview_mesh: ImmediateMesh
var _trail_mesh_inst: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: Array[Vector3] = []
var _ghost_orig_mesh_inst: MeshInstance3D
var _ghost_orig_mesh: ImmediateMesh
var _ghost_prev_mesh_inst: MeshInstance3D
var _ghost_prev_mesh: ImmediateMesh
var _ghost_prev_points: Array[Vector3] = []
var _closest_marker: MeshInstance3D
var _impact_marker: MeshInstance3D

var _session_clock: float = 0.0
var _event_log: Array[String] = []
var _attempts: Array[Dictionary] = []

var _ui_canvas: CanvasLayer
var _telemetry_lbl: RichTextLabel
var _log_lbl: RichTextLabel
var _why_card: PanelContainer
var _why_lbl: RichTextLabel
var _history_lbl: RichTextLabel
var _demo_lbl: RichTextLabel
var _defend_btn: Button
var _pause_btn: Button
var _inspect_btn: Button

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_planets()
	_build_asteroid_and_rings()
	_build_trajectory_meshes()
	_build_markers()
	_build_ui()
	_reset_scenario()

# ---- World ----

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.set_script(SpaceEnvScript)
	add_child(env)

	var light := DirectionalLight3D.new()
	light.position = Vector3(8, 14, 10)
	light.light_energy = 1.2
	add_child(light)
	light.look_at(Vector3.ZERO)

	_camera = Camera3D.new()
	add_child(_camera)
	_update_camera_transform()

func _update_camera_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _cam_dist
	_camera.position = _orbit_pivot + offset
	_camera.look_at(_orbit_pivot, Vector3.UP)

func _build_camera() -> void:
	pass # camera built in _build_environment(); kept separate for readability of _ready()

func _build_planets() -> void:
	var count := SolarSystemData.PLANETS.size()
	var start_x := -PLANET_SPACING * float(count - 1) * 0.5
	for i in count:
		var data: Dictionary = SolarSystemData.PLANETS[i]
		var radius: float = clampf(data.radius * 2.2, 0.5, 2.2)
		var mesh_inst := _make_realistic_sphere(radius, _planet_material(data))
		mesh_inst.position = Vector3(start_x + PLANET_SPACING * i, 0.0, PLANET_ROW_Z)
		mesh_inst.rotation.z = deg_to_rad(float(data.get("tilt", 0.0)))
		add_child(mesh_inst)

		if data.get("has_clouds", false):
			_add_cloud_layer(mesh_inst, radius)
		if String(data.name) == "Saturn":
			_add_rings(mesh_inst, radius)

		var label := Label3D.new()
		label.text = String(data.name)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.006
		label.font_size = 36
		label.outline_size = 8
		label.position = mesh_inst.position + Vector3(0.0, radius + 0.4, 0.0)
		add_child(label)

		_planet_nodes.append({"mesh": mesh_inst, "radius": radius, "data": data, "idx": i, "spin": float(data.get("spin_speed", 20.0))})

	_target_ring = _make_ring(Color(0.3, 0.9, 1.0, 0.9))
	_target_label = Label3D.new()
	_target_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_target_label.no_depth_test = true
	_target_label.pixel_size = 0.005
	_target_label.font_size = 32
	_target_label.outline_size = 7
	_target_label.modulate = Color(0.3, 0.9, 1.0)
	add_child(_target_label)

## Same textured/shader planet look as SolarSystem.gd's _planet_material(),
## so this scenario's planets match the main Solar System instead of looking
## like flat placeholder spheres.
func _planet_material(data: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter("color_a", data.color)
	mat.set_shader_parameter("color_b", data.get("color2", data.color))
	mat.set_shader_parameter("banded", data.get("banded", false))
	mat.set_shader_parameter("atmosphere_color", data.get("atmosphere", Color(0.5, 0.5, 0.5)))
	mat.set_shader_parameter("atmosphere_strength", data.get("atmo", 0.0))
	mat.set_shader_parameter("has_spot", data.get("spot", false))
	mat.set_shader_parameter("water", data.get("ocean", false))
	var tex_path: String = data.get("texture", "")
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		mat.set_shader_parameter("albedo_texture", load(tex_path))
		mat.set_shader_parameter("use_texture", true)
	return mat

func _make_realistic_sphere(radius: float, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = material
	return mi

func _add_cloud_layer(planet: Node3D, planet_radius: float) -> void:
	var cloud_radius := planet_radius * 1.015
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = cloud_radius
	cloud_mesh.height = cloud_radius * 2.0
	cloud_mesh.radial_segments = 48
	cloud_mesh.rings = 24

	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

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

func _add_rings(planet: Node3D, planet_radius: float) -> void:
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

func _make_ring(color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.15
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	ring.material_override = mat
	add_child(ring)
	return ring

func _build_asteroid_and_rings() -> void:
	# Low-poly, irregularly-scaled rock (same style as SolarSystem.gd's
	# asteroid-belt instances) instead of a smooth toy ball.
	var rock := SphereMesh.new()
	rock.radius = ASTEROID_VISUAL_RADIUS
	rock.height = ASTEROID_VISUAL_RADIUS * 2.0
	rock.radial_segments = 9
	rock.rings = 5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.55, 0.35)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 2.2

	_asteroid_mesh = MeshInstance3D.new()
	_asteroid_mesh.mesh = rock
	_asteroid_mesh.material_override = mat
	_asteroid_mesh.scale = Vector3(1.0, 0.82, 1.18)
	add_child(_asteroid_mesh)

	_asteroid_ring = _make_ring(Color(1.0, 0.85, 0.3, 0.9))
	_scale_ring(_asteroid_ring, ASTEROID_VISUAL_RADIUS * 2.2)

	_build_asteroid_trail_particles()

func _build_asteroid_trail_particles() -> void:
	_debris_trail = GPUParticles3D.new()
	_debris_trail.name = "DebrisTrail"
	_debris_trail.amount = 48
	_debris_trail.lifetime = 0.7
	_debris_trail.explosiveness = 0.0
	_debris_trail.randomness = 0.5
	_debris_trail.emitting = false
	_debris_trail.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 0, 1)
	pmat.spread = 12.0
	pmat.initial_velocity_min = 0.2
	pmat.initial_velocity_max = 0.6
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.02
	pmat.scale_max = 0.05
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.3, 0.8))
	grad.add_point(0.6, Color(0.9, 0.4, 0.15, 0.4))
	grad.set_color(1, Color(0.5, 0.2, 0.1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pmat.color_ramp = ramp
	_debris_trail.process_material = pmat

	var draw := SphereMesh.new()
	draw.radius = 0.025
	draw.height = 0.05
	draw.radial_segments = 6
	draw.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	dmat.emission_enabled = true
	dmat.emission = Color(1.0, 0.5, 0.15)
	dmat.emission_energy_multiplier = 2.0
	draw.material = dmat
	_debris_trail.draw_pass_1 = draw

	add_child(_debris_trail)

func _scale_ring(ring: MeshInstance3D, radius: float) -> void:
	var torus := ring.mesh as TorusMesh
	torus.outer_radius = radius
	torus.inner_radius = radius * 0.85

# ---- Trajectory / arrow / marker meshes ----

func _build_trajectory_meshes() -> void:
	_arrow_mesh = ImmediateMesh.new()
	_arrow_mesh_inst = MeshInstance3D.new()
	_arrow_mesh_inst.mesh = _arrow_mesh
	add_child(_arrow_mesh_inst)

	_preview_mesh = ImmediateMesh.new()
	_preview_mesh_inst = MeshInstance3D.new()
	_preview_mesh_inst.mesh = _preview_mesh
	add_child(_preview_mesh_inst)

	_trail_mesh = ImmediateMesh.new()
	_trail_mesh_inst = MeshInstance3D.new()
	_trail_mesh_inst.mesh = _trail_mesh
	add_child(_trail_mesh_inst)

	_ghost_orig_mesh = ImmediateMesh.new()
	_ghost_orig_mesh_inst = MeshInstance3D.new()
	_ghost_orig_mesh_inst.mesh = _ghost_orig_mesh
	add_child(_ghost_orig_mesh_inst)

	_ghost_prev_mesh = ImmediateMesh.new()
	_ghost_prev_mesh_inst = MeshInstance3D.new()
	_ghost_prev_mesh_inst.mesh = _ghost_prev_mesh
	add_child(_ghost_prev_mesh_inst)

func _build_markers() -> void:
	_closest_marker = MeshInstance3D.new()
	var s1 := SphereMesh.new()
	s1.radius = 0.12
	s1.height = 0.24
	_closest_marker.mesh = s1
	var m1 := StandardMaterial3D.new()
	m1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m1.albedo_color = Color(1.0, 0.9, 0.2, 0.9)
	m1.emission_enabled = true
	m1.emission = Color(1.0, 0.9, 0.2)
	_closest_marker.material_override = m1
	_closest_marker.visible = false
	add_child(_closest_marker)

	_impact_marker = MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = 0.18
	s2.height = 0.36
	_impact_marker.mesh = s2
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.albedo_color = Color(1.0, 0.25, 0.15, 0.95)
	m2.emission_enabled = true
	m2.emission = Color(1.0, 0.2, 0.1)
	_impact_marker.material_override = m2
	_impact_marker.visible = false
	add_child(_impact_marker)

# ---- UI (compact, secondary — the 3D scene is the primary interaction) ----

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _build_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_canvas.add_child(root)

	var title := Label.new()
	title.text = "🛡️ Asteroid Impact & Planetary Defense"
	title.add_theme_font_size_override("font_size", 20)
	title.position = Vector2(16, 12)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "🎓 Educational simulation — drag the asteroid in 3D to aim & launch it. No real-world impact physics."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	subtitle.position = Vector2(16, 36)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle)

	# Telemetry (top-left)
	var tel_card := PanelContainer.new()
	tel_card.position = Vector2(16, 62)
	tel_card.custom_minimum_size = Vector2(300, 168)
	tel_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(tel_card)
	_telemetry_lbl = RichTextLabel.new()
	_telemetry_lbl.bbcode_enabled = true
	_telemetry_lbl.fit_content = false
	_telemetry_lbl.scroll_active = false
	_telemetry_lbl.custom_minimum_size = Vector2(280, 150)
	_telemetry_lbl.add_theme_font_size_override("normal_font_size", 13)
	_telemetry_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tel_card.add_child(_telemetry_lbl)

	# Event log (below telemetry)
	var log_card := PanelContainer.new()
	log_card.position = Vector2(16, 240)
	log_card.custom_minimum_size = Vector2(300, 150)
	log_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(log_card)
	_log_lbl = RichTextLabel.new()
	_log_lbl.bbcode_enabled = true
	_log_lbl.custom_minimum_size = Vector2(280, 134)
	_log_lbl.add_theme_font_size_override("normal_font_size", 12)
	_log_lbl.scroll_following = true
	_log_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_card.add_child(_log_lbl)

	# Attempt history (right side)
	var hist_card := PanelContainer.new()
	hist_card.position = Vector2(-260, 62)
	hist_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hist_card.custom_minimum_size = Vector2(244, 200)
	hist_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(hist_card)
	var hist_vbox := VBoxContainer.new()
	hist_card.add_child(hist_vbox)
	var hist_title := Label.new()
	hist_title.text = "📜 Attempt History"
	hist_title.add_theme_font_size_override("font_size", 14)
	hist_vbox.add_child(hist_title)
	_history_lbl = RichTextLabel.new()
	_history_lbl.bbcode_enabled = true
	_history_lbl.fit_content = false
	_history_lbl.custom_minimum_size = Vector2(224, 160)
	_history_lbl.add_theme_font_size_override("normal_font_size", 12)
	_history_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hist_vbox.add_child(_history_lbl)

	# Demo checklist (right side, below history)
	var demo_card := PanelContainer.new()
	demo_card.position = Vector2(-260, 272)
	demo_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	demo_card.custom_minimum_size = Vector2(244, 230)
	demo_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(demo_card)
	var demo_vbox := VBoxContainer.new()
	demo_card.add_child(demo_vbox)
	var demo_title := Label.new()
	demo_title.text = "📋 Demo Steps"
	demo_title.add_theme_font_size_override("font_size", 14)
	demo_vbox.add_child(demo_title)
	_demo_lbl = RichTextLabel.new()
	_demo_lbl.bbcode_enabled = true
	_demo_lbl.fit_content = false
	_demo_lbl.custom_minimum_size = Vector2(224, 190)
	_demo_lbl.add_theme_font_size_override("normal_font_size", 11)
	_demo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	demo_vbox.add_child(_demo_lbl)

	# Why-explanation (bottom-left)
	var why_card := PanelContainer.new()
	why_card.position = Vector2(16, -140)
	why_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	why_card.custom_minimum_size = Vector2(420, 120)
	why_card.add_theme_stylebox_override("panel", _panel_style())
	why_card.visible = false
	root.add_child(why_card)
	_why_card = why_card
	_why_lbl = RichTextLabel.new()
	_why_lbl.bbcode_enabled = true
	_why_lbl.fit_content = false
	_why_lbl.custom_minimum_size = Vector2(400, 104)
	_why_lbl.add_theme_font_size_override("normal_font_size", 13)
	_why_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why_card.add_child(_why_lbl)

	# Button rows (bottom-right)
	var btn_card := PanelContainer.new()
	btn_card.position = Vector2(-360, -220)
	btn_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_card.custom_minimum_size = Vector2(344, 204)
	btn_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(btn_card)
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	btn_card.add_child(btn_vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	btn_vbox.add_child(row1)
	_add_btn(row1, "☄️ Launch", _on_launch_button)
	_pause_btn = _add_btn(row1, "⏸ Pause", _on_pause_toggle)
	_add_btn(row1, "🔁 Restart", _on_restart_attempt)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	btn_vbox.add_child(row2)
	_defend_btn = _add_btn(row2, "🛡️ Defend", _on_defend_toggle)
	_add_btn(row2, "🔍 What If?", _on_what_if)
	_add_btn(row2, "🔄 Reset", _on_reset_pressed)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	btn_vbox.add_child(row3)
	_add_btn(row3, "0.5x", func(): _set_speed(0.5))
	_add_btn(row3, "1x", func(): _set_speed(1.0))
	_add_btn(row3, "2x", func(): _set_speed(2.0))

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	btn_vbox.add_child(row4)
	_add_btn(row4, "🎯 Asteroid", func(): _focus_on(_ast_pos, 6.0))
	_add_btn(row4, "🌍 Target", func(): _focus_on(_active_target_pos(), 6.0))
	_inspect_btn = _add_btn(row4, "🔎 Impact", func(): _focus_on(_impact_point, 3.0))

	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 6)
	btn_vbox.add_child(row5)
	_add_btn(row5, "⬅️ Back to Menu", _on_back_pressed)

func _add_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

# ---- Selection / drag input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_cam = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(4.0, _cam_dist - 1.5)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(48.0, _cam_dist + 1.5)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_begin_drag(event.position)
			else:
				_end_drag(event.position)
	elif event is InputEventMouseMotion:
		if _dragging_cam:
			var d: Vector2 = event.position - _last_mouse_pos
			_last_mouse_pos = event.position
			_yaw -= d.x * 0.005
			_pitch = clampf(_pitch - d.y * 0.005, 0.05, 1.4)
			_update_camera_transform()
		elif _dragging:
			_update_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_try_begin_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventScreenDrag and _dragging:
		_update_drag(event.position)

func _screen_ray(screen_pos: Vector2) -> Array:
	return [_camera.project_ray_origin(screen_pos), _camera.project_ray_normal(screen_pos)]

func _screen_to_world_plane(screen_pos: Vector2, plane_y: float) -> Vector3:
	var ray := _screen_ray(screen_pos)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, plane_y, origin.z)
	var t := (plane_y - origin.y) / dir.y
	var hit: Vector3 = origin + dir * t
	hit.y = plane_y
	return hit

func _ray_hit_t(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t

func _try_begin_drag(screen_pos: Vector2) -> void:
	var ray := _screen_ray(screen_pos)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]

	var best_t := INF
	var best_kind := ""
	var best_idx := -1

	var ast_t := _ray_hit_t(origin, dir, _asteroid_mesh.position, ASTEROID_VISUAL_RADIUS * 2.5)
	if ast_t > 0.0 and ast_t < best_t:
		best_t = ast_t
		best_kind = "asteroid"

	for p: Dictionary in _planet_nodes:
		var mesh: MeshInstance3D = p.mesh
		var t := _ray_hit_t(origin, dir, mesh.position, float(p.radius) * 1.1)
		if t > 0.0 and t < best_t:
			best_t = t
			best_kind = "planet"
			best_idx = int(p.idx)

	if best_kind == "asteroid":
		_selected = "asteroid"
		if _state == SimState.READY:
			_drag_mode = "aim"
			_dragging = true
			_drag_anchor = _asteroid_mesh.position
			_log("Asteroid selected")
		elif _state == SimState.FLYING and _defend_armed:
			_drag_mode = "deflect"
			_dragging = true
			_drag_anchor = _ast_pos
			_log("Deflection drag started")
	elif best_kind == "planet":
		if _state == SimState.READY:
			_target_idx = best_idx
			_target_selected_update()
			_log("Target: %s" % String(SolarSystemData.PLANETS[best_idx].name))

func _update_drag(screen_pos: Vector2) -> void:
	var world := _screen_to_world_plane(screen_pos, 0.0)
	if _drag_mode == "aim":
		_asteroid_mesh.position = world
		_drag_vector = (world - _drag_anchor) * SPEED_SCALE
		if _drag_vector.length() > MAX_VELOCITY:
			_drag_vector = _drag_vector.normalized() * MAX_VELOCITY
		_draw_arrow(world, _drag_vector)
		_draw_preview(world, _drag_vector)
	elif _drag_mode == "deflect":
		var raw := (world - _drag_anchor) * SPEED_SCALE
		if raw.length() > MAX_DEFLECT_DRAG:
			raw = raw.normalized() * MAX_DEFLECT_DRAG
		_drag_vector = raw
		_draw_arrow(_ast_pos, _drag_vector)

func _end_drag(_screen_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	if _drag_mode == "aim":
		_arrow_mesh.clear_surfaces()
		if _drag_vector.length() >= MIN_LAUNCH_DRAG:
			_begin_flight(_asteroid_mesh.position, _drag_vector)
		# else: just repositioned, stays selected & READY
	elif _drag_mode == "deflect":
		_arrow_mesh.clear_surfaces()
		_apply_deflection(_drag_vector)
	_drag_mode = ""
	_drag_vector = Vector3.ZERO

func _draw_arrow(from: Vector3, vec: Vector3) -> void:
	_arrow_mesh.clear_surfaces()
	if vec.length() < 0.05:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3, 0.95)
	_arrow_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var to := from + vec
	_arrow_mesh.surface_add_vertex(from)
	_arrow_mesh.surface_add_vertex(to)
	var back := -vec.normalized() * minf(0.4, vec.length() * 0.25)
	var side := back.cross(Vector3.UP).normalized() * minf(0.25, vec.length() * 0.2)
	_arrow_mesh.surface_add_vertex(to)
	_arrow_mesh.surface_add_vertex(to + back + side)
	_arrow_mesh.surface_add_vertex(to)
	_arrow_mesh.surface_add_vertex(to + back - side)
	_arrow_mesh.surface_end()

func _draw_preview(from: Vector3, vel: Vector3) -> void:
	_preview_mesh.clear_surfaces()
	if vel.length() < 0.05:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.85, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pts := _simulate_forward(from, vel, _target_idx, 160)
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p: Vector3 in pts:
		_preview_mesh.surface_add_vertex(p)
	_preview_mesh.surface_end()

# ---- Target selection ----

func _active_target_pos() -> Vector3:
	return (_planet_nodes[_active_target_idx].mesh as MeshInstance3D).position

func _target_selected_update() -> void:
	var p: Dictionary = _planet_nodes[_target_idx]
	var mesh: MeshInstance3D = p.mesh
	_target_ring.position = mesh.position
	_scale_ring(_target_ring, float(p.radius) * 1.3)
	_target_label.text = "🎯 %s" % String(p.data.name)
	_target_label.position = mesh.position + Vector3(0.0, float(p.radius) + 0.9, 0.0)

# ---- Reusable forward gravity simulation (shared by preview + ghost paths) ----

func _simulate_forward(start_pos: Vector3, start_vel: Vector3, target_idx: int, max_steps: int) -> Array[Vector3]:
	var p: Dictionary = _planet_nodes[target_idx]
	var target_pos: Vector3 = (p.mesh as MeshInstance3D).position
	var target_mass: float = TARGET_MASSES[target_idx]
	var collision_r: float = float(p.radius) + ASTEROID_VISUAL_RADIUS

	var pts: Array[Vector3] = []
	var pos := start_pos
	var vel := start_vel
	var dt := 0.05
	for step in max_steps:
		pts.append(pos)
		var to_center := target_pos - pos
		var dist := to_center.length()
		if dist <= collision_r:
			break
		if dist > ESCAPE_RADIUS * 1.3 and vel.dot(to_center) < 0.0:
			break
		var acc := to_center.normalized() * (G_CONST * target_mass / maxf(dist * dist, 0.05))
		vel += acc * dt
		pos += vel * dt
	return pts

# ---- Flight lifecycle ----

func _begin_flight(pos: Vector3, vel: Vector3) -> void:
	_active_target_idx = _target_idx
	_ast_pos = pos
	_ast_vel = vel
	_last_launch_pos = pos
	_last_launch_vel = vel
	_deflection_applied = false
	_sim_time = 0.0
	_min_dist = INF
	_min_dist_speed = 0.0
	_angle_swept_rad = 0.0
	_prev_angle = atan2(pos.z - _active_target_pos().z, pos.x - _active_target_pos().x)
	_trail_points.clear()
	_trail_mesh.clear_surfaces()
	_preview_mesh.clear_surfaces()
	_ghost_orig_mesh.clear_surfaces()
	_closest_marker.visible = false
	_impact_marker.visible = false
	_state = SimState.FLYING
	_paused = false
	_outcome = Outcome.NONE
	_defend_armed = false
	_why_lbl.text = ""
	_why_card.visible = false
	_debris_trail.emitting = true
	_log("Launch initiated — target %s" % String(SolarSystemData.PLANETS[_active_target_idx].name))
	_update_defend_btn()

func _on_launch_button() -> void:
	if _state != SimState.READY:
		return
	var vel := _drag_vector if _drag_vector.length() >= MIN_LAUNCH_DRAG else Vector3(1.0, 0.0, -1.0).normalized() * 6.0
	_begin_flight(_asteroid_mesh.position, vel)

func _on_pause_toggle() -> void:
	if _state != SimState.FLYING:
		return
	_paused = not _paused
	_pause_btn.text = "▶ Resume" if _paused else "⏸ Pause"
	_debris_trail.emitting = not _paused
	_log("Paused" if _paused else "Resumed")

func _on_restart_attempt() -> void:
	_deflection_applied = false
	_begin_flight(_last_launch_pos, _last_launch_vel)

func _on_defend_toggle() -> void:
	if _state != SimState.FLYING:
		return
	_defend_armed = not _defend_armed
	_update_defend_btn()
	_log("Defend Planet armed — drag the asteroid to nudge its course" if _defend_armed else "Defend Planet disarmed")

func _update_defend_btn() -> void:
	if _defend_btn == null:
		return
	_defend_btn.text = "🛡️ Defend (ON)" if _defend_armed else "🛡️ Defend"
	_defend_btn.disabled = _state != SimState.FLYING

func _apply_deflection(drag_vec: Vector3) -> void:
	if drag_vec.length() < 0.15:
		return
	# Snapshot the "what would have happened" ghost path before altering velocity.
	var ghost := _simulate_forward(_ast_pos, _ast_vel, _active_target_idx, 220)
	_ghost_orig_mesh.clear_surfaces()
	if ghost.size() > 1:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.4, 0.35, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_orig_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for p: Vector3 in ghost:
			_ghost_orig_mesh.surface_add_vertex(p)
		_ghost_orig_mesh.surface_end()

	_ast_vel += drag_vec * DEFLECT_SCALE
	_deflection_applied = true
	_defend_armed = false
	_update_defend_btn()
	_log("Course correction applied — trajectory changed")

func _on_what_if() -> void:
	if _state == SimState.READY:
		return
	_ghost_prev_points = _trail_points.duplicate()
	_redraw_ghost_prev()
	_state = SimState.READY
	_outcome = Outcome.NONE
	_paused = false
	_asteroid_mesh.position = _last_launch_pos
	_drag_vector = Vector3.ZERO
	_trail_mesh.clear_surfaces()
	_trail_points.clear()
	_closest_marker.visible = false
	_impact_marker.visible = false
	_debris_trail.emitting = false
	_log("What If? — adjust and relaunch (previous path kept as ghost)")
	_update_defend_btn()

func _redraw_ghost_prev() -> void:
	_ghost_prev_mesh.clear_surfaces()
	if _ghost_prev_points.size() < 2:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.6, 0.7, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_prev_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p: Vector3 in _ghost_prev_points:
		_ghost_prev_mesh.surface_add_vertex(p)
	_ghost_prev_mesh.surface_end()

func _set_speed(v: float) -> void:
	_sim_speed = v

func _focus_on(pos: Vector3, dist: float) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.tween_method(_tween_pivot, _orbit_pivot, pos, 0.6)
	_camera_tween.tween_method(_tween_dist, _cam_dist, dist, 0.6)

func _tween_pivot(v: Vector3) -> void:
	_orbit_pivot = v
	_update_camera_transform()

func _tween_dist(v: float) -> void:
	_cam_dist = v
	_update_camera_transform()

func _on_reset_pressed() -> void:
	_reset_scenario()

func _reset_scenario() -> void:
	_state = SimState.READY
	_paused = false
	_sim_speed = 1.0
	_outcome = Outcome.NONE
	_selected = ""
	_dragging = false
	_drag_mode = ""
	_drag_vector = Vector3.ZERO
	_defend_armed = false
	_deflection_applied = false

	_target_idx = 2
	_active_target_idx = 2
	_target_selected_update()

	_ast_pos = ASTEROID_DEFAULT_POS
	_ast_vel = Vector3.ZERO
	_asteroid_mesh.position = ASTEROID_DEFAULT_POS
	_last_launch_pos = ASTEROID_DEFAULT_POS
	_last_launch_vel = Vector3.ZERO

	_sim_time = 0.0
	_min_dist = INF
	_angle_swept_rad = 0.0
	_warning_level = "STANDBY"

	_trail_points.clear()
	_trail_mesh.clear_surfaces()
	_preview_mesh.clear_surfaces()
	_arrow_mesh.clear_surfaces()
	_ghost_orig_mesh.clear_surfaces()
	_ghost_prev_mesh.clear_surfaces()
	_ghost_prev_points.clear()
	_closest_marker.visible = false
	_impact_marker.visible = false
	_debris_trail.emitting = false

	_event_log.clear()
	_attempts.clear()
	_why_lbl.text = ""
	if _why_card != null:
		_why_card.visible = false
	_orbit_pivot = Vector3(0.0, 0.5, -1.0)
	_yaw = 0.0
	_pitch = 0.24
	_cam_dist = 19.0
	_update_camera_transform()
	_update_defend_btn()
	_log("Scenario reset")

# ---- Per-frame physics + HUD ----

func _process(delta: float) -> void:
	_session_clock += delta
	for p: Dictionary in _planet_nodes:
		(p.mesh as MeshInstance3D).rotate_object_local(Vector3.UP, deg_to_rad(float(p.spin)) * delta)
	if _state == SimState.FLYING and not _paused:
		_step_physics(delta * _sim_speed)
	_asteroid_ring.position = _asteroid_mesh.position
	_asteroid_ring.visible = _selected == "asteroid" and _state == SimState.READY
	_update_telemetry()
	_update_demo_checklist()

func _step_physics(delta: float) -> void:
	_sim_time += delta

	var target_pos := _active_target_pos()
	var target_mass: float = TARGET_MASSES[_active_target_idx]
	var target_radius: float = float(_planet_nodes[_active_target_idx].radius)
	var collision_r := target_radius + ASTEROID_VISUAL_RADIUS

	var to_center := target_pos - _ast_pos
	var dist := to_center.length()
	if dist < _min_dist:
		_min_dist = dist
		_min_dist_speed = _ast_vel.length()
		_min_dist_point = _ast_pos

	var cur_angle := atan2(_ast_pos.z - target_pos.z, _ast_pos.x - target_pos.x)
	_angle_swept_rad += absf(wrapf(cur_angle - _prev_angle, -PI, PI))
	_prev_angle = cur_angle

	_update_warning_level(dist, collision_r)

	if dist <= collision_r:
		_last_impact_speed = _ast_vel.length()
		_impact_point = target_pos + (_ast_pos - target_pos).normalized() * target_radius
		_resolve_outcome(Outcome.COLLISION)
		return

	var acc := to_center.normalized() * (G_CONST * target_mass / maxf(dist * dist, 0.05))
	_ast_vel += acc * delta
	_ast_pos += _ast_vel * delta
	_asteroid_mesh.position = _ast_pos
	_asteroid_mesh.rotate_object_local(Vector3(0.3, 1.0, 0.2).normalized(), 2.0 * delta)
	_debris_trail.global_position = _ast_pos
	if _ast_vel.length() > 0.01:
		var pmat := _debris_trail.process_material as ParticleProcessMaterial
		pmat.direction = -_ast_vel.normalized()
	_append_trail_point(_ast_pos)

	var new_dist := (target_pos - _ast_pos).length()
	if new_dist > ESCAPE_RADIUS and _ast_vel.dot(_ast_pos - target_pos) > 0.0:
		_resolve_outcome(_classify_outcome(collision_r))
		return

	if _sim_time > MAX_SIM_TIME:
		_resolve_outcome(Outcome.TEMP_ORBIT)

func _update_warning_level(dist: float, collision_r: float) -> void:
	var ratio := dist / collision_r
	var new_level := "SAFE"
	if ratio <= 1.0:
		new_level = "IMPACT DETECTED"
	elif ratio <= 1.5:
		new_level = "IMPACT POSSIBLE"
	elif ratio <= 4.0:
		new_level = "CLOSE APPROACH"
	elif ratio <= 8.0:
		new_level = "MONITOR"
	if new_level != _warning_level:
		_warning_level = new_level
		if new_level in ["CLOSE APPROACH", "IMPACT POSSIBLE"]:
			_log("Warning: %s" % new_level)

func _classify_outcome(collision_r: float) -> int:
	var ratio := _min_dist / collision_r
	var deg := rad_to_deg(_angle_swept_rad)
	if ratio <= CLOSE_APPROACH_MULT and deg < 90.0:
		return Outcome.CLOSE_FLYBY
	if deg >= 300.0:
		return Outcome.TEMP_ORBIT
	if deg >= 90.0:
		return Outcome.DEFLECTED
	if ratio <= CLOSE_APPROACH_MULT:
		return Outcome.CLOSE_FLYBY
	if deg < SAFE_MISS_ANGLE_DEG and ratio > SAFE_MISS_DIST_MULT:
		return Outcome.SAFE_MISS
	return Outcome.ESCAPE_TRAJECTORY

func _append_trail_point(pos: Vector3) -> void:
	_trail_points.append(pos)
	if _trail_points.size() > TRAIL_MAX_POINTS:
		_trail_points.remove_at(0)
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.9, 0.5, 0.9) if _deflection_applied else Color(1.0, 0.6, 0.2, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p: Vector3 in _trail_points:
		_trail_mesh.surface_add_vertex(p)
	_trail_mesh.surface_end()

func _resolve_outcome(outcome: int) -> void:
	_outcome = outcome
	_state = SimState.RESOLVED
	_paused = false
	_defend_armed = false
	_debris_trail.emitting = false
	_update_defend_btn()

	_closest_marker.position = _min_dist_point
	_closest_marker.visible = outcome != Outcome.COLLISION

	if outcome == Outcome.COLLISION:
		_impact_marker.position = _impact_point
		_impact_marker.visible = true
		_log("☄️ IMPACT DETECTED")
		_focus_on(_impact_point, 3.5)
	else:
		var title := String(OUTCOME_INFO[outcome].title)
		_log(title)

	_record_attempt(outcome)
	_build_why_text(outcome)

func _record_attempt(outcome: int) -> void:
	_attempts.append({
		"n": _attempts.size() + 1,
		"target": String(SolarSystemData.PLANETS[_active_target_idx].name),
		"velocity": _last_launch_vel.length(),
		"outcome": String(OUTCOME_INFO[outcome].title),
		"deflected": _deflection_applied,
	})
	if _attempts.size() > ATTEMPT_HISTORY_MAX:
		_attempts.remove_at(0)

func _build_why_text(outcome: int) -> void:
	var target_name := String(SolarSystemData.PLANETS[_active_target_idx].name)
	var info: Dictionary = OUTCOME_INFO[outcome]
	var text := "[b]%s[/b]\n%s" % [String(info.title), String(info.desc) % target_name]
	if _deflection_applied:
		text += "\n\n[i]The course correction you applied changed the closest approach — compare the red (original) and %s (actual) paths.[/i]" % ("green" if outcome != Outcome.COLLISION else "orange")
	_why_lbl.text = text
	_why_card.visible = true

# ---- HUD text ----

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

func _log(msg: String) -> void:
	_event_log.append("[%s] %s" % [_fmt_time(_session_clock), msg])
	if _event_log.size() > EVENT_LOG_MAX:
		_event_log.remove_at(0)
	if _log_lbl != null:
		_log_lbl.text = "\n".join(_event_log)

func _update_telemetry() -> void:
	if _telemetry_lbl == null:
		return
	var target_name := String(SolarSystemData.PLANETS[_active_target_idx if _state != SimState.READY else _target_idx].name)
	var mission := "%s" % _state_name()
	var dist := (_active_target_pos() - _ast_pos).length() if _state != SimState.READY else (_active_target_pos() - _asteroid_mesh.position).length()
	var vel := _ast_vel.length() if _state != SimState.READY else _drag_vector.length()
	var closest := "%.2f" % _min_dist if _min_dist < INF else "—"

	_telemetry_lbl.text = "[b]ASTEROID[/b]\nTarget: %s\nVelocity: %.2f u/s\nDistance: %.2f u\nClosest Approach: %s\nTrajectory State: %s\nSimulation Time: %.1f s\nMission State: %s" % [
		target_name, vel, dist, closest, _warning_level, _sim_time, mission
	]

	if _history_lbl != null:
		var lines := []
		for a: Dictionary in _attempts:
			lines.append("#%d %s v=%.1f%s\n  → %s" % [
				int(a.n), String(a.target), float(a.velocity),
				"  🛡️" if bool(a.deflected) else "",
				String(a.outcome)
			])
		_history_lbl.text = "\n".join(lines) if not lines.is_empty() else "No attempts yet."

func _state_name() -> String:
	match _state:
		SimState.READY:
			return "STANDBY" if _selected != "asteroid" else "ARMED"
		SimState.FLYING:
			return "PAUSED" if _paused else "IN FLIGHT"
		SimState.RESOLVED:
			return String(OUTCOME_INFO[_outcome].title) if _outcome != Outcome.NONE else "RESOLVED"
	return ""

func _update_demo_checklist() -> void:
	if _demo_lbl == null:
		return
	var steps := [
		["Select Earth (or any planet)", _target_idx >= 0],
		["Spawn is automatic — select the asteroid", _selected == "asteroid" or _state != SimState.READY],
		["Drag the asteroid", _state != SimState.READY or _drag_mode != ""],
		["Change direction, watch preview update", _state != SimState.READY],
		["Release to launch", _state == SimState.FLYING or _state == SimState.RESOLVED],
		["Observe gravity bending the path", _angle_swept_rad > deg_to_rad(10.0)],
		["See the outcome (miss/fly-by/impact)", _state == SimState.RESOLVED],
		["Reset and try a different trajectory", _attempts.size() >= 1],
		["Activate Planetary Defense", _defend_armed or _deflection_applied],
		["Apply a deflection", _deflection_applied],
		["Compare original vs deflected path", _deflection_applied and _state == SimState.RESOLVED],
	]
	var lines := []
	for s in steps:
		var done: bool = s[1]
		lines.append(("[color=#7CFC9A]✔[/color] " if done else "[color=#666]○[/color] ") + String(s[0]))
	_demo_lbl.text = "\n".join(lines)

func _on_back_pressed() -> void:
	var main := get_node_or_null("/root/Main")
	if main != null and main.has_method("_load_scene"):
		main._load_scene("res://scenes/Menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
