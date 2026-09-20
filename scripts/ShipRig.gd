extends Node
## Spaceship rig: you pilot a ship through the solar system.
##
## Renders through a single fullscreen SubViewport (no Cardboard split-screen,
## no barrel-distortion shader — that layout belongs to the observer VRRig).
## Head-look is driven by the gyroscope on mobile / left-mouse drag on desktop
## and pans the camera relative to the ship. A/D yaw the hull, W/S pitch it,
## and Space thrusts along ship-forward. Arcade drag decays velocity, a
## max-speed clamp keeps things bounded, and fuel drains while thrusting and
## refills near the Sun.
##
## HUD is a 2D screen-space overlay on its own CanvasLayer — speed, fuel bar,
## nearest planet + distance, and the control hint stay fixed on screen no
## matter what the 3D camera is doing.

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")
const MissionsScript := preload("res://scripts/ShipMissions.gd")
const XRGameScript := preload("res://scripts/xr/XRGame.gd")

# --- Head-look tuning ---
@export var fov: float = 75.0
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
@export var thrust_accel: float = 2.5
## Peak speed clamp.
@export var max_speed: float = 8.0
## Fraction of velocity lost per second (arcade drag).
@export var drag_per_sec: float = 0.25
## Full tank size.
@export var fuel_capacity: float = 100.0
## Fuel drained per second while thrusting.
@export var fuel_burn_per_sec: float = 4.0
## Fuel gained per second when very close to the Sun (scaled by proximity).
@export var solar_refuel_per_sec: float = 20.0
## Distance from the Sun (world units) at which refueling starts.
@export var refuel_radius: float = 8.0
## Yaw / pitch rate (rad/s) applied while A/D / W/S are held.
@export var steer_rate: float = 1.6
## Collision sphere radius for the ship. Approximate hull half-extent so we can
## stop the ship at planet surfaces without a full physics setup.
@export var ship_radius: float = 0.35
## Extra buffer added to collision so the ship stops just outside the surface
## rather than intersecting it.
@export var collision_skin: float = 0.15
## Desktop mouse flight: the cursor steers (offset from screen centre), hold
## left click to thrust, right-drag to look around. Toggle with M.
@export var mouse_flight: bool = true
## VR: "auto" starts OpenXR when a headset / runtime is present and otherwise keeps the
## normal desktop / phone mode; "off" never uses VR; "simulate" builds the full VR rig
## (cockpit, hands, HUD panel) without a headset, for testing.
@export_enum("auto", "off", "simulate") var vr_mode: String = "auto"
## Fraction of the half-screen around the centre where the cursor does nothing.
@export_range(0.0, 0.5) var mouse_deadzone: float = 0.10

# --- Ship visual model (Kenney Space Kit, CC0 — see models/kenney_space_kit/LICENSE.txt) ---
## Path to the .glb hull model. Any craft_*.glb from Kenney's Space Kit works.
@export_file("*.glb") var ship_model_path: String = "res://models/kenney_space_kit/craft_speederA.glb"
## Uniform scale applied to the imported model.
@export var ship_scale: float = 0.5
## Corrective rotation for the imported model if it doesn't face -Z (Godot
## forward) out of the box. Kenney speeders usually don't need this; if the
## ship appears to be flying backward, set the Y component to 180.
@export var ship_model_rotation_deg: Vector3 = Vector3.ZERO

# --- Chase camera (third-person) ---
## Camera stand-off behind the ship, along the ship's local +Z (backward).
@export var chase_back: float = 2.5
## Camera height above the ship, along the ship's local +Y.
@export var chase_up: float = 1.0

var _left_viewport: Node   # world container: a SubViewport on desktop / phone, a Node3D in VR (name kept so
                                  # existing add_child call sites stay stable)
var _left_cam: Camera3D
var _left_rect: TextureRect

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

# HUD (2D, screen-space — anchored via CanvasLayer so it stays put regardless
# of what the 3D camera is doing).
var _hud_layer: CanvasLayer = null
var _hud_speed: Label = null
var _hud_target: Label = null
var _hud_hint: Label = null
var _fuel_bar: ProgressBar = null
var _fuel_bar_label: Label = null

# Game layer: docking, scanner, missions (see ShipMissions.gd).
var _missions: Node = null

