extends Control
## Interactive 3D Solar System Knowledge Quiz.
##
## Layout (anchor-based, no manual position overrides):
##   [Header 56px — full width]
##   [Left: 3D SubViewport 40%  |  Right: Question + Options + Explanation 60%]
##
## 3D preview: pre-created SphereMesh, only material_override swapped per question.
## No queue_free, no call_deferred — synchronous material swaps only.

const SolarSystemData := preload("res://data/planets.gd")
const PLANET_SHADER   := preload("res://shaders/planet.gdshader")
const SUN_SHADER      := preload("res://shaders/sun.gdshader")

# ── Quiz data ──────────────────────────────────────────────────────
const QUESTIONS: Array = [
	{
		"q":       "Which planet is the HOTTEST in the Solar System due to a runaway greenhouse effect?",
		"target":  "Venus",
		"opts":    ["Mercury", "Venus", "Mars", "Jupiter"],
		"correct": 1,
		"explain": "Venus reaches 465 °C — hotter than Mercury — because its thick CO₂ atmosphere traps all heat."
	},
	{
		"q":       "Which body contains 99.86 % of the entire Solar System's mass?",
		"target":  "Sun",
		"opts":    ["Jupiter", "Saturn", "The Sun", "Earth"],
		"correct": 2,
		"explain": "The Sun's enormous mass provides the gravity that keeps every planet in its orbit."
	},
	{
		"q":       "Which planet rotates almost entirely on its side (axial tilt ≈ 98°)?",
		"target":  "Uranus",
		"opts":    ["Neptune", "Uranus", "Saturn", "Mars"],
		"correct": 1,
		"explain": "Uranus's extreme tilt means its poles receive more direct sunlight than its equator!"
	},
	{
		"q":       "Which moon is the LARGEST natural satellite in the Solar System?",
		"target":  "Jupiter",
		"opts":    ["Titan", "Earth's Moon", "Ganymede", "Io"],
		"correct": 2,
		"explain": "Ganymede (orbiting Jupiter) is even larger than the planet Mercury and has its own magnetic field."
	},
	{
		"q":       "Which small icy body produces a glowing tail that always points AWAY from the Sun?",
		"target":  "Sun",
		"opts":    ["Phobos", "Halley's Comet", "Ceres", "Vesta"],
		"correct": 1,
		"explain": "Solar wind and radiation pressure push cometary gas and dust away from the Sun, forming the tail."
	},
]

const HEADER_H := 56.0
const MARGIN   := 10.0
const LETTERS  := ["A", "B", "C", "D"]

# ── State ──────────────────────────────────────────────────────────
var _q_idx:  int = 0
var _score:  int = 0

# ── UI refs ────────────────────────────────────────────────────────
var _q_num_lbl:    Label
var _q_lbl:        Label
var _opt_btns:     Array[Button] = []
var _explain_lbl:  Label
var _next_btn:     Button
var _score_lbl:    Label

# ── 3D preview ────────────────────────────────────────────────────
var _preview_mesh: MeshInstance3D    # pre-created, stays in viewport
var _rot_y: float = 0.0

# ══════════════════════════════════════════════════════════════════
func _ready() -> void:
	_build_ui()
	_show_question(0)

func _process(delta: float) -> void:
	_rot_y += delta * 0.50
	if is_instance_valid(_preview_mesh):
		_preview_mesh.rotation.y = _rot_y

