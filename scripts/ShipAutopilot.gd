extends RefCounted
## Click-to-travel autopilot.
##
## Click (short press) a planet, or press T while gazing at one, and the ship
## flies there by itself. It never teleports: it steers the hull (yaw / pitch at
## a limited rate) and switches the same thrust the player uses on and off, so
## the normal flight physics, drag, speed clamp and fuel burn all still apply.
##
## Guidance: pick a desired speed toward the stop point that is capped at
## CRUISE_SPEED and shrinks as sqrt(2 * BRAKE_ACCEL * distance) near the end.
## Accelerate toward that, and when the ship is too fast turn around and burn
## against its motion (the ship can only thrust forward). Planets orbit, so
## everything is done in the planet's frame; at the stop point the autopilot
## keeps station beside the planet until the player docks (E) or takes over.
##
## Any manual input (W/A/S/D, Space, holding the mouse button, X) hands
## control back to the player.

const CRUISE_SPEED := 6.0        # u/s, below the ship's max_speed
const BRAKE_ACCEL := 1.1         # planned deceleration (conservative vs thrust_accel)
const STOP_SURFACE_DIST := 1.0   # stop this far from the surface (inside DOCK_RANGE)
const CONTROL_TAU := 1.0         # s, velocity-error time constant
const ALIGN_MAX := 0.30          # rad, hull must point this close to the burn direction
const BURN_MIN := 0.30           # u/s², below this the engine stays off
const ARRIVE_DIST := 0.6
const ARRIVE_SPEED := 0.6
const WAYPOINT_REACHED := 1.5
const CLICK_MAX_SEC := 0.3
const CLICK_MAX_MOVE := 8.0

var mm = null               # ShipMissions
var rig = null              # ShipRig

var active: bool = false
var arrived: bool = false
var target: Node3D = null
var phase: String = ""

var _approach: Vector3 = Vector3.FORWARD    # unit vector from planet toward the stop point
var _has_wp: bool = false
var _wp: Vector3 = Vector3.ZERO
var _d0: float = 1.0
var _fuel0: float = 0.0
var _prev_c: Vector3 = Vector3.ZERO
var _pv: Vector3 = Vector3.ZERO
var _have_pv: bool = false
var _press_ms: int = -1
var _press_pos: Vector2 = Vector2.ZERO

var _panel: PanelContainer
var _title: Label
var _info: Label
var _bar: ProgressBar
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_info: Label
var _hover_lbl: Label
var _confirm_target: Node3D = null
var confirm_open: bool = false


# ---- UI ----

func build_ui(layer: CanvasLayer) -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-190, 150)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", mm._panel_style())
	layer.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = rig._make_hud_label(18, Color(0.6, 0.9, 1.0))
	v.add_child(_title)
	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(360, 12)
	v.add_child(_bar)
	_info = rig._make_hud_label(14, Color(0.85, 0.95, 1.0))
	v.add_child(_info)
	v.add_child(mm._make_button("✖ CANCEL AUTOPILOT [X]", func(): cancel("Autopilot cancelled")))

	# "Travel to X?" confirmation (Yes / No).
	_confirm = PanelContainer.new()
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.position = Vector2(-200, -150)
	_confirm.custom_minimum_size = Vector2(400, 0)
	_confirm.visible = false
	_confirm.add_theme_stylebox_override("panel", mm._panel_style())
	layer.add_child(_confirm)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_confirm.add_child(cv)
	_confirm_title = rig._make_hud_label(22, Color(0.7, 0.95, 1.0))
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_confirm_title)
	_confirm_info = rig._make_hud_label(14, Color(0.85, 0.95, 1.0))
	_confirm_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_confirm_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cv.add_child(row)
	var yes: Button = mm._make_button("✔ YES  [Y]", confirm_yes)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(yes)
	var no: Button = mm._make_button("✖ NO  [N]", confirm_no)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)

	# Small hint that follows the mouse when it is over a planet (desktop).
	_hover_lbl = rig._make_hud_label(15, Color(1.0, 0.95, 0.6))
	_hover_lbl.visible = false
	layer.add_child(_hover_lbl)


# ---- Confirmation ----

## Ask "Travel to <planet>?". Nothing moves until the player answers Yes.
func ask(b: Node3D) -> void:
	if b == null or mm.rover_hold or mm.surface_hold:
		return
	if active and b == target:
		return
	_confirm_target = b
	var pos: Vector3 = rig._pos
	var d: float = pos.distance_to(b.global_position) - mm._radius(b)
	_confirm_title.text = "Travel to %s?" % mm._pname(b)
	var v_peak := minf(CRUISE_SPEED, sqrt(BRAKE_ACCEL * maxf(d, 1.0)))
	var need: float = rig.fuel_burn_per_sec * (2.0 * v_peak / rig.thrust_accel) * 1.15
	_confirm_info.text = "Distance %.1f u  •  about %d fuel  (you have %d)\nThe autopilot will fly there and hold beside it so you can dock." % [d, int(need), int(rig._fuel)]
	_confirm.visible = true
	_hover_lbl.visible = false
	confirm_open = true


