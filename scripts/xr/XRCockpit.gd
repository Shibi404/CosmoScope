extends Node3D
## The VR cockpit. Authored in metres and scaled by the world scale, so it is
## human-sized to the player while the planets outside stay enormous.
##
## Physical controls
##   Throttle lever (left)   grab with grip, push forward = more thrust. Stays where you leave it.
##   Flight stick   (right)  grab with grip, tilt: left/right = yaw, forward/back = pitch. Springs to centre.
##   Console buttons         poke with a fingertip: DOCK, SCAN, MISSION, ACTION, EXPLORE, CANCEL AP, RESCUE, LOG.
##   Scanner / camera tool   grab from the right-hand holder; aim it at a planet to scan, trigger = mission action.
##   Satellite               appears in the left holder when a satellite can be deployed; throw it out of the cockpit.
##
## Everything here only produces inputs for the existing ship: throttle -> rig._throttle / _thrusting,
## stick -> rig.ext_yaw / ext_pitch, buttons -> the same ShipMissions functions the keyboard calls.

const THROTTLE_Z_IDLE := 0.15
const THROTTLE_Z_FULL := -0.15
const STICK_MAX := 0.5           # rad of tilt = full deflection
const POKE_HALF := 0.055         # button half-size in metres (poke area)

var game = null
var rig = null
var mm = null
var player = null

var throttle: float = 0.0
var stick: Vector2 = Vector2.ZERO          # x = right, y = forward
var buttons: Array = []                    # {id, node, mesh, color, cb, lamp, armed, cool, pressed}
var tool_held: bool = false
var sat_visible: bool = false

var _console_top: Node3D
var _throttle_base: Node3D
var _throttle_handle: Node3D
var _stick_base: Node3D
var _stick_pivot: Node3D
var _stick_hand: String = ""
var _throttle_hand: String = ""
var _tool: Node3D
var _tool_home: Transform3D
var _tool_hand: String = ""
var _tool_prev_trigger: bool = false
var _sat: Node3D
var _sat_home: Transform3D
var _returning: Dictionary = {}            # Node3D -> seconds left of the return animation
var _fuel_fill: MeshInstance3D
var _thr_fill: MeshInstance3D
var _t: float = 0.0


func build(g) -> void:
	game = g
	rig = g.rig
	mm = g.mm
	player = g.player
	name = "Cockpit"
	scale = Vector3.ONE * g.cockpit_scale

	var metal := Color(0.16, 0.18, 0.22)
	var trim := Color(0.28, 0.32, 0.4)
	_box(self, Vector3(2.4, 0.04, 2.4), Vector3(0, -0.02, 0), metal)
	# Seat behind the player position.
	_box(self, Vector3(0.5, 0.45, 0.5), Vector3(0, 0.225, 0.62), trim)
	_box(self, Vector3(0.5, 0.6, 0.08), Vector3(0, 0.75, 0.86), trim)
	# Front console.
	_box(self, Vector3(1.7, 0.6, 0.55), Vector3(0, 0.3, -0.85), metal)
	_console_top = Node3D.new()
	_console_top.name = "ConsoleTop"
	_console_top.position = Vector3(0, 0.62, -0.78)
	_console_top.rotation_degrees.x = 20.0
	add_child(_console_top)
	_box(_console_top, Vector3(1.7, 0.03, 0.45), Vector3(0, -0.015, 0), trim)
	# Side consoles (throttle left, stick right).
	_box(self, Vector3(0.2, 0.05, 0.62), Vector3(-0.44, 0.58, -0.3), trim)
	_box(self, Vector3(0.2, 0.05, 0.62), Vector3(0.44, 0.58, -0.3), trim)
	_box(self, Vector3(0.14, 0.58, 0.5), Vector3(-0.52, 0.29, -0.3), metal)
	_box(self, Vector3(0.14, 0.58, 0.5), Vector3(0.52, 0.29, -0.3), metal)
	# Canopy frame.
	for x in [-1.05, 1.05]:
		_box(self, Vector3(0.06, 2.1, 0.06), Vector3(x, 1.05, -1.05), trim)
		_box(self, Vector3(0.06, 2.1, 0.06), Vector3(x, 1.05, 0.9), trim)
		_box(self, Vector3(0.06, 0.06, 1.95), Vector3(x, 2.1, -0.08), trim)
	_box(self, Vector3(2.16, 0.06, 0.06), Vector3(0, 2.1, -1.05), trim)
	_box(self, Vector3(2.16, 0.06, 0.06), Vector3(0, 2.1, 0.9), trim)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.9, -0.2)
	lamp.omni_range = 3.5
	lamp.light_energy = 0.9
	lamp.light_color = Color(0.85, 0.92, 1.0)
	add_child(lamp)

	_build_throttle()
	_build_stick()
	_build_buttons()
	_build_gauges()
	_build_tool()
	_build_satellite()

	# The HUD hangs in front of the console.
	game.hud.mount(self, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0, 1.5, -1.5)), 1.9)


