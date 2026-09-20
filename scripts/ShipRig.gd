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
## Starting ship position (the ship, not the camera — cameras sit chase_back
## units behind and chase_up units above this point).
@export var spawn_position: Vector3 = Vector3(0.0, 2.0, 8.0)
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
## Max angular rate (rad/s) at which the ship hull follows head look.
## Cameras still track head instantly; the hull lags, so glancing sideways
## reveals the wing before the ship catches up.
@export var ship_turn_rate: float = 2.4

# --- Ship visual model (Kenney Space Kit, CC0 — see models/kenney_space_kit/LICENSE.txt) ---
## Path to the .glb hull model. Any craft_*.glb from Kenney's Space Kit works.
@export_file("*.glb") var ship_model_path: String = "res://models/kenney_space_kit/craft_speederA.glb"
## Uniform scale applied to the imported model.
@export var ship_scale: float = 1.0
## Corrective rotation for the imported model if it doesn't face -Z (Godot
## forward) out of the box. Kenney speeders usually don't need this; if the
## ship appears to be flying backward, set the Y component to 180.
@export var ship_model_rotation_deg: Vector3 = Vector3.ZERO

# --- Chase camera (third-person) ---
## Camera stand-off behind the ship, along the ship's local +Z (backward).
@export var chase_back: float = 3.5
## Camera height above the ship, along the ship's local +Y.
@export var chase_up: float = 1.4

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
var _yaw: float = 0.0        # head yaw (drives cameras)
var _pitch: float = 0.0      # head pitch (drives cameras)
var _ship_yaw: float = 0.0   # hull yaw (drives thrust + hull mesh; lags head)
var _ship_pitch: float = 0.0 # hull pitch
var _thrusting: bool = false
var _fuel: float = 0.0

# Procedural ship hull (parented to _ship_root, moved/rotated each frame).
var _ship_root: Node3D = null
var _engine_glow: OmniLight3D = null
var _engine_core: MeshInstance3D = null

# HUD (world-space, shared by both eyes).
var _reticle: MeshInstance3D = null
var _hud_speed: Label3D = null
var _hud_target: Label3D = null
var _hud_hint: Label3D = null
var _fuel_bar_bg: MeshInstance3D = null
var _fuel_bar_fill: MeshInstance3D = null


func _ready() -> void:
	_pos = spawn_position
	_fuel = fuel_capacity
	_build_eyes()
	_build_world()
	_build_ship_model()
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


# ---- Ship hull (Kenney .glb model, third-person) ----
#
# _ship_root sits at the ship's world position and is oriented by
# (_ship_yaw, _ship_pitch). The imported .glb is centered inside it so the
# ship IS the origin of the world; the two cameras sit chase_back units
# behind and chase_up units above along ship-local axes. Engine glow rides
# at the ship's tail (+Z in ship-local, since Godot forward is -Z).

func _build_ship_model() -> void:
	_ship_root = Node3D.new()
	_left_viewport.add_child(_ship_root)

	var hull_holder := Node3D.new()
	hull_holder.name = "HullHolder"
	hull_holder.scale = Vector3.ONE * ship_scale
	hull_holder.rotation = Vector3(
		deg_to_rad(ship_model_rotation_deg.x),
		deg_to_rad(ship_model_rotation_deg.y),
		deg_to_rad(ship_model_rotation_deg.z),
	)
	_ship_root.add_child(hull_holder)

	var packed := load(ship_model_path) as PackedScene
	if packed != null:
		var instance := packed.instantiate()
		hull_holder.add_child(instance)
		# Kenney's glb models often have their pivot at a corner or the model
		# center offset from origin; auto-center it so the visible hull sits on
		# the ship's world position instead of drifting off to one side.
		call_deferred("_recenter_model", instance)
	else:
		push_warning("ShipRig: could not load %s" % ship_model_path)

	# Rear engine glow — a small emissive core + an OmniLight that pulse with
	# the throttle. Positioned in ship-local coords a bit behind the model
	# center so they read as engine exhaust.
	_engine_core = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.10 * ship_scale
	s.height = 0.20 * ship_scale
	_engine_core.mesh = s
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.0, 0.55, 0.2, 1.0)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.5, 0.15, 1.0)
	em.emission_energy_multiplier = 0.4
	_engine_core.material_override = em
	_engine_core.position = Vector3(0.0, 0.0, 0.6 * ship_scale)
	_ship_root.add_child(_engine_core)

	_engine_glow = OmniLight3D.new()
	_engine_glow.omni_range = 6.0
	_engine_glow.light_energy = 0.0
	_engine_glow.light_color = Color(1.0, 0.55, 0.25)
	_engine_glow.position = Vector3(0.0, 0.0, 0.8 * ship_scale)
	_ship_root.add_child(_engine_glow)


