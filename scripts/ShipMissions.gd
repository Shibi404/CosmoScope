extends Node
## Game layer for the ship: docking, gaze scanner, per-planet missions,
## mission log / score and the out-of-fuel rescue tow.
##
## ShipRig owns flight physics and the base HUD. It creates this node, sets
## `rig`, and calls `update(delta)` at the top of every frame. While `docked`
## is true this node drives the ship's position/heading and ShipRig skips its
## own flight integration.
##
## Controls (also available as on-screen buttons for touch):
##   E dock / undock  •  1 scan  •  2 start mission  •  F photo  •  R rescue tow
##   Gaze at a planet for SCAN_DWELL seconds to scan it (works in flight too).

const MissionData := preload("res://data/missions.gd")
const AutopilotScript := preload("res://scripts/ShipAutopilot.gd")
const ActivitiesScript := preload("res://scripts/PlanetActivities.gd")

const SCAN_DWELL := 2.0          # seconds of steady gaze to complete a scan
const SCAN_RANGE := 14.0         # max gaze distance (world units)
const DOCK_RANGE := 1.6          # max distance from a planet's surface to dock
const DOCK_MAX_SPEED := 3.0      # must be slower than this to dock
const ABORT_DIST := 16.0         # flying this far from the mission planet aborts it
const DOCK_REFUEL_PER_SEC := 12.0
const MISSION_FUEL_BONUS := 20.0
const SCAN_SCORE := 50
const RESCUE_PENALTY := 100
const LIGHT_KM_PER_SEC := 299792.0

var rig = null              # ShipRig (untyped so its private vars are reachable)
var docked: bool = false
## True while something other than the pilot drives the ship (docked, or the Mars rover cam).
var rover_hold: bool = false
var hold_ship: bool:
	get:
		return docked or rover_hold or surface_hold
var autopilot_active: bool:
	get:
		return _ap != null and _ap.active
var _ap = null
## VR layer (XRGame) or null on desktop / phone.
var vr = null
## True while the player is on foot on a planet surface (VR only).
var surface_hold: bool = false
var surface_info: String = ""
## 0..1 storm / wind strength this frame, set by activities; drives VR rumble + wind audio.
var rumble_extra: float = 0.0
## VR scanner tool: {"origin", "dir"} replaces the head gaze ray while held.
var scan_ray_override: Dictionary = {}
## VR: left-stick drive input for the Mars rover (x = turn right, y = forward).
var vr_drive: Vector2 = Vector2.ZERO
var dialog_open: bool:
	get:
		return _ap != null and _ap.confirm_open
var _gaze_objects: Array = []
var _surface_finds: Array = []
var _last_flash: float = 0.0
var score: int = 0

var _targets: Array[Node3D] = []      # the planets, nearest Sun first
var _completed: Dictionary = {}       # planet name -> true
var _scanned: Dictionary = {}         # planet name -> true

# Docking.
var _dock_body: Node3D = null
var _dock_candidate: Node3D = null
var _dock_angle: float = 0.0
var _dock_r: float = 0.0
var _dock_y: float = 0.0

# Scanner.
var _gaze_body: Node3D = null
var _dwell: float = 0.0
var _card_timer: float = 0.0

# Active mission.
var _m: Dictionary = {}
var _m_name: String = ""
var _m_body: Node3D = null
var _m_msg: String = ""
var _act = null                        # PlanetActivities for the running mission
var _log: Array = []                   # completed-mission discoveries
var _frozen: bool = false
var _prev_orbit: bool = true
## Label of the context action button (set by the running activity; "" hides it).
var action_text: String = ""
## On-screen rover drive buttons (touch): held state.
var ctl_left: bool = false
var ctl_right: bool = false
var ctl_fwd: bool = false

var _deployed: Array = []             # {node, kind, rate}
var _out_of_fuel: bool = false

