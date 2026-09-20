extends Node
## Spaceship VR rig: you pilot a ship through the solar system.
##
## Reuses the DIY stereo eye pattern from VRRig (two SubViewports through a
## barrel-distortion shader, sharing the root World3D). Head orientation comes
## from the gyroscope (mouse-drag on desktop) and steers the ship — thrust is
## applied along the look direction while the Cardboard button (screen tap /
## Space) is held down. Arcade drag decays velocity so controls stay forgiving,
## a max-speed clamp keeps things bounded, and fuel drains while thrusting and
## refills as you approach the Sun.
##
## HUD is rendered via world-space Label3D/MeshInstance3D nodes anchored a fixed
## distance in front of the ship, so both eye cameras see the same overlay
## without any per-eye UI plumbing.

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")
const LENS_SHADER := preload("res://shaders/lens_distortion.gdshader")

# --- Stereo / head-look tuning (mirrors VRRig defaults) ---
@export var ipd: float = 0.064
@export var eye_fov: float = 80.0
@export var use_gyroscope: bool = true
@export_range(0, 2) var gyro_yaw_axis: int = 1
@export_range(0, 2) var gyro_pitch_axis: int = 0
@export var gyro_yaw_sign: float = 1.0
@export var gyro_pitch_sign: float = 1.0

# --- Ship physics ---
## Starting position — behind Earth, looking toward the Sun.
@export var spawn_position: Vector3 = Vector3(0.0, 3.0, 12.0)
## Thrust acceleration (world units / s²).
@export var thrust_accel: float = 8.0
## Peak speed clamp.
@export var max_speed: float = 30.0
## Fraction of velocity lost per second (arcade drag).
@export var drag_per_sec: float = 0.35
## Full tank size.
@export var fuel_capacity: float = 100.0
## Fuel drained per second while thrusting.
@export var fuel_burn_per_sec: float = 4.0
## Fuel gained per second when very close to the Sun (scaled by proximity).
@export var solar_refuel_per_sec: float = 20.0
## Distance from the Sun (world units) at which refueling starts.
@export var refuel_radius: float = 8.0

var _left_viewport: SubViewport
var _right_viewport: SubViewport
var _left_cam: Camera3D
var _right_cam: Camera3D
var _left_rect: TextureRect
var _right_rect: TextureRect

var _solar: Node3D = null
var _planets: Array[Node3D] = []
var _sun: Node3D = null

# Ship state.
var _pos: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _thrusting: bool = false
var _fuel: float = 0.0

# HUD (world-space, shared by both eyes).
var _reticle: MeshInstance3D = null
var _hud_speed: Label3D = null
var _hud_target: Label3D = null
var _hud_hint: Label3D = null
var _fuel_bar_bg: MeshInstance3D = null
var _fuel_bar_fill: MeshInstance3D = null
var _thrust_light: OmniLight3D = null


func _ready() -> void:
	_pos = spawn_position
	_fuel = fuel_capacity
	_build_eyes()
	_build_world()
	_build_hud()
	_build_menu_overlay()
	_layout()
	get_viewport().size_changed.connect(_layout)


# ---- Stereo rendering plumbing (parallel to VRRig) ----

func _build_eyes() -> void:
	_left_viewport = _make_eye_viewport()
	_left_cam = _make_eye_camera(_left_viewport)
	_right_viewport = _make_eye_viewport()
	_right_cam = _make_eye_camera(_right_viewport)
	_left_rect = _make_eye_rect(_left_viewport)
	_right_rect = _make_eye_rect(_right_viewport)


func _make_eye_viewport() -> SubViewport:
	var vp := SubViewport.new()
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
	var env := WorldEnvironment.new()
	env.set_script(SpaceEnvScript)
	_left_viewport.add_child(env)

	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	_left_viewport.add_child(_solar)
	_planets = _solar.get_planet_bodies()
	_sun = _solar.get_node_or_null("Sun") as Node3D


func _layout() -> void:
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


# ---- HUD ----

func _build_hud() -> void:
	# Small crosshair-like reticle.
	_reticle = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.015
	dot.height = 0.03
	_reticle.mesh = dot
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.6, 1.0, 0.7, 0.85)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.disable_receive_shadows = true
	_reticle.material_override = rmat
	_left_viewport.add_child(_reticle)

	_hud_speed = _make_hud_label(36)
	_hud_target = _make_hud_label(32)
	_hud_hint = _make_hud_label(28)
	_hud_hint.modulate = Color(1, 1, 1, 0.7)

	# Fuel bar: two flat quads (background + fill), unshaded.
	_fuel_bar_bg = _make_bar(Color(0.15, 0.15, 0.2, 0.7))
	_fuel_bar_fill = _make_bar(Color(0.35, 0.9, 0.55, 0.95))

	# Warm glow when thrusting — a small, brief light attached to the ship.
	_thrust_light = OmniLight3D.new()
	_thrust_light.omni_range = 6.0
	_thrust_light.light_energy = 0.0
	_thrust_light.light_color = Color(1.0, 0.75, 0.4)
	_left_viewport.add_child(_thrust_light)


