extends Camera3D
## Desktop-only helper camera for inspecting scenes in the editor.
##
## NOT used by the AR or VR modes — those supply their own cameras. This only
## exists so Phase 0 content can be viewed and verified with mouse orbit +
## scroll zoom before any device work.

@export var target: Vector3 = Vector3.ZERO
@export var distance: float = 40.0
@export var orbit_sensitivity: float = 0.005

var _yaw: float = 0.0
var _pitch: float = 0.4  # radians above the orbital plane
var _dragging: bool = false

func _ready() -> void:
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -1.4, 1.4)
		_update_transform()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		distance = maxf(5.0, distance - 2.0)
		_update_transform()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		distance += 2.0
		_update_transform()

func _update_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * distance
	position = target + offset
	look_at(target, Vector3.UP)