# VR layer (XRGame) or null when running in the normal desktop / phone mode.
var _vr: Node = null
## Thrust multiplier 0..1 (VR throttle lever; 1 on desktop / phone).
var _throttle: float = 1.0
## External steering added to the keyboard / mouse input (VR flight stick), -1..1.
var ext_yaw: float = 0.0
var ext_pitch: float = 0.0


func _ready() -> void:
	_pos = spawn_position
	_fuel = fuel_capacity
	_vr = XRGameScript.create(self)
	if _vr != null:
		add_child(_vr)
	_build_view()
	_build_world()
	_build_ship_model()
	_build_hud()
	_missions = MissionsScript.new()
	_missions.rig = self
	add_child(_missions)
	if _vr != null:
		_vr.finish(_missions)
	_build_menu_overlay()
	_layout()
	get_viewport().size_changed.connect(_layout)


# ---- Rendering plumbing (single fullscreen viewport + camera) ----

func _build_view() -> void:
	if _vr != null:
		# VR: the world lives in the main viewport, seen through the XR camera.
		var world := Node3D.new()
		world.name = "World"
		add_child(world)
		_left_viewport = world
		_vr.attach_world(world)
		_left_cam = _vr.player.camera
		get_viewport().msaa_3d = Viewport.MSAA_2X
		return
	_left_viewport = SubViewport.new()
	_left_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_left_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_left_viewport)

	_left_cam = Camera3D.new()
	_left_cam.fov = fov
	_left_cam.current = true
	_left_viewport.add_child(_left_cam)

	_left_rect = TextureRect.new()
	_left_rect.texture = _left_viewport.get_texture()
	_left_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_left_rect)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.set_script(SpaceEnvScript)
	_left_viewport.add_child(env)

	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	_left_viewport.add_child(_solar)
	_planets = _solar.get_planet_bodies()
	_sun = _solar.get_node_or_null("Sun") as Node3D


# In VR the HUD's CanvasLayers live inside the HUD panel's SubViewport instead of the screen.
func _hud_parent() -> Node:
	if _vr != null:
		return _vr.hud_viewport()
	return self


func _layout() -> void:
	if _vr != null:
		return
	var view := get_viewport().get_visible_rect().size
	var full_w := int(view.x)
	var full_h := int(view.y)
	if full_w <= 0 or full_h <= 0:
		return
	_left_viewport.size = Vector2i(full_w, full_h)
	_left_rect.position = Vector2.ZERO
	_left_rect.size = Vector2(full_w, full_h)


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
	# In VR the cockpit is the ship: the outer hull mesh would surround the player.
	hull_holder.visible = _vr == null

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


# ---- HUD (2D screen-space overlay) ----

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10  # under the menu back button (which lives at layer 20)
	_hud_parent().add_child(_hud_layer)

	_hud_speed = _make_hud_label(24, Color(0.85, 0.95, 1.0))
	_hud_speed.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud_speed.position = Vector2(120, 16)
	_hud_speed.size = Vector2(220, 32)
	_hud_layer.add_child(_hud_speed)

	_hud_target = _make_hud_label(22, Color(0.85, 0.95, 1.0))
	_hud_target.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_target.position = Vector2(-260, 16)
	_hud_target.size = Vector2(240, 48)
	_hud_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_layer.add_child(_hud_target)

	# Fuel bar — a proper ProgressBar so the fill is pixel-accurate.
	var fuel_root := VBoxContainer.new()
	fuel_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	fuel_root.position = Vector2(-180, -70)
	fuel_root.size = Vector2(360, 44)
	fuel_root.add_theme_constant_override("separation", 2)
	_hud_layer.add_child(fuel_root)

	_fuel_bar_label = _make_hud_label(14, Color(0.7, 0.85, 0.95))
	_fuel_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fuel_bar_label.custom_minimum_size = Vector2(0, 18)
	fuel_root.add_child(_fuel_bar_label)

	_fuel_bar = ProgressBar.new()
	_fuel_bar.min_value = 0.0
	_fuel_bar.max_value = fuel_capacity
	_fuel_bar.value = _fuel
	_fuel_bar.show_percentage = false
	_fuel_bar.custom_minimum_size = Vector2(360, 18)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.07, 0.12, 0.75)
	bg_style.border_color = Color(0.4, 0.5, 0.7, 0.6)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	_fuel_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.35, 0.9, 0.55, 0.95)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	_fuel_bar.add_theme_stylebox_override("fill", fill_style)
	fuel_root.add_child(_fuel_bar)

	_hud_hint = _make_hud_label(13, Color(0.7, 0.78, 0.9, 0.75))
	_hud_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_hint.position = Vector2(-260, -32)
	_hud_hint.size = Vector2(520, 20)
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_hud_hint)