func confirm_yes() -> void:
	var b := _confirm_target
	_close_confirm()
	if b != null:
		start(b)


func confirm_no() -> void:
	_close_confirm()
	mm._toast("Staying here")


func _close_confirm() -> void:
	_confirm_target = null
	confirm_open = false
	if _confirm != null:
		_confirm.visible = false


# ---- Selection ----

func handle_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if confirm_open and key != null and key.pressed and not key.echo:
		if key.keycode == KEY_Y or key.keycode == KEY_ENTER:
			confirm_yes()
		elif key.keycode == KEY_N or key.keycode == KEY_ESCAPE:
			confirm_no()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if confirm_open:
			return
		if mb.pressed:
			_press_ms = Time.get_ticks_msec()
			_press_pos = mb.position
		elif _press_ms >= 0:
			var held := (Time.get_ticks_msec() - _press_ms) / 1000.0
			_press_ms = -1
			if held <= CLICK_MAX_SEC and mb.position.distance_to(_press_pos) <= CLICK_MAX_MOVE:
				var p := pick(mb.position)
				if p != null:
					rig._thrusting = false
					ask(p)
		return
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_X:
			cancel("Autopilot cancelled")
		elif key.keycode == KEY_T and mm._gaze_body != null and mm._targets.has(mm._gaze_body):
			ask(mm._gaze_body)


# Planet under a screen position, or null.
func pick(screen_pos: Vector2) -> Node3D:
	var cam: Camera3D = rig._left_cam
	return pick_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))["node"]


# Planet along a ray (mouse, VR controller laser). Returns {"node": Node3D or null, "t": distance}.
func pick_ray(o: Vector3, dir: Vector3) -> Dictionary:
	var best: Node3D = null
	var best_t := INF
	for b in mm._targets:
		var oc: Vector3 = b.global_position - o
		var t := oc.dot(dir)
		if t <= 0.0:
			continue
		var perp := (oc - dir * t).length()
		if perp < maxf(mm._radius(b) * 1.25, 0.03 * t) and t < best_t:
			best_t = t
			best = b
	return {"node": best, "t": best_t}


# ---- Control ----


func start(b: Node3D) -> void:
	if b == null or mm.rover_hold or mm.surface_hold:
		return
	if mm.docked:
		mm.undock()
	target = b
	active = true
	arrived = false
	_have_pv = false
	var pos: Vector3 = rig._pos
	var c := b.global_position
	_approach = (pos - c).normalized()
	if _approach.length() < 0.5:
		_approach = Vector3.BACK
	_plan_route(pos, _stop_point())
	_d0 = maxf(_path_length(pos), 1.0)
	_fuel0 = rig._fuel
	# Rough fuel estimate: accelerate + brake at full thrust.
	var v_peak := minf(CRUISE_SPEED, sqrt(BRAKE_ACCEL * _d0))
	var need: float = rig.fuel_burn_per_sec * (2.0 * v_peak / rig.thrust_accel) * 1.15
	if rig._fuel < need:
		mm._toast("Autopilot → %s  (fuel may run short: ~%d needed)" % [mm._pname(b), int(need)])
	else:
		mm._toast("Autopilot engaged → %s" % mm._pname(b))


# Silent stop (docking or takeover by something else).
func stop() -> void:
	active = false
	arrived = false
	target = null
	if _panel != null:
		_panel.visible = false


func cancel(reason: String) -> void:
	if not active:
		return
	active = false
	arrived = false
	target = null
	rig._thrusting = false
	_panel.visible = false
	mm._toast(reason)


func _stop_point() -> Vector3:
	return target.global_position + _approach * (mm._radius(target) + STOP_SURFACE_DIST)


# If the straight line passes too close to the Sun, route around it first.
func _plan_route(from: Vector3, to: Vector3) -> void:
	_has_wp = false
	if rig._sun == null:
		return
	var sun: Vector3 = rig._sun.global_position
	var clear: float = mm._radius(rig._sun) + 1.8
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.01:
		return
	var t := clampf((sun - from).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
	var closest := from + seg * t
	var off := closest - sun
	if off.length() >= clear:
		return
	var side := off
	if side.length() < 0.05:
		side = seg.normalized().cross(Vector3.UP)
	_wp = sun + side.normalized() * clear * 1.4
	_has_wp = true


func _path_length(pos: Vector3) -> float:
	if _has_wp:
		return pos.distance_to(_wp) + _wp.distance_to(_stop_point())
	return pos.distance_to(_stop_point())


func _manual_input() -> bool:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_SPACE):
		return true
	if _press_ms >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return (Time.get_ticks_msec() - _press_ms) / 1000.0 > CLICK_MAX_SEC
	return false


