extends Node3D
## AR Mode for CosmoScope — fully compatible with mobile ARCore and desktop/laptop preview.
##
## On desktop/laptop: renders the 3D Solar System hovering over a 3D table grid
## plane with full mouse controls (drag to rotate, scroll to zoom, click planet for info).
## On mobile: connects to ARCore/ARKit plane tracking when available.

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")

@export var try_real_ar: bool = true
@export var initial_scale: float = 0.8
@export var min_scale: float = 0.1
@export var max_scale: float = 3.0

var _camera: Camera3D
var _solar: Node3D = null
var _grid_plane: MeshInstance3D = null
var _model_scale: float = 0.8
var _model_rotation_y: float = 0.0

# Desktop camera orbit controls.
var _yaw: float = 0.0
var _pitch: float = 0.35  # rad above plane
var _cam_dist: float = 14.0
var _dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

# Touch gesture tracking.
var _touches: Dictionary = {}
var _prev_pinch_dist: float = 0.0

# Info panel UI.
var _info_panel: PanelContainer = null
var _info_label: RichTextLabel = null
var _close_btn: Button = null

# HUD overlay.
var _hud_layer: CanvasLayer = null
var _speed_btn: Button = null
var _planets: Array[Node3D] = []

var _ar_interface: XRInterface = null
var _using_real_ar: bool = false

func _ready() -> void:
	_model_scale = initial_scale
	_try_init_ar()
	_build_camera()
	_build_world()
	_build_3d_table_grid()
	_build_hud()
	_build_info_panel()

func _try_init_ar() -> void:
	if not try_real_ar or OS.get_name() != "Android":
		_using_real_ar = false
		return

	for iface_info in XRServer.get_interfaces():
		var iface_name: String = iface_info.get("name", "")
		if iface_name.contains("ARCore") or iface_name.contains("ARKit"):
			var iface := XRServer.find_interface(iface_name)
			if iface != null and iface.initialize():
				_ar_interface = iface
				_using_real_ar = true
				break

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ARCamera"
	_camera.fov = 65.0
	_update_camera_transform()
	_camera.current = true
	add_child(_camera)

	if _using_real_ar and _ar_interface != null:
		get_viewport().use_xr = true

func _update_camera_transform() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _cam_dist
	_camera.position = Vector3.ZERO + offset
	_camera.look_at(Vector3.ZERO, Vector3.UP)

func _build_world() -> void:
	# Build the shared 3D Solar System content.
	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	_solar.scale = Vector3.ONE * _model_scale
	add_child(_solar)

	# Ensure SolarSystem is initialized and get all selectable planet bodies.
	_planets = _solar.get_planet_bodies()

	# Add bright lighting for AR inspection.
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "ARLight"
	dir_light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	dir_light.light_energy = 1.4
	add_child(dir_light)

	# Add space environment skybox & ambient light.
	var env_node := WorldEnvironment.new()
	env_node.set_script(SpaceEnvScript)
	add_child(env_node)

func _build_3d_table_grid() -> void:
	# A 3D grid plane positioned underneath the solar system to represent an AR detected surface.
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(40.0, 40.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.5, 0.8, 0.15)
	mat.wireframe = true

	_grid_plane = MeshInstance3D.new()
	_grid_plane.name = "TableGrid"
	_grid_plane.mesh = plane_mesh
	_grid_plane.material_override = mat
	_grid_plane.position = Vector3(0.0, -2.5, 0.0)
	add_child(_grid_plane)

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	# Back to Menu button (top-left).
	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "← Menu"
	back_btn.position = Vector2(14, 14)
	back_btn.size = Vector2(100, 38)
	back_btn.add_theme_font_size_override("font_size", 16)

	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.12, 0.15, 0.25, 0.85)
	back_style.corner_radius_top_left = 8
	back_style.corner_radius_top_right = 8
	back_style.corner_radius_bottom_left = 8
	back_style.corner_radius_bottom_right = 8
	back_btn.add_theme_stylebox_override("normal", back_style)

	back_btn.pressed.connect(func():
		Input.action_press("ui_cancel")
		await get_tree().process_frame
		Input.action_release("ui_cancel")
	)
	_hud_layer.add_child(back_btn)

	# Speed control button (top-right).
	_speed_btn = Button.new()
	_speed_btn.name = "SpeedButton"
	_speed_btn.text = "▶ 1×"
	_speed_btn.position = Vector2(-120, 14)
	_speed_btn.size = Vector2(100, 38)
	_speed_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_speed_btn.add_theme_font_size_override("font_size", 14)

	var speed_style := StyleBoxFlat.new()
	speed_style.bg_color = Color(0.1, 0.2, 0.38, 0.85)
	speed_style.corner_radius_top_left = 8
	speed_style.corner_radius_top_right = 8
	speed_style.corner_radius_bottom_left = 8
	speed_style.corner_radius_bottom_right = 8
	_speed_btn.add_theme_stylebox_override("normal", speed_style)

	_speed_btn.pressed.connect(func():
		if _solar != null:
			_solar.cycle_time_scale()
			_speed_btn.text = _solar.get_time_scale_label()
	)
	_hud_layer.add_child(_speed_btn)

	# Mode badge.
	var mode_lbl := Label.new()
	mode_lbl.text = "🔭 AR Mode (Mobile & Laptop Preview)"
	mode_lbl.position = Vector2(14, 58)
	mode_lbl.add_theme_font_size_override("font_size", 13)
	mode_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6, 0.8))
	mode_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(mode_lbl)

	# Instructions at bottom.
	var instr := Label.new()
	instr.text = "Drag: Orbit Camera  •  Scroll/Pinch: Zoom  •  Click planet: Info"
	instr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instr.position = Vector2(-220, -35)
	instr.size = Vector2(440, 25)
	instr.add_theme_font_size_override("font_size", 14)
	instr.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9, 0.75))
	instr.add_theme_color_override("font_outline_color", Color.BLACK)
	instr.add_theme_constant_override("outline_size", 4)
	instr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(instr)

