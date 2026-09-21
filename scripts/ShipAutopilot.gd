extends RefCounted
## Planet selection, targeting, and Navigation Mode Autopilot/Manual Controller.
##
## Features:
## 1. Continuous planet detection via pointer/gaze/aiming.
## 2. Choice Popup: AUTO PILOT vs MANUAL CONTROL when a planet is targeted.
## 3. Target Lock: Locks the destination planet regardless of crosshair movement during flight.
## 4. Arrival Detection & Permission: When reaching the destination (in either Auto Pilot or Manual),
##    prompts the user to [ BEGIN TASK ] before launching predefined planet tasks.

const CRUISE_SPEED := 6.0        # u/s, below the ship's max_speed
const BRAKE_ACCEL := 1.1         # planned deceleration (conservative vs thrust_accel)
const STOP_SURFACE_DIST := 1.0   # stop this far from the surface (inside DOCK_RANGE)
const CONTROL_TAU := 1.0         # s, velocity-error time constant
const ALIGN_MAX := 0.30          # rad, hull must point this close to the burn direction
const BURN_MIN := 0.30           # u/s², below this the engine stays off
const ARRIVE_DIST := 1.2         # arrival proximity threshold
const ARRIVE_SPEED := 0.6
const WAYPOINT_REACHED := 1.5
const CLICK_MAX_SEC := 0.3
const CLICK_MAX_MOVE := 8.0

enum NavState {
	IDLE,
	PLANET_TARGETED,
	AUTO_PILOT,
	MANUAL_CONTROL,
	PLANET_REACHED,
	TASK_IN_PROGRESS
}

var mm = null               # ShipMissions
var rig = null              # ShipRig

var nav_state: int = NavState.IDLE
var active: bool = false
var arrived: bool = false
var target: Node3D = null
var targeted_planet: Node3D = null
var locked_planet: Node3D = null
var selected_mode: String = ""   # "AUTO_PILOT" or "MANUAL_CONTROL"
var phase: String = ""

var _approach: Vector3 = Vector3.FORWARD
var _has_wp: bool = false
var _wp: Vector3 = Vector3.ZERO
var _d0: float = 1.0
var _fuel0: float = 0.0
var _prev_c: Vector3 = Vector3.ZERO
var _pv: Vector3 = Vector3.ZERO
var _have_pv: bool = false
var _press_ms: int = -1
var _press_pos: Vector2 = Vector2.ZERO

# --- UI elements ---
var _panel: PanelContainer        # Autopilot flight HUD
var _title: Label
var _info: Label
var _bar: ProgressBar

var _choice_panel: PanelContainer # Navigation choice modal
var _choice_title: Label
var _choice_info: Label
var _btn_autopilot: Button
var _btn_manual: Button
var _btn_choice_cancel: Button
var choice_open: bool = false

var _permission_panel: PanelContainer # Arrival permission modal
var _permission_title: Label
var _permission_info: Label
var _btn_begin_task: Button
var _btn_perm_cancel: Button
var permission_open: bool = false

var _manual_panel: PanelContainer # Manual control HUD readout
var _manual_title: Label
var _manual_info: Label

var _confirm: PanelContainer     # Legacy confirmation popup fallback
var _confirm_title: Label
var _confirm_info: Label
var _confirm_target: Node3D = null
var confirm_open: bool = false

var _hover_lbl: Label


# ---- UI Construction ----