# UI.
var _score_label: Label
var _mission_label: Label
var _prompt: Label
var _toast_label: Label
var _toast_timer: float = 0.0
var _flash: ColorRect
var _btn_dock: Button
var _btn_action: Button
var _ctl_row: HBoxContainer
var _log_panel: PanelContainer
var _log_label: Label
var _g_rows: Array[VBoxContainer] = []
var _g_labels: Array[Label] = []
var _g_bars: Array[ProgressBar] = []
var _g_fills: Array[StyleBoxFlat] = []
var _btn_rescue: Button
var _reticle: Label
var _dwell_box: VBoxContainer
var _dwell_bar: ProgressBar
var _dwell_label: Label
var _card: PanelContainer
var _card_label: Label
var _menu: PanelContainer
var _menu_title: Label
var _menu_brief: Label
var _menu_refuel: Label
var _menu_scan: Button
var _menu_mission: Button
var _menu_explore: Button
var _btn_return: Button


func _ready() -> void:
	for p in rig._planets:
		var data: Dictionary = p.get_meta("data", {})
		if data.has("distance") and MissionData.MISSIONS.has(String(data.get("name", ""))):
			_targets.append(p)
	_targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return float(_data(a).get("distance", 0.0)) < float(_data(b).get("distance", 0.0)))
	_ap = AutopilotScript.new()
	_ap.mm = self
	_ap.rig = rig
	_build_ui()
	_refresh_menu()


# ---- Helpers ----

func _data(b: Node3D) -> Dictionary:
	return b.get_meta("data", {})


func _pname(b: Node3D) -> String:
	return String(_data(b).get("name", b.name))


func _radius(b: Node3D) -> float:
	return rig._body_radius(b)


# Basis of a planet's equatorial frame (orbit pivot rotation + axial tilt), so
# checkpoint gates sit in the same plane Saturn's rings are drawn in.
func _ref_basis(b: Node3D) -> Basis:
	var tilt := deg_to_rad(float(_data(b).get("tilt", 0.0)))
	return b.get_parent().global_basis.orthonormalized() * Basis(Vector3(0, 0, 1), tilt)




# ---- Per-frame ----

func update(delta: float) -> void:
	rumble_extra = 0.0
	_ap.update(delta)
	_tick_toast(delta)
	if docked:
		_tick_dock(delta)
	else:
		_find_dock_candidate()
		if rover_hold:
			_dock_candidate = null
	_tick_scanner(delta)
	_tick_mission(delta)
	_tick_deployed(delta)
	_tick_rescue()
	_update_ui()


# ---- Docking ----

func _find_dock_candidate() -> void:
	_dock_candidate = null
	var best := INF
	for b in _targets:
		var surf: float = rig._pos.distance_to(b.global_position) - _radius(b)
		if surf < DOCK_RANGE and surf < best:
			best = surf
			_dock_candidate = b


func request_dock() -> void:
	if rover_hold:
		return
	if docked:
		undock()
		return
	if _dock_candidate == null:
		return
	if rig._vel.length() > DOCK_MAX_SPEED:
		_toast("Too fast to dock — slow below %.0f u/s" % DOCK_MAX_SPEED)
		return
	_ap.stop()
	docked = true
	_dock_body = _dock_candidate
	var rel: Vector3 = rig._pos - _dock_body.global_position
	_dock_angle = atan2(rel.z, rel.x)
	_dock_r = Vector2(rel.x, rel.z).length()
	_dock_y = rel.y
	rig._vel = Vector3.ZERO
	_toast("Docked at %s" % _pname(_dock_body))
	vr_event("dock")
	_refresh_menu()


func undock() -> void:
	if not docked:
		return
	var out: Vector3 = (rig._pos - _dock_body.global_position).normalized()
	rig._vel = out * 1.5
	rig._ship_yaw = atan2(-out.x, -out.z)
	docked = false
	_dock_body = null
	_toast("Undocked")
	vr_event("undock")
	_refresh_menu()