# ══════════════════════════════════════════════════════════════════
#  UI BUILD
# ══════════════════════════════════════════════════════════════════
func _build_ui() -> void:
	# Dark background.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_header()

	# ── Body row anchored below header ─────────────────────────────
	var body := HBoxContainer.new()
	body.anchor_left   = 0.0
	body.anchor_top    = 0.0
	body.anchor_right  = 1.0
	body.anchor_bottom = 1.0
	body.offset_left   = MARGIN
	body.offset_top    = HEADER_H + MARGIN
	body.offset_right  = -MARGIN
	body.offset_bottom = -MARGIN
	body.add_theme_constant_override("separation", 16)
	add_child(body)

	# ── Left: 3D viewport (40 %) ────────────────────────────────────
	var svc := SubViewportContainer.new()
	svc.stretch               = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_stretch_ratio = 0.40
	svc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d              = true   # CRITICAL: isolate this VP's 3D world
	vp.transparent_bg            = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 2.8)
	cam.current  = true
	vp.add_child(cam)

	var key := DirectionalLight3D.new()
	key.look_at_from_position(Vector3(4, 4, 4), Vector3.ZERO, Vector3.UP)
	key.light_energy = 1.3
	vp.add_child(key)

	var fill := OmniLight3D.new()
	fill.position     = Vector3(-3, 1, 2)
	fill.light_energy = 0.45
	fill.light_color  = Color(0.6, 0.7, 1.0)
	vp.add_child(fill)

	# Pre-created planet sphere — only material swapped between questions.
	var sphere := SphereMesh.new()
	sphere.radius          = 1.0
	sphere.height          = 2.0
	sphere.radial_segments = 64
	sphere.rings           = 32

	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.mesh = sphere
	vp.add_child(_preview_mesh)

	# ── Right: question + answers panel (60 %) ─────────────────────
	var q_panel := PanelContainer.new()
	q_panel.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	q_panel.size_flags_stretch_ratio = 0.60
	q_panel.size_flags_vertical      = Control.SIZE_EXPAND_FILL
	var qps := StyleBoxFlat.new()
	qps.bg_color             = Color(0.07, 0.09, 0.17, 0.90)
	qps.border_width_left    = 2
	qps.border_color         = Color(0.30, 0.55, 0.90, 0.55)
	qps.content_margin_left   = 22
	qps.content_margin_right  = 22
	qps.content_margin_top    = 18
	qps.content_margin_bottom = 18
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		qps.set("corner_radius_" + c, 10)
	q_panel.add_theme_stylebox_override("panel", qps)
	body.add_child(q_panel)

	# Inner VBox for all question content.
	var qv := VBoxContainer.new()
	qv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	qv.add_theme_constant_override("separation", 10)
	q_panel.add_child(qv)

	# Question counter label.
	_q_num_lbl = Label.new()
	_q_num_lbl.add_theme_font_size_override("font_size", 12)
	_q_num_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.88))
	qv.add_child(_q_num_lbl)

	# Question text.
	_q_lbl = Label.new()
	_q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_lbl.add_theme_font_size_override("font_size", 17)
	_q_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.52))
	qv.add_child(_q_lbl)

	# Thin separator.
	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.28, 0.38, 0.60, 0.4)
	sep_s.content_margin_top = 1
	sep.add_theme_stylebox_override("separator", sep_s)
	qv.add_child(sep)

	# 4 answer option buttons.
	for i in 4:
		var btn := Button.new()
		btn.name                    = "Opt%d" % i
		btn.custom_minimum_size     = Vector2(0, 44)
		btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
		btn.clip_text               = false
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		_set_btn_style(btn, "idle")
		var idx := i
		btn.pressed.connect(func(): _on_answer(idx))
		qv.add_child(btn)
		_opt_btns.append(btn)

	# Explanation text (hidden until answered).
	_explain_lbl = Label.new()
	_explain_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain_lbl.add_theme_font_size_override("font_size", 14)
	_explain_lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	_explain_lbl.visible = false
	qv.add_child(_explain_lbl)

	# Elastic spacer — pushes Next button to the very bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	qv.add_child(spacer)

	# Next / Restart button.
	_next_btn = Button.new()
	_next_btn.text                  = "Next Question  ➔"
	_next_btn.custom_minimum_size   = Vector2(0, 44)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.add_theme_font_size_override("font_size", 15)
	_next_btn.visible = false
	_set_btn_style(_next_btn, "next")
	_next_btn.pressed.connect(func(): _on_next())
	qv.add_child(_next_btn)

func _build_header() -> void:
	var header := PanelContainer.new()
	header.anchor_left   = 0.0
	header.anchor_top    = 0.0
	header.anchor_right  = 1.0
	header.anchor_bottom = 0.0
	header.offset_bottom = HEADER_H
	var hs := StyleBoxFlat.new()
	hs.bg_color            = Color(0.08, 0.12, 0.22, 0.96)
	hs.content_margin_left  = 14
	hs.content_margin_right = 14
	header.add_theme_stylebox_override("panel", hs)

	var row := HBoxContainer.new()
	header.add_child(row)

	var back := Button.new()
	back.text = "← Menu"
	back.add_theme_font_size_override("font_size", 14)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.18, 0.22, 0.36)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		bs.set("corner_radius_" + c, 6)
	back.add_theme_stylebox_override("normal", bs)
	back.pressed.connect(func():
		Input.action_press("ui_cancel")
		await get_tree().process_frame
		Input.action_release("ui_cancel"))
	row.add_child(back)

	var title := Label.new()
	title.text = "🧠  Solar System Knowledge Quiz"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	row.add_child(title)

	_score_lbl = Label.new()
	_score_lbl.text = "Score: 0 / %d" % QUESTIONS.size()
	_score_lbl.custom_minimum_size = Vector2(110, 0)
	_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_lbl.add_theme_font_size_override("font_size", 15)
	_score_lbl.add_theme_color_override("font_color", Color(0.38, 0.88, 0.52))
	row.add_child(_score_lbl)

	add_child(header)

# ══════════════════════════════════════════════════════════════════
#  QUIZ LOGIC
# ══════════════════════════════════════════════════════════════════
func _show_question(idx: int) -> void:
	if idx >= QUESTIONS.size():
		_show_results()
		return

	_q_idx = idx
	var q: Dictionary = QUESTIONS[idx]

	_q_num_lbl.text    = "Question  %d  of  %d" % [idx + 1, QUESTIONS.size()]
	_q_lbl.text        = q.q
	_explain_lbl.visible = false
	_next_btn.visible    = false

	var opts: Array = q.opts
	for i in 4:
		var btn := _opt_btns[i]
		btn.text     = "  %s.  %s" % [LETTERS[i], opts[i]]
		btn.visible  = true
		btn.disabled = false
		_set_btn_style(btn, "idle")

	# Apply the question's planet material to the pre-created sphere.
	_apply_preview(q.target)

