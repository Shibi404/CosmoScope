extends Node3D
## Planetary Gravity & Weight Jump Simulator for CosmoScope
##
## Simulates real physics jump heights, hang times, and relative weights across
## different solar system bodies (Earth, Moon, Mars, Jupiter, Mercury, Sun, etc.).

const SolarSystemData := preload("res://data/planets.gd")

var _current_body_idx: int = 2 # Default Earth (idx 2 in PLANETS)
var _earth_weight_kg: float = 70.0
var _earth_jump_m: float = 0.5

var _planet_mesh_inst: MeshInstance3D
var _astronaut_pivot: Node3D
var _astronaut_mesh: MeshInstance3D
var _jump_arc_line: ImmediateMesh
var _jump_arc_inst: MeshInstance3D
var _camera: Camera3D

var _ui_canvas: CanvasLayer
var _body_option: OptionButton
var _weight_slider: HSlider
var _weight_val_label: Label
var _jump_btn: Button
var _back_btn: Button

var _calc_weight_lbl: Label
var _calc_height_lbl: Label
var _calc_hangtime_lbl: Label
var _body_info_lbl: Label

# Jump animation state
var _is_jumping: bool = false
var _jump_time: float = 0.0
var _jump_duration: float = 1.0
var _max_jump_height: float = 0.5

func _ready() -> void:
	_build_scene_environment()
	_build_3d_simulation()
	_build_ui()
	_update_simulation_body()

func _build_scene_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.position = Vector3(5, 10, 5)
	light.look_at(Vector3.ZERO)
	light.light_color = Color(1.0, 0.95, 0.9)
	light.light_energy = 1.2
	add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 2.5, 6.0)
	_camera.look_at(Vector3(0, 1.0, 0))
	add_child(_camera)

func _build_3d_simulation() -> void:
	# Base platform / planet sphere surface segment
	_planet_mesh_inst = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	_planet_mesh_inst.mesh = sphere
	_planet_mesh_inst.position = Vector3(0, -2.5, 0)
	add_child(_planet_mesh_inst)

	# Astronaut Avatar (Capsule + Visor)
	_astronaut_pivot = Node3D.new()
	_astronaut_pivot.position = Vector3(0, 0.5, 0)
	add_child(_astronaut_pivot)

	_astronaut_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.95)
	mat.roughness = 0.3
	_astronaut_mesh.mesh = capsule
	_astronaut_mesh.material_override = mat
	_astronaut_pivot.add_child(_astronaut_mesh)

	# Visor
	var visor := MeshInstance3D.new()
	var visor_box := BoxMesh.new()
	visor_box.size = Vector3(0.3, 0.15, 0.15)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(1.0, 0.7, 0.1)
	visor_mat.metallic = 0.9
	visor_mat.roughness = 0.1
	visor.mesh = visor_box
	visor.material_override = visor_mat
	visor.position = Vector3(0, 0.25, 0.2)
	_astronaut_pivot.add_child(visor)

func _build_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)

	# Root Control Container
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.add_child(root)

	# Title Banner
	var title_lbl := Label.new()
	title_lbl.text = "⚖️ Planetary Gravity & Jump Height Simulator"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.position = Vector2(20, 20)
	root.add_child(title_lbl)

	# Controls Card (Left side)
	var card := PanelContainer.new()
	card.position = Vector2(20, 70)
	card.custom_minimum_size = Vector2(340, 420)
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

	var sel_label := Label.new()
	sel_label.text = "Select Celestial Body:"
	vbox.add_child(sel_label)

	_body_option = OptionButton.new()
	_body_option.add_item("Mercury (0.38g)")
	_body_option.add_item("Venus (0.90g)")
	_body_option.add_item("Earth (1.00g)")
	_body_option.add_item("Moon (0.166g)")
	_body_option.add_item("Mars (0.38g)")
	_body_option.add_item("Jupiter (2.53g)")
	_body_option.add_item("Saturn (1.07g)")
	_body_option.add_item("Uranus (0.89g)")
	_body_option.add_item("Neptune (1.14g)")
	_body_option.add_item("Pluto (0.063g)")
	_body_option.select(2) # Default Earth
	_body_option.item_selected.connect(_on_body_selected)
	vbox.add_child(_body_option)

	var weight_lbl := Label.new()
	weight_lbl.text = "Earth Mass (kg):"
	vbox.add_child(weight_lbl)

	_weight_slider = HSlider.new()
	_weight_slider.min_value = 20.0
	_weight_slider.max_value = 150.0
	_weight_slider.value = 70.0
	_weight_slider.value_changed.connect(_on_weight_changed)
	vbox.add_child(_weight_slider)

	_weight_val_label = Label.new()
	_weight_val_label.text = "70 kg"
	vbox.add_child(_weight_val_label)

	_jump_btn = Button.new()
	_jump_btn.text = "🚀 JUMP!"
	_jump_btn.custom_minimum_size = Vector2(0, 45)
	_jump_btn.pressed.connect(_on_jump_pressed)
	vbox.add_child(_jump_btn)

	_back_btn = Button.new()
	_back_btn.text = "⬅️ Back to Menu"
	_back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(_back_btn)

	# Results Display Panel (Right side)
	var res_card := PanelContainer.new()
	res_card.position = Vector2(380, 70)
	res_card.custom_minimum_size = Vector2(360, 300)
	res_card.add_theme_stylebox_override("panel", card_style)
	root.add_child(res_card)

	var res_vbox := VBoxContainer.new()
	res_vbox.add_theme_constant_override("separation", 10)
	res_card.add_child(res_vbox)

	_body_info_lbl = Label.new()
	_body_info_lbl.text = "Body: Earth"
	_body_info_lbl.add_theme_font_size_override("font_size", 18)
	res_vbox.add_child(_body_info_lbl)

	_calc_weight_lbl = Label.new()
	_calc_weight_lbl.text = "Your Weight: 70.0 kg (686 N)"
	res_vbox.add_child(_calc_weight_lbl)

	_calc_height_lbl = Label.new()
	_calc_height_lbl.text = "Max Jump Height: 0.50 m"
	res_vbox.add_child(_calc_height_lbl)

	_calc_hangtime_lbl = Label.new()
	_calc_hangtime_lbl.text = "Air Hang Time: 0.64 s"
	res_vbox.add_child(_calc_hangtime_lbl)

