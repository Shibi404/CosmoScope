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

var _left_viewport: SubViewport
var _right_viewport: SubViewport
var _left_cam: Camera3D
var _right_cam: Camera3D
var _left_rect: TextureRect
var _right_rect: TextureRect

var _solar: Node3D
var _reticle: MeshInstance3D
var _info_label: Label3D
var _planets: Array[Node3D] = []

var _orientation: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _pitch: float = 0.0
var _gazed: Node3D = null
var _dwell: float = 0.0

func _ready() -> void:
	_build_eyes()
	_build_world()
	_build_gaze_ui()
	_layout()
	get_viewport().size_changed.connect(_layout)

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
	_info_label.pixel_size = 0.005
	_info_label.font_size = 64
	_info_label.outline_size = 12
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
	_update_gaze(delta)

func _update_orientation(delta: float) -> void:
	var gyro := Input.get_gyroscope() if use_gyroscope else Vector3.ZERO
	if use_gyroscope and gyro.length() > 0.0001:
		# Integrate angular velocity (rad/s) in the head's own frame.
		# Axis signs may need per-device tuning.
		_orientation = _orientation.rotated(_orientation.x, -gyro.x * delta)
		_orientation = _orientation.rotated(_orientation.y, -gyro.y * delta)
		_orientation = _orientation.rotated(_orientation.z, -gyro.z * delta)
		_orientation = _orientation.orthonormalized()
	else:
		# Desktop/editor fallback: drag to look.
		_orientation = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

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
		_info_label.visible = false
	elif best != null:
		_dwell += delta
		if _dwell >= gaze_dwell_time and not _info_label.visible:
			_show_info(best)

func _show_info(planet: Node3D) -> void:
	_info_label.text = "%s\n%s" % [planet.name, planet.get_meta("fact", "")]
	_info_label.global_position = planet.global_position + Vector3(0.0, 1.2, 0.0)
	_info_label.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 1.4)
