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
var _shadow_cone: MeshInstance3D

var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.2
var _cam_dist: float = 12.0

var _ui_canvas: CanvasLayer
var _preset_option: OptionButton
var _align_slider: HSlider
var _info_label: RichTextLabel
var _cam_view_btn: Button
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

func _build_3d_bodies() -> void:
	# Sun (at origin left: -5.0)
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

	# Earth (at center right: +2.0)
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

	# Moon Pivot & Mesh
	_moon_pivot = Node3D.new()
	_earth_pivot.add_child(_moon_pivot)

	_moon_mesh = MeshInstance3D.new()
	var moon_sphere := SphereMesh.new()
	moon_sphere.radius = 0.25
	moon_sphere.height = 0.5
	_moon_mesh.mesh = moon_sphere
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.7, 0.7, 0.7)
	_moon_mesh.material_override = moon_mat
	_moon_mesh.position = Vector3(-1.8, 0, 0) # Default in front of Earth (Solar Eclipse)
	_moon_pivot.add_child(_moon_mesh)

	# Shadow Cone frustum mesh
	_shadow_cone = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.25
	cylinder.bottom_radius = 0.05
	cylinder.height = 2.5
	_shadow_cone.mesh = cylinder
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.1, 0.0, 0.0, 0.35)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_cone.material_override = shadow_mat
	_shadow_cone.rotation_degrees.z = -90
	_shadow_cone.position = Vector3(0.9, 0, 0)
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
	card.custom_minimum_size = Vector2(360, 420)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
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
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var preset_lbl := Label.new()
	preset_lbl.text = "Select Alignment Preset:"
	vbox.add_child(preset_lbl)

	_preset_option = OptionButton.new()
	_preset_option.add_item("🌞 Total Solar Eclipse")
	_preset_option.add_item("🌕 Total Lunar Eclipse")
	_preset_option.add_item("☿ Mercury Transit")
	_preset_option.add_item("🎛️ Custom Moon Angle")
	_preset_option.select(0)
	_preset_option.item_selected.connect(_on_preset_selected)
	vbox.add_child(_preset_option)

	var align_lbl := Label.new()
	align_lbl.text = "Moon Orbit Alignment Angle:"
	vbox.add_child(align_lbl)

	_align_slider = HSlider.new()
	_align_slider.min_value = 0.0
	_align_slider.max_value = 360.0
	_align_slider.value = 180.0
	_align_slider.value_changed.connect(_on_align_changed)
	vbox.add_child(_align_slider)

	_info_label = RichTextLabel.new()
	_info_label.custom_minimum_size = Vector2(0, 160)
	_info_label.bbcode_enabled = true
	vbox.add_child(_info_label)

	_back_btn = Button.new()
	_back_btn.text = "⬅️ Back to Menu"
	_back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(_back_btn)

func _on_preset_selected(index: int) -> void:
	_apply_preset(index)

func _apply_preset(index: int) -> void:
	_current_preset = index
	match index:
		0: # Solar Eclipse
			_align_slider.value = 180.0
			_moon_pivot.rotation_degrees.y = 180.0
			_info_label.text = "[b][color=#ffcc00]Total Solar Eclipse[/color][/b]\n\nOccurs when the Moon passes directly between Earth and the Sun, blocking sunlight and casting an umbral shadow cone onto Earth's surface."
		1: # Lunar Eclipse
			_align_slider.value = 0.0
			_moon_pivot.rotation_degrees.y = 0.0
			_info_label.text = "[b][color=#ff6666]Total Lunar Eclipse[/color][/b]\n\nOccurs when Earth passes directly between the Sun and Moon. Sunlight refracted through Earth's atmosphere turns the Moon a deep reddish 'blood moon' color."
		2: # Mercury Transit
			_align_slider.value = 180.0
			_moon_pivot.rotation_degrees.y = 180.0
			_info_label.text = "[b][color=#66ccff]Mercury Transit[/color][/b]\n\nMercury passes directly across the solar disk as seen from Earth. Occurs only 13 to 14 times per century."
		3: # Custom
			_info_label.text = "[b][color=#cccccc]Custom Orbit Slider[/color][/b]\n\nDrag the alignment slider above to observe how small orbital inclination angles determine whether an eclipse occurs."

func _on_align_changed(val: float) -> void:
	_moon_pivot.rotation_degrees.y = val

func _on_back_pressed() -> void:
	var main := get_node_or_null("/root/Main")
	if main != null and main.has_method("_load_scene"):
		main._load_scene("res://scenes/Menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
