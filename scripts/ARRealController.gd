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

func _ready() -> void:
	_build_world()
	_build_hud()
	_init_ar()

func _init_ar() -> void:
	# The Android singleton drives the ARCore session lifecycle.
	if Engine.has_singleton("ARCorePlugin"):
		_plugin = Engine.get_singleton("ARCorePlugin")
		_plugin.initializeEnvironment()

	# The GDExtension XRInterface wrapper autoload starts tracking + passthrough.
	var inst := get_node_or_null("/root/ARCoreInterfaceInstance")
	if inst != null and _plugin != null:
		inst.enable_horizontal_plane_detection(true)
		inst.start()  # initializes the interface and sets viewport.use_xr = true
		_ar_ready = true

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
	if _placed:
		_status.text = "Placed! Walk around the Solar System.\nTracking: %s   (tap to move)" % track
	else:
		_status.text = "Point at a flat surface and TAP to place.\nTracking: %s" % track

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
