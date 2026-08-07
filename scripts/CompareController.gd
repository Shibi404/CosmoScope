extends Control
## Side-by-side 3D Planet Comparison Tool.
##
## Architecture:
##  • SubViewport nodes are set up ONCE in _build_ui().
##  • Each viewport contains a pre-created Camera3D + lights + SphereMesh.
##  • On selection change _update_comparison() only swaps material_override —
##    no queue_free, no call_deferred, no timing races.
##  • Material creation mirrors SolarSystem.gd _planet_material() exactly.

const SolarSystemData := preload("res://data/planets.gd")
const PLANET_SHADER   := preload("res://shaders/planet.gdshader")
const SUN_SHADER      := preload("res://shaders/sun.gdshader")

# ── Constants ──────────────────────────────────────────────────────
const HEADER_H  := 56.0
const STATS_H   := 185.0
const MARGIN    := 10.0

# ── State ──────────────────────────────────────────────────────────
var _planet_list: Array[Dictionary] = []
var _option1: OptionButton
var _option2: OptionButton
var _mesh1:   MeshInstance3D
var _mesh2:   MeshInstance3D
var _stats_lbl: RichTextLabel
var _rot1: float = 0.0
var _rot2: float = 0.0

# ══════════════════════════════════════════════════════════════════
func _ready() -> void:
	# Build ordered list: Sun, 8 planets, dwarf planets.
	_planet_list.append(SolarSystemData.SUN)
	for p in SolarSystemData.PLANETS:
		_planet_list.append(p)
	for dp in SolarSystemData.DWARF_PLANETS:
		_planet_list.append(dp)

	_build_ui()
	# Initial render after the first layout pass so SubViewports have a size.
	_update_comparison()

func _process(delta: float) -> void:
	_rot1 += delta * 0.45
	_rot2 += delta * 0.45
	if is_instance_valid(_mesh1):
		_mesh1.rotation.y = _rot1
	if is_instance_valid(_mesh2):
		_mesh2.rotation.y = _rot2

# ══════════════════════════════════════════════════════════════════
#  UI BUILD
# ══════════════════════════════════════════════════════════════════
func _build_ui() -> void:
	# Full-screen dark background.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_header()

	# Stats panel anchored to the bottom.
	var stats_root := PanelContainer.new()
	stats_root.anchor_left   = 0.0
	stats_root.anchor_top    = 1.0
	stats_root.anchor_right  = 1.0
	stats_root.anchor_bottom = 1.0
	stats_root.offset_left   = MARGIN
	stats_root.offset_right  = -MARGIN
	stats_root.offset_top    = -(STATS_H + MARGIN)
	stats_root.offset_bottom = -MARGIN
	var ss := StyleBoxFlat.new()
	ss.bg_color           = Color(0.06, 0.08, 0.15, 0.96)
	ss.border_width_top   = 2
	ss.border_color       = Color(0.30, 0.55, 0.90, 0.55)
	ss.content_margin_left   = 18
	ss.content_margin_right  = 18
	ss.content_margin_top    = 10
	ss.content_margin_bottom = 10
	stats_root.add_theme_stylebox_override("panel", ss)

	_stats_lbl = RichTextLabel.new()
	_stats_lbl.bbcode_enabled = true
	_stats_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_lbl.add_theme_font_size_override("normal_font_size", 14)
	_stats_lbl.add_theme_color_override("default_color", Color(0.90, 0.92, 0.98))
	stats_root.add_child(_stats_lbl)
	add_child(stats_root)

	# Middle HBox — fills area between header and stats panel.
	var mid := HBoxContainer.new()
	mid.anchor_left   = 0.0
	mid.anchor_top    = 0.0
	mid.anchor_right  = 1.0
	mid.anchor_bottom = 1.0
	mid.offset_left   = MARGIN
	mid.offset_top    = HEADER_H + MARGIN
	mid.offset_right  = -MARGIN
	mid.offset_bottom = -(STATS_H + MARGIN * 2.0)
	mid.add_theme_constant_override("separation", 12)
	add_child(mid)

	_option1 = OptionButton.new()
	_option2 = OptionButton.new()

	_mesh1 = _build_panel(mid, _option1)
	_mesh2 = _build_panel(mid, _option2)

	# Populate both dropdowns and set defaults.
	for i in _planet_list.size():
		_option1.add_item(_planet_list[i].name, i)
		_option2.add_item(_planet_list[i].name, i)

	# Defaults: Mercury (idx 1 in list) and Jupiter (idx 5).
	_option1.select(1)
	_option2.select(5)

	_option1.item_selected.connect(func(_i: int): _update_comparison())
	_option2.item_selected.connect(func(_i: int): _update_comparison())

## Build one viewport panel (Left or Right). Returns the pre-created SphereMesh instance.
func _build_panel(parent: HBoxContainer, opt: OptionButton) -> MeshInstance3D:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	parent.add_child(vbox)

	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", 15)
	vbox.add_child(opt)

	var svc := SubViewportContainer.new()
	svc.stretch               = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d            = true   # CRITICAL: isolate this VP's 3D world
	vp.transparent_bg          = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)

	# Camera — fixed position looking at origin.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 2.8)
	cam.current  = true
	vp.add_child(cam)

	# Key light (directional, from upper-right).
	var key := DirectionalLight3D.new()
	key.position = Vector3(4.0, 4.0, 4.0)
	key.look_at_from_position(Vector3(4.0, 4.0, 4.0), Vector3.ZERO, Vector3.UP)
	key.light_energy = 1.3
	vp.add_child(key)

	# Fill light (soft blue from opposite side).
	var fill := OmniLight3D.new()
	fill.position      = Vector3(-3.0, 1.0, 2.0)
	fill.light_energy  = 0.45
	fill.light_color   = Color(0.60, 0.70, 1.0)
	vp.add_child(fill)

	# Pre-created planet sphere — stays in the viewport permanently.
	var sphere := SphereMesh.new()
	sphere.radius          = 1.0
	sphere.height          = 2.0
	sphere.radial_segments = 64
	sphere.rings           = 32

	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	vp.add_child(mi)

	return mi

