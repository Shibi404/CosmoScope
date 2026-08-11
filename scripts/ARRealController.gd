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

func _ready() -> void:
	_build_world()
	_build_hud()
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

	# A fill light; ARCore light-estimation could later drive this for realism.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_status = Label.new()
	_status.position = Vector2(16, 16)
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

	var ids := ""
	for i in feed_count:
		ids += str(CameraServer.get_feed(i).get_id()) + " "
	var hint := ""
	if not _placed:
		hint = "Point at a surface and TAP to place."
	elif _dragging:
		hint = "Dragging… move your finger to reposition."
	else:
		hint = "Long-press & drag to move. Two fingers: scale / rotate."
	_status.text = "%s\nTracking:%s  feeds:%d ids:[%s]" % [hint, track, feed_count, ids]

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
			# A quick, still tap places the system (only before it's placed).
			if was_single and not _dragging and not _placed and held < LONG_PRESS_SEC and moved < 30.0:
				_place_in_front()
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

func _exit_tree() -> void:
	get_viewport().use_xr = false
	if _plugin != null:
		_plugin.uninitializeEnvironment()