# ---- Per-frame ----

func update(delta: float) -> void:
	_update_hover()
	if not active:
		return
	if mm.docked:
		active = false
		target = null
		_panel.visible = false
		return
	if mm.rover_hold:
		cancel("Autopilot cancelled")
		return
	if _manual_input():
		cancel("Manual control")
		return
	if rig._fuel <= 0.01:
		cancel("Autopilot stopped — out of fuel")
		return

	var c := target.global_position
	if _have_pv and delta > 0.0:
		_pv = _pv.lerp((c - _prev_c) / delta, 0.25)
	_have_pv = true
	_prev_c = c

	var pos: Vector3 = rig._pos
	var v_rel: Vector3 = rig._vel - _pv
	var stop_pt := _stop_point()

	var goal := stop_pt
	if _has_wp:
		goal = _wp
		if pos.distance_to(_wp) < WAYPOINT_REACHED:
			_has_wp = false
			goal = stop_pt
	var to_goal := goal - pos
	var d_goal := to_goal.length()
	var dir := to_goal / maxf(d_goal, 0.001)

	# Desired closing speed: cruise, then a sqrt() ramp down to zero at the stop point.
	var v_cmd := CRUISE_SPEED
	if not _has_wp:
		v_cmd = minf(CRUISE_SPEED, sqrt(2.0 * BRAKE_ACCEL * maxf(d_goal - 0.1, 0.0)))
	var a_cmd: Vector3 = (dir * v_cmd - v_rel) / CONTROL_TAU + rig._vel * rig.drag_per_sec
	var a_len := a_cmd.length()

	if not arrived and not _has_wp and d_goal < ARRIVE_DIST and v_rel.length() < ARRIVE_SPEED:
		arrived = true
		mm._toast("Arrived at %s — press E to dock" % mm._pname(target))

	# Heading: burn direction when a burn is needed, otherwise point down the
	# track (or at the planet once arrived) so the hull doesn't flip needlessly.
	var burn := a_len > BURN_MIN
	var face := dir
	if burn:
		face = a_cmd / a_len
	elif arrived:
		face = (c - pos).normalized()
	var t_yaw := atan2(-face.x, -face.z)
	var t_pitch := clampf(asin(clampf(face.y, -1.0, 1.0)), -1.35, 1.35)
	var step: float = rig.steer_rate * 1.3 * delta
	rig._ship_yaw += clampf(angle_difference(rig._ship_yaw, t_yaw), -step, step)
	rig._ship_pitch += clampf(t_pitch - rig._ship_pitch, -step, step)

	var fwd: Vector3 = -rig._ship_basis().z
	rig._thrusting = burn and fwd.angle_to(face) < ALIGN_MAX

	# Phase label + HUD.
	var speed := v_rel.length()
	if arrived:
		phase = "STATION-KEEPING — press E to DOCK"
	elif _has_wp:
		phase = "ROUTING AROUND THE SUN"
	elif v_cmd < CRUISE_SPEED * 0.98:
		phase = "BRAKING"
	elif speed < CRUISE_SPEED * 0.93:
		phase = "ACCELERATING"
	else:
		phase = "CRUISING"
	var remaining := _path_length(pos)
	var progress := clampf(1.0 - remaining / _d0, 0.0, 1.0)
	var closing := maxf(v_rel.dot(dir), 0.5)
	_panel.visible = true
	_title.text = "AUTOPILOT → %s" % mm._pname(target).to_upper()
	_bar.value = progress * 100.0
	_info.text = "Distance %.1f u  •  Speed %.1f u/s  •  ETA %d s\n%s  •  Fuel used %d" % [
		maxf(remaining - 0.0, 0.0), speed,
		0 if arrived else int(ceil(remaining / closing)), phase, int(round(_fuel0 - rig._fuel))]


# Desktop hint: a label that follows the mouse while it is over a planet.
func _update_hover() -> void:
	if _hover_lbl == null:
		return
	_hover_lbl.visible = false
	if active or confirm_open or mm.vr != null or mm.hold_ship:
		return
	var vp: Viewport = rig.get_viewport()
	var mp := vp.get_mouse_position()
	if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mp):
		return
	var p := pick(mp)
	if p != null:
		_hover_lbl.text = "%s — click to travel" % mm._pname(p)
		_hover_lbl.position = mp + Vector2(18, 18)
		_hover_lbl.visible = true