func _tick_dock(delta: float) -> void:
	var c: Vector3 = _dock_body.global_position
	var orbit_r: float = _radius(_dock_body) + rig.ship_radius + rig.collision_skin + 0.6
	_dock_r = move_toward(_dock_r, orbit_r, 2.0 * delta)
	_dock_y = move_toward(_dock_y, 0.15, 0.6 * delta)
	_dock_angle += 0.35 * delta
	rig._pos = c + Vector3(cos(_dock_angle) * _dock_r, _dock_y, sin(_dock_angle) * _dock_r)
	rig._vel = Vector3.ZERO
	# Nose points at the planet so the view frames it.
	var d: Vector3 = c - rig._pos
	d.y = 0.0
	if d.length() > 0.001:
		rig._ship_yaw = lerp_angle(rig._ship_yaw, atan2(-d.x, -d.z), minf(1.0, 4.0 * delta))
	rig._ship_pitch = move_toward(rig._ship_pitch, 0.0, 1.5 * delta)
	if MissionData.REFUEL_PLANETS.has(_pname(_dock_body)):
		rig._fuel = minf(rig.fuel_capacity, rig._fuel + DOCK_REFUEL_PER_SEC * delta)


# ---- Scanner (gaze + dwell) ----

func _tick_scanner(delta: float) -> void:
	# Gaze ray: the head camera, or (VR) the hand-held scanner tool while it is held.
	var origin: Vector3
	var dir: Vector3
	if not scan_ray_override.is_empty():
		origin = scan_ray_override["origin"]
		dir = scan_ray_override["dir"]
	else:
		var cam: Camera3D = rig._left_cam
		origin = cam.global_position
		dir = -cam.global_transform.basis.z
	var best: Node3D = null
	var best_t := INF
	if not surface_hold:
		for b in _targets:
			var oc: Vector3 = b.global_position - origin
			var t := oc.dot(dir)
			if t <= 0.0 or t > SCAN_RANGE:
				continue
			var perp := (oc - dir * t).length()
			# Generous gaze radius so tiny planets (Mercury) are still targetable.
			if perp < maxf(_radius(b) * 1.2, 0.04 * t) and t < best_t:
				best_t = t
				best = b
	# Important objects (deployed satellite / rover, surface samples) use the same gaze + dwell.
	for i in range(_gaze_objects.size() - 1, -1, -1):
		var o: Node3D = _gaze_objects[i]
		if not is_instance_valid(o):
			_gaze_objects.remove_at(i)
			continue
		var oc2: Vector3 = o.global_position - origin
		var t2 := oc2.dot(dir)
		var max_range := 40.0 if surface_hold else SCAN_RANGE
		if t2 <= 0.0 or t2 > max_range:
			continue
		var perp2 := (oc2 - dir * t2).length()
		if perp2 < maxf(float(o.get_meta("gaze_radius", 0.2)), 0.04 * t2) and t2 < best_t:
			best_t = t2
			best = o
	if best == null:
		_gaze_body = null
		_dwell = 0.0
	elif best == _gaze_body:
		_dwell += delta
	else:
		_gaze_body = best
		_dwell = 0.0
	if _dwell >= SCAN_DWELL and _gaze_body != null:
		_scan_target(_gaze_body)
		_dwell = -1.5   # brief cooldown so the card isn't re-triggered instantly


func _gaze_title(n: Node3D) -> String:
	if n.has_meta("gaze_title"):
		return String(n.get_meta("gaze_title"))
	return _pname(n)


## Register a node the player can inspect with gaze + dwell (or the scanner tool).
func register_gaze_object(n: Node3D, radius: float, title: String, text: String) -> void:
	n.set_meta("gaze_radius", radius)
	n.set_meta("gaze_title", title)
	n.set_meta("gaze_text", text)
	if not _gaze_objects.has(n):
		_gaze_objects.append(n)


func unregister_gaze_object(n: Node3D) -> void:
	_gaze_objects.erase(n)
	if _gaze_body == n:
		_gaze_body = null
		_dwell = 0.0


# A planet gets the full fact card; a registered object shows its own text.
func _scan_target(n: Node3D) -> void:
	if n.has_meta("gaze_text"):
		_card_label.text = "%s\n\n%s" % [_gaze_title(n).to_upper(), n.get_meta("gaze_text")]
		_card.visible = true
		_card_timer = 9.0
		vr_event("scan_done")
	else:
		_do_scan(n)