func _make_hud_label(size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


# ---- Menu back button ----

func _build_menu_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_hud_parent().add_child(layer)

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
	back_btn.visible = _vr == null   # the 2D menu is not usable in a headset
	layer.add_child(back_btn)


# ---- Per-frame update ----

func _process(delta: float) -> void:
	if _vr != null:
		_vr.update(delta)
	_missions.update(delta)
	_update_orientation(delta)
	_update_ship(delta)
	_update_cameras()
	_update_hud()


func _update_orientation(delta: float) -> void:
	if use_gyroscope and _vr == null:
		var g := Input.get_gyroscope()
		_yaw += g[gyro_yaw_axis] * gyro_yaw_sign * delta
		_pitch += g[gyro_pitch_axis] * gyro_pitch_sign * delta
	_pitch = clampf(_pitch, -1.4, 1.4)


func _update_ship(delta: float) -> void:
	# Steering: A/D yaw the ship left/right, W/S pitch the nose up/down.
	# Head-look stays a pure camera — you steer with the keys, look with the
	# mouse/gyro.
	var yaw_input := 0.0
	var pitch_input := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		yaw_input += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		yaw_input -= 1.0
	if Input.is_physical_key_pressed(KEY_W):
		pitch_input -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pitch_input += 1.0
	# Mouse flight: cursor offset from screen centre sets turn rate.
	# Autopilot / docked / rover-cam own the hull: ignore manual steering then.
	var manual: bool = not _missions.hold_ship and not _missions.autopilot_active
	if not manual:
		yaw_input = 0.0
		pitch_input = 0.0
	if manual and _vr == null and not _missions.dialog_open and mouse_flight and not OS.has_feature("mobile"):
		var vp := get_viewport()
		var half := vp.get_visible_rect().size * 0.5
		var mp := vp.get_mouse_position()
		if half.x > 0.0 and half.y > 0.0 and Rect2(Vector2.ZERO, half * 2.0).has_point(mp):
			var off := (mp - half) / half
			yaw_input -= _mouse_axis(off.x)
			pitch_input -= _mouse_axis(off.y)
	if manual:
		yaw_input += ext_yaw
		pitch_input += ext_pitch
	_ship_yaw += yaw_input * steer_rate * delta
	_ship_pitch = clampf(_ship_pitch + pitch_input * steer_rate * delta, -1.4, 1.4)

	# Docked: ShipMissions drives position/heading; just keep the hull in sync.
	if _missions.hold_ship:
		_vel = Vector3.ZERO
		_ship_root.global_transform = Transform3D(_ship_basis(), _pos)
		_engine_glow.light_energy = 0.0
		return

	var ship_forward := -_ship_basis().z

	if _thrusting and _fuel > 0.0:
		_vel += ship_forward * thrust_accel * _throttle * delta
		_fuel = maxf(0.0, _fuel - fuel_burn_per_sec * _throttle * delta)

	var drag_factor := clampf(1.0 - drag_per_sec * delta, 0.0, 1.0)
	_vel *= drag_factor

	var speed := _vel.length()
	if speed > max_speed:
		_vel = _vel.normalized() * max_speed

	_pos += _vel * delta

	_resolve_collisions()

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


# Simple sphere-vs-sphere collision so the ship stops at planet surfaces
# instead of flying through them. No physics engine involved — after the
# velocity integration step we push _pos out to (body_center + surface + skin)
# for any body we've penetrated, and zero out the velocity component that was
# aimed into the body so we slide tangentially instead of sticking.

func _resolve_collisions() -> void:
	if _sun != null:
		_push_out_of(_sun.global_position, _body_radius(_sun))
	for p in _planets:
		if p != null:
			_push_out_of(p.global_position, _body_radius(p))


func _push_out_of(center: Vector3, radius: float) -> void:
	var min_dist := radius + ship_radius + collision_skin
	var offset := _pos - center
	var dist := offset.length()
	if dist > 0.0001 and dist < min_dist:
		var n := offset / dist
		_pos = center + n * min_dist
		var into := _vel.dot(n)
		if into < 0.0:
			_vel -= n * into


# Radius of a body in world units, factoring in whatever scale the SolarSystem
# has applied for the enhanced/true-scale morph. Falls back to the Sun's known
# radius (2.0) when the body carries no metadata.
func _body_radius(body: Node3D) -> float:
	var data: Dictionary = body.get_meta("data", {})
	var base: float = 2.0
	if not data.is_empty():
		base = float(data.get("radius", 2.0))
	return base * body.scale.x


# Head-look basis, expressed in the ship's local frame — pure "look-around"
# on top of whatever direction the ship is facing.
func _head_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


# Ship-hull basis (drives thrust direction and the visible hull).
func _ship_basis() -> Basis:
	return Basis(Vector3.UP, _ship_yaw) * Basis(Vector3.RIGHT, _ship_pitch)


# Camera basis in world coords: head-look composed on top of ship orientation.
# With the head at neutral, this equals the ship's basis (view looks straight
# down the ship's forward), so rotating the ship rotates the view too. Mouse /
# gyro just adds a local pan on top.
func _orient_basis() -> Basis:
	return _ship_basis() * _head_basis()


func _update_cameras() -> void:
	if _vr != null:
		_vr.sync_origin()   # the head camera is driven by the headset; the player rides the ship
		return
	_left_cam.global_transform = Transform3D(_orient_basis(), _camera_center())


# Cameras sit chase_back units behind the ship and chase_up units above it,
# in the ship's local frame. So as the ship banks/yaws, the cameras follow
# behind it. Head-look rotates the view direction on top of that.
func _camera_center() -> Vector3:
	var sb := _ship_basis()
	return _pos + sb.y * chase_up + sb.z * chase_back


func _update_hud() -> void:
	_hud_speed.text = "SPD  %.1f u/s" % _vel.length()
	_hud_target.text = _nearest_planet_text()
	_fuel_bar.value = _fuel
	_fuel_bar_label.text = "FUEL  %d / %d" % [int(round(_fuel)), int(round(fuel_capacity))]
	# Fill turns amber below 30% as a low-fuel warning.
	var fill_style := _fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		var frac := _fuel / fuel_capacity if fuel_capacity > 0.0 else 0.0
		fill_style.bg_color = Color(0.9, 0.55, 0.2, 0.95) if frac < 0.3 else Color(0.35, 0.9, 0.55, 0.95)
	if _vr != null:
		_hud_hint.text = "VR: grab the throttle + stick  •  poke the console  •  point + trigger on a planet to travel  •  gaze to scan"
	elif mouse_flight and not _missions.hold_ship and not OS.has_feature("mobile"):
		_hud_hint.text = "MOUSE steer  •  HOLD LEFT CLICK / SPACE thrust  •  RIGHT-DRAG look  •  CLICK A PLANET to auto-travel  •  E dock"
	else:
		_hud_hint.text = "A/D steer  •  W/S pitch  •  SPACE thrust  •  E dock  •  T travel to gazed planet  •  M mouse mode"


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

# Deadzone + smooth response curve for a cursor axis in -1..1.
func _mouse_axis(v: float) -> float:
	var a := absf(v)
	if a <= mouse_deadzone:
		return 0.0
	var t := clampf((a - mouse_deadzone) / (1.0 - mouse_deadzone), 0.0, 1.0)
	return signf(v) * t * t


func _unhandled_input(event: InputEvent) -> void:
	# Head-look drag: right button in mouse-flight mode, left button otherwise.
	var look_mask: int = MOUSE_BUTTON_MASK_RIGHT if mouse_flight else MOUSE_BUTTON_MASK_LEFT
	if event is InputEventMouseMotion and (event.button_mask & look_mask):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventMouseButton and mouse_flight and event.button_index == MOUSE_BUTTON_LEFT:
		_thrusting = event.pressed
	elif event is InputEventScreenTouch:
		_thrusting = event.pressed
	elif event is InputEventKey and event.keycode == KEY_SPACE:
		_thrusting = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		mouse_flight = not mouse_flight
		_thrusting = false
