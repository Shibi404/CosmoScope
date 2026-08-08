extends Control
## Animated landing screen with AR / VR mode selection.
##
## Displays the CosmoScope title with a starfield background, a floating
## animated planet, and two large mode-selection buttons. Emits scene-switch
## signals consumed by Main.gd.

signal mode_selected(mode: String)

var _stars: Array[Dictionary] = []
var _planet_angle: float = 0.0

func _ready() -> void:
	# Generate a set of animated stars for the background.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 120:
		_stars.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"size": rng.randf_range(1.0, 3.0),
			"speed": rng.randf_range(0.2, 1.0),
			"phase": rng.randf() * TAU,
			"brightness": rng.randf_range(0.5, 1.0),
		})

	# Build the full UI tree.
	_build_ui()
	queue_redraw()

func _process(delta: float) -> void:
	_planet_angle += delta * 15.0
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size

	# Dark space background gradient.
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.06))

	# Twinkling stars.
	var t := Time.get_ticks_msec() / 1000.0
	for s in _stars:
		var brightness: float = s.brightness * (0.6 + 0.4 * sin(t * s.speed + s.phase))
		var col := Color(brightness, brightness, brightness * 1.1, brightness)
		var pos := Vector2(s.pos.x * sz.x, s.pos.y * sz.y)
		draw_circle(pos, s.size, col)

	# Decorative orbiting dot (simulates a planet in the menu background).
	var cx := sz.x * 0.5
	var cy := sz.y * 0.45
	var orbit_r := minf(sz.x, sz.y) * 0.18
	var px := cx + cos(deg_to_rad(_planet_angle)) * orbit_r
	var py := cy + sin(deg_to_rad(_planet_angle)) * orbit_r * 0.4

	# Orbit ring.
	_draw_ellipse(Vector2(cx, cy), orbit_r, orbit_r * 0.4, Color(0.3, 0.4, 0.7, 0.2))

	# Planet glow.
	draw_circle(Vector2(px, py), 18.0, Color(0.2, 0.4, 0.9, 0.15))
	draw_circle(Vector2(px, py), 10.0, Color(0.3, 0.5, 1.0, 0.4))
	draw_circle(Vector2(px, py), 5.0, Color(0.5, 0.7, 1.0, 0.9))

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	var segments := 64
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		points.append(Vector2(center.x + cos(a) * rx, center.y + sin(a) * ry))
	for i in segments:
		draw_line(points[i], points[i + 1], color, 1.5, true)

func _build_ui() -> void:
	# === Title ===
	var title_container := VBoxContainer.new()
	title_container.name = "TitleContainer"
	title_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_container.position = Vector2(-250, 20)
	title_container.size = Vector2(500, 100)
	title_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(title_container)

	var title := Label.new()
	title.name = "Title"
	title.text = "🌌 CosmoScope"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.3, 0.6))
	title.add_theme_constant_override("outline_size", 6)
	title_container.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Experience the Solar System in AR & VR"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 0.85))
	title_container.add_child(subtitle)

	# === Mode buttons (centered, 2 rows) ===
	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_CENTER)
	main_vbox.position = Vector2(-360, -90)
	main_vbox.size = Vector2(720, 240)
	main_vbox.add_theme_constant_override("separation", 14)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(main_vbox)

	# Row 1: AR, VR, Tour
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(row1)

	var ar_panel := _make_mode_button(
		"🔭 AR Mode",
		"Place planets on table\nvia camera/grid",
		Color(0.15, 0.45, 0.35),
		Color(0.1, 0.3, 0.25),
		"ar"
	)
	row1.add_child(ar_panel)

	var vr_panel := _make_mode_button(
		"🥽 VR Mode",
		"Cardboard stereoscopic\nhead-look VR",
		Color(0.25, 0.2, 0.5),
		Color(0.15, 0.12, 0.35),
		"vr"
	)
	row1.add_child(vr_panel)

	var tour_panel := _make_mode_button(
		"🎬 Guided Tour",
		"Cinematic narrated\nSolar System flight",
		Color(0.45, 0.25, 0.15),
		Color(0.35, 0.18, 0.1),
		"tour"
	)
	row1.add_child(tour_panel)

	var sandbox_panel := _make_mode_button(
		"☄️ Orbit Sandbox",
		"Slingshot asteroids into\nKepler 3D orbits",
		Color(0.45, 0.35, 0.15),
		Color(0.32, 0.25, 0.1),
		"sandbox"
	)
	row1.add_child(sandbox_panel)

	# Row 2: Compare, Gravity, Eclipse, Quiz
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(row2)

	var comp_panel := _make_mode_button(
		"⚖️ Compare",
		"Side-by-side planet\nscale analysis",
		Color(0.15, 0.3, 0.45),
		Color(0.1, 0.2, 0.35),
		"compare"
	)
	row2.add_child(comp_panel)

	var gravity_panel := _make_mode_button(
		"🚀 Gravity Jump",
		"Physics jump height\n& mass simulator",
		Color(0.15, 0.4, 0.3),
		Color(0.1, 0.28, 0.2),
		"gravity"
	)
	row2.add_child(gravity_panel)

	var eclipse_panel := _make_mode_button(
		"🌒 Eclipses",
		"Solar/lunar eclipse\n3D shadow cones",
		Color(0.35, 0.2, 0.45),
		Color(0.25, 0.12, 0.32),
		"eclipse"
	)
	row2.add_child(eclipse_panel)

	var quiz_panel := _make_mode_button(
		"🧠 Quiz",
		"Test 3D astronomy\nknowledge & score",
		Color(0.4, 0.15, 0.35),
		Color(0.3, 0.1, 0.25),
		"quiz"
	)
	row2.add_child(quiz_panel)

	# === Footer ===
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "Tap a mode to begin  •  CosmoScope v1.0"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.position = Vector2(-200, -35)
	footer.size = Vector2(400, 25)
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.45, 0.48, 0.6, 0.6))
	add_child(footer)

func _make_mode_button(title_text: String, desc_text: String,
		bg_color: Color, hover_color: Color, mode_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "%sPanel" % mode_id.to_upper()
	panel.custom_minimum_size = Vector2(160, 105)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.6, 0.8, 0.3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82, 0.85))
	vbox.add_child(desc_lbl)

	# Make the entire panel clickable.
	var btn := Button.new()
	btn.name = "%sButton" % mode_id.to_upper()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Transparent style overrides so the Button doesn't draw its own box.
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)

	btn.pressed.connect(func():
		mode_selected.emit(mode_id)
	)
	panel.add_child(btn)

	# Hover feedback: brighten border.
	btn.mouse_entered.connect(func():
		style.border_color = Color(0.7, 0.8, 1.0, 0.7)
		style.bg_color = hover_color.lightened(0.15)
	)
	btn.mouse_exited.connect(func():
		style.border_color = Color(0.5, 0.6, 0.8, 0.3)
		style.bg_color = bg_color
	)

	return panel
