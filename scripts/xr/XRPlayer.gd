extends XROrigin3D
## The VR player: tracking origin, head camera, two tracked controllers with
## procedural hands and a laser pointer each.
##
## Inputs are read through small accessor functions (trigger / grip / stick /
## button) so the rest of the XR code never touches the OpenXR action names, and
## so a "simulated" player (no headset) can be driven by writing to `sim`.
## Actions used are the ones in Godot's default OpenXR action map.

const HANDS := ["left", "right"]

var camera: XRCamera3D
var controllers: Dictionary = {}     # "left"/"right" -> XRController3D
var _models: Dictionary = {}         # hand -> Node3D (authored in metres, scaled by world scale)
var _fingers: Dictionary = {}        # hand -> Array of finger pivots [thumb, index, middle, ring, pinky]
var _lasers: Dictionary = {}         # hand -> Node3D beam pivot (scaled along -Z = length in metres)
var _dots: Dictionary = {}           # hand -> MeshInstance3D end-of-laser dot
var real: bool = false               # true when a live OpenXR session drives tracking
var ws: float = 1.0                  # current world scale (game units per metre)

## Simulated inputs, used when `real` is false (tests / no headset).
var sim: Dictionary = {}
## Haptic pulses requested (for tests and debugging): hand -> [amplitude, duration]
var last_pulse: Dictionary = {}
var pulse_count: int = 0


func build(is_real: bool) -> void:
	real = is_real
	name = "XRPlayer"
	for h in HANDS:
		sim[h] = {"trigger": 0.0, "grip": 0.0, "stick": Vector2.ZERO, "ax": false, "by": false, "menu": false}
	camera = XRCamera3D.new()
	camera.name = "XRCamera"
	camera.near = 0.003
	camera.far = 4000.0
	camera.current = true
	add_child(camera)
	for h in HANDS:
		var c := XRController3D.new()
		c.name = "Controller_%s" % h
		c.tracker = "left_hand" if h == "left" else "right_hand"
		add_child(c)
		controllers[h] = c
		var parts := build_hand(h == "left")
		var model: Node3D = parts["root"]
		c.add_child(model)
		_models[h] = model
		_fingers[h] = parts["fingers"]
		var laser := Node3D.new()
		laser.name = "Laser"
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0025
		cyl.bottom_radius = 0.0025
		cyl.height = 1.0
		beam.mesh = cyl
		beam.material_override = _unshaded(Color(0.4, 0.85, 1.0), 0.75)
		beam.rotation_degrees.x = 90.0
		beam.position = Vector3(0.0, 0.0, -0.5)
		laser.add_child(beam)
		laser.position = Vector3(0.0, 0.0, -0.06)
		model.add_child(laser)
		_lasers[h] = laser
		var dot := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.012
		sph.height = 0.024
		dot.mesh = sph
		dot.material_override = _unshaded(Color(1.0, 1.0, 1.0), 1.0)
		dot.visible = false
		model.add_child(dot)
		_dots[h] = dot
		set_laser(h, false, 1.0)
	apply_world_scale(ws)


static func _unshaded(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# A simple low-poly hand authored in metres, palm at the origin, fingers along -Z.
static func build_hand(left: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "HandModel"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.9, 1.0)
	mat.metallic = 0.3
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.32, 0.5)
	mat.emission_energy_multiplier = 0.35
	var palm := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.085, 0.028, 0.09)
	palm.mesh = pb
	palm.material_override = mat
	palm.position = Vector3(0.0, 0.0, -0.03)
	root.add_child(palm)
	var fingers: Array = []
	var side := -1.0 if left else 1.0
	# thumb, then index..pinky
	var xs := [0.05 * side, 0.03 * side, 0.01 * side, -0.01 * side, -0.03 * side]
	for i in 5:
		var pivot := Node3D.new()
		pivot.position = Vector3(xs[i], 0.0, -0.06 if i > 0 else -0.01)
		if i == 0:
			pivot.rotation_degrees.y = -35.0 * side
		root.add_child(pivot)
		var seg1 := _finger_segment(mat, 0.045 if i > 0 else 0.04)
		pivot.add_child(seg1)
		var pivot2 := Node3D.new()
		pivot2.position = Vector3(0.0, 0.0, -0.045 if i > 0 else -0.04)
		pivot.add_child(pivot2)
		var seg2 := _finger_segment(mat, 0.032)
		pivot2.add_child(seg2)
		fingers.append(pivot)
	return {"root": root, "fingers": fingers}


