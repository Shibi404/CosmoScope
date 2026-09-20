extends Node
## Coordinator for the VR layer. ShipRig creates one of these when a headset is
## present (or in "simulate" mode for tests) and calls into it at fixed points:
##
##   create(rig)          -> null (stay in the normal desktop / phone mode) or an XRGame
##   attach_world(world)  -> builds the player (origin, head, controllers) in the 3D world
##   finish(mm)           -> once ShipMissions exists: cockpit, surface, audio, reticle
##   update(delta)        -> start of every frame (inputs -> ship)
##   sync_origin()        -> end of every frame (player rides the ship)
##
## Interaction model
##   Grab     grip near an object (cockpit lever / stick / tool, satellite, surface samples).
##   Point    the laser on each controller hits the HUD panel (acts as a mouse) or a planet
##            (trigger = "travel here?" confirmation).
##   Gaze     head direction feeds the existing scanner, including deployed probes.
##   Poke     fingertips press the physical console buttons.
##   Shortcuts  right A = mission action, right B = dock / undock, left X = log, left Y = cancel autopilot.

const PlayerScript := preload("res://scripts/xr/XRPlayer.gd")
const HudScript := preload("res://scripts/xr/XRHudPanel.gd")
const CockpitScript := preload("res://scripts/xr/XRCockpit.gd")
const SurfaceScript := preload("res://scripts/xr/XRSurface.gd")
const AudioScript := preload("res://scripts/xr/XRAudio.gd")
const XRSetupScript := preload("res://scripts/xr/XRSetup.gd")

const GRIP_ON := 0.6
const GRIP_OFF := 0.4
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.4
const HANDS := ["left", "right"]

var rig = null
var mm = null
var real: bool = false
var player = null
var hud = null
var cockpit = null
var surface = null
var audio = null
var cockpit_scale: float = XRSetupScript.COCKPIT_WORLD_SCALE
var audio_unit: float = 0.5
var wind_level: float = 0.0

var _world: Node3D = null
var _grabbables: Array = []
var _held: Dictionary = {"left": null, "right": null}
var _grab_off: Dictionary = {}
var _grip_state: Dictionary = {"left": false, "right": false}
var _trig_state: Dictionary = {"left": false, "right": false}
var _btn_prev: Dictionary = {}
var _hud_hover: Dictionary = {"left": false, "right": false}
var _hud_px: Dictionary = {"left": Vector2.ZERO, "right": Vector2.ZERO}
var _hover_planet: Dictionary = {"left": null, "right": null}
var _reticle: Node3D = null
var _reticle_label: Label3D = null
var _gaze_label: Label3D = null
var _hover_label: Label3D = null
var _rumble_t: float = 0.0
var _scan_tick: float = 0.0
var last_event: String = ""
var events: Dictionary = {}


## Returns null when VR is off or unavailable, so the normal desktop / phone game runs.
static func create(rig_node) -> Node:
	var mode: String = rig_node.vr_mode
	var real_xr := false
	if mode == "auto":
		real_xr = XRSetupScript.ensure_openxr(rig_node.get_viewport())
		if not real_xr:
			return null
	elif mode != "simulate":
		return null
	var g: Node = (load("res://scripts/xr/XRGame.gd") as GDScript).new()
	g.real = real_xr
	g.rig = rig_node
	return g


# ---- Setup ----

func attach_world(world: Node3D) -> void:
	_world = world
	name = "XRGame"
	player = PlayerScript.new()
	world.add_child(player)
	player.build(real)
	player.apply_world_scale(cockpit_scale)
	hud = HudScript.new()
	world.add_child(hud)
	hud.build()
	audio = AudioScript.new()
	world.add_child(audio)


func hud_viewport() -> SubViewport:
	return hud.viewport


func finish(missions) -> void:
	mm = missions
	mm.vr = self
	cockpit = CockpitScript.new()
	_world.add_child(cockpit)
	cockpit.build(self)
	surface = SurfaceScript.new()
	add_child(surface)
	surface.setup(self)
	audio.build(self)
	_build_reticle()


func _build_reticle() -> void:
	_reticle = Node3D.new()
	_reticle.name = "GazeReticle"
	player.camera.add_child(_reticle)
	_reticle_label = _label3d("+", Vector3(0, 0, -1.6), 64, Color(0.8, 0.95, 1.0, 0.6))
	_reticle.add_child(_reticle_label)
	_gaze_label = _label3d("", Vector3(0, -0.16, -1.6), 36, Color(0.85, 0.95, 1.0))
	_reticle.add_child(_gaze_label)
	_hover_label = _label3d("", Vector3.ZERO, 34, Color(1.0, 0.95, 0.6))
	_hover_label.fixed_size = true
	_hover_label.pixel_size = 0.0012
	_hover_label.visible = false
	_world.add_child(_hover_label)