func _on_answer(picked: int) -> void:
	var q: Dictionary = QUESTIONS[_q_idx]
	var correct: int  = q.correct

	# Disable all buttons immediately.
	for btn in _opt_btns:
		btn.disabled = true

	if picked == correct:
		_score += 1
		_score_lbl.text = "Score: %d / %d" % [_score, QUESTIONS.size()]
		_set_btn_style(_opt_btns[picked], "correct")
		_explain_lbl.text = "✅  Correct!   " + q.explain
	else:
		_set_btn_style(_opt_btns[picked],  "wrong")
		_set_btn_style(_opt_btns[correct], "correct")
		_explain_lbl.text = "❌  Not quite.   " + q.explain

	_explain_lbl.visible = true
	_next_btn.visible    = true

func _on_next() -> void:
	_show_question(_q_idx + 1)

func _show_results() -> void:
	var pct := int(float(_score) / float(QUESTIONS.size()) * 100.0)
	var grade: String
	if   pct >= 80: grade = "Excellent work! 🌟"
	elif pct >= 60: grade = "Good job! 🚀"
	elif pct >= 40: grade = "Not bad — keep exploring! 🔭"
	else:           grade = "Keep studying the cosmos! ☄️"

	_q_num_lbl.text = "Quiz Complete!"
	_q_lbl.text     = "🎉  Final Score:  %d / %d   (%d%%)\n\n%s" % [
		_score, QUESTIONS.size(), pct, grade]

	for btn in _opt_btns:
		btn.visible = false
	_explain_lbl.visible = false

	_next_btn.text    = "🔄  Play Again"
	_next_btn.visible = true
	# Reconnect for restart (disconnect previous _on_next first).
	_next_btn.pressed.disconnect(_on_next)
	_next_btn.pressed.connect(_restart, CONNECT_ONE_SHOT)

func _restart() -> void:
	_score = 0
	_score_lbl.text = "Score: 0 / %d" % QUESTIONS.size()
	for btn in _opt_btns:
		btn.visible = true
	# Reconnect normal flow.
	if not _next_btn.pressed.is_connected(_on_next):
		_next_btn.pressed.connect(_on_next)
	_show_question(0)

# ══════════════════════════════════════════════════════════════════
#  3D PREVIEW — synchronous material swap on existing mesh
# ══════════════════════════════════════════════════════════════════
func _apply_preview(target: String) -> void:
	if not is_instance_valid(_preview_mesh):
		return

	var data := _find_planet(target)
	var mat  := ShaderMaterial.new()

	if target == "Sun" or data.is_empty():
		mat.shader = SUN_SHADER
		var sun_data: Dictionary = SolarSystemData.SUN
		mat.set_shader_parameter("hot", sun_data.get("color", Color(1.0, 0.85, 0.2)))
		var sun_tex: String = sun_data.get("texture", "")
		if not sun_tex.is_empty() and ResourceLoader.exists(sun_tex):
			mat.set_shader_parameter("sun_texture", load(sun_tex))
			mat.set_shader_parameter("use_texture", true)
	else:
		mat.shader = PLANET_SHADER
		mat.set_shader_parameter("color_a",             data.color)
		mat.set_shader_parameter("color_b",             data.get("color2", data.color))
		mat.set_shader_parameter("banded",              data.get("banded",     false))
		mat.set_shader_parameter("atmosphere_color",    data.get("atmosphere", Color(0.5, 0.5, 0.5)))
		mat.set_shader_parameter("atmosphere_strength", data.get("atmo",       0.0))
		mat.set_shader_parameter("has_spot",            data.get("spot",       false))
		mat.set_shader_parameter("water",               data.get("ocean",      false))
		var tex_path: String = data.get("texture", "")
		if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
			mat.set_shader_parameter("albedo_texture", load(tex_path) as Texture2D)
			mat.set_shader_parameter("use_texture", true)

	_preview_mesh.material_override = mat

func _find_planet(target: String) -> Dictionary:
	if target == "Sun":
		return SolarSystemData.SUN
	for p in SolarSystemData.PLANETS:
		if p.name == target:
			return p
	for p in SolarSystemData.DWARF_PLANETS:
		if p.name == target:
			return p
	return {}

# ══════════════════════════════════════════════════════════════════
#  BUTTON STYLING
# ══════════════════════════════════════════════════════════════════
func _set_btn_style(btn: Button, state: String) -> void:
	var s := StyleBoxFlat.new()
	match state:
		"idle":
			s.bg_color = Color(0.12, 0.17, 0.30, 0.90)
		"correct":
			s.bg_color = Color(0.10, 0.48, 0.22, 0.95)
		"wrong":
			s.bg_color = Color(0.52, 0.14, 0.14, 0.95)
		"next":
			s.bg_color = Color(0.15, 0.42, 0.26, 0.95)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		s.set("corner_radius_" + c, 8)
	s.content_margin_left  = 14
	s.content_margin_right = 14
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_stylebox_override("disabled", s)
