extends Node3D
## Interactive Solar & Lunar Eclipse & Transit Simulator for CosmoScope
##
## Demonstrates alignment geometry of Solar Eclipses, Lunar Eclipses,
## Mercury/Venus Transits with 3D shadow umbra/penumbra cones and preset views.

const SolarSystemData := preload("res://data/planets.gd")

var _sun_mesh: MeshInstance3D
var _earth_pivot: Node3D
var _earth_mesh: MeshInstance3D
var _moon_pivot: Node3D
var _moon_mesh: MeshInstance3D
var _mercury_mesh: MeshInstance3D
var _shadow_cone: MeshInstance3D

var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.2
var _cam_dist: float = 12.0

var _dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

var _ui_canvas: CanvasLayer
var _preset_option: OptionButton
var _align_slider: HSlider
var _info_label: RichTextLabel
var _preset_lbl: Label
var _align_lbl: Label
var _back_btn: Button

var _current_preset: int = 0 # 0: Solar Eclipse, 1: Lunar Eclipse, 2: Mercury Transit, 3: Custom

func _ready() -> void:
	_build_environment()
	_build_3d_bodies()
	_build_ui()
	_apply_preset(0) # Solar Eclipse default

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Sun light source
	var light := DirectionalLight3D.new()
	light.position = Vector3(-10, 0, 0)
	light.look_at(Vector3(10, 0, 0))
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 1.5
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_dist = max(5.0, _cam_dist - 1.0)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_dist = min(25.0, _cam_dist + 1.0)
			_update_camera_transform()
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		_yaw -= delta.x * 0.005
		_pitch = clamp(_pitch + delta.y * 0.005, -1.4, 1.4)
		_update_camera_transform()

func _build_3d_bodies() -> void:
	# 1. Sun (Position: X = -6.0)
	_sun_mesh = MeshInstance3D.new()
	var sun_sphere := SphereMesh.new()
	sun_sphere.radius = 1.8
	sun_sphere.height = 3.6
	_sun_mesh.mesh = sun_sphere
	var sun_mat := StandardMaterial3D.new()
	sun_mat.albedo_color = Color(1.0, 0.8, 0.2)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.7, 0.1)
	sun_mat.emission_energy_multiplier = 2.0
	_sun_mesh.material_override = sun_mat
	_sun_mesh.position = Vector3(-6.0, 0, 0)
	add_child(_sun_mesh)

	# 2. Earth (Position: X = +2.0)
	_earth_pivot = Node3D.new()
	_earth_pivot.position = Vector3(2.0, 0, 0)
	add_child(_earth_pivot)

	_earth_mesh = MeshInstance3D.new()
	var earth_sphere := SphereMesh.new()
	earth_sphere.radius = 0.8
	earth_sphere.height = 1.6
	_earth_mesh.mesh = earth_sphere
	var earth_mat := StandardMaterial3D.new()
	earth_mat.albedo_color = Color(0.2, 0.5, 0.8)
	_earth_mesh.material_override = earth_mat
	_earth_pivot.add_child(_earth_mesh)

	# 3. Moon Pivot & Mesh (Attached to Earth)
	_moon_pivot = Node3D.new()
	_earth_pivot.add_child(_moon_pivot)

	_moon_mesh = MeshInstance3D.new()
	var moon_sphere := SphereMesh.new()
	moon_sphere.radius = 0.25
	moon_sphere.height = 0.5
	_moon_mesh.mesh = moon_sphere
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.75, 0.75, 0.75)
	_moon_mesh.material_override = moon_mat
	# Local offset Vector3(-1.8, 0, 0):
	# When rotation_degrees.y = 0: Moon is at (2.0 - 1.8) = X +0.2 -> Between Sun (-6) and Earth (+2) -> Solar Eclipse (Sun -> Moon -> Earth)
	# When rotation_degrees.y = 180: Moon is at (2.0 + 1.8) = X +3.8 -> Behind Earth (+2) relative to Sun (-6) -> Lunar Eclipse (Sun -> Earth -> Moon)
	_moon_mesh.position = Vector3(-1.8, 0, 0)
	_moon_pivot.add_child(_moon_mesh)

	# 4. Mercury Mesh (Position: X = -2.0, between Sun at -6 and Earth at +2)
	_mercury_mesh = MeshInstance3D.new()
	var merc_sphere := SphereMesh.new()
	merc_sphere.radius = 0.22
	merc_sphere.height = 0.44
	_mercury_mesh.mesh = merc_sphere
	var merc_mat := StandardMaterial3D.new()
	merc_mat.albedo_color = Color(0.55, 0.50, 0.48)
	_mercury_mesh.material_override = merc_mat
	_mercury_mesh.position = Vector3(-2.0, 0, 0)
	_mercury_mesh.visible = false
	add_child(_mercury_mesh)

	# 5. Shadow Cone Frustum Mesh
	_shadow_cone = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.25
	cylinder.bottom_radius = 0.05
	cylinder.height = 2.5
	_shadow_cone.mesh = cylinder
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.1, 0.0, 0.0, 0.4)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_cone.material_override = shadow_mat
	_shadow_cone.rotation_degrees.z = -90
	add_child(_shadow_cone)

