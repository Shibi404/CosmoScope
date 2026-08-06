extends Node
## DIY stereoscopic VR rig for Google Cardboard (no OpenXR / no headset).
##
## Builds two eye viewports sharing one 3D world, renders each into a
## TextureRect through the barrel-distortion lens shader, tracks head
## orientation from the phone gyroscope (mouse-drag on desktop), and selects
## planets by gaze-and-dwell. Reuses the shared SolarSystem + SpaceEnvironment.

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")
const LENS_SHADER := preload("res://shaders/lens_distortion.gdshader")

## Interpupillary distance in world units (~human 6.4 cm).
@export var ipd: float = 0.064
@export var eye_fov: float = 80.0
## Where the viewer stands, looking toward the Sun at the origin.
@export var head_position: Vector3 = Vector3(0.0, 3.0, 10.0)
@export var use_gyroscope: bool = true
## Seconds of continuous gaze needed to select a planet.
@export var gaze_dwell_time: float = 1.5
## Half-angle (degrees) of the gaze cone used to pick a planet.
@export var gaze_angle_deg: float = 6.0
@export var reticle_distance: float = 3.0

# --- Focus / inspect mode ---
@export var inspect_distance: float = 4.0
@export var inspect_radius: float = 1.0
@export var inspect_spin_speed: float = 20.0

# --- Gyro mapping (tuned against real device readings) ---
## Which gyroscope component drives yaw / pitch (0=x, 1=y, 2=z).
@export_range(0, 2) var gyro_yaw_axis: int = 1
@export_range(0, 2) var gyro_pitch_axis: int = 0
@export var gyro_yaw_sign: float = 1.0
@export var gyro_pitch_sign: float = 1.0
## Show a live sensor readout on screen (debugging aid).
@export var debug_sensors: bool = false

var _left_viewport: SubViewport
var _right_viewport: SubViewport
var _left_cam: Camera3D
var _right_cam: Camera3D
var _left_rect: TextureRect
var _right_rect: TextureRect

var _reticle: MeshInstance3D
var _info_label: Label3D
var _planets: Array[Node3D] = []

var _orientation: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _pitch: float = 0.0
var _gazed: Node3D = null
var _dwell: float = 0.0
var _debug_label: Label = null
var _inspecting: bool = false
var _inspect_mesh: MeshInstance3D = null
var _inspect_light: OmniLight3D = null

func _ready() -> void:
	_build_eyes()
	_build_world()
	_build_gaze_ui()
	_build_debug()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _build_debug() -> void:
	if not debug_sensors:
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(14, 14)
	_debug_label.add_theme_font_size_override("font_size", 22)
	_debug_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_debug_label)

func _build_eyes() -> void:
	_left_viewport = _make_eye_viewport()
	_left_cam = _make_eye_camera(_left_viewport)
	_right_viewport = _make_eye_viewport()
	_right_cam = _make_eye_camera(_right_viewport)

	_left_rect = _make_eye_rect(_left_viewport)
	_right_rect = _make_eye_rect(_right_viewport)

func _make_eye_viewport() -> SubViewport:
	var vp := SubViewport.new()
	# own_world_3d stays false, so both eyes share the root window's World3D.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	return vp

func _make_eye_camera(vp: SubViewport) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = eye_fov
	cam.current = true
	vp.add_child(cam)
	return cam

func _make_eye_rect(vp: SubViewport) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = LENS_SHADER
	rect.material = mat
	add_child(rect)
	return rect

func _build_world() -> void:
	# The 3D content lives under the left viewport but, because the eyes share
	# the root world, both cameras render it.
	var env := WorldEnvironment.new()
	env.set_script(SpaceEnvScript)
	_left_viewport.add_child(env)

	var solar := Node3D.new()
	solar.set_script(SolarSystemScript)
	_left_viewport.add_child(solar)
	_planets = solar.get_planet_bodies()

func _build_gaze_ui() -> void:
	_reticle = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.02
	dot.height = 0.04
	_reticle.mesh = dot
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.disable_receive_shadows = true
	_reticle.material_override = rmat
	_left_viewport.add_child(_reticle)

	_info_label = Label3D.new()
	_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info_label.no_depth_test = true
	_info_label.pixel_size = 0.004
	_info_label.font_size = 48
	_info_label.outline_size = 10
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.visible = false
	_left_viewport.add_child(_info_label)

func _layout() -> void:
	# Use the visible rect (2D canvas space) rather than OS window pixels, so it
	# stays correct under the project's canvas_items stretch mode.
	var view := get_viewport().get_visible_rect().size
	var full_w := int(view.x)
	var full_h := int(view.y)
	var half := int(full_w / 2)
	if half <= 0:
		return
	_left_viewport.size = Vector2i(half, full_h)
	_right_viewport.size = Vector2i(full_w - half, full_h)
	_left_rect.position = Vector2(0, 0)
	_left_rect.size = Vector2(half, full_h)
	_right_rect.position = Vector2(half, 0)
	_right_rect.size = Vector2(full_w - half, full_h)