func _label3d(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0028
	l.outline_size = 8
	l.modulate = color
	l.no_depth_test = true
	l.render_priority = 10
	l.position = pos
	return l


func in_surface() -> bool:
	return surface != null and surface.active


## Switch between cockpit (tiny world scale, small audio units) and surface (metres).
func apply_scale_mode(on_surface: bool) -> void:
	audio_unit = 6.0 if on_surface else 0.5
	if audio != null:
		for p in [audio.engine_player, audio.wind_player, audio.hum_player]:
			if p != null:
				p.unit_size = audio_unit


# ---- Grabbing ----

func add_grabbable(e: Dictionary) -> void:
	_grabbables.append(e)


func remove_grabbable(node: Node) -> void:
	for i in range(_grabbables.size() - 1, -1, -1):
		if _grabbables[i]["node"] == node:
			for h in HANDS:
				if _held[h] == _grabbables[i]:
					_held[h] = null
			_grabbables.remove_at(i)


func is_held(entry_name: String) -> bool:
	for h in HANDS:
		if _held[h] != null and _held[h]["name"] == entry_name:
			return true
	return false


func held_by(h: String) -> Variant:
	return _held[h]


func _update_grabs(delta: float) -> void:
	for h in HANDS:
		var g: float = player.grip(h)
		var pressed: bool = _grip_state[h]
		if not pressed and g > GRIP_ON:
			_grip_state[h] = true
			if _held[h] == null:
				_try_grab(h)
		elif pressed and g < GRIP_OFF:
			_grip_state[h] = false
			if _held[h] != null:
				var e: Dictionary = _held[h]
				_held[h] = null
				(e["on_release"] as Callable).call(h)
		var cur: Variant = _held[h]
		if cur != null:
			var entry: Dictionary = cur
			if not is_instance_valid(entry["node"]):
				_held[h] = null
				continue
			if entry["follow"]:
				(entry["node"] as Node3D).global_transform = player.controller(h).global_transform * (_grab_off[h] as Transform3D)
			(entry["on_hold"] as Callable).call(h, delta)


func _try_grab(h: String) -> void:
	var palm: Vector3 = player.palm(h)
	var best: Variant = null
	var best_d := INF
	for e in _grabbables:
		if not is_instance_valid(e["node"]):
			continue
		var en: Callable = e["enabled"]
		if en.is_valid() and not bool(en.call()):
			continue
		var other := "left" if h == "right" else "right"
		if _held[other] == e:
			continue
		var d := palm.distance_to((e["node"] as Node3D).global_position)
		if d < float(e["radius"]) and d < best_d:
			best = e
			best_d = d
	if best != null:
		var entry: Dictionary = best
		_held[h] = entry
		_grab_off[h] = player.controller(h).global_transform.affine_inverse() * (entry["node"] as Node3D).global_transform
		(entry["on_grab"] as Callable).call(h)


# ---- Pointers (laser: HUD + planets) ----

func _update_pointers(_delta: float) -> void:
	var hover_text := ""
	var hover_pos := Vector3.ZERO
	for h in HANDS:
		var holding: bool = _held[h] != null
		var o: Vector3 = player.aim_origin(h)
		var d: Vector3 = player.aim_dir(h)
		var show: bool = not holding and player.grip(h) < 0.3
		var kind := ""
		var dist := 1.0e9
		var px := Vector2.ZERO
		var planet: Node3D = null
		if show and hud.visible:
			var hh: Dictionary = hud.raycast(o, d)
			if hh["ok"]:
				kind = "hud"
				dist = hh["dist"]
				px = hh["px"]
		if show and not in_surface():
			var pk: Dictionary = mm._ap.pick_ray(o, d)
			if pk["node"] != null and float(pk["t"]) < dist:
				kind = "planet"
				dist = pk["t"]
				planet = pk["node"]
		# Laser visuals.
		var ws: float = player.ws
		var len_m := (dist / ws) if kind != "" else 1.5
		player.set_laser(h, show, minf(len_m, 400.0), kind != "")
		# HUD as a mouse.
		var trig: float = player.trigger(h)
		var was: bool = _trig_state[h]
		if kind == "hud":
			hud.push_motion(px)
			_hud_hover[h] = true
			_hud_px[h] = px
			if not was and trig > TRIGGER_ON:
				hud.push_button(px, true)
				event("button", {"hand": h, "at": hud})
			elif was and trig < TRIGGER_OFF:
				hud.push_button(px, false)
		else:
			if _hud_hover[h]:
				if was:
					hud.push_button(_hud_px[h], false)
				hud.push_leave()
				_hud_hover[h] = false
		# Planets: trigger asks "travel here?".
		_hover_planet[h] = planet
		if planet != null:
			hover_text = "%s\ntrigger: travel here" % mm._pname(planet)
			hover_pos = planet.global_position
			if not was and trig > TRIGGER_ON:
				event("button", {"hand": h, "at": planet})
				mm._ap.ask(planet)
		if not was and trig > TRIGGER_ON:
			_trig_state[h] = true
		elif was and trig < TRIGGER_OFF:
			_trig_state[h] = false
	if _hover_label != null:
		_hover_label.visible = hover_text != ""
		if hover_text != "":
			_hover_label.text = hover_text
			_hover_label.global_position = hover_pos


# ---- Controller shortcuts ----

func _edge(h: String, btn: String) -> bool:
	var key := h + btn
	var now: bool = player.button(h, btn)
	var was: bool = bool(_btn_prev.get(key, false))
	_btn_prev[key] = now
	return now and not was


func _update_shortcuts() -> void:
	var r_ax := _edge("right", "ax")
	var r_by := _edge("right", "by")
	var l_ax := _edge("left", "ax")
	var l_by := _edge("left", "by")
	if in_surface():
		return     # A boards the ship (handled by the surface); the rest are ship-only
	if r_ax:
		mm.mission_action()
	if r_by:
		mm.request_dock()
	if l_ax:
		mm.toggle_log()
	if l_by:
		mm._ap.cancel("Autopilot cancelled")


# ---- Gaze reticle ----

func _update_reticle(delta: float) -> void:
	_reticle.scale = Vector3.ONE * player.ws
	var txt := ""
	var g: Node3D = mm._gaze_body
	if g != null:
		txt = mm._gaze_title(g)
		if mm._dwell > 0.0:
			txt += "\nscanning %d%%" % int(clampf(mm._dwell / mm.SCAN_DWELL, 0.0, 1.0) * 100.0)
			_scan_tick -= delta
			if _scan_tick <= 0.0:
				_scan_tick = 0.3
				audio.play("beep", player.camera, Vector3(0, 0, -0.5 * player.ws), -12.0)
				pulse_both(0.12, 0.03)
		else:
			txt += "\nhold your gaze to scan"
	_gaze_label.text = txt
	_reticle_label.modulate.a = 0.85 if g != null else 0.35


# ---- Haptics + events ----

func pulse_both(amp: float, dur: float) -> void:
	for h in HANDS:
		player.pulse(h, amp, dur)


func _update_haptics(delta: float) -> void:
	_rumble_t -= delta
	if _rumble_t > 0.0:
		return
	_rumble_t = 0.1
	var amp := 0.0
	if not in_surface() and rig._thrusting and rig._fuel > 0.0 and not mm.hold_ship:
		amp += 0.06 + 0.10 * clampf(rig._throttle, 0.0, 1.0)
	amp += wind_level * 0.5
	if amp > 0.05:
		pulse_both(minf(amp, 0.8), 0.11)


## Central hook: ShipMissions / cockpit / surface report what happened; this plays the
## matching spatial sound and controller haptics.
func event(kind: String, data: Dictionary = {}) -> void:
	last_event = kind
	events[kind] = int(events.get(kind, 0)) + 1
	if audio == null or player == null:
		return
	var at: Node3D = null
	if data.has("at") and data["at"] is Node3D and is_instance_valid(data["at"]):
		at = data["at"]
	var hand: String = String(data.get("hand", ""))
	match kind:
		"button":
			audio.play("click", at)
			_pulse_hand(hand, 0.35, 0.04)
		"grab":
			audio.play("grab", at)
			_pulse_hand(hand, 0.5, 0.06)
		"release":
			audio.play("release", at)
			_pulse_hand(hand, 0.2, 0.04)
		"dock":
			audio.play("dock", player)
			pulse_both(0.8, 0.15)
		"undock":
			audio.play("undock", player)
			pulse_both(0.5, 0.1)
		"scan_done":
			audio.play("scan_done", player.camera)
			pulse_both(0.5, 0.12)
		"mission_complete":
			audio.play("chime", player.camera)
			pulse_both(0.6, 0.12)
			for i in 2:
				get_tree().create_timer(0.2 * (i + 1)).timeout.connect(func(): pulse_both(0.6, 0.1))
		"mission_fail":
			audio.play("buzz", player.camera)
			pulse_both(1.0, 0.3)
		"flash":
			audio.play("shutter", player.camera)
			pulse_both(clampf(float(data.get("amount", 0.5)), 0.2, 0.9), 0.1)
		"deploy":
			audio.play("clunk", player)
			_pulse_hand(hand, 0.8, 0.12)
		"sample":
			audio.play("sample", at)
			_pulse_hand(hand, 0.7, 0.12)
		"surface_enter", "surface_exit", "board":
			audio.play("dock", player)
			pulse_both(0.6, 0.12)


func _pulse_hand(hand: String, amp: float, dur: float) -> void:
	if hand == "left" or hand == "right":
		player.pulse(hand, amp, dur)
	else:
		pulse_both(amp, dur)


# ---- Frame hooks ----

func update(delta: float) -> void:
	if mm == null:
		return
	player.animate_hands()
	wind_level = lerpf(wind_level, clampf(mm.rumble_extra, 0.0, 1.0), minf(1.0, delta * 5.0))
	_update_grabs(delta)
	if in_surface():
		surface.update(delta)
	else:
		cockpit.update(delta)
	_update_pointers(delta)
	_update_shortcuts()
	_update_reticle(delta)
	_update_haptics(delta)
	audio.update(delta)


## The player rides the ship: origin + cockpit follow it after it has moved this frame.
func sync_origin() -> void:
	if mm == null or in_surface():
		return
	var xf := Transform3D(rig._ship_basis(), rig._pos)
	player.global_transform = xf
	cockpit.global_transform = Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * cockpit_scale), xf.origin)
