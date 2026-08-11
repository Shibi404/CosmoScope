extends Node3D
## Real world-tracked AR using the ARCore GDExtension plugin (Android only).
##
## Once placed, the Solar System is anchored in the real world — walk around it
## and it stays put, viewed through the live camera (passthrough via ARCore).
## On non-AR platforms (e.g. desktop) it shows a message instead of crashing.

const SolarSystemScript := preload("res://scripts/SolarSystem.gd")

## World scale of the placed model (SolarSystem spans ~26 units -> keep it small).
@export var model_scale: float = 0.04
## How far in front of the camera the system is dropped, in metres.
@export var place_distance: float = 0.8

var _plugin: Object = null           # ARCorePlugin Android singleton (from the .aar)
var _solar: Node3D = null
var _placed: bool = false
var _ar_ready: bool = false
var _status: Label = null
var _cam_env: Environment = null
var _feed_bound: bool = false

# Touch gestures: long-press to drag, two fingers to scale/rotate.
const LONG_PRESS_SEC := 0.35
var _touches: Dictionary = {}
var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _dragging: bool = false
var _pinch_dist: float = 0.0
var _twist_angle: float = 0.0

var _planets: Array[Node3D] = []
var _info_panel: PanelContainer = null
var _info_rich: RichTextLabel = null
var _last_tap_info: String = ""

func _ready() -> void:
	_build_world()
	_build_hud()
	_build_info_panel()
	_init_ar()

func _init_ar() -> void:
	# BG_CAMERA_FEED can only fetch the ARCore feed when the server is monitoring.
	CameraServer.monitoring_feeds = true

	# The Android singleton drives the ARCore session lifecycle.
	if Engine.has_singleton("ARCorePlugin"):
		_plugin = Engine.get_singleton("ARCorePlugin")
		_plugin.initializeEnvironment()

	# The GDExtension XRInterface wrapper autoload starts tracking + passthrough.
	# NOTE: only call start() here. Calling plane-detection toggles before the
	# session exists dereferences a null session and hard-crashes (configureSession).
	# World tracking alone anchors placed content; plane detection can be enabled
	# later, safely, once tracking is established.
	var inst := get_node_or_null("/root/ARCoreInterfaceInstance")
	if inst != null and _plugin != null:
		inst.start()  # initializes the interface + session and sets viewport.use_xr = true
		_ar_ready = true
		_setup_camera_passthrough()

# The ARCore camera image is exposed as a CameraFeed; Godot draws it as the 3D
# background only when the camera's environment uses BG_CAMERA_FEED. Without
# this the viewport clears to grey and hides the passthrough.
func _setup_camera_passthrough() -> void:
	var cam: Camera3D = get_node_or_null("XROrigin3D/XRCamera3D")
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam != null:
		_cam_env = Environment.new()
		_cam_env.background_mode = Environment.BG_CAMERA_FEED
		cam.environment = _cam_env

func _build_world() -> void:
	_solar = Node3D.new()
	_solar.set_script(SolarSystemScript)
	_solar.set("show_corona", false)  # the additive corona reads as haze up close in AR
	_solar.scale = Vector3.ONE * model_scale
	_solar.visible = false  # shown once the user taps to place it
	add_child(_solar)
	_planets = _solar.get_planet_bodies()

	# A fill light; ARCore light-estimation could later drive this for realism.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	# Back-to-menu button (top-left).
	var back := Button.new()
	back.text = "← Menu"
	back.position = Vector2(16, 16)
	back.add_theme_font_size_override("font_size", 16)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.12, 0.15, 0.25, 0.9)
	bs.set_corner_radius_all(8)
	bs.content_margin_left = 14
	bs.content_margin_right = 14
	bs.content_margin_top = 8
	bs.content_margin_bottom = 8
	back.add_theme_stylebox_override("normal", bs)
	back.pressed.connect(_go_to_menu)
	layer.add_child(back)

	_status = Label.new()
	_status.position = Vector2(16, 66)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 5)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)

func _process(_delta: float) -> void:
	if _status == null:
		return
	if not _ar_ready:
		_status.text = "Real AR needs an ARCore-capable Android device.\n(No ARCore session on this platform.)"
		return
	var track := ""
	var inst := get_node_or_null("/root/ARCoreInterfaceInstance")
	if inst != null and inst.has_method("get_tracking_status"):
		track = str(inst.get_tracking_status())

	# Bind the camera-feed background to the actual ARCore feed id once it
	# registers (it may not be the default id 1).
	var feed_count := CameraServer.get_feed_count()
	if _cam_env != null and not _feed_bound and feed_count > 0:
		_cam_env.background_camera_feed_id = CameraServer.get_feed(feed_count - 1).get_id()
		_feed_bound = true

	var hint := ""
	if not _placed:
		hint = "Point at a surface and TAP to place."
	elif _dragging:
		hint = "Dragging… move your finger to reposition."
	else:
		hint = "Long-press & drag to move. Two fingers: scale / rotate."
	_status.text = "%s\nTracking:%s  feeds:%d  %s" % [hint, track, feed_count, _last_tap_info]

	# Long-press onset: a single finger held still for a moment starts a drag.
	if _placed and not _dragging and _touches.size() == 1:
		var now := Time.get_ticks_msec() / 1000.0
		var cur: Vector2 = _touches.values()[0]
		if now - _press_time >= LONG_PRESS_SEC and cur.distance_to(_press_pos) < 40.0:
			_dragging = true

