extends Node3D
## Interactive Orbital Gravity Sandbox & Slingshot Launcher for CosmoScope
##
## Allows users to launch custom asteroids/probes around central bodies (Earth,
## Jupiter, Sun) with click-and-drag velocity vectors, real-time trajectory arcs,
## and true Kepler/Newtonian orbital gravity physics.

const SolarSystemData := preload("res://data/planets.gd")

const G_CONST: float = 8.0 # Tuned visual gravity constant

var _center_body_idx: int = 2 # Default Earth
var _center_mesh: MeshInstance3D
var _center_mass: float = 100.0

var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.4
var _cam_dist: float = 12.0
var _dragging_cam: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

# Slingshot aiming state
var _aiming: bool = false
var _aim_start_pos: Vector3 = Vector3.ZERO
var _aim_current_pos: Vector3 = Vector3.ZERO

# Trajectory prediction preview line
var _traj_mesh_inst: MeshInstance3D
var _traj_mesh: ImmediateMesh

# Launched asteroids list: [{ "mesh_inst": MeshInstance3D, "pos": Vector3, "vel": Vector3 }]
var _asteroids: Array[Dictionary] = []

var _ui_canvas: CanvasLayer
var _center_option: OptionButton
var _spawn_btn: Button
var _clear_btn: Button
var _back_btn: Button
var _info_lbl: Label
var _count_lbl: Label

func _ready() -> void:
	_build_environment()
	_build_center_body()
	_build_trajectory_line()
	_build_ui()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.04)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.position = Vector3(6, 10, 8)
	light.look_at(Vector3.ZERO)
	light.light_color = Color(1.0, 0.95, 0.9)
	light.light_energy = 1.3
	add_child(light)

	_camera = Camera3D.new()
	_update_camera_transform()
	add_child(_camera)

func _update_camera_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _cam_dist
	_camera.position = Vector3.ZERO + offset
	_camera.look_at(Vector3.ZERO, Vector3.UP)

func _build_center_body() -> void:
	_center_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_center_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 0.85) # Default Earth
	_center_mesh.material_override = mat
	add_child(_center_mesh)

func _build_trajectory_line() -> void:
	_traj_mesh = ImmediateMesh.new()
	_traj_mesh_inst = MeshInstance3D.new()
	_traj_mesh_inst.mesh = _traj_mesh
	add_child(_traj_mesh_inst)

func _build_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)

	# Full-screen root control container MUST ignore mouse filter so 3D clicks pass through!
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_canvas.add_child(root)

	var title_lbl := Label.new()
	title_lbl.text = "☄️ Orbital Gravity Sandbox & Slingshot Launcher"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.position = Vector2(20, 20)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_lbl)

	# Instructions card
	var card := PanelContainer.new()
	card.position = Vector2(20, 65)
	card.custom_minimum_size = Vector2(340, 320)
	card.mouse_filter = Control.MOUSE_FILTER_STOP # Keep UI panel stopping clicks inside it
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.corner_radius_bottom_right = 12
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_style)
	root.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var sel_lbl := Label.new()
	sel_lbl.text = "Central Gravitational Body:"
	vbox.add_child(sel_lbl)

	_center_option = OptionButton.new()
	_center_option.add_item("🌍 Earth (Mass 100)")
	_center_option.add_item("🪐 Jupiter (Mass 300)")
	_center_option.add_item("☀️ Sun (Mass 800)")
	_center_option.select(0)
	_center_option.item_selected.connect(_on_center_selected)
	vbox.add_child(_center_option)

	_info_lbl = Label.new()
	_info_lbl.text = "• Click button below OR click/drag in 3D space to launch asteroids into orbit!"
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_lbl.add_theme_font_size_override("font_size", 12)
	_info_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	vbox.add_child(_info_lbl)

	_spawn_btn = Button.new()
	_spawn_btn.text = "☄️ Spawn Orbiting Asteroid"
	_spawn_btn.custom_minimum_size = Vector2(0, 38)
	var spawn_style := StyleBoxFlat.new()
	spawn_style.bg_color = Color(0.15, 0.45, 0.35)
	spawn_style.corner_radius_top_left = 6
	spawn_style.corner_radius_top_right = 6
	spawn_style.corner_radius_bottom_left = 6
	spawn_style.corner_radius_bottom_right = 6
	_spawn_btn.add_theme_stylebox_override("normal", spawn_style)
	_spawn_btn.pressed.connect(_on_spawn_pressed)
	vbox.add_child(_spawn_btn)

	_count_lbl = Label.new()
	_count_lbl.text = "Active Asteroids: 0"
	vbox.add_child(_count_lbl)

	_clear_btn = Button.new()
	_clear_btn.text = "🗑️ Clear Asteroids"
	_clear_btn.pressed.connect(_on_clear_pressed)
	vbox.add_child(_clear_btn)

	_back_btn = Button.new()
	_back_btn.text = "⬅️ Back to Menu"
	_back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(_back_btn)

func _on_center_selected(idx: int) -> void:
	_center_body_idx = idx
	var mat := StandardMaterial3D.new()
	match idx:
		0: # Earth
			_center_mass = 100.0
			mat.albedo_color = Color(0.2, 0.55, 0.85)
		1: # Jupiter
			_center_mass = 300.0
			mat.albedo_color = Color(0.85, 0.72, 0.55)
		2: # Sun
			_center_mass = 800.0
			mat.albedo_color = Color(1.0, 0.8, 0.2)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.6, 0.1)
	_center_mesh.material_override = mat