## Scan the thing being looked at (or the docked planet) right now, without waiting for the dwell.
func scan_now() -> void:
	if docked and _dock_body != null:
		_do_scan(_dock_body)
	elif _gaze_body != null:
		_scan_target(_gaze_body)
	else:
		_toast("Aim at a planet to scan it")


func _do_scan(b: Node3D) -> void:
	var data := _data(b)
	var pname := _pname(b)
	var first := not _scanned.has(pname)
	if first:
		_scanned[pname] = true
		score += SCAN_SCORE
		_toast("Scan logged: %s  +%d" % [pname, SCAN_SCORE])
	var light_min := float(data.get("sun_dist_mkm", 0.0)) * 1.0e6 / LIGHT_KM_PER_SEC / 60.0
	_card_label.text = "%s\n%s\n\nDiameter   %s km\nFrom Sun   %s M km\nLight time %.1f min\nYear %s  •  Day %s\nMoons %s  •  Gravity %.2f g" % [
		pname.to_upper(), data.get("fact", ""),
		str(data.get("diameter_km", "?")), str(data.get("sun_dist_mkm", "?")), light_min,
		data.get("year", "?"), data.get("day", "?"),
		str(data.get("moons", 0)), float(data.get("gravity_g", 0.0))]
	_card.visible = true
	_card_timer = 9.0
	vr_event("scan_done")


# ---- VR hooks ----

## Report a game event to the VR layer (sound + haptics). No-op on desktop / phone.
func vr_event(kind: String, data: Dictionary = {}) -> void:
	if vr != null:
		vr.event(kind, data)


func toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible
	_refresh_log()


## Walkable rocky planets can be explored on foot in VR.
func can_explore() -> bool:
	return vr != null and docked and _dock_body != null and MissionData.WALKABLE.has(_pname(_dock_body)) and not surface_hold and _m.is_empty()


func enter_surface() -> void:
	if vr == null:
		return
	if not docked or _dock_body == null:
		_toast("Dock at a planet first")
		return
	var pname := _pname(_dock_body)
	if not MissionData.WALKABLE.has(pname):
		_toast("%s has no solid surface to walk on" % pname)
		return
	if not _m.is_empty():
		_toast("Finish or abort the current mission first")
		return
	surface_hold = true
	_ap.stop()
	vr.surface.enter(_dock_body)
	_refresh_menu()


func exit_surface() -> void:
	if not surface_hold:
		return
	surface_hold = false
	surface_info = ""
	vr.surface.exit()
	_refresh_menu()


func add_surface_find(planet: String, item: String, fact: String) -> void:
	_surface_finds.append({"planet": planet, "item": item, "fact": fact})
	_refresh_log()


# ---- Missions ----
# The framework (start / complete / abort, score, fuel, log, HUD) lives here.
# Each planet's rules are in PlanetActivities.gd.

func start_mission() -> void:
	if not docked or _dock_body == null:
		return
	var pname := _pname(_dock_body)
	if not MissionData.MISSIONS.has(pname) or _completed.has(pname) or not _m.is_empty():
		return
	var def: Dictionary = MissionData.MISSIONS[pname]
	_m = def
	_m_name = pname
	_m_body = _dock_body
	_m_msg = ""
	action_text = ""
	clear_gauges()
	_toast("MISSION: %s  (planet motion paused)" % def.get("title", ""))
	undock()
	_freeze_time(true)
	_act = ActivitiesScript.new()
	_act.mm = self
	_act.rig = rig
	_act.begin(_m_body, def)
	_refresh_menu()


# Called by an activity when the player succeeds.
func finish(stats: String) -> void:
	_complete_mission(stats)


# Called by an activity when the player fails.
func fail(reason: String) -> void:
	_abort_mission(reason)


func mission_action() -> void:
	if _act != null:
		_act.action()


func _end_activity(success: bool) -> void:
	if _act != null:
		_act.end(success)
		_act = null
	_freeze_time(false)
	action_text = ""
	clear_gauges()
	show_controls(false)


