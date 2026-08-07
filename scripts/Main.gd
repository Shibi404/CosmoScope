extends Node
## Main entry point — handles scene switching between Menu, AR, and VR modes
## with a fade-to-black transition.

const MENU_SCENE := "res://scenes/Menu.tscn"
const VR_SCENE := "res://scenes/VRScene.tscn"
const AR_SCENE := "res://scenes/ARScene.tscn"
const TOUR_SCENE := "res://scenes/TourScene.tscn"
const COMPARE_SCENE := "res://scenes/CompareScene.tscn"
const QUIZ_SCENE := "res://scenes/QuizScene.tscn"

var _current_scene: Node = null
var _fade_rect: ColorRect = null
var _fade_layer: CanvasLayer = null
var _transitioning: bool = false

func _ready() -> void:
	_build_fade_overlay()
	# Start by loading the menu.
	_load_scene(MENU_SCENE)

func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100  # on top of everything
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1.0)  # start opaque (fades in on first load)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

func _load_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true

	# Fade to black.
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 0.35)
	await tween.finished

	# Remove old scene.
	if _current_scene != null:
		_current_scene.queue_free()
		_current_scene = null

	# Instantiate new scene.
	var packed := load(path) as PackedScene
	_current_scene = packed.instantiate()
	add_child(_current_scene)

	# Connect signals if it's the menu.
	if _current_scene.has_signal("mode_selected"):
		_current_scene.mode_selected.connect(_on_mode_selected)

	# Fade from black.
	var tween2 := create_tween()
	tween2.tween_property(_fade_rect, "color:a", 0.0, 0.5)
	await tween2.finished
	_transitioning = false

func _on_mode_selected(mode: String) -> void:
	match mode:
		"vr":
			_load_scene(VR_SCENE)
		"ar":
			_load_scene(AR_SCENE)
		"tour":
			_load_scene(TOUR_SCENE)
		"compare":
			_load_scene(COMPARE_SCENE)
		"quiz":
			_load_scene(QUIZ_SCENE)

## Allow returning to menu from any mode via back button / Escape.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _current_scene != null and not _transitioning:
			_load_scene(MENU_SCENE)