func build_ui(layer: CanvasLayer) -> void:
	# 1. Autopilot Active Flight Panel
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

	# 2. Navigation Choice Popup Modal
	_choice_panel = PanelContainer.new()
	_choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	_choice_panel.position = Vector2(-220, -160)
	_choice_panel.custom_minimum_size = Vector2(440, 0)
	_choice_panel.visible = false
	_choice_panel.add_theme_stylebox_override("panel", mm._panel_style())
	layer.add_child(_choice_panel)
	
	var ch_v := VBoxContainer.new()
	ch_v.add_theme_constant_override("separation", 10)
	_choice_panel.add_child(ch_v)
	
	_choice_title = rig._make_hud_label(22, Color(0.6, 0.95, 1.0))
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch_v.add_child(_choice_title)
	
	_choice_info = rig._make_hud_label(15, Color(0.85, 0.95, 1.0))
	_choice_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch_v.add_child(_choice_info)
	
	var ch_sub: Label = rig._make_hud_label(14, Color(1.0, 0.9, 0.5))
	ch_sub.text = "How would you like to travel to this planet?"
	ch_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch_v.add_child(ch_sub)

	var ch_btns := HBoxContainer.new()
	ch_btns.add_theme_constant_override("separation", 12)
	ch_v.add_child(ch_btns)

	_btn_autopilot = mm._make_button("🚀 AUTO PILOT [1]", select_autopilot)
	_btn_autopilot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_btns.add_child(_btn_autopilot)

	_btn_manual = mm._make_button("🎮 MANUAL CONTROL [2]", select_manual_control)
	_btn_manual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_btns.add_child(_btn_manual)

	_btn_choice_cancel = mm._make_button("✖ CANCEL [ESC]", close_choice_popup)
	ch_v.add_child(_btn_choice_cancel)

	# 3. Arrival Permission Modal
	_permission_panel = PanelContainer.new()
	_permission_panel.set_anchors_preset(Control.PRESET_CENTER)
	_permission_panel.position = Vector2(-210, -140)
	_permission_panel.custom_minimum_size = Vector2(420, 0)
	_permission_panel.visible = false
	_permission_panel.add_theme_stylebox_override("panel", mm._panel_style())
	layer.add_child(_permission_panel)

	var p_v := VBoxContainer.new()
	p_v.add_theme_constant_override("separation", 10)
	_permission_panel.add_child(p_v)

	_permission_title = rig._make_hud_label(22, Color(0.4, 1.0, 0.6))
	_permission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_v.add_child(_permission_title)

	_permission_info = rig._make_hud_label(15, Color(0.9, 0.95, 1.0))
	_permission_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_v.add_child(_permission_info)

	var p_btns := HBoxContainer.new()
	p_btns.add_theme_constant_override("separation", 12)
	p_v.add_child(p_btns)

	_btn_begin_task = mm._make_button("✔ BEGIN TASK [ENTER]", confirm_begin_task)
	_btn_begin_task.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_btns.add_child(_btn_begin_task)

	_btn_perm_cancel = mm._make_button("✖ CANCEL [ESC]", cancel_arrival_permission)
	_btn_perm_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_btns.add_child(_btn_perm_cancel)

	# 4. Manual Control Flight HUD Panel
	_manual_panel = PanelContainer.new()
	_manual_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_manual_panel.position = Vector2(-190, 150)
	_manual_panel.custom_minimum_size = Vector2(380, 0)
	_manual_panel.visible = false
	_manual_panel.add_theme_stylebox_override("panel", mm._panel_style())
	layer.add_child(_manual_panel)

	var m_v := VBoxContainer.new()
	m_v.add_theme_constant_override("separation", 4)
	_manual_panel.add_child(m_v)

	_manual_title = rig._make_hud_label(18, Color(1.0, 0.85, 0.4))
	m_v.add_child(_manual_title)

	_manual_info = rig._make_hud_label(14, Color(0.85, 0.95, 1.0))
	m_v.add_child(_manual_info)

	m_v.add_child(mm._make_button("✖ UNLOCK TARGET [X]", cancel_manual))

	# 5. Legacy Confirmation Dialog (Fallback)
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

	# Hover label
	_hover_lbl = rig._make_hud_label(15, Color(1.0, 0.95, 0.6))
	_hover_lbl.visible = false
	layer.add_child(_hover_lbl)


# ---- Planet Detection & Popup Logic ----

func update_planet_targeting(delta: float, gaze_planet: Node3D) -> void:
	# Ignore targeting while locked in active navigation, docked, or in surface/rover mode
	if mm.docked or mm.rover_hold or mm.surface_hold or nav_state == NavState.TASK_IN_PROGRESS:
		return
	if nav_state == NavState.AUTO_PILOT or nav_state == NavState.MANUAL_CONTROL or nav_state == NavState.PLANET_REACHED:
		return
	
	if gaze_planet != null:
		if targeted_planet != gaze_planet or not choice_open:
			open_choice_popup(gaze_planet)
	elif choice_open and nav_state == NavState.PLANET_TARGETED:
		pass


