extends Node3D
## Guided Tour Mode for CosmoScope.
##
## Smoothly flies the camera through the Solar System from the Sun through
## every planet, dwarf planet, and comet. At each stop, the camera orbits
## dramatically around the object, displays its stats, and narrates key details.
## Includes tour playback controls (Pause, Resume, Next, Prev, Exit).

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")
const SpaceEnvScript := preload("res://scripts/SpaceEnvironment.gd")

# Tour stop definitions for complete Solar System journey.
const TOUR_STOPS := [
	{
		"name": "Overview",
		"target": "Sun",
		"standoff": 18.0,
		"title": "🌌 Solar System Overview — Our Cosmic Home",
		"narration": "Welcome to the CosmoScope Grand Tour! The Solar System formed 4.6 billion years ago from a collapsing interstellar cloud. It consists of our central star, 8 major planets, dwarf planets, dozens of moons, asteroid and Kuiper belts, and the distant Oort Cloud.",
		"pitch": 0.55,
	},
	{
		"name": "Sun",
		"target": "Sun",
		"standoff": 4.5,
		"title": "☀️ The Sun (Sol) — Our Central Star",
		"narration": "The Sun is a G-type main-sequence star containing 99.86% of the Solar System's total mass. Nuclear fusion in its core converts 600 million tons of hydrogen per second, radiating energy, solar wind flares, and intense light across space.",
		"pitch": 0.25,
	},
	{
		"name": "Mercury",
		"target": "Mercury",
		"standoff": 3.5,
		"title": "☿ Mercury — Innermost Terrestrial World",
		"narration": "Mercury is the smallest planet and closest to the Sun. Orbiting in just 88 days, it has virtually no atmosphere, causing extreme temperature swings from a scorching 430°C by day to a freezing -180°C by night.",
		"pitch": 0.3,
	},
	{
		"name": "Venus",
		"target": "Venus",
		"standoff": 3.8,
		"title": "♀ Venus — Earth's Runaway Greenhouse Twin",
		"narration": "Venus is the hottest planet in the Solar System at 465°C. Wrapped in dense clouds of carbon dioxide and sulfuric acid, atmospheric pressure at its surface is 92 times greater than Earth—equivalent to 900 meters underwater.",
		"pitch": 0.2,
	},
	{
		"name": "Earth",
		"target": "Earth",
		"standoff": 4.0,
		"title": "🌍 Earth & The Moon — Oasis of Life",
		"narration": "Earth is our home, the only planet known to harbour life. Liquid oceans cover 71% of its surface. Earth is orbited by the Moon, which stabilizes Earth's axial tilt and drives ocean tides.",
		"pitch": 0.35,
	},
	{
		"name": "Mars",
		"target": "Mars",
		"standoff": 3.6,
		"title": "♂ Mars & Its Moons — The Red Planet",
		"narration": "Mars gets its reddish hue from iron oxide dust. It is home to Olympus Mons, the largest volcano in the Solar System at 21.9 km tall, and two small captured asteroid moons: Phobos and Deimos.",
		"pitch": 0.25,
	},
	{
		"name": "AsteroidBelt",
		"target": "Sun",
		"standoff": 12.0,
		"title": "🪨 The Main Asteroid Belt & Ceres",
		"narration": "Located between Mars and Jupiter, the Main Asteroid Belt contains hundreds of thousands of rocky bodies. It features dwarf planet Ceres alongside 600 instanced asteroids—leftover planetesimals prevented from forming a planet by Jupiter's gravity.",
		"pitch": 0.45,
	},
	{
		"name": "Jupiter",
		"target": "Jupiter",
		"standoff": 4.2,
		"title": "♃ Jupiter & Galilean Moons — King of Planets",
		"narration": "Jupiter is the largest planet, over 11 times Earth's diameter. This gas giant features turbulent storm belts, the iconic Great Red Spot, and 95 moons—including volcanic Io, ocean-covered Europa, giant Ganymede, and cratered Callisto.",
		"pitch": 0.2,
	},
	{
		"name": "Saturn",
		"target": "Saturn",
		"standoff": 4.5,
		"title": "♄ Saturn, Rings & Titan — The Ringed Gem",
		"narration": "Saturn is world-renowned for its brilliant ring system of water ice particles spanning 282,000 km across. It hosts 146 moons, dominated by Titan—the only moon in the Solar System with a dense nitrogen atmosphere and liquid methane lakes.",
		"pitch": 0.4,
	},
	{
		"name": "Uranus",
		"target": "Uranus",
		"standoff": 4.0,
		"title": "♅ Uranus — The Sideways Ice Giant",
		"narration": "Uranus is an ice giant of pale cyan methane clouds. Uniquely, it has an extreme axial tilt of 98 degrees, causing it to effectively rotate on its side as it completes its 84-year orbit around the Sun.",
		"pitch": 0.3,
	},
	{
		"name": "Neptune",
		"target": "Neptune",
		"standoff": 4.0,
		"title": "♆ Neptune & Triton — Realm of Supersonic Winds",
		"narration": "Neptune is the farthest major planet, an ice giant of deep cobalt blue. It experiences the fiercest winds in the Solar System reaching 2,100 km/h, and is orbited by Triton, a retrograde moon with icy nitrogen geysers.",
		"pitch": 0.25,
	},
	{
		"name": "Pluto",
		"target": "Pluto",
		"standoff": 3.5,
		"title": "♇ Pluto & Dwarf Planets — Binary World of the Outer Rim",
		"narration": "Pluto resides in the outer reaches as a dwarf planet. It orbits in close binary partnership with its giant moon Charon, featuring nitrogen ice plains and icy mountains rising 3,500 meters high.",
		"pitch": 0.3,
	},
	{
		"name": "KuiperBelt",
		"target": "Pluto",
		"standoff": 15.0,
		"title": "❄️ The Kuiper Belt & Trans-Neptunian Objects",
		"narration": "Extending beyond Neptune from 30 to 55 AU, the Kuiper Belt is a vast circumstellar ring of icy remnants, home to dwarf planets Pluto, Haumea, Makemake, and Eris, along with short-period comets.",
		"pitch": 0.5,
	},
	{
		"name": "HalleysComet",
		"target": "HalleysComet",
		"standoff": 3.5,
		"title": "☄️ Comets, Meteoroids & Solar Tails",
		"narration": "Comets like Halley's travel on highly elliptical orbits. As they approach the Sun, solar heating causes volatile ice to sublimate, generating dust and ionized plasma tails that always point away from the Sun.",
		"pitch": 0.2,
	},
	{
		"name": "OortCloud",
		"target": "Sun",
		"standoff": 24.0,
		"title": "🌌 The Oort Cloud & Heliosphere Boundary",
		"narration": "At the outermost boundary of our Solar System lies the Oort Cloud—a theoretical spherical shell containing trillions of icy planetesimals extending up to 100,000 AU, marking the limit of the Sun's gravitational dominance.",
		"pitch": 0.6,
	},
]