func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanel"
	_info_panel.visible = false
	_info_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_info_panel.position = Vector2(-290, -110)
	_info_panel.size = Vector2(270, 220)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.16, 0.9)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9, 0.5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_info_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_info_panel.add_child(vbox)

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.scroll_active = false
	_info_label.add_theme_font_size_override("normal_font_size", 14)
	_info_label.add_theme_color_override("default_color", Color(0.9, 0.92, 0.98))
	vbox.add_child(_info_label)

	_close_btn = Button.new()
	_close_btn.text = "✕ Close"
	_close_btn.add_theme_font_size_override("font_size", 13)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.35, 0.15, 0.15, 0.7)
	close_style.corner_radius_top_left = 6
	close_style.corner_radius_top_right = 6
	close_style.corner_radius_bottom_left = 6
	close_style.corner_radius_bottom_right = 6
	_close_btn.add_theme_stylebox_override("normal", close_style)
	_close_btn.pressed.connect(func(): _info_panel.visible = false)
	vbox.add_child(_close_btn)

	_hud_layer.add_child(_info_panel)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse drag camera orbit.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_last_mouse_pos = event.position
			else:
				if _dragging and event.position.distance_to(_last_mouse_pos) < 5.0:
					_try_select_planet(event.position)
				_dragging = false

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(4.0, _cam_dist - 1.2)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(35.0, _cam_dist + 1.2)
			_update_camera_transform()

	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		_yaw -= delta.x * 0.005
		_pitch = clampf(_pitch - delta.y * 0.005, -1.4, 1.4)
		_update_camera_transform()

	# Mobile touch gestures.
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				var keys := _touches.keys()
				var p1: Vector2 = _touches[keys[0]]
				var p2: Vector2 = _touches[keys[1]]
				_prev_pinch_dist = p1.distance_to(p2)
		else:
			if _touches.size() == 1 and event.index in _touches:
				_try_select_planet(event.position)
			_touches.erase(event.index)

	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch - event.relative.y * 0.005, -1.4, 1.4)
			_update_camera_transform()
		elif _touches.size() == 2:
			var keys := _touches.keys()
			var p1: Vector2 = _touches[keys[0]]
			var p2: Vector2 = _touches[keys[1]]
			var dist: float = p1.distance_to(p2)
			if _prev_pinch_dist > 10.0:
				var ratio: float = dist / _prev_pinch_dist
				_cam_dist = clampf(_cam_dist / ratio, 4.0, 35.0)
				_update_camera_transform()
			_prev_pinch_dist = dist

func _try_select_planet(screen_pos: Vector2) -> void:
	if _camera == null or _solar == null:
		return

	# Re-fetch planet bodies in case they loaded dynamically.
	if _planets.is_empty():
		_planets = _solar.get_planet_bodies()

	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)

	var best: Node3D = null
	var best_dist: float = 999.0
	for p in _planets:
		if not is_instance_valid(p):
			continue
		var to_planet: Vector3 = p.global_position - from
		var proj: float = to_planet.dot(dir)
		if proj < 0.0:
			continue
		var closest: Vector3 = from + dir * proj
		var dist: float = closest.distance_to(p.global_position)
		var data: Dictionary = p.get_meta("data", {})
		var r: float = data.get("radius", 0.3) * _model_scale * 2.0
		if dist < r and proj < best_dist:
			best = p
			best_dist = proj

	if best != null:
		_show_info(best)
	else:
		_info_panel.visible = false

func _show_info(planet: Node3D) -> void:
	var data: Dictionary = planet.get_meta("data", {})
	if data.is_empty():
		return

	var text := "[b][font_size=18]%s[/font_size][/b]\n\n" % data.name
	if data.has("diameter_km"):
		text += "Diameter: %s km\n" % _commas(data.diameter_km)
	if data.has("sun_dist_mkm"):
		text += "Distance from Sun: %s M km\n" % _trim(data.sun_dist_mkm)
	if data.has("year"):
		text += "Orbital period: %s\n" % data.year
	if data.has("day"):
		text += "Day length: %s\n" % data.day
	if data.has("moons"):
		text += "Moons: %d\n" % data.moons
	if data.has("gravity_g"):
		text += "Gravity: %.2f× Earth\n" % data.gravity_g
	if data.has("fact"):
		text += "\n[i]%s[/i]" % data.fact

	_info_label.text = text
	_info_panel.visible = true

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

func _trim(v: float) -> String:
	return "%.1f" % v if v != floor(v) else str(int(v))