func _on_spawn_pressed() -> void:
	# Spawn an asteroid at radius 3.5 with circular Kepler velocity
	var r_dist: float = 3.5
	var pos: Vector3 = Vector3(r_dist, 0.0, 0.0)
	var orbital_speed: float = sqrt(G_CONST * _center_mass / r_dist)
	var vel: Vector3 = Vector3(0.0, 0.0, -orbital_speed)
	_launch_asteroid(pos, vel)

func _on_clear_pressed() -> void:
	for ast in _asteroids:
		var mi: MeshInstance3D = ast.get("mesh_inst", null)
		if is_instance_valid(mi):
			mi.queue_free()
	_asteroids.clear()
	_count_lbl.text = "Active Asteroids: 0"

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Ignore left UI panel area (width 380, height 380)
				if event.position.x < 380 and event.position.y < 380:
					return
				var world_pos: Vector3 = _screen_to_world(event.position)
				_aiming = true
				_aim_start_pos = world_pos
				_aim_current_pos = world_pos
			else:
				if _aiming:
					_aiming = false
					_traj_mesh.clear_surfaces()
					var drag_vector: Vector3 = (_aim_start_pos - _aim_current_pos) * 2.0
					if drag_vector.length() > 0.4:
						_launch_asteroid(_aim_start_pos, drag_vector)
					else:
						# Simple click in space: calculate circular orbit velocity
						var r_dist: float = maxf(1.5, _aim_start_pos.length())
						var orbital_speed: float = sqrt(G_CONST * _center_mass / r_dist)
						var tangent: Vector3 = Vector3(-_aim_start_pos.z, 0.0, _aim_start_pos.x).normalized() * orbital_speed
						_launch_asteroid(_aim_start_pos, tangent)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_dragging_cam = true
				_last_mouse_pos = event.position
			else:
				_dragging_cam = false

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(4.0, _cam_dist - 1.2)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(35.0, _cam_dist + 1.2)
			_update_camera_transform()

	elif event is InputEventMouseMotion:
		if _aiming:
			var world_pos: Vector3 = _screen_to_world(event.position)
			_aim_current_pos = world_pos
			_update_trajectory_preview()
		elif _dragging_cam:
			var delta: Vector2 = event.position - _last_mouse_pos
			_last_mouse_pos = event.position
			_yaw -= delta.x * 0.005
			_pitch = clampf(_pitch - delta.y * 0.005, 0.05, 1.4)
			_update_camera_transform()

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	# Raycast onto ecliptic XZ plane (y = 0)
	if absf(dir.y) < 0.0001:
		return Vector3(screen_pos.x * 0.01, 0.0, screen_pos.y * 0.01)
	var t: float = -origin.y / dir.y
	var hit: Vector3 = origin + dir * t
	hit.y = 0.0
	return hit

func _update_trajectory_preview() -> void:
	_traj_mesh.clear_surfaces()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.85, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)

	var sim_pos: Vector3 = _aim_start_pos
	var sim_vel: Vector3 = (_aim_start_pos - _aim_current_pos) * 2.0
	var dt: float = 0.04

	for step in 60:
		_traj_mesh.surface_add_vertex(sim_pos)
		var r_vec: Vector3 = Vector3.ZERO - sim_pos
		var r_dist: float = r_vec.length()
		if r_dist < 1.0:
			break # Hit central body
		var acc: Vector3 = r_vec.normalized() * (G_CONST * _center_mass / (r_dist * r_dist))
		sim_vel += acc * dt
		sim_pos += sim_vel * dt

	_traj_mesh.surface_end()

func _launch_asteroid(pos: Vector3, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mi.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.5, 0.1)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

	_asteroids.append({
		"mesh_inst": mi,
		"pos": pos,
		"vel": vel,
	})
	_count_lbl.text = "Active Asteroids: %d" % _asteroids.size()

func _process(delta: float) -> void:
	var to_remove: Array[int] = []
	var dt: float = delta

	for i in _asteroids.size():
		var ast: Dictionary = _asteroids[i]
		var pos: Vector3 = ast.get("pos", Vector3.ZERO)
		var vel: Vector3 = ast.get("vel", Vector3.ZERO)
		var mi: MeshInstance3D = ast.get("mesh_inst", null)

		var r_vec: Vector3 = Vector3.ZERO - pos
		var r_dist: float = r_vec.length()

		if r_dist < 1.0 or r_dist > 50.0:
			to_remove.append(i)
			continue

		# Newton's Law of Universal Gravitation: a = G * M / r^2
		var acc: Vector3 = r_vec.normalized() * (G_CONST * _center_mass / (r_dist * r_dist))
		vel += acc * dt
		pos += vel * dt
		if is_instance_valid(mi):
			mi.position = pos

		ast["pos"] = pos
		ast["vel"] = vel

	# Remove destroyed or escaped asteroids in reverse order
	for i in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[i]
		var mi: MeshInstance3D = _asteroids[idx].get("mesh_inst", null)
		if is_instance_valid(mi):
			mi.queue_free()
		_asteroids.remove_at(idx)
		_count_lbl.text = "Active Asteroids: %d" % _asteroids.size()

func _on_back_pressed() -> void:
	var main := get_node_or_null("/root/Main")
	if main != null and main.has_method("_load_scene"):
		main._load_scene("res://scenes/Menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