# States.
enum { STATE_TRANSITION, STATE_ORBIT_HOLD }
var _current_state: int = STATE_TRANSITION

var _current_stop_idx: int = 0
var _solar: Node3D = null
var _camera: Camera3D = null

# Easing & Flight math.
var _fly_t: float = 0.0
var _fly_duration: float = 3.0       # flight time between stops
var _hold_duration: float = 8.5      # dwell & orbit time at stop
var _hold_t: float = 0.0

var _cam_start_pos: Vector3 = Vector3.ZERO
var _cam_start_rot: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.0
var _is_paused: bool = false

# UI Elements.
var _hud_layer: CanvasLayer = null
var _narration_title: Label = null
var _narration_body: RichTextLabel = null
var _typewriter_t: float = 0.0
var _full_narration_text: String = ""

var _info_panel: PanelContainer = null
var _info_label: RichTextLabel = null

var _play_pause_btn: Button = null
var _progress_lbl: Label = null

func _ready() -> void:
	_build_camera()
	_build_world()
	_build_ui()
	_start_stop(_current_stop_idx)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TourCamera"
	_camera.fov = 65.0
	_camera.current = true
	_camera.position = Vector3(0.0, 10.0, 30.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	add_child(_camera)

func _build_world() -> void:
	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	add_child(_solar)

	var dir_light := DirectionalLight3D.new()
	dir_light.name = "TourLight"
	dir_light.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	dir_light.light_energy = 1.3
	add_child(dir_light)

	var env_node := WorldEnvironment.new()
	env_node.set_script(SpaceEnvScript)
	add_child(env_node)

func _build_ui() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	# --- Header Bar (Top) ---
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.size = Vector2(0, 50)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.05, 0.07, 0.12, 0.85)
	top_style.content_margin_left = 16
	top_style.content_margin_right = 16
	top_bar.add_theme_stylebox_override("panel", top_style)

	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_hbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_hbox)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.22, 0.35, 0.9)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn_style.content_margin_left = 12
	btn_style.content_margin_right = 12
	btn_style.content_margin_top = 6
	btn_style.content_margin_bottom = 6

	var back_btn := Button.new()
	back_btn.text = "← Exit Tour"
	back_btn.custom_minimum_size = Vector2(105, 34)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_stylebox_override("normal", btn_style)
	back_btn.pressed.connect(func():
		var main := get_node_or_null("/root/Main")
		if main != null and main.has_method("_load_scene"):
			main._load_scene("res://scenes/Menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/Menu.tscn")
	)
	top_hbox.add_child(back_btn)

	# Tour Progress Indicator.
	_progress_lbl = Label.new()
	_progress_lbl.text = "Planet 1 of 11"
	_progress_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_lbl.add_theme_font_size_override("font_size", 16)
	_progress_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	top_hbox.add_child(_progress_lbl)

	# Playback controls (Prev, Pause/Play, Next).
	var prev_btn := Button.new()
	prev_btn.text = "⏮ Prev"
	prev_btn.custom_minimum_size = Vector2(85, 34)
	prev_btn.add_theme_font_size_override("font_size", 13)
	prev_btn.add_theme_stylebox_override("normal", btn_style)
	prev_btn.pressed.connect(func(): _prev_stop())
	top_hbox.add_child(prev_btn)

	_play_pause_btn = Button.new()
	_play_pause_btn.text = "⏸ Pause"
	_play_pause_btn.custom_minimum_size = Vector2(95, 34)
	_play_pause_btn.add_theme_font_size_override("font_size", 13)
	_play_pause_btn.add_theme_stylebox_override("normal", btn_style)
	_play_pause_btn.pressed.connect(func(): _toggle_pause())
	top_hbox.add_child(_play_pause_btn)

	var next_btn := Button.new()
	next_btn.text = "Next ⏭"
	next_btn.custom_minimum_size = Vector2(85, 34)
	next_btn.add_theme_font_size_override("font_size", 13)
	next_btn.add_theme_stylebox_override("normal", btn_style)
	next_btn.pressed.connect(func(): _next_stop())
	top_hbox.add_child(next_btn)

	_hud_layer.add_child(top_bar)

	# --- Subtitle / Narration Box (Bottom) ---
	var narr_panel := PanelContainer.new()
	narr_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	narr_panel.position = Vector2(0, -140)
	narr_panel.size = Vector2(0, 130)

	var narr_style := StyleBoxFlat.new()
	narr_style.bg_color = Color(0.04, 0.05, 0.1, 0.88)
	narr_style.border_width_top = 2
	narr_style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	narr_style.content_margin_left = 24
	narr_style.content_margin_right = 24
	narr_style.content_margin_top = 12
	narr_style.content_margin_bottom = 12
	narr_panel.add_theme_stylebox_override("panel", narr_style)

	var narr_vbox := VBoxContainer.new()
	narr_vbox.add_theme_constant_override("separation", 6)
	narr_panel.add_child(narr_vbox)

	_narration_title = Label.new()
	_narration_title.add_theme_font_size_override("font_size", 20)
	_narration_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	narr_vbox.add_child(_narration_title)

	_narration_body = RichTextLabel.new()
	_narration_body.bbcode_enabled = true
	_narration_body.fit_content = true
	_narration_body.scroll_active = false
	_narration_body.add_theme_font_size_override("normal_font_size", 15)
	_narration_body.add_theme_color_override("default_color", Color(0.9, 0.92, 0.98))
	narr_vbox.add_child(_narration_body)

	_hud_layer.add_child(narr_panel)

	# --- Target Info Panel (Top-Right) ---
	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info_panel.position = Vector2(-280, 60)
	_info_panel.size = Vector2(260, 200)

	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.06, 0.08, 0.16, 0.85)
	info_style.corner_radius_top_left = 10
	info_style.corner_radius_top_right = 10
	info_style.corner_radius_bottom_left = 10
	info_style.corner_radius_bottom_right = 10
	info_style.border_width_left = 1
	info_style.border_width_right = 1
	info_style.border_width_top = 1
	info_style.border_width_bottom = 1
	info_style.border_color = Color(0.3, 0.5, 0.8, 0.4)
	info_style.content_margin_left = 14
	info_style.content_margin_right = 14
	info_style.content_margin_top = 10
	info_style.content_margin_bottom = 10
	_info_panel.add_theme_stylebox_override("panel", info_style)

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.scroll_active = false
	_info_label.add_theme_font_size_override("normal_font_size", 13)
	_info_label.add_theme_color_override("default_color", Color(0.85, 0.88, 0.95))
	_info_panel.add_child(_info_label)

	_hud_layer.add_child(_info_panel)