func _build_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.add_child(root)

	var title_lbl := Label.new()
	title_lbl.text = "🌒 Interactive Eclipse & Transit Simulator"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.position = Vector2(20, 20)
	root.add_child(title_lbl)

	# Controls Panel
	var card := PanelContainer.new()
	card.position = Vector2(20, 70)
	card.custom_minimum_size = Vector2(380, 480)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.08, 0.15, 0.88)
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.corner_radius_bottom_right = 12
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", card_style)
	root.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	_preset_lbl = Label.new()
	_preset_lbl.text = "Select Preset:"
	vbox.add_child(_preset_lbl)

	_preset_option = OptionButton.new()
	_preset_option.add_item("🌞 Total Solar Eclipse")
	_preset_option.add_item("🌕 Total Lunar Eclipse")
	_preset_option.add_item("☀️ Mercury Transit")
	_preset_option.add_item("🌙 Custom Moon Angle")
	_preset_option.select(0)
	_preset_option.item_selected.connect(_on_preset_selected)
	vbox.add_child(_preset_option)

	_align_lbl = Label.new()
	_align_lbl.text = "Moon Orbit Angle: 0.0°"
	vbox.add_child(_align_lbl)

	_align_slider = HSlider.new()
	_align_slider.min_value = 0.0
	_align_slider.max_value = 360.0
	_align_slider.value = 0.0
	_align_slider.value_changed.connect(_on_align_changed)
	vbox.add_child(_align_slider)

	# Camera Preset View Buttons
	var cam_lbl := Label.new()
	cam_lbl.text = "Camera Angle Presets:"
	vbox.add_child(cam_lbl)

	var hbox_cam := HBoxContainer.new()
	hbox_cam.add_theme_constant_override("separation", 8)

	var btn_side := Button.new()
	btn_side.text = "📷 Side"
	btn_side.pressed.connect(func(): _set_camera_view(0.0, 0.1, 12.0))
	hbox_cam.add_child(btn_side)

	var btn_top := Button.new()
	btn_top.text = "📷 Top-Down"
	btn_top.pressed.connect(func(): _set_camera_view(0.0, 1.4, 14.0))
	hbox_cam.add_child(btn_top)

	var btn_3d := Button.new()
	btn_3d.text = "📷 3D Angle"
	btn_3d.pressed.connect(func(): _set_camera_view(0.5, 0.35, 12.0))
	hbox_cam.add_child(btn_3d)

	vbox.add_child(hbox_cam)

	_info_label = RichTextLabel.new()
	_info_label.custom_minimum_size = Vector2(0, 160)
	_info_label.bbcode_enabled = true
	vbox.add_child(_info_label)

	_back_btn = Button.new()
	_back_btn.text = "⬅️ Back to Menu"
	_back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(_back_btn)