func _get_selected_g() -> float:
	var idx := _body_option.selected
	match idx:
		0: return 0.38 # Mercury
		1: return 0.90 # Venus
		2: return 1.00 # Earth
		3: return 0.166 # Moon
		4: return 0.38 # Mars
		5: return 2.53 # Jupiter
		6: return 1.07 # Saturn
		7: return 0.89 # Uranus
		8: return 1.14 # Neptune
		9: return 0.063 # Pluto
		_: return 1.0

func _get_selected_name() -> String:
	var idx := _body_option.selected
	match idx:
		0: return "Mercury"
		1: return "Venus"
		2: return "Earth"
		3: return "Moon"
		4: return "Mars"
		5: return "Jupiter"
		6: return "Saturn"
		7: return "Uranus"
		8: return "Neptune"
		9: return "Pluto"
		_: return "Earth"

func _get_selected_color() -> Color:
	var idx := _body_option.selected
	match idx:
		0: return Color(0.55, 0.50, 0.48)
		1: return Color(0.85, 0.70, 0.45)
		2: return Color(0.20, 0.55, 0.80)
		3: return Color(0.7, 0.7, 0.7)
		4: return Color(0.80, 0.35, 0.20)
		5: return Color(0.85, 0.72, 0.55)
		6: return Color(0.88, 0.82, 0.62)
		7: return Color(0.60, 0.85, 0.85)
		8: return Color(0.30, 0.45, 0.85)
		9: return Color(0.72, 0.65, 0.55)
		_: return Color.WHITE

func _update_simulation_body() -> void:
	var g := _get_selected_g()
	var body_name := _get_selected_name()
	var body_color := _get_selected_color()

	# Update planet mesh material color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	_planet_mesh_inst.material_override = mat

	# Calculate physics values
	var weight_kg := _earth_weight_kg * g
	var weight_n := weight_kg * 9.81
	_max_jump_height = clamp(_earth_jump_m / g, 0.1, 8.0)
	var g_ms2 := g * 9.81
	var hang_time := 2.0 * sqrt(2.0 * _max_jump_height / g_ms2)

	_body_info_lbl.text = "Body: %s (g = %.3fg)" % [body_name, g]
	_calc_weight_lbl.text = "Equivalent Weight: %.1f kg (%.0f N)" % [weight_kg, weight_n]
	_calc_height_lbl.text = "Max Jump Height: %.2f meters" % _max_jump_height
	_calc_hangtime_lbl.text = "Air Hang Time: %.2f seconds" % hang_time

func _on_body_selected(_index: int) -> void:
	_update_simulation_body()

func _on_weight_changed(val: float) -> void:
	_earth_weight_kg = val
	_weight_val_label.text = "%.0f kg" % val
	_update_simulation_body()

func _on_jump_pressed() -> void:
	if _is_jumping:
		return
	_is_jumping = true
	_jump_time = 0.0
	var g := _get_selected_g()
	_jump_duration = clamp(1.2 / sqrt(g), 0.5, 3.5)

func _process(delta: float) -> void:
	if _is_jumping:
		_jump_time += delta
		var t := _jump_time / _jump_duration
		if t >= 1.0:
			_is_jumping = false
			_astronaut_pivot.position.y = 0.5
		else:
			# Parabolic jump trajectory: height = 4 * max_h * t * (1 - t)
			var h := 4.0 * _max_jump_height * t * (1.0 - t)
			_astronaut_pivot.position.y = 0.5 + h

func _on_back_pressed() -> void:
	var main := get_node_or_null("/root/Main")
	if main != null and main.has_method("_load_scene"):
		main._load_scene("res://scenes/Menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")