func _make_hud_label(size: int) -> Label3D:
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.0028
	lbl.font_size = size
	lbl.outline_size = 8
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_viewport.add_child(lbl)
	return lbl


func _make_bar(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 0.09)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	mat.no_depth_test = true
	# QuadMesh faces one direction; disable culling so the bar is visible no
	# matter which way the transform basis flips it against the camera.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	_left_viewport.add_child(mi)
	return mi


# ---- Menu back button ----

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


# ---- Per-frame update ----

func _process(delta: float) -> void:
	_update_orientation(delta)
	_update_ship(delta)
	_update_cameras()
	_update_hud()


func _update_orientation(delta: float) -> void:
	if use_gyroscope:
		var g := Input.get_gyroscope()
		_yaw += g[gyro_yaw_axis] * gyro_yaw_sign * delta
		_pitch += g[gyro_pitch_axis] * gyro_pitch_sign * delta
	_pitch = clampf(_pitch, -1.4, 1.4)


func _update_ship(delta: float) -> void:
	var orient := _orient_basis()
	var forward := -orient.z

	if _thrusting and _fuel > 0.0:
		_vel += forward * thrust_accel * delta
		_fuel = maxf(0.0, _fuel - fuel_burn_per_sec * delta)

	var drag_factor := clampf(1.0 - drag_per_sec * delta, 0.0, 1.0)
	_vel *= drag_factor

	var speed := _vel.length()
	if speed > max_speed:
		_vel = _vel.normalized() * max_speed

	_pos += _vel * delta

	if _sun != null:
		var d := _pos.distance_to(_sun.global_position)
		if d < refuel_radius:
			var pull := 1.0 - clampf(d / refuel_radius, 0.0, 1.0)
			_fuel = minf(fuel_capacity, _fuel + solar_refuel_per_sec * pull * delta)


func _orient_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


func _update_cameras() -> void:
	var orient := _orient_basis()
	var right := orient.x
	var left_pos := _pos - right * (ipd * 0.5)
	var right_pos := _pos + right * (ipd * 0.5)
	_left_cam.global_transform = Transform3D(orient, left_pos)
	_right_cam.global_transform = Transform3D(orient, right_pos)


func _update_hud() -> void:
	var orient := _orient_basis()
	var forward := -orient.z
	var up := orient.y
	var right := orient.x

	# Reticle sits ~2m in front of the ship.
	var center := _pos + forward * 2.0
	_reticle.global_position = center

	# Speed readout, upper-left of the field.
	_hud_speed.global_position = _pos + forward * 2.4 + up * 0.9 - right * 0.9
	_hud_speed.text = "%.1f u/s" % _vel.length()

	# Nearest planet readout, upper-right.
	_hud_target.global_position = _pos + forward * 2.4 + up * 0.9 + right * 0.9
	_hud_target.text = _nearest_planet_text()

	# Fuel bar, lower-center. Scale the fill quad on X to reflect fuel level.
	var bar_center := _pos + forward * 2.4 - up * 0.85
	_fuel_bar_bg.global_transform = Transform3D(orient, bar_center)
	var fill_frac := clampf(_fuel / fuel_capacity, 0.0, 1.0)
	# Anchor the fill to the left edge of the bar so it drains rightward.
	var half_w := 1.4 * 0.5
	var fill_offset := right * (-half_w + half_w * fill_frac)
	var fill_basis := orient.scaled(Vector3(maxf(fill_frac, 0.0001), 1.0, 1.0))
	_fuel_bar_fill.global_transform = Transform3D(fill_basis, bar_center + fill_offset)
	# Fill turns amber below 30% as a low-fuel warning.
	var mat := _fuel_bar_fill.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.9, 0.55, 0.2, 0.95) if fill_frac < 0.3 else Color(0.35, 0.9, 0.55, 0.95)

	# Hint text under the bar.
	_hud_hint.global_position = _pos + forward * 2.4 - up * 1.05
	_hud_hint.text = "HOLD to thrust  •  approach ☀ to refuel"

	# Thrust light glow — pulsing when engaged.
	if _thrusting and _fuel > 0.0:
		_thrust_light.light_energy = lerpf(_thrust_light.light_energy, 1.4, 0.3)
	else:
		_thrust_light.light_energy = lerpf(_thrust_light.light_energy, 0.0, 0.2)
	_thrust_light.global_position = _pos + forward * 0.4


func _nearest_planet_text() -> String:
	if _planets.is_empty():
		return ""
	var best: Node3D = null
	var best_d := INF
	for p in _planets:
		var d := _pos.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		return ""
	var data: Dictionary = best.get_meta("data", {})
	var label: String = String(data.get("name", best.name)) if not data.is_empty() else String(best.name)
	return "%s\n%.1f u" % [label, best_d]


# ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventScreenTouch:
		_thrusting = event.pressed
	elif event is InputEventKey and event.keycode == KEY_SPACE:
		_thrusting = event.pressed