func open_choice_popup(b: Node3D) -> void:
	if b == null or mm.rover_hold or mm.surface_hold:
		return
	targeted_planet = b
	nav_state = NavState.PLANET_TARGETED
	choice_open = true
	confirm_open = false
	_confirm.visible = false
	
	var pos: Vector3 = rig._pos
	var d: float = pos.distance_to(b.global_position) - mm._radius(b)
	_choice_title.text = "TARGET LOCKED: %s" % mm._pname(b).to_upper()
	_choice_info.text = "Planet: %s  •  Distance: %.1f u" % [mm._pname(b), d]
	_choice_panel.visible = true
	if _hover_lbl != null:
		_hover_lbl.visible = false


func close_choice_popup() -> void:
	choice_open = false
	if _choice_panel != null:
		_choice_panel.visible = false
	if nav_state == NavState.PLANET_TARGETED:
		nav_state = NavState.IDLE
		targeted_planet = null


func select_autopilot() -> void:
	if targeted_planet == null:
		return
	var b := targeted_planet
	close_choice_popup()
	locked_planet = b
	selected_mode = "AUTO_PILOT"
	nav_state = NavState.AUTO_PILOT
	start(b)


func select_manual_control() -> void:
	if targeted_planet == null:
		return
	var b := targeted_planet
	close_choice_popup()
	locked_planet = b
	target = b
	selected_mode = "MANUAL_CONTROL"
	nav_state = NavState.MANUAL_CONTROL
	active = false
	_manual_panel.visible = true
	mm._toast("TARGET LOCKED: %s — MANUAL CONTROL ACTIVE" % mm._pname(b))


func cancel_manual() -> void:
	nav_state = NavState.IDLE
	locked_planet = null
	target = null
	selected_mode = ""
	if _manual_panel != null:
		_manual_panel.visible = false
	mm._toast("Target unlocked")


# ---- Arrival Permission Flow ----

func show_arrival_permission(b: Node3D) -> void:
	if b == null:
		return
	nav_state = NavState.PLANET_REACHED
	permission_open = true
	active = false
	rig._thrusting = false
	if _panel != null:
		_panel.visible = false
	if _manual_panel != null:
		_manual_panel.visible = false
	
	_permission_title.text = "DESTINATION REACHED: %s" % mm._pname(b).to_upper()
	_permission_info.text = "You have safely arrived at %s.\nReady to begin the mission?" % mm._pname(b)
	_permission_panel.visible = true
	mm._toast("Arrived at %s" % mm._pname(b))


func confirm_begin_task() -> void:
	permission_open = false
	if _permission_panel != null:
		_permission_panel.visible = false
	
	var b := locked_planet if locked_planet != null else target
	nav_state = NavState.TASK_IN_PROGRESS
	if b != null:
		mm.dock_and_start_mission(b)


func cancel_arrival_permission() -> void:
	permission_open = false
	if _permission_panel != null:
		_permission_panel.visible = false
	nav_state = NavState.IDLE
	locked_planet = null
	target = null
	selected_mode = ""
	mm._toast("Mission postponed")


# ---- Legacy Confirmation Support ----

func ask(b: Node3D) -> void:
	open_choice_popup(b)


func confirm_yes() -> void:
	var b := _confirm_target
	_close_confirm()
	if b != null:
		open_choice_popup(b)


func confirm_no() -> void:
	_close_confirm()
	mm._toast("Staying here")


func _close_confirm() -> void:
	_confirm_target = null
	confirm_open = false
	if _confirm != null:
		_confirm.visible = false


# ---- Selection & Input Handling ----