func _build_header() -> void:
	var header := PanelContainer.new()
	header.anchor_left   = 0.0
	header.anchor_top    = 0.0
	header.anchor_right  = 1.0
	header.anchor_bottom = 0.0
	header.offset_bottom = HEADER_H
	var hs := StyleBoxFlat.new()
	hs.bg_color            = Color(0.08, 0.10, 0.18, 0.96)
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
	title.text = "⚖️  3D Planet Side-by-Side Comparison Tool"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	row.add_child(title)
	add_child(header)

# ══════════════════════════════════════════════════════════════════
#  COMPARISON UPDATE — synchronous, no deferred calls
# ══════════════════════════════════════════════════════════════════
func _update_comparison() -> void:
	var idx1 := _option1.selected
	var idx2 := _option2.selected
	if idx1 < 0 or idx1 >= _planet_list.size(): return
	if idx2 < 0 or idx2 >= _planet_list.size(): return

	var d1: Dictionary = _planet_list[idx1]
	var d2: Dictionary = _planet_list[idx2]

	# Apply each planet's material to its dedicated pre-created mesh.
	_apply_material(_mesh1, d1)
	_apply_material(_mesh2, d2)
	_update_stats(d1, d2)

## Mirror of SolarSystem.gd's _planet_material() / _sun_material() —
## creates and applies a ShaderMaterial directly on the mesh instance.
func _apply_material(mi: MeshInstance3D, data: Dictionary) -> void:
	if not is_instance_valid(mi):
		return

	var mat := ShaderMaterial.new()

	if data.get("name", "") == "Sun":
		mat.shader = SUN_SHADER
		mat.set_shader_parameter("hot", data.get("color", Color(1.0, 0.85, 0.2)))
		var sun_tex: String = data.get("texture", "")
		if not sun_tex.is_empty() and ResourceLoader.exists(sun_tex):
			mat.set_shader_parameter("sun_texture", load(sun_tex))
			mat.set_shader_parameter("use_texture", true)
	else:
		mat.shader = PLANET_SHADER
		# Replicate _planet_material() exactly — use direct key access like SolarSystem.gd.
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
			mat.set_shader_parameter("use_texture",    true)
		# Note: if use_texture is never set to true, the shader defaults to false (procedural).

	mi.material_override = mat

# ══════════════════════════════════════════════════════════════════
#  STATS TABLE
# ══════════════════════════════════════════════════════════════════
func _update_stats(d1: Dictionary, d2: Dictionary) -> void:
	var n1: String = str(d1.get("name", "?")).to_upper()
	var n2: String = str(d2.get("name", "?")).to_upper()

	# Build typed row arrays — all values are converted to String here.
	var rows: Array[PackedStringArray] = [
		PackedStringArray(["Equatorial Diameter",
			_commas(int(d1.get("diameter_km", 0))) + " km",
			_commas(int(d2.get("diameter_km", 0))) + " km"]),
		PackedStringArray(["Distance from Sun",
			_fmt(float(d1.get("sun_dist_mkm", 0.0))) + " M km",
			_fmt(float(d2.get("sun_dist_mkm", 0.0))) + " M km"]),
		PackedStringArray(["Orbital Period",
			str(d1.get("year", "—")),
			str(d2.get("year", "—"))]),
		PackedStringArray(["Rotation Period",
			str(d1.get("day",  "—")),
			str(d2.get("day",  "—"))]),
		PackedStringArray(["Known Moons",
			str(int(d1.get("moons", 0))),
			str(int(d2.get("moons", 0)))]),
		PackedStringArray(["Surface Gravity",
			"%.2f × Earth" % float(d1.get("gravity_g", 1.0)),
			"%.2f × Earth" % float(d2.get("gravity_g", 1.0))]),
		PackedStringArray(["Fun Fact",
			str(d1.get("fact", "—")).left(55),
			str(d2.get("fact", "—")).left(55)]),
	]

	var bb: String = "[table=3]"
	bb += "[cell][b]PROPERTY[/b][/cell]"
	bb += "[cell][color=#aac4ff][b]  %s[/b][/color][/cell]" % n1
	bb += "[cell][color=#ffcca0][b]  %s[/b][/color][/cell]" % n2
	for row: PackedStringArray in rows:
		bb += "[cell]%s[/cell]"                           % row[0]
		bb += "[cell][color=#aac4ff]%s[/color][/cell]"   % row[1]
		bb += "[cell][color=#ffcca0]%s[/color][/cell]"   % row[2]
	bb += "[/table]"

	_stats_lbl.text = bb

# ══════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════
func _commas(n: int) -> String:
	var s: String   = str(n)
	var out: String = ""
	var cnt: int    = 0
	for i: int in range(s.length() - 1, -1, -1):
		out  = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out

func _fmt(v: float) -> String:
	if v == 0.0:
		return "—"
	return ("%.1f" % v) if (v != floor(v)) else str(int(v))