static func _finger_segment(mat: Material, length: float) -> MeshInstance3D:
	var cap := CapsuleMesh.new()
	cap.radius = 0.0105
	cap.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = mat
	mi.rotation_degrees.x = 90.0
	mi.position = Vector3(0.0, 0.0, -length * 0.5)
	return mi


func apply_world_scale(new_ws: float) -> void:
	ws = new_ws
	# Both hooks exist in current Godot 4; guard so older builds still run.
	if real:
		XRServer.world_scale = ws
	if "world_scale" in self:
		set("world_scale", ws)
	for h in HANDS:
		if _models.has(h):
			(_models[h] as Node3D).scale = Vector3.ONE * ws
	if camera != null:
		camera.near = maxf(0.003, 0.06 * ws)
	# No headset: give the simulated head / hands a sensible standing pose.
	if not real and camera != null:
		camera.position = Vector3(0.0, 1.25, 0.2) * ws
		if controllers.has("left"):
			(controllers["left"] as Node3D).position = Vector3(-0.28, 0.95, -0.3) * ws
			(controllers["right"] as Node3D).position = Vector3(0.28, 0.95, -0.3) * ws


# ---- Input accessors ----

func trigger(h: String) -> float:
	if real:
		return (controllers[h] as XRController3D).get_float("trigger")
	return float(sim[h]["trigger"])


func grip(h: String) -> float:
	if real:
		return (controllers[h] as XRController3D).get_float("grip")
	return float(sim[h]["grip"])


func stick(h: String) -> Vector2:
	if real:
		return (controllers[h] as XRController3D).get_vector2("primary")
	return sim[h]["stick"]


## name: "ax" (A / X), "by" (B / Y) or "menu".
func button(h: String, btn: String) -> bool:
	if real:
		var action := {"ax": "ax_button", "by": "by_button", "menu": "menu_button"}[btn] as String
		return (controllers[h] as XRController3D).is_button_pressed(action)
	return bool(sim[h][btn])


func pulse(h: String, amplitude: float, duration: float) -> void:
	last_pulse[h] = [amplitude, duration]
	pulse_count += 1
	if real:
		(controllers[h] as XRController3D).trigger_haptic_pulse("haptic", 0.0, clampf(amplitude, 0.0, 1.0), duration, 0.0)


# ---- Poses ----

func controller(h: String) -> XRController3D:
	return controllers[h]


func palm(h: String) -> Vector3:
	return (controllers[h] as Node3D).global_transform * (Vector3(0.0, 0.0, -0.05) * ws)


func tip(h: String) -> Vector3:
	return (controllers[h] as Node3D).global_transform * (Vector3(0.0, -0.005, -0.135) * ws)


func aim_origin(h: String) -> Vector3:
	return (controllers[h] as Node3D).global_transform * (Vector3(0.0, 0.0, -0.06) * ws)


func aim_dir(h: String) -> Vector3:
	return -(controllers[h] as Node3D).global_transform.basis.z.normalized()


func head_position() -> Vector3:
	return camera.global_position


# ---- Visuals ----

## Show the pointer beam `length_m` metres long, with a dot at the end.
func set_laser(h: String, on: bool, length_m: float, dot: bool = false) -> void:
	(_lasers[h] as Node3D).visible = on
	(_lasers[h] as Node3D).scale = Vector3(1.0, 1.0, maxf(length_m, 0.02))
	(_dots[h] as MeshInstance3D).visible = on and dot
	(_dots[h] as MeshInstance3D).position = Vector3(0.0, 0.0, -(length_m + 0.06))


func hand_model(h: String) -> Node3D:
	return _models[h]


## Finger curl from the trigger / grip values (call every frame).
func animate_hands() -> void:
	for h in HANDS:
		var g := grip(h)
		var t := trigger(h)
		var f: Array = _fingers[h]
		for i in f.size():
			var curl := g
			if i == 1:
				curl = maxf(t, g * 0.9)
			elif i == 0:
				curl = g * 0.7
			var piv: Node3D = f[i]
			piv.rotation.x = -curl * 1.25
			(piv.get_child(1) as Node3D).rotation.x = -curl * 1.4