func _abort_mission(reason: String) -> void:
	_end_activity(false)
	_m = {}
	_m_body = null
	_toast("Mission failed — %s. Dock again to retry." % reason)
	vr_event("mission_fail")
	_refresh_menu()


func _complete_mission(stats: String) -> void:
	var earned := int(_m.get("score", 100))
	var title := String(_m.get("title", ""))
	score += earned
	rig._fuel = minf(rig.fuel_capacity, rig._fuel + MISSION_FUEL_BONUS)
	_completed[_m_name] = true
	_log.append({"planet": _m_name, "title": title, "discovery": String(_m.get("discovery", "")), "stats": stats})
	_card_label.text = "✔ MISSION COMPLETE\n%s: %s\n%s\n\nWHAT YOU LEARNED\n%s\n\n+%d score   +%d fuel   (recorded in the mission log)" % [
		_m_name.to_upper(), title, stats, _m.get("learned", ""), earned, int(MISSION_FUEL_BONUS)]
	_card.visible = true
	_card_timer = 20.0
	_toast("MISSION COMPLETE: %s  +%d" % [title, earned])
	vr_event("mission_complete")
	_end_activity(true)
	_m = {}
	_m_body = null
	if _completed.size() >= _targets.size():
		_toast("GRAND TOUR COMPLETE — all %d planets done!  Score %d" % [_targets.size(), score])
	_refresh_menu()
	_refresh_log()


func _tick_mission(delta: float) -> void:
	if _m.is_empty() or _m_body == null or _act == null:
		return
	var dist: float = rig._pos.distance_to(_m_body.global_position)
	if not rover_hold and dist > ABORT_DIST:
		_abort_mission("too far from %s" % _m_name)
		return
	_act.tick(delta)


# Planetary motion (orbits + spin) is paused while a mission runs so surfaces,
# storms and rings hold still; it resumes afterwards.
func _freeze_time(on: bool) -> void:
	var solar = rig._solar
	if solar == null:
		return
	if on and not _frozen:
		_prev_orbit = solar.orbit_enabled
		solar.orbit_enabled = false
		_frozen = true
	elif not on and _frozen:
		solar.orbit_enabled = _prev_orbit
		_frozen = false


# ---- HUD gauges (label + bar rows under the mission text) ----

func set_gauge(i: int, text: String, frac: float, color: Color) -> void:
	if i < 0 or i >= _g_rows.size():
		return
	_g_rows[i].visible = true
	_g_labels[i].text = text
	_g_bars[i].value = clampf(frac, 0.0, 1.0) * 100.0
	_g_fills[i].bg_color = color


func clear_gauges() -> void:
	for r in _g_rows:
		r.visible = false


func show_controls(on: bool) -> void:
	_ctl_row.visible = on
	if not on:
		ctl_left = false
		ctl_right = false
		ctl_fwd = false


# -- Deployed probes (Earth satellite / Mars rover) --