# ---- Construction helpers ----

func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(color: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.5
	m.roughness = 0.45
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _label(parent: Node, text: String, pos: Vector3, size: int = 30, flat: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0012
	l.outline_size = 6
	l.modulate = Color(0.85, 0.95, 1.0)
	l.position = pos
	if flat:
		l.rotation_degrees.x = -90.0
	parent.add_child(l)
	return l


func _grabbable(entry_name: String, node: Node3D, radius_m: float, follow: bool, on_grab: Callable, on_hold: Callable, on_release: Callable, enabled: Callable = Callable()) -> void:
	game.add_grabbable({
		"name": entry_name, "node": node, "radius": radius_m * game.cockpit_scale, "follow": follow,
		"on_grab": on_grab, "on_hold": on_hold, "on_release": on_release, "enabled": enabled,
	})


# ---- Throttle ----

func _build_throttle() -> void:
	_throttle_base = Node3D.new()
	_throttle_base.name = "ThrottleBase"
	_throttle_base.position = Vector3(-0.44, 0.61, -0.3)
	add_child(_throttle_base)
	_box(_throttle_base, Vector3(0.035, 0.02, 0.36), Vector3(0, 0.0, 0), Color(0.05, 0.06, 0.08))
	_thr_fill = _box(_throttle_base, Vector3(0.012, 0.012, 0.3), Vector3(0.0, 0.014, 0.0), Color(0.3, 0.9, 0.5), 1.4)
	_throttle_handle = Node3D.new()
	_throttle_handle.name = "ThrottleHandle"
	_throttle_handle.position = Vector3(0, 0.05, THROTTLE_Z_IDLE)
	_throttle_base.add_child(_throttle_handle)
	_box(_throttle_handle, Vector3(0.05, 0.02, 0.05), Vector3(0, -0.02, 0), Color(0.6, 0.6, 0.65))
	_box(_throttle_handle, Vector3(0.04, 0.09, 0.04), Vector3(0, 0.035, 0), Color(0.9, 0.55, 0.15), 0.4)
	_label(self, "THROTTLE", Vector3(-0.44, 0.615, -0.03), 26)
	_grabbable("throttle", _throttle_handle, 0.11, false,
		_on_throttle_grab,
		func(h, _d): _throttle_from_hand(h),
		_on_throttle_release)


func _throttle_from_hand(h: String) -> void:
	var lp := _throttle_base.to_local(player.palm(h))
	throttle = clampf((THROTTLE_Z_IDLE - lp.z) / (THROTTLE_Z_IDLE - THROTTLE_Z_FULL), 0.0, 1.0)


# ---- Flight stick ----

func _build_stick() -> void:
	_stick_base = Node3D.new()
	_stick_base.name = "StickBase"
	_stick_base.position = Vector3(0.44, 0.61, -0.3)
	add_child(_stick_base)
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = 0.04
	cyl.mesh = cm
	cyl.material_override = _mat(Color(0.08, 0.09, 0.12))
	cyl.position = Vector3(0, 0.02, 0)
	_stick_base.add_child(cyl)
	_stick_pivot = Node3D.new()
	_stick_pivot.name = "StickPivot"
	_stick_pivot.position = Vector3(0, 0.03, 0)
	_stick_base.add_child(_stick_pivot)
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.013
	rm.bottom_radius = 0.016
	rm.height = 0.22
	rod.mesh = rm
	rod.material_override = _mat(Color(0.5, 0.52, 0.58))
	rod.position = Vector3(0, 0.11, 0)
	_stick_pivot.add_child(rod)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.038
	sm.height = 0.076
	knob.mesh = sm
	knob.material_override = _mat(Color(0.2, 0.55, 0.9), 0.5)
	knob.position = Vector3(0, 0.25, 0)
	_stick_pivot.add_child(knob)
	_label(self, "STEER", Vector3(0.44, 0.615, -0.03), 26)
	_grabbable("stick", knob, 0.12, false,
		_on_stick_grab,
		func(h, _d): _stick_from_hand(h),
		_on_stick_release)


func _stick_from_hand(h: String) -> void:
	var lp := _stick_base.to_local(player.palm(h))
	var up := maxf(lp.y - 0.03, 0.05)
	var tx := clampf(atan2(lp.x, up), -STICK_MAX, STICK_MAX)
	var tf := clampf(atan2(-lp.z, up), -STICK_MAX, STICK_MAX)
	stick = Vector2(tx / STICK_MAX, tf / STICK_MAX)


# ---- Buttons ----

func _build_buttons() -> void:
	var xs := [-0.63, -0.45, -0.27, -0.09, 0.09, 0.27, 0.45, 0.63]
	_add_button("dock", "DOCK", xs[0], Color(0.2, 0.75, 0.35), func(): mm.request_dock(),
		func() -> float: return 1.0 if mm.docked else (0.85 if mm._dock_candidate != null else 0.0))
	_add_button("scan", "SCAN", xs[1], Color(0.25, 0.7, 0.95), func(): mm.scan_now(),
		func() -> float: return 0.9 if (mm._gaze_body != null or mm.docked) else 0.0)
	_add_button("mission", "MISSION", xs[2], Color(0.7, 0.4, 0.95), func(): mm.start_mission(),
		func() -> float: return 0.9 if (mm.docked and mm._m.is_empty()) else 0.0)
	_add_button("action", "ACTION", xs[3], Color(0.95, 0.7, 0.2), func(): mm.mission_action(),
		func() -> float: return 1.0 if mm.action_text != "" else 0.0)
	_add_button("explore", "EXPLORE", xs[4], Color(0.55, 0.85, 0.35), func(): mm.enter_surface(),
		func() -> float: return 0.9 if mm.can_explore() else 0.0)
	_add_button("cancel", "CANCEL AP", xs[5], Color(0.95, 0.5, 0.2), func(): mm._ap.cancel("Autopilot cancelled"),
		func() -> float: return 1.0 if mm.autopilot_active else 0.0)
	_add_button("rescue", "RESCUE", xs[6], Color(0.9, 0.2, 0.2), func(): mm.call_rescue(),
		func() -> float: return (0.6 + 0.4 * sin(_t * 8.0)) if mm._out_of_fuel else 0.0)
	_add_button("log", "LOG", xs[7], Color(0.7, 0.75, 0.85), func(): mm.toggle_log(),
		func() -> float: return 0.5)


func _add_button(id: String, text: String, x: float, color: Color, cb: Callable, lamp: Callable) -> void:
	var n := Node3D.new()
	n.name = "Btn_" + id
	n.position = Vector3(x, 0.0, 0.05)
	_console_top.add_child(n)
	var mesh := _box(n, Vector3(0.09, 0.03, 0.09), Vector3(0, 0.015, 0), color, 0.3)
	_label(_console_top, text, Vector3(x, 0.002, 0.155), 22)
	buttons.append({"id": id, "node": n, "mesh": mesh, "color": color, "cb": cb, "lamp": lamp,
		"armed": true, "cool": 0.0, "pressed": false})


func button_node(id: String) -> Node3D:
	for b in buttons:
		if b["id"] == id:
			return b["node"]
	return null


func _update_buttons(delta: float) -> void:
	for b in buttons:
		var node: Node3D = b["node"]
		var inside := false
		var hand_used := ""
		for h in ["left", "right"]:
			var p := node.to_local(player.tip(h))
			if absf(p.x) < POKE_HALF and absf(p.z) < POKE_HALF and p.y < 0.022 and p.y > -0.03:
				inside = true
				hand_used = h
		b["cool"] = maxf(0.0, float(b["cool"]) - delta)
		if inside and b["armed"] and float(b["cool"]) <= 0.0:
			b["armed"] = false
			b["cool"] = 0.35
			game.event("button", {"hand": hand_used, "at": node})
			(b["cb"] as Callable).call()
		if not inside:
			b["armed"] = true
		b["pressed"] = inside
		var mesh: MeshInstance3D = b["mesh"]
		mesh.position.y = lerpf(mesh.position.y, 0.007 if inside else 0.015, minf(1.0, delta * 25.0))
		# Lamp: brightness of the button shows its state.
		var v: float = (b["lamp"] as Callable).call()
		var m := mesh.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 0.15 + 1.9 * v


# ---- Gauges ----

func _build_gauges() -> void:
	var frame := _box(_console_top, Vector3(0.66, 0.012, 0.05), Vector3(0.0, 0.006, -0.14), Color(0.03, 0.04, 0.06))
	_fuel_fill = _box(_console_top, Vector3(0.64, 0.014, 0.036), Vector3(0.0, 0.012, -0.14), Color(0.3, 0.9, 0.5), 1.2)
	_label(_console_top, "FUEL", Vector3(-0.44, 0.002, -0.14), 24)


func _update_gauges(_delta: float) -> void:
	var f := clampf(rig._fuel / rig.fuel_capacity, 0.0, 1.0)
	_fuel_fill.scale.x = maxf(f, 0.001)
	_fuel_fill.position.x = -0.32 * (1.0 - f)
	var m := _fuel_fill.material_override as StandardMaterial3D
	var c := Color(0.95, 0.5, 0.2) if f < 0.3 else Color(0.3, 0.9, 0.5)
	m.albedo_color = c
	m.emission = c
	_thr_fill.scale.z = maxf(throttle, 0.001)
	_thr_fill.position.z = THROTTLE_Z_IDLE - 0.15 * throttle


# ---- Scanner / camera tool ----

func _build_tool() -> void:
	var holder := Node3D.new()
	holder.name = "ToolHolder"
	holder.position = Vector3(0.66, 0.66, -0.02)
	add_child(holder)
	_box(holder, Vector3(0.1, 0.02, 0.18), Vector3(0, -0.02, 0), Color(0.12, 0.14, 0.18))
	_tool = Node3D.new()
	_tool.name = "ScannerTool"
	holder.add_child(_tool)
	_box(_tool, Vector3(0.04, 0.045, 0.15), Vector3(0, 0.03, 0), Color(0.2, 0.22, 0.28), 0.2)
	_box(_tool, Vector3(0.03, 0.08, 0.035), Vector3(0, -0.02, 0.04), Color(0.15, 0.16, 0.2))
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.024
	sm.height = 0.048
	lens.mesh = sm
	lens.material_override = _mat(Color(0.3, 0.9, 1.0), 1.6)
	lens.position = Vector3(0, 0.03, -0.085)
	_tool.add_child(lens)
	_label(holder, "SCANNER", Vector3(0, 0.0, 0.14), 22)
	_tool_home = _tool.transform
	_grabbable("tool", _tool, 0.13, true,
		_on_tool_grab,
		func(_h, _d): pass,
		_on_tool_release)


func _update_tool(_delta: float) -> void:
	if not tool_held:
		return
	# Aim: the tool's nose is its -Z axis. While held it replaces the head gaze for scanning.
	var xf := _tool.global_transform
	mm.scan_ray_override = {"origin": xf.origin, "dir": -xf.basis.z.normalized()}
	var trig: bool = player.trigger(_tool_hand) > 0.6
	if trig and not _tool_prev_trigger:
		game.event("button", {"hand": _tool_hand, "at": _tool})
		if mm.action_text != "":
			mm.mission_action()
		else:
			mm.scan_now()
	_tool_prev_trigger = trig


# ---- Satellite (Earth mission) ----

func _build_satellite() -> void:
	var holder := Node3D.new()
	holder.name = "SatHolder"
	holder.position = Vector3(-0.66, 0.66, -0.02)
	add_child(holder)
	_box(holder, Vector3(0.1, 0.02, 0.18), Vector3(0, -0.02, 0), Color(0.12, 0.14, 0.18))
	_label(holder, "SATELLITE", Vector3(0, 0.0, 0.14), 22)
	_sat = Node3D.new()
	_sat.name = "Satellite"
	holder.add_child(_sat)
	_box(_sat, Vector3(0.06, 0.06, 0.08), Vector3(0, 0.04, 0), Color(0.85, 0.85, 0.9), 0.3)
	_box(_sat, Vector3(0.14, 0.004, 0.06), Vector3(0.1, 0.04, 0), Color(0.2, 0.35, 0.8), 0.6)
	_box(_sat, Vector3(0.14, 0.004, 0.06), Vector3(-0.1, 0.04, 0), Color(0.2, 0.35, 0.8), 0.6)
	_sat.visible = false
	_sat_home = _sat.transform
	_grabbable("satellite", _sat, 0.14, true,
		_on_sat_grab,
		func(_h, _d): pass,
		_release_satellite,
		func() -> bool: return _sat.visible)


func _release_satellite(h: String) -> void:
	game.event("release", {"hand": h, "at": _sat})
	var p := to_local(_sat.global_position)
	var outside := p.z < -1.1 or absf(p.x) > 1.1 or p.y > 2.15 or p.y < -0.1
	if outside and mm.action_text.contains("DEPLOY"):
		_sat.visible = false
		_sat.transform = _sat_home
		game.event("deploy", {"hand": h})
		mm.mission_action()
	else:
		_returning[_sat] = 0.4


# ---- Per-frame ----

func update(delta: float) -> void:
	_t += delta
	# Spring the stick back to centre when let go.
	if _stick_hand == "":
		stick = stick.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_stick_pivot.rotation = Vector3(-stick.y * STICK_MAX, 0.0, -stick.x * STICK_MAX)
	_throttle_handle.position.z = THROTTLE_Z_IDLE - throttle * (THROTTLE_Z_IDLE - THROTTLE_Z_FULL)
	sat_visible = mm.action_text.contains("DEPLOY") and mm._act != null and String(mm._act.kind) == "orbit"
	if _sat.visible != sat_visible and not game.is_held("satellite"):
		_sat.visible = sat_visible
	_update_buttons(delta)
	_update_tool(delta)
	_update_gauges(delta)
	# Magnetic return of released items to their holders.
	for n in _returning.keys():
		var left := float(_returning[n]) - delta
		var home: Transform3D = _tool_home if n == _tool else _sat_home
		if not is_instance_valid(n) or left <= 0.0:
			if is_instance_valid(n):
				(n as Node3D).transform = home
			_returning.erase(n)
		else:
			(n as Node3D).transform = (n as Node3D).transform.interpolate_with(home, minf(1.0, delta * 9.0))
			_returning[n] = left
	# Outputs to the ship. Autopilot keeps full authority over thrust while it is flying.
	if mm.autopilot_active:
		rig._throttle = 1.0
	else:
		rig._throttle = maxf(throttle, 0.001)
		rig._thrusting = throttle > 0.04
	rig.ext_yaw = -stick.x
	rig.ext_pitch = -stick.y


# ---- Grab handlers ----

func _on_throttle_grab(h: String) -> void:
	_throttle_hand = h
	game.event("grab", {"hand": h, "at": _throttle_handle})


func _on_throttle_release(h: String) -> void:
	_throttle_hand = ""
	game.event("release", {"hand": h, "at": _throttle_handle})


func _on_stick_grab(h: String) -> void:
	_stick_hand = h
	game.event("grab", {"hand": h, "at": _stick_pivot})


func _on_stick_release(h: String) -> void:
	_stick_hand = ""
	game.event("release", {"hand": h, "at": _stick_pivot})


func _on_tool_grab(h: String) -> void:
	_tool_hand = h
	tool_held = true
	_returning.erase(_tool)
	game.event("grab", {"hand": h, "at": _tool})


func _on_tool_release(h: String) -> void:
	_tool_hand = ""
	tool_held = false
	_returning[_tool] = 0.4
	mm.scan_ray_override = {}
	game.event("release", {"hand": h, "at": _tool})


func _on_sat_grab(h: String) -> void:
	_returning.erase(_sat)
	game.event("grab", {"hand": h, "at": _sat})


func _noop_hold(_h: String, _d: float) -> void:
	pass