func _process(delta: float) -> void:
	_update_orientation(delta)
	_update_cameras()
	if _inspecting:
		_update_inspect(delta)
	else:
		_update_gaze(delta)
	_update_debug()

func _update_orientation(delta: float) -> void:
	# Unified yaw/pitch model: the gyroscope integrates into the same _yaw and
	# _pitch that mouse-drag drives, so desktop and device share one code path
	# and there is no roll drift.
	if use_gyroscope:
		var g := Input.get_gyroscope()
		_yaw += g[gyro_yaw_axis] * gyro_yaw_sign * delta
		_pitch += g[gyro_pitch_axis] * gyro_pitch_sign * delta
	_pitch = clampf(_pitch, -1.5, 1.5)
	_orientation = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

func _update_debug() -> void:
	if _debug_label == null:
		return
	var g := Input.get_gyroscope()
	var a := Input.get_accelerometer()
	_debug_label.text = "gyro  x %+5.2f  y %+5.2f  z %+5.2f\naccel x %+5.2f  y %+5.2f  z %+5.2f\nyaw %+5.2f  pitch %+5.2f" % [
		g.x, g.y, g.z, a.x, a.y, a.z, _yaw, _pitch
	]

func _update_cameras() -> void:
	var right := _orientation.x
	var left_pos := head_position - right * (ipd * 0.5)
	var right_pos := head_position + right * (ipd * 0.5)
	_left_cam.global_transform = Transform3D(_orientation, left_pos)
	_right_cam.global_transform = Transform3D(_orientation, right_pos)

func _update_gaze(delta: float) -> void:
	var forward := -_orientation.z
	_reticle.global_position = head_position + forward * reticle_distance

	# Pick the planet closest to the gaze direction, within the gaze cone.
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(gaze_angle_deg))
	for p in _planets:
		var dir := (p.global_position - head_position).normalized()
		var d := forward.dot(dir)
		if d > best_dot:
			best_dot = d
			best = p

	if best != _gazed:
		_gazed = best
		_dwell = 0.0
	elif best != null:
		_dwell += delta
		if _dwell >= gaze_dwell_time:
			_enter_inspect(best)

# --- Focus / inspect mode ---
# Gaze-dwell brings the planet forward as an enlarged, rotating model with its
# stats panel; a tap (Cardboard button / screen) returns to the system view.

func _enter_inspect(planet: Node3D) -> void:
	_inspecting = true
	_reticle.visible = false

	var forward := -_orientation.z
	var anchor := head_position + forward * inspect_distance

	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = inspect_radius
	mesh.height = inspect_radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mi.mesh = mesh
	var src := planet as MeshInstance3D
	if src != null:
		mi.material_override = src.material_override  # reuse the planet's surface
	mi.position = anchor
	_left_viewport.add_child(mi)
	_inspect_mesh = mi

	# Fill light on the viewer's side, so the camera-facing surface is lit
	# (the Sun alone would leave it backlit and dark).
	var light := OmniLight3D.new()
	light.position = head_position + forward * 0.5 + _orientation.y * 0.8
	light.omni_range = inspect_distance + inspect_radius + 3.0
	light.light_energy = 2.5
	_left_viewport.add_child(light)
	_inspect_light = light

	_info_label.text = _panel_text(planet.get_meta("data", {}))
	_info_label.global_position = anchor + Vector3(0.0, -(inspect_radius + 0.8), 0.0)
	_info_label.visible = true

func _update_inspect(delta: float) -> void:
	if is_instance_valid(_inspect_mesh):
		_inspect_mesh.rotate_y(deg_to_rad(inspect_spin_speed) * delta)

func _exit_inspect() -> void:
	_inspecting = false
	if is_instance_valid(_inspect_mesh):
		_inspect_mesh.queue_free()
	_inspect_mesh = null
	if is_instance_valid(_inspect_light):
		_inspect_light.queue_free()
	_inspect_light = null
	_info_label.visible = false
	_reticle.visible = true
	_gazed = null
	_dwell = 0.0

func _panel_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	return "%s\nDiameter: %s km\nDistance: %sM km from Sun\nYear: %s   Day: %s\nMoons: %d   Gravity: %.2fx Earth\n\n%s" % [
		d.name, _commas(d.diameter_km), _trim(d.sun_dist_mkm), d.year, d.day, d.moons, d.gravity_g, d.fact
	]

# Insert thousands separators (GDScript has no built-in for this).
func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

# Drop a trailing ".0" so whole numbers read cleanly.
func _trim(v: float) -> String:
	return "%.1f" % v if v != floor(v) else str(int(v))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventScreenTouch and not event.pressed:
		_on_tap()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_on_tap()  # desktop equivalent of the Cardboard button

func _on_tap() -> void:
	if _inspecting:
		_exit_inspect()
