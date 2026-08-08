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

# --- Focus mode (camera flies to the selected planet) ---
## Seconds for the fly-in / fly-out camera animation.
@export var focus_fly_time: float = 1.4
## Stand-off from the planet surface, as a multiple of its radius.
@export var focus_standoff: float = 3.0

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

var _solar: Node3D = null
var _reticle: MeshInstance3D
var _info_label: Label3D
var _hint_label: Label3D
var _planets: Array[Node3D] = []

var _orientation: Basis = Basis.IDENTITY
var _view_origin: Vector3 = Vector3.ZERO  # current camera position (animated on focus)
var _yaw: float = 0.0
var _pitch: float = 0.0
var _gazed: Node3D = null
var _dwell: float = 0.0
var _debug_label: Label = null

# Focus flight state machine.
enum { FOCUS_NONE, FOCUS_FLY_IN, FOCUS_HELD, FOCUS_FLY_OUT }
var _focus_state: int = FOCUS_NONE
var _focus_planet: Node3D = null
var _fly_t: float = 0.0
var _fly_from_origin: Vector3 = Vector3.ZERO
var _fly_to_origin: Vector3 = Vector3.ZERO
var _fly_from_yaw: float = 0.0
var _fly_to_yaw: float = 0.0
var _fly_from_pitch: float = 0.0
var _fly_to_pitch: float = 0.0
# Where to fly back to (the pre-focus position + look).
var _return_yaw: float = 0.0
var _return_pitch: float = 0.0
# Camera offset from the focused planet, kept fixed so the camera follows it.
var _focus_offset: Vector3 = Vector3.ZERO
# Viewer-side fill light so the planet's near face stays lit as it revolves.
var _focus_light: OmniLight3D = null

func _ready() -> void:
	_view_origin = head_position
	_build_eyes()
	_build_world()
	_build_gaze_ui()
	_build_debug()
	_build_menu_overlay()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _build_menu_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var back_btn := Button.new()
	back_btn.text = "← Menu"
	back_btn.position = Vector2(12, 12)
	back_btn.size = Vector2(90, 36)
	back_btn.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	back_btn.add_theme_stylebox_override("normal", style)
	back_btn.pressed.connect(func():
		var main := get_node_or_null("/root/Main")
		if main != null and main.has_method("_load_scene"):
			main._load_scene("res://scenes/Menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/Menu.tscn")
	)
	layer.add_child(back_btn)

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

	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	_left_viewport.add_child(_solar)
	_planets = _solar.get_planet_bodies()

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
	_info_label.pixel_size = 0.0032
	_info_label.font_size = 48
	_info_label.outline_size = 10
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.visible = false
	_left_viewport.add_child(_info_label)

	# Small hint anchored below the reticle, explaining what a tap does.
	_hint_label = Label3D.new()
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.no_depth_test = true
	_hint_label.pixel_size = 0.003
	_hint_label.font_size = 40
	_hint_label.outline_size = 8
	_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	_left_viewport.add_child(_hint_label)

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
	match _focus_state:
		FOCUS_FLY_IN, FOCUS_FLY_OUT:
			_update_fly(delta)          # scripted camera: sets _view_origin, _yaw, _pitch
		FOCUS_HELD:
			_update_orientation(delta)  # free head-look while the planet keeps moving
			# Follow the still-orbiting planet, keeping the same relative offset
			# so it stays framed while the Sun and stars sweep past.
			_view_origin = _focus_planet.global_position + _focus_offset
		_:
			_update_orientation(delta)  # free head-look via gyro / mouse
	_orientation = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	_update_cameras()
	if _focus_state == FOCUS_NONE:
		_update_gaze(delta)
	else:
		_place_focus_light()
		if _focus_state == FOCUS_HELD:
			_pin_info_panel()
	_update_hint()
	_update_debug()

func _update_hint() -> void:
	if _hint_label == null:
		return
	if _focus_state != FOCUS_NONE:
		_hint_label.visible = false
		return
	_hint_label.visible = true
	var forward := -_orientation.z
	_hint_label.global_position = _view_origin + forward * reticle_distance - _orientation.y * 0.5
	var to_true: bool = _solar == null or not _solar.is_true_scale()
	_hint_label.text = "Tap: %s sizes" % ("true" if to_true else "enhanced")

func _update_orientation(delta: float) -> void:
	# Unified yaw/pitch model: the gyroscope integrates into the same _yaw and
	# _pitch that mouse-drag drives, so desktop and device share one code path
	# and there is no roll drift.
	if use_gyroscope:
		var g := Input.get_gyroscope()
		_yaw += g[gyro_yaw_axis] * gyro_yaw_sign * delta
		_pitch += g[gyro_pitch_axis] * gyro_pitch_sign * delta
	_pitch = clampf(_pitch, -1.5, 1.5)

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
	var left_pos := _view_origin - right * (ipd * 0.5)
	var right_pos := _view_origin + right * (ipd * 0.5)
	_left_cam.global_transform = Transform3D(_orientation, left_pos)
	_right_cam.global_transform = Transform3D(_orientation, right_pos)

