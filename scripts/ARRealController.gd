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
	var hint := "Placed! Walk around it. (tap to move)" if _placed else "Point at a surface and TAP to place."
	_status.text = "%s\nTracking:%s  feeds:%d ids:[%s] bound:%s" % [hint, track, feed_count, ids, str(_feed_bound)]

func _unhandled_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if tapped and _ar_ready:
		_place_in_front()

func _place_in_front() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	_solar.global_position = cam.global_position + fwd * place_distance + Vector3(0.0, -0.2, 0.0)
	_solar.visible = true
	_placed = true

func _exit_tree() -> void:
	get_viewport().use_xr = false
	if _plugin != null:
		_plugin.uninitializeEnvironment()