func _process(delta: float) -> void:
	if _is_paused:
		return

	# Typewriter text reveal effect.
	if _full_narration_text.length() > 0 and _narration_body.visible_characters < _full_narration_text.length():
		_typewriter_t += delta * 45.0  # characters per second
		_narration_body.visible_characters = int(_typewriter_t)

	match _current_state:
		STATE_TRANSITION:
			_update_transition(delta)
		STATE_ORBIT_HOLD:
			_update_orbit_hold(delta)

func _update_transition(delta: float) -> void:
	_fly_t = minf(1.0, _fly_t + delta / maxf(_fly_duration, 0.1))
	# Smooth cubic ease-in-out curve for camera movement.
	var e: float = _fly_t * _fly_t * (3.0 - 2.0 * _fly_t)

	var stop: Dictionary = TOUR_STOPS[_current_stop_idx]
	var target_node: Node3D = _get_stop_node(stop.target)
	if target_node == null:
		return

	var target_pos: Vector3 = target_node.global_position
	var standoff: float = float(stop.standoff) * _get_node_radius(target_node)
	var pitch: float = float(stop.pitch)

	# Calculate destination camera offset.
	var dest_offset := Vector3(
		cos(pitch) * sin(_orbit_angle),
		sin(pitch),
		cos(pitch) * cos(_orbit_angle)
	) * standoff

	var dest_pos: Vector3 = target_pos + dest_offset
	_camera.position = _cam_start_pos.lerp(dest_pos, e)

	# Camera look-at target smoothly interpolates.
	var look_target: Vector3 = target_pos
	_camera.look_at(look_target, Vector3.UP)

	if _fly_t >= 1.0:
		_current_state = STATE_ORBIT_HOLD
		_hold_t = 0.0
		_show_target_info(target_node)