# Called via call_deferred so the tree/transforms are settled. Walks every
# MeshInstance3D inside the imported model, computes the combined AABB in the
# instance's local frame, and shifts the instance so that AABB is centered on
# its own origin — which is our hull_holder origin.
func _recenter_model(instance: Node3D) -> void:
	if not is_instance_valid(instance):
		return
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var inv := instance.global_transform.affine_inverse()
	var aabb: AABB
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		var xform := inv * mi.global_transform
		var mi_aabb := xform * mi.get_aabb()
		if first:
			aabb = mi_aabb
			first = false
		else:
			aabb = aabb.merge(mi_aabb)
	if aabb.size.length() > 0.001:
		instance.position -= aabb.get_center()


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
	# Ship hull orientation lags head orientation at a bounded angular rate.
	_ship_yaw = _step_toward_angle(_ship_yaw, _yaw, ship_turn_rate * delta)
	_ship_pitch = clampf(_step_toward(_ship_pitch, _pitch, ship_turn_rate * delta), -1.4, 1.4)

	var ship_forward := -_ship_basis().z

	if _thrusting and _fuel > 0.0:
		_vel += ship_forward * thrust_accel * delta
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

	# Sync the hull mesh to the ship transform.
	if _ship_root != null:
		_ship_root.global_transform = Transform3D(_ship_basis(), _pos)

	# Engine glow ramps with thrust state (light is parented to _ship_root).
	if _engine_glow != null:
		var target: float = 1.6 if (_thrusting and _fuel > 0.0) else 0.0
		_engine_glow.light_energy = lerpf(_engine_glow.light_energy, target, 0.25)
	if _engine_core != null:
		var mat := _engine_core.material_override as StandardMaterial3D
		if mat != null:
			var e_target: float = 1.8 if (_thrusting and _fuel > 0.0) else 0.4
			mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, e_target, 0.25)


# Head-look basis (drives the two eye cameras).
func _orient_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


# Ship-hull basis (drives thrust direction and the visible hull).
func _ship_basis() -> Basis:
	return Basis(Vector3.UP, _ship_yaw) * Basis(Vector3.RIGHT, _ship_pitch)


func _step_toward(cur: float, target: float, max_step: float) -> float:
	return cur + clampf(target - cur, -max_step, max_step)


# Wrap the angular difference into (-PI, PI] before clamping so a 179°→−179°
# hop takes the short way around.
func _step_toward_angle(cur: float, target: float, max_step: float) -> float:
	var diff := wrapf(target - cur, -PI, PI)
	return cur + clampf(diff, -max_step, max_step)


func _update_cameras() -> void:
	var orient := _orient_basis()
	var right := orient.x
	var cam_center := _camera_center()
	var left_pos := cam_center - right * (ipd * 0.5)
	var right_pos := cam_center + right * (ipd * 0.5)
	_left_cam.global_transform = Transform3D(orient, left_pos)
	_right_cam.global_transform = Transform3D(orient, right_pos)


# Cameras sit chase_back units behind the ship and chase_up units above it,
# in the ship's local frame. So as the ship banks/yaws, the cameras follow
# behind it. Head-look rotates the view direction on top of that.
func _camera_center() -> Vector3:
	var sb := _ship_basis()
	return _pos + sb.y * chase_up + sb.z * chase_back


func _update_hud() -> void:
	var orient := _orient_basis()
	var forward := -orient.z
	var up := orient.y
	var right := orient.x
	var cam := _camera_center()

	# Reticle sits ~2m in front of the camera.
	var center := cam + forward * 2.0
	_reticle.global_position = center

	# Speed readout, upper-left of the field.
	_hud_speed.global_position = cam + forward * 2.4 + up * 0.9 - right * 0.9
	_hud_speed.text = "%.1f u/s" % _vel.length()

	# Nearest planet readout, upper-right.
	_hud_target.global_position = cam + forward * 2.4 + up * 0.9 + right * 0.9
	_hud_target.text = _nearest_planet_text()

	# Fuel bar, lower-center. Scale the fill quad on X to reflect fuel level.
	var bar_center := cam + forward * 2.4 - up * 0.85
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
	_hud_hint.global_position = cam + forward * 2.4 - up * 1.05
	_hud_hint.text = "HOLD to thrust  •  approach ☀ to refuel"


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