func _set_camera_view(yaw: float, pitch: float, dist: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_cam_dist = dist
	_update_camera_transform()

func _on_preset_selected(index: int) -> void:
	_apply_preset(index)

func _apply_preset(index: int) -> void:
	_current_preset = index
	match index:
		0: # Total Solar Eclipse
			_moon_pivot.visible = true
			_mercury_mesh.visible = false
			_shadow_cone.visible = true
			_align_slider.editable = false

			_align_slider.value = 0.0
			_moon_pivot.rotation_degrees.y = 0.0
			_align_lbl.text = "Moon Orbit Angle: 0.0° (Aligned)"

			# Cone extends from Moon (X = 0.2) towards Earth (X = 2.0)
			_shadow_cone.position = Vector3(1.1, 0, 0)
			_shadow_cone.rotation_degrees = Vector3(0, 0, -90)
			_shadow_cone.scale = Vector3(1.0, 1.0, 1.0)

			_info_label.text = "[b][color=#ffcc00]🌞 Total Solar Eclipse[/color][/b]\n\n" + \
				"[b]Alignment:[/b] [color=#ffdd66]Sun → Moon → Earth[/color]\n\n" + \
				"The Moon passes directly between the Sun and Earth. " + \
				"The Moon blocks sunlight and casts its umbral shadow cone onto Earth's surface."

		1: # Total Lunar Eclipse
			_moon_pivot.visible = true
			_mercury_mesh.visible = false
			_shadow_cone.visible = true
			_align_slider.editable = false

			_align_slider.value = 180.0
			_moon_pivot.rotation_degrees.y = 180.0
			_align_lbl.text = "Moon Orbit Angle: 180.0° (Aligned)"

			# Cone extends from Earth (X = 2.0) towards Moon (X = 3.8)
			_shadow_cone.position = Vector3(2.9, 0, 0)
			_shadow_cone.rotation_degrees = Vector3(0, 0, -90)
			_shadow_cone.scale = Vector3(1.0, 1.0, 1.0)

			_info_label.text = "[b][color=#ff6666]🌞 Total Lunar Eclipse[/color][/b]\n\n" + \
				"[b]Alignment:[/b] [color=#ff9999]Sun → Earth → Moon[/color]\n\n" + \
				"Earth passes directly between the Sun and Moon. " + \
				"Earth blocks solar rays and casts its shadow over the Moon, giving it a deep reddish 'Blood Moon' hue."

		2: # Mercury Transit
			_moon_pivot.visible = false
			_mercury_mesh.visible = true
			_shadow_cone.visible = true
			_align_slider.editable = false

			_align_lbl.text = "Mercury Transit Geometry"

			# Ray/cone from Mercury (X = -2.0) to Earth (X = 2.0)
			_shadow_cone.position = Vector3(0.0, 0, 0)
			_shadow_cone.rotation_degrees = Vector3(0, 0, -90)
			_shadow_cone.scale = Vector3(0.5, 1.6, 0.5)

			_info_label.text = "[b][color=#66ccff]☀️ Mercury Transit[/color][/b]\n\n" + \
				"[b]Alignment:[/b] [color=#99e6ff]Sun → Mercury → Earth[/color]\n\n" + \
				"Mercury passes directly between the Sun and Earth. " + \
				"This event does not involve the Moon. As seen from Earth, Mercury appears as a tiny dark silhouetted dot crossing the Sun."

		3: # Custom Moon Angle
			_moon_pivot.visible = true
			_mercury_mesh.visible = false
			_align_slider.editable = true
			_update_custom_angle(_align_slider.value)

func _on_align_changed(val: float) -> void:
	if _current_preset == 3:
		_update_custom_angle(val)

func _update_custom_angle(val: float) -> void:
	_moon_pivot.rotation_degrees.y = val
	_align_lbl.text = "Moon Orbit Angle: %.1f°" % val

	# Check eclipse proximity
	var diff_solar: float = abs(wrapf(val, -180.0, 180.0)) # 0° is Solar
	var diff_lunar: float = abs(wrapf(val - 180.0, -180.0, 180.0)) # 180° is Lunar

	if diff_solar < 15.0:
		_shadow_cone.visible = true
		_shadow_cone.position = Vector3(1.1, 0, 0)
		_shadow_cone.rotation_degrees = Vector3(0, 0, -90)
		_shadow_cone.scale = Vector3(1.0, 1.0, 1.0)
		_info_label.text = "[b][color=#cccccc]🌙 Custom Moon Angle (%.1f°)[/color][/b]\n\n" % val + \
			"[b]Alignment Status:[/b] [color=#ffcc00]Near Solar Eclipse (Sun → Moon → Earth)[/color]\n\n" + \
			"The Moon is passing between the Sun and Earth!"
	elif diff_lunar < 15.0:
		_shadow_cone.visible = true
		_shadow_cone.position = Vector3(2.9, 0, 0)
		_shadow_cone.rotation_degrees = Vector3(0, 0, -90)
		_shadow_cone.scale = Vector3(1.0, 1.0, 1.0)
		_info_label.text = "[b][color=#cccccc]🌙 Custom Moon Angle (%.1f°)[/color][/b]\n\n" % val + \
			"[b]Alignment Status:[/b] [color=#ff6666]Near Lunar Eclipse (Sun → Earth → Moon)[/color]\n\n" + \
			"The Earth is passing between the Sun and Moon!"
	else:
		_shadow_cone.visible = false
		_info_label.text = "[b][color=#cccccc]🌙 Custom Moon Angle (%.1f°)[/color][/b]\n\n" % val + \
			"[b]Alignment Status:[/b] No Eclipse\n\n" + \
			"The Moon is outside alignment line with the Sun and Earth. Sunlight misses direct obstruction."

func _on_back_pressed() -> void:
	var main: Node = get_node_or_null("/root/Main")
	if main != null and main.has_method("_load_scene"):
		main._load_scene("res://scenes/Menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