func _update_orbit_hold(delta: float) -> void:
	_hold_t += delta
	_orbit_angle += delta * 0.15  # slow cinematic orbit around planet

	var stop: Dictionary = TOUR_STOPS[_current_stop_idx]
	var target_node: Node3D = _get_stop_node(stop.target)
	if target_node != null:
		var target_pos: Vector3 = target_node.global_position
		var standoff: float = float(stop.standoff) * _get_node_radius(target_node)
		var pitch: float = float(stop.pitch)

		var offset := Vector3(
			cos(pitch) * sin(_orbit_angle),
			sin(pitch),
			cos(pitch) * cos(_orbit_angle)
		) * standoff

		_camera.position = target_pos + offset
		_camera.look_at(target_pos, Vector3.UP)

	if _hold_t >= _hold_duration:
		_next_stop()

func _start_stop(idx: int) -> void:
	_current_stop_idx = posmod(idx, TOUR_STOPS.size())
	var stop: Dictionary = TOUR_STOPS[_current_stop_idx]

	_current_state = STATE_TRANSITION
	_fly_t = 0.0
	_hold_t = 0.0
	_cam_start_pos = _camera.position

	# Narration text setup.
	_narration_title.text = stop.title
	_full_narration_text = stop.narration
	_narration_body.text = _full_narration_text
	_narration_body.visible_characters = 0
	_typewriter_t = 0.0

	_progress_lbl.text = "Stop %d of %d — %s" % [_current_stop_idx + 1, TOUR_STOPS.size(), stop.name]

	# Update info panel if node is ready.
	var target_node: Node3D = _get_stop_node(stop.target)
	if target_node != null:
		_show_target_info(target_node)

func _next_stop() -> void:
	_start_stop(_current_stop_idx + 1)

func _prev_stop() -> void:
	_start_stop(_current_stop_idx - 1)

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	_play_pause_btn.text = "▶ Resume" if _is_paused else "⏸ Pause"

func _get_stop_node(node_name: String) -> Node3D:
	if _solar == null:
		return null
	if node_name == "Sun":
		return _solar.get_node_or_null("Sun")
	for body in _solar.get_planet_bodies():
		if body != null and body.name == node_name:
			return body
	# Check dwarf planets or comets.
	return _solar.get_node_or_null(node_name)

func _get_node_radius(node: Node3D) -> float:
	var data: Dictionary = node.get_meta("data", {})
	if data.has("radius"):
		return float(data.radius)
	if node.name == "Sun":
		return 2.0
	return 1.0

func _show_target_info(node: Node3D) -> void:
	var data: Dictionary = node.get_meta("data", {})
	if data.is_empty() and node.name == "Sun":
		data = SolarSystemScript.SolarSystemData.SUN

	if data.is_empty():
		_info_panel.visible = false
		return

	var text := "[b][font_size=16]%s[/font_size][/b]\n\n" % data.get("name", node.name)
	if data.has("diameter_km"):
		text += "Diameter: %s km\n" % _commas(data.diameter_km)
	if data.has("sun_dist_mkm"):
		text += "Sun Distance: %s M km\n" % _trim(data.sun_dist_mkm)
	if data.has("year"):
		text += "Year: %s\n" % data.year
	if data.has("day"):
		text += "Day: %s\n" % data.day
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