func _spawn_probe(body: Node3D, kind: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	mesh.material_override = mat
	var holder := Node3D.new()
	if kind == "satellite":
		box.size = Vector3(0.14, 0.05, 0.05)
		mesh.mesh = box
		# Sits under the orbit pivot at the planet's position so it follows the
		# planet round the Sun but doesn't spin with it.
		body.get_parent().add_child(holder)
		holder.position = body.position
		holder.rotation.z = 0.5
		mesh.position = Vector3(_radius(body) * 2.0 + 0.3, 0.0, 0.0)
		holder.add_child(mesh)
		_deployed.append({"node": holder, "kind": kind, "rate": 1.4})
		register_gaze_object(mesh, 0.16, "Your satellite", "It stays in orbit by moving sideways as fast as it falls toward Earth. Real satellites relay signals, watch weather and guide navigation.")
	else:
		# Rover rides the planet's surface (child of the planet, so it spins with it).
		var base := float(_data(body).get("radius", 0.2))
		box.size = Vector3.ONE * 0.05
		mesh.mesh = box
		body.add_child(holder)
		mesh.position = Vector3(0.0, base + 0.02, 0.0)
		holder.add_child(mesh)
		_deployed.append({"node": holder, "kind": kind, "rate": 0.5})


func _tick_deployed(delta: float) -> void:
	for d in _deployed:
		var n: Node3D = d.node
		if not is_instance_valid(n):
			continue
		if d.kind == "satellite":
			n.rotate_y(float(d.rate) * delta)
		else:
			n.rotate_x(float(d.rate) * delta)


# ---- Out of fuel ----

func _tick_rescue() -> void:
	var near_sun := false
	if rig._sun != null:
		near_sun = rig._pos.distance_to(rig._sun.global_position) < rig.refuel_radius
	_out_of_fuel = (not docked) and rig._fuel <= 0.01 and rig._vel.length() < 0.6 and not near_sun


func call_rescue() -> void:
	if not _out_of_fuel:
		return
	_ap.cancel("Autopilot cancelled")
	score = maxi(0, score - RESCUE_PENALTY)
	rig._pos = rig.spawn_position
	rig._vel = Vector3.ZERO
	rig._fuel = rig.fuel_capacity * 0.5
	if not _m.is_empty():
		_abort_mission("towed back to the Sun")
	_toast("Rescue tow complete  −%d score  (fuel 50%%)" % RESCUE_PENALTY)


# ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	_ap.handle_input(event)
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			request_dock()
		KEY_1:
			if docked:
				_do_scan(_dock_body)
		KEY_3:
			enter_surface()
		KEY_2:
			start_mission()
		KEY_F, KEY_G:
			mission_action()
		KEY_L:
			_log_panel.visible = not _log_panel.visible
			_refresh_log()
		KEY_R:
			call_rescue()


# ---- UI ----

func _build_ui() -> void:
	var layer: CanvasLayer = rig._hud_layer

	var top := VBoxContainer.new()
	top.position = Vector2(16, 56)
	top.custom_minimum_size = Vector2(330, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	_score_label = rig._make_hud_label(17, Color(1.0, 0.9, 0.5))
	top.add_child(_score_label)
	_mission_label = rig._make_hud_label(15, Color(0.7, 1.0, 0.8))
	_mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_label.custom_minimum_size = Vector2(330, 0)
	top.add_child(_mission_label)

	# Science gauges: label + bar rows an activity fills through set_gauge().
	for i in 3:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		top.add_child(row)
		var lbl: Label = rig._make_hud_label(13, Color(0.9, 0.95, 1.0))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(330, 0)
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(330, 10)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.07, 0.12, 0.75)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.4, 0.75, 1.0)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		_g_rows.append(row)
		_g_labels.append(lbl)
		_g_bars.append(bar)
		_g_fills.append(fill)

	# Gaze reticle + dwell progress at screen centre.
	_reticle = rig._make_hud_label(28, Color(0.8, 0.95, 1.0, 0.7))
	_reticle.text = "+"
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.position = Vector2(-8, -20)
	layer.add_child(_reticle)

	_dwell_box = VBoxContainer.new()
	_dwell_box.set_anchors_preset(Control.PRESET_CENTER)
	_dwell_box.position = Vector2(-70, 24)
	_dwell_box.size = Vector2(140, 40)
	_dwell_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dwell_box.visible = false
	layer.add_child(_dwell_box)
	_dwell_label = rig._make_hud_label(14, Color(0.8, 0.95, 1.0))
	_dwell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dwell_box.add_child(_dwell_label)
	_dwell_bar = ProgressBar.new()
	_dwell_bar.max_value = SCAN_DWELL
	_dwell_bar.show_percentage = false
	_dwell_bar.custom_minimum_size = Vector2(140, 10)
	_dwell_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dwell_box.add_child(_dwell_bar)

	# Fact card (top right, under the nearest-planet readout).
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.position = Vector2(-340, 84)
	_card.custom_minimum_size = Vector2(324, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_card.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(_card)
	_card_label = rig._make_hud_label(15, Color(0.9, 0.96, 1.0))
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.custom_minimum_size = Vector2(300, 0)
	_card.add_child(_card_label)

	# Dock menu (left).
	_menu = PanelContainer.new()
	_menu.position = Vector2(16, 200)
	_menu.custom_minimum_size = Vector2(300, 0)
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(_menu)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	_menu.add_child(mv)
	_menu_title = rig._make_hud_label(20, Color(0.9, 0.96, 1.0))
	mv.add_child(_menu_title)
	_menu_brief = rig._make_hud_label(13, Color(0.75, 0.85, 0.95))
	_menu_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_brief.custom_minimum_size = Vector2(280, 0)
	mv.add_child(_menu_brief)
	_menu_refuel = rig._make_hud_label(14, Color(0.4, 1.0, 0.6))
	_menu_refuel.text = "⛽ Refuelling while docked…"
	mv.add_child(_menu_refuel)
	_menu_scan = _make_button("[1] Scan planet", func(): if docked: _do_scan(_dock_body))
	mv.add_child(_menu_scan)
	_menu_mission = _make_button("[2] Start mission", start_mission)
	_menu_explore = _make_button("[3] 🚶 Exit ship: explore the surface (VR)", enter_surface)
	_menu_explore.visible = false
	mv.add_child(_menu_mission)
	mv.add_child(_menu_explore)
	mv.add_child(_make_button("[E] Undock", undock))

	# Context prompt + action buttons (bottom centre, above the fuel bar).
	_prompt = rig._make_hud_label(18, Color(1.0, 0.95, 0.6))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-260, -150)
	_prompt.size = Vector2(520, 26)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_prompt)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.position = Vector2(-230, -122)
	row.size = Vector2(460, 48)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(row)
	_btn_dock = _make_button("DOCK [E]", request_dock)
	_btn_action = _make_button("ACTION [G]", mission_action)
	_btn_rescue = _make_button("RESCUE TOW [R]", call_rescue)
	_btn_return = _make_button("🚀 RETURN TO SHIP", exit_surface)
	for b in [_btn_dock, _btn_action, _btn_rescue, _btn_return]:
		b.visible = false
		row.add_child(b)

	# Toast + camera flash.
	_toast_label = rig._make_hud_label(20, Color(1.0, 1.0, 1.0))
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(-300, 110)
	_toast_label.size = Vector2(600, 30)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	layer.add_child(_toast_label)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

	# Rover drive buttons (bottom right): hold to drive. Hidden except in the Mars rover phase.
	_ctl_row = HBoxContainer.new()
	_ctl_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ctl_row.position = Vector2(-300, -110)
	_ctl_row.size = Vector2(280, 56)
	_ctl_row.add_theme_constant_override("separation", 8)
	_ctl_row.visible = false
	layer.add_child(_ctl_row)
	for spec in [["◀", "left"], ["▲ DRIVE", "fwd"], ["▶", "right"]]:
		var cb := _make_button(spec[0], func(): pass)
		cb.custom_minimum_size = Vector2(80 if spec[1] != "fwd" else 110, 56)
		var which: String = spec[1]
		cb.button_down.connect(func(): _set_ctl(which, true))
		cb.button_up.connect(func(): _set_ctl(which, false))
		_ctl_row.add_child(cb)

	# Mission log (toggle with L or the button, bottom left).
	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_log_panel.position = Vector2(16, -220)
	_log_panel.custom_minimum_size = Vector2(420, 0)
	_log_panel.visible = false
	_log_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(_log_panel)
	_log_label = rig._make_hud_label(14, Color(0.9, 0.96, 1.0))
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size = Vector2(400, 0)
	_log_panel.add_child(_log_label)
	var log_btn := _make_button("📖 LOG [L]", func():
		_log_panel.visible = not _log_panel.visible
		_refresh_log())
	log_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_btn.position = Vector2(16, -60)
	log_btn.size = Vector2(120, 44)
	layer.add_child(log_btn)
	_refresh_log()

	_ap.build_ui(layer)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.12, 0.8)
	s.border_color = Color(0.4, 0.55, 0.8, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	return s


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_timer = 3.5


func _tick_toast(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_label.modulate.a = clampf(_toast_timer, 0.0, 1.0)
	if _card.visible:
		_card_timer -= delta
		if _card_timer <= 0.0:
			_card.visible = false
	if _flash.color.a > _last_flash + 0.05:
		vr_event("flash", {"amount": _flash.color.a})
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(0.0, _flash.color.a - 2.5 * delta)
	_last_flash = _flash.color.a


func _set_ctl(which: String, down: bool) -> void:
	match which:
		"left":
			ctl_left = down
		"right":
			ctl_right = down
		"fwd":
			ctl_fwd = down


func _refresh_log() -> void:
	var text := "MISSION LOG   %d / %d discoveries\n" % [_log.size(), _targets.size()]
	for b in _targets:
		var pname := _pname(b)
		var found := false
		for e in _log:
			if e["planet"] == pname:
				text += "\n✔ %s — %s\n    %s" % [pname, e["title"], e["discovery"]]
				found = true
				break
		if not found:
			text += "\n○ %s — %s (not completed)" % [pname, MissionData.MISSIONS[pname].get("title", "")]
	if not _surface_finds.is_empty():
		text += "\n\nSURFACE FINDS"
		for s in _surface_finds:
			text += "\n• %s: %s" % [s["planet"], s["item"]]
	_log_label.text = text


func _refresh_menu() -> void:
	_menu.visible = docked and not surface_hold
	if not docked or _dock_body == null:
		return
	var pname := _pname(_dock_body)
	_menu_title.text = "DOCKED — %s" % pname
	_menu_explore.visible = vr != null and MissionData.WALKABLE.has(pname)
	_menu_explore.disabled = not _m.is_empty()
	_menu_refuel.visible = MissionData.REFUEL_PLANETS.has(pname)
	var def: Dictionary = MissionData.MISSIONS.get(pname, {})
	if def.is_empty():
		_menu_brief.text = ""
		_menu_mission.visible = false
		return
	_menu_brief.text = String(def.get("brief", ""))
	_menu_mission.visible = true
	if _completed.has(pname):
		_menu_mission.text = "✓ %s complete" % def.get("title", "")
		_menu_mission.disabled = true
	elif not _m.is_empty():
		_menu_mission.text = "Mission in progress"
		_menu_mission.disabled = true
	else:
		_menu_mission.text = "[2] Start: %s" % def.get("title", "")
		_menu_mission.disabled = false


func _update_ui() -> void:
	_score_label.text = "SCORE %d   MISSIONS %d/%d   SCANS %d/%d" % [
		score, _completed.size(), _targets.size(), _scanned.size(), _targets.size()]

	if _m.is_empty():
		_mission_label.text = "No active mission. Dock at a planet to start one." if _completed.is_empty() else ""
	else:
		_mission_label.text = "▶ %s — %s\n%s\n%s" % [_m_name, _m.get("title", ""), _m.get("objective", ""), _m_msg]

	if surface_hold:
		_mission_label.text = surface_info

	# Gaze scan progress ring.
	var scanning := _gaze_body != null and _dwell > 0.0
	_dwell_box.visible = scanning and vr == null
	_reticle.visible = vr == null
	if scanning:
		_dwell_bar.value = _dwell
		_dwell_label.text = "SCANNING %s" % _gaze_title(_gaze_body).to_upper()

	# Context prompt + buttons.
	var prompt := ""
	if docked:
		pass
	elif _out_of_fuel:
		prompt = "OUT OF FUEL — call a rescue tow (−%d score)" % RESCUE_PENALTY
	elif _dock_candidate != null:
		if rig._vel.length() > DOCK_MAX_SPEED:
			prompt = "Slow down to dock at %s" % _pname(_dock_candidate)
		else:
			prompt = "Press E to DOCK at %s" % _pname(_dock_candidate)
	elif rig._fuel < rig.fuel_capacity * 0.25:
		prompt = "⚠ LOW FUEL — refuel at the ☀ or dock at Earth / Jupiter / Saturn"
	_prompt.text = prompt
	_btn_dock.visible = (_dock_candidate != null and not docked)
	_btn_action.visible = (not _m.is_empty() and action_text != "")
	_btn_action.text = action_text
	_btn_rescue.visible = _out_of_fuel
	_btn_return.visible = surface_hold