func _unhandled_input(event: InputEvent) -> void:
	if not _ar_ready:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_press_pos = event.position
				_press_time = Time.get_ticks_msec() / 1000.0
				_dragging = false
			elif _touches.size() == 2:
				_begin_two_finger()
		else:
			var was_single: bool = _touches.size() == 1
			var held: float = Time.get_ticks_msec() / 1000.0 - _press_time
			var moved: float = event.position.distance_to(_press_pos)
			_touches.erase(event.index)
			# A quick, still tap: place the system, or (once placed) select a planet.
			if was_single and not _dragging and held < LONG_PRESS_SEC and moved < 45.0:
				if not _placed:
					_place_in_front()
				else:
					var hit := _try_select_planet(event.position)
					if hit != null:
						_show_planet_info(hit)
					elif _info_panel != null:
						_info_panel.visible = false
			_dragging = false

	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1 and _placed and _dragging:
			_drag_to(event.position)
		elif _touches.size() == 2 and _placed:
			_update_two_finger()

func _place_in_front() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	_solar.global_position = cam.global_position + fwd * place_distance + Vector3(0.0, -0.2, 0.0)
	_solar.visible = true
	_placed = true

# Drag the system across a horizontal plane at its current height (like AR
# Quick Look), projecting the touch ray onto that plane.
func _drag_to(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _solar == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var plane_y := _solar.global_position.y
	var t := (plane_y - from.y) / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	_solar.global_position = Vector3(hit.x, plane_y, hit.z)

func _build_info_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)

	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_info_panel.offset_left = -300.0
	_info_panel.offset_right = -16.0
	_info_panel.offset_top = -150.0
	_info_panel.offset_bottom = 150.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.13, 0.92)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.6, 0.95, 0.6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_info_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_info_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_info_panel.add_child(vbox)

	_info_rich = RichTextLabel.new()
	_info_rich.bbcode_enabled = true
	_info_rich.fit_content = true
	_info_rich.scroll_active = false
	_info_rich.custom_minimum_size = Vector2(268, 0)
	_info_rich.add_theme_color_override("default_color", Color(0.9, 0.93, 0.98))
	vbox.add_child(_info_rich)

	var close := Button.new()
	close.text = "✕ Close"
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(func() -> void: _info_panel.visible = false)
	vbox.add_child(close)

# Screen-space pick: choose the planet whose projected position is nearest the
# tap (within a pixel tolerance). Far more forgiving than a 3D radius when the
# AR model is small and orbiting.
func _try_select_planet(screen_pos: Vector2) -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _solar == null:
		_last_tap_info = "tap: no camera"
		return null
	var best: Node3D = null
	var best_d := 110.0  # pixel tolerance
	for p in _planets:
		if not is_instance_valid(p) or cam.is_position_behind(p.global_position):
			continue
		var sp := cam.unproject_position(p.global_position)
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = p
	_last_tap_info = "tap:%s d=%d" % ["none" if best == null else str(best.name), int(best_d)]
	return best

func _show_planet_info(planet: Node3D) -> void:
	if _info_rich == null:
		return
	var d: Dictionary = planet.get_meta("data", {})
	if d.is_empty():
		return
	var t := "[b][font_size=20]%s[/font_size][/b]\n\n" % d.name
	t += "Diameter: %s km\n" % _commas(int(d.get("diameter_km", 0)))
	t += "Distance: %s M km from Sun\n" % _trim(float(d.get("sun_dist_mkm", 0.0)))
	t += "Year: %s\n" % str(d.get("year", "-"))
	t += "Day: %s\n" % str(d.get("day", "-"))
	t += "Moons: %d\n" % int(d.get("moons", 0))
	t += "Gravity: %.2fx Earth\n" % float(d.get("gravity_g", 1.0))
	t += "\n[i]%s[/i]" % str(d.get("fact", ""))
	_info_rich.text = t
	_info_panel.visible = true

func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func _trim(v: float) -> String:
	return "%.1f" % v if v != floor(v) else str(int(v))

func _begin_two_finger() -> void:
	var pts := _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
	_twist_angle = ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()

# Pinch to scale, twist to rotate the placed system.
func _update_two_finger() -> void:
	if _solar == null:
		return
	var pts := _touches.values()
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var dist := p0.distance_to(p1)
	var angle := (p1 - p0).angle()
	if _pinch_dist > 1.0:
		model_scale = clampf(model_scale * (dist / _pinch_dist), 0.01, 0.4)
		_solar.scale = Vector3.ONE * model_scale
	_solar.rotate_y(angle - _twist_angle)
	_pinch_dist = dist
	_twist_angle = angle

func _go_to_menu() -> void:
	var main := get_node_or_null("/root/Main")
	if main != null and main.has_method("go_to_menu"):
		main.go_to_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _exit_tree() -> void:
	# Fully tear down XR, otherwise the viewport stays resized to the XR render
	# target and the next scene's UI (the menu) renders tiny.
	get_viewport().use_xr = false
	var inst := get_node_or_null("/root/ARCoreInterfaceInstance")
	if inst != null and inst.has_method("get_interface"):
		var iface = inst.get_interface()
		if iface != null and iface.is_initialized():
			iface.uninitialize()
	if _plugin != null:
		_plugin.uninitializeEnvironment()