func handle_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if choice_open and key != null and key.pressed and not key.echo:
		if key.keycode == KEY_1 or key.keycode == KEY_A or key.keycode == KEY_Y:
			select_autopilot()
		elif key.keycode == KEY_2 or key.keycode == KEY_M:
			select_manual_control()
		elif key.keycode == KEY_ESCAPE or key.keycode == KEY_X or key.keycode == KEY_N:
			close_choice_popup()
		return
		
	if permission_open and key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ENTER or key.keycode == KEY_SPACE or key.keycode == KEY_Y or key.keycode == KEY_1:
			confirm_begin_task()
		elif key.keycode == KEY_ESCAPE or key.keycode == KEY_X or key.keycode == KEY_N:
			cancel_arrival_permission()
		return

	if confirm_open and key != null and key.pressed and not key.echo:
		if key.keycode == KEY_Y or key.keycode == KEY_ENTER:
			confirm_yes()
		elif key.keycode == KEY_N or key.keycode == KEY_ESCAPE:
			confirm_no()
		return

	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if choice_open or permission_open or confirm_open:
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
					open_choice_popup(p)
		return

	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_X:
			if nav_state == NavState.AUTO_PILOT:
				cancel("Autopilot cancelled")
			elif nav_state == NavState.MANUAL_CONTROL:
				cancel_manual()
		elif key.keycode == KEY_T and mm._gaze_body != null and mm._targets.has(mm._gaze_body):
			open_choice_popup(mm._gaze_body)


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
	locked_planet = b
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
	var v_peak := minf(CRUISE_SPEED, sqrt(BRAKE_ACCEL * _d0))
	var need: float = rig.fuel_burn_per_sec * (2.0 * v_peak / rig.thrust_accel) * 1.15
	if rig._fuel < need:
		mm._toast("Autopilot → %s  (fuel may run short: ~%d needed)" % [mm._pname(b), int(need)])
	else:
		mm._toast("Autopilot engaged → %s" % mm._pname(b))


func stop() -> void:
	active = false
	arrived = false
	target = null
	if nav_state != NavState.TASK_IN_PROGRESS:
		nav_state = NavState.IDLE
	if _panel != null:
		_panel.visible = false
	if _manual_panel != null:
		_manual_panel.visible = false


func cancel(reason: String) -> void:
	active = false
	arrived = false
	target = null
	locked_planet = null
	selected_mode = ""
	nav_state = NavState.IDLE
	rig._thrusting = false
	if _panel != null:
		_panel.visible = false
	if _manual_panel != null:
		_manual_panel.visible = false
	mm._toast(reason)


func _stop_point() -> Vector3:
	return target.global_position + _approach * (mm._radius(target) + STOP_SURFACE_DIST)


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
	
	# Manual Control Proximity / Arrival Check
	if nav_state == NavState.MANUAL_CONTROL and locked_planet != null:
		_manual_panel.visible = true
		var pos: Vector3 = rig._pos
		var d: float = pos.distance_to(locked_planet.global_position) - mm._radius(locked_planet)
		_manual_title.text = "TARGET: %s  [MANUAL CONTROL]" % mm._pname(locked_planet).to_upper()
		_manual_info.text = "Distance %.1f u  •  Speed %.1f u/s\nFly toward planet to arrive." % [
			maxf(d, 0.0), rig._vel.length()]
		if d <= ARRIVE_DIST + 0.5:
			show_arrival_permission(locked_planet)
			return

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

	var v_cmd := CRUISE_SPEED
	if not _has_wp:
		v_cmd = minf(CRUISE_SPEED, sqrt(2.0 * BRAKE_ACCEL * maxf(d_goal - 0.1, 0.0)))
	var a_cmd: Vector3 = (dir * v_cmd - v_rel) / CONTROL_TAU + rig._vel * rig.drag_per_sec
	var a_len := a_cmd.length()

	if not arrived and not _has_wp and d_goal < ARRIVE_DIST and v_rel.length() < ARRIVE_SPEED:
		arrived = true
		show_arrival_permission(target)
		return

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

	var speed := v_rel.length()
	if arrived:
		phase = "STATION-KEEPING"
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


func _update_hover() -> void:
	if _hover_lbl == null:
		return
	_hover_lbl.visible = false
	if active or confirm_open or choice_open or permission_open or mm.vr != null or mm.hold_ship:
		return
	var vp: Viewport = rig.get_viewport()
	var mp := vp.get_mouse_position()
	if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mp):
		return
	var p := pick(mp)
	if p != null:
		_hover_lbl.text = "%s — point/click to select navigation mode" % mm._pname(p)
		_hover_lbl.position = mp + Vector2(18, 18)
		_hover_lbl.visible = true