func _update_gaze(delta: float) -> void:
	var forward := -_orientation.z
	_reticle.global_position = _view_origin + forward * reticle_distance

	# Pick the planet closest to the gaze direction, within the gaze cone.
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(gaze_angle_deg))
	for p in _planets:
		var dir := (p.global_position - _view_origin).normalized()
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
			_begin_focus(best)

# --- Focus mode ---
# Gaze-dwell flies the camera in toward the real planet and shows its stats.
# The orbit keeps running: the camera holds a fixed offset and follows the
# planet, so it stays framed while everything sweeps past. A tap flies back out.

func _begin_focus(planet: Node3D) -> void:
	_focus_state = FOCUS_FLY_IN
	_focus_planet = planet
	_reticle.visible = false
	_info_label.visible = false

	var planet_pos := planet.global_position
	var radius := _planet_radius(planet)
	var dir := _view_origin - planet_pos
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.BACK
	_focus_offset = dir * (radius * focus_standoff + 0.6)

	# Remember where to return to (pre-focus position + look).
	_return_yaw = _yaw
	_return_pitch = _pitch
	_fly_from_origin = _view_origin
	_fly_from_yaw = _yaw
	_fly_from_pitch = _pitch
	_fly_t = 0.0

	if _focus_light == null:
		_focus_light = OmniLight3D.new()
		_focus_light.omni_range = 40.0
		_focus_light.light_energy = 1.4
		_left_viewport.add_child(_focus_light)

func _begin_return() -> void:
	_focus_state = FOCUS_FLY_OUT
	_info_label.visible = false
	_fly_from_origin = _view_origin
	_fly_to_origin = head_position
	_fly_from_yaw = _yaw
	_fly_to_yaw = _return_yaw
	_fly_from_pitch = _pitch
	_fly_to_pitch = _return_pitch
	_fly_t = 0.0

func _update_fly(delta: float) -> void:
	_fly_t = minf(1.0, _fly_t + delta / max(focus_fly_time, 0.01))
	var e := _fly_t * _fly_t * (3.0 - 2.0 * _fly_t)  # smoothstep ease
	if _focus_state == FOCUS_FLY_IN:
		# The target tracks the moving planet, and the look eases onto it.
		var target := _focus_planet.global_position + _focus_offset
		_view_origin = _fly_from_origin.lerp(target, e)
		var f := (_focus_planet.global_position - _view_origin).normalized()
		_yaw = lerp_angle(_fly_from_yaw, atan2(-f.x, -f.z), e)
		_pitch = lerpf(_fly_from_pitch, asin(clampf(f.y, -1.0, 1.0)), e)
	else:  # FLY_OUT: fixed home target
		_view_origin = _fly_from_origin.lerp(_fly_to_origin, e)
		_yaw = lerp_angle(_fly_from_yaw, _fly_to_yaw, e)
		_pitch = lerpf(_fly_from_pitch, _fly_to_pitch, e)
	if _fly_t < 1.0:
		return
	if _focus_state == FOCUS_FLY_IN:
		_focus_state = FOCUS_HELD
		_show_planet_info(_focus_planet)
	else:
		_end_focus()

func _show_planet_info(planet: Node3D) -> void:
	_info_label.text = _panel_text(planet.get_meta("data", {}))
	_info_label.visible = true
	_pin_info_panel()

# Pin the panel a fixed distance in front of the camera (lower third) so it
# reads at a consistent size, always fits, and tracks head-look during focus.
func _pin_info_panel() -> void:
	var forward := -_orientation.z
	var down := -_orientation.y
	_info_label.global_position = _view_origin + forward * 2.4 + down * 0.95

# Keep the fill light beside/above the camera so the planet's near face stays
# lit as it revolves in and out of the Sun's direct light.
func _place_focus_light() -> void:
	if not is_instance_valid(_focus_light):
		return
	_focus_light.global_position = _view_origin + (-_orientation.z) * 0.5 + _orientation.y * 0.8

func _end_focus() -> void:
	_focus_state = FOCUS_NONE
	_focus_planet = null
	if is_instance_valid(_focus_light):
		_focus_light.queue_free()
	_focus_light = null
	_reticle.visible = true
	_gazed = null
	_dwell = 0.0

func _planet_radius(planet: Node3D) -> float:
	var data: Dictionary = planet.get_meta("data", {})
	var base: float = data.get("radius", 0.3) if not data.is_empty() else 0.3
	return base * planet.scale.x

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
	# Taps during the fly animation are ignored.
	if _focus_state == FOCUS_HELD:
		_begin_return()
	elif _focus_state == FOCUS_NONE and _solar != null:
		_solar.set_true_scale(not _solar.is_true_scale())
