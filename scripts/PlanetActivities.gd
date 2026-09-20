extends RefCounted
## The eight planet-specific activities. ShipMissions owns the framework
## (docking, start / complete / abort, score, fuel, log, HUD) and hands control
## to this object while a mission is running:
##
##   begin(body, def)  — set up visuals / initial ship state
##   tick(delta)       — the rules; ends the mission via mm.finish(stats) / mm.fail(reason)
##   action()          — the G / F key or the on-screen action button
##   end(success)      — remove visuals, restore anything that was changed
##
## Every activity shows live scientific readings through mm.set_gauge() and
## mm._m_msg, and needs real piloting: gravity, wind, heat, particles and orbital
## motion all act on the ship's velocity, so the player has to fly.
##
## While a mission runs, ShipMissions pauses planetary motion (orbits + spin) so
## surfaces, storms and rings hold still while the player works.

# ---- Mercury: thermal ----
const TH_HOT := 430.0
const TH_COLD := -180.0
const TH_MAX := 170.0
const TH_MIN := -90.0
const TH_RATE := 22.0          # °C/s hull temperature moves toward the surface temperature
const TH_RANGE := 3.0          # must stay this close to the surface
const TH_NEED := 3             # side crossings

# ---- Venus: descent ----
const VE_GRAVITY := 0.7        # u/s² pull toward the planet
const VE_P0 := 92.0            # bar at the surface
const VE_T0 := 465.0           # °C at the surface
const VE_P_MAX := 85.0
const VE_H_MAX := 360.0
const VE_TAU := 4.0            # s, hull heat lag
const VE_DEEP := 0.9           # altitude below which sampling counts
const VE_GOAL := 5.0

# ---- Earth: orbit ----
const EO_MU := 1.2             # gravitational parameter (u³/s²)
const EO_ALT_CIRC := 1.5       # altitude of the guide ring
const EO_ALT_MIN := 0.9
const EO_ALT_MAX := 2.8
const EO_VR_TOL := 0.45
const EO_V_TOL := 0.30
const EO_STABLE_T := 3.0
const EO_LIMB_TOL := 0.07

# ---- Mars: rover ----
const MR_GRAVITY := 0.35
const MR_LAND_ALT := 0.85
const MR_LAND_ANGLE := 0.5
const MR_LAND_SPEED := 1.2
const MR_SPEED := 0.35         # rad/s across the surface
const MR_TURN := 1.8
const MR_HIT := 0.11           # rad
const MR_SITE_NAME := "Jezero Crater (ancient river delta)"

# ---- Jupiter: Great Red Spot ----
const JU_UV := Vector2(0.369, 0.615)   # spot position in the 2k_jupiter texture
const JU_ZONE := 0.35          # rad, measurement zone around the spot centre
const JU_INFLUENCE := 0.9      # rad, storm wind radius
const JU_WIND_KMH := 430.0
const JU_WIND_ACC := 1.3
const JU_GRAVITY := 0.4
const JU_GOAL := 6.0

# ---- Saturn: rings ----
const SA_GAP_R := 1.85         # Cassini Division radius (world units)
const SA_GAP_HALF := 0.20
const SA_RING_IN := 1.4
const SA_RING_OUT := 2.4
const SA_PARTICLES := 220
const SA_GATE_HIT := 0.5
const SA_SHIP_R := 0.2

# ---- Uranus: tilt ----
const UR_RANGE := 7.0

# ---- Neptune: winds ----
const NE_RADIUS := 1.5
const NE_WMAX := 2100.0
const NE_ACC := 3.0

var mm = null
var rig = null
var body: Node3D = null
var def: Dictionary = {}
var kind: String = ""
var test_drive: Vector2 = Vector2.ZERO      # test hook: x = turn, y = forward
var use_test_drive: bool = false

var _t: float = 0.0
var _visuals: Array[Node] = []

# thermal
var th_temp: float = 20.0
var th_side: int = 0
var th_cross: int = 0
var th_peak: float = 20.0
var th_low: float = 20.0
# descent
var ve_hull: float = 60.0
var ve_sample: float = 0.0
var ve_pmax: float = 0.0
# orbit
var eo_phase: int = 0
var eo_stable: float = 0.0
var eo_seen: Dictionary = {}
var eo_alt: float = 0.0
var eo_img: Image = null
# rover
var mr_phase: int = 0
var mr_site: Vector3 = Vector3.UP
var mr_targets: Array = []
var mr_i: int = 0
var mr_p: Vector3 = Vector3.UP
var mr_h: Vector3 = Vector3.RIGHT
var mr_node: Node3D = null
var mr_battery: float = 100.0
var mr_arrived: bool = false
var mr_scans: int = 0
var mr_base: float = 0.2
var mr_chase_back: float = 0.0
var mr_chase_up: float = 0.0
var mr_site_beacon: MeshInstance3D = null
var mr_site_label: Label3D = null
# jupiter
var ju_local: Vector3 = Vector3.FORWARD
var ju_prog: float = 0.0
var ju_wind: float = 0.0
var ju_peak: float = 0.0
# saturn
var sa_hull: float = 100.0
var sa_cool: float = 0.0
var sa_gates: Array[MeshInstance3D] = []
var sa_gate_i: int = 0
var sa_multi: MultiMesh = null
var sa_theta: PackedFloat32Array = PackedFloat32Array()
var sa_rad: PackedFloat32Array = PackedFloat32Array()
var sa_y: PackedFloat32Array = PackedFloat32Array()
var sa_size: PackedFloat32Array = PackedFloat32Array()
var sa_ref: Basis = Basis.IDENTITY
var sa_hits: int = 0
# uranus
var ur_seen: Dictionary = {}
# neptune
var ne_dir: Vector3 = Vector3.RIGHT
var ne_center: Vector3 = Vector3.ZERO
var ne_control: float = 100.0
var ne_r1: float = 0.0
var ne_r2: float = 0.0
var ne_peak: float = 0.0
var ne_tori: Array[MeshInstance3D] = []


# ---- Helpers ----

func _c() -> Vector3:
	return body.global_position


func _r() -> float:
	return mm._radius(body)


func _alt() -> float:
	var p: Vector3 = rig._pos
	return p.distance_to(_c()) - _r()


func _add_world(n: Node) -> void:
	rig._left_viewport.add_child(n)
	_visuals.append(n)


func _add_body(n: Node) -> void:
	body.add_child(n)
	_visuals.append(n)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _label3d(text: String, pos: Vector3, color: Color = Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.004
	l.font_size = 40
	l.outline_size = 10
	l.modulate = color
	l.position = pos
	return l


func _torus(radius: float, thickness: float, color: Color, alpha: float = 1.0) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius + thickness
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _mat(color, alpha)
	return mi


func _danger(f: float) -> Color:
	return Color(0.35, 0.9, 0.55).lerp(Color(0.95, 0.25, 0.2), clampf(f, 0.0, 1.0))


# UV <-> direction for Godot's SphereMesh (u = longitude around Y from +Z, v = 0 at the north pole).
static func uv_to_dir(u: float, v: float) -> Vector3:
	var a := u * TAU
	var s := sin(v * PI)
	return Vector3(sin(a) * s, cos(v * PI), cos(a) * s)


static func dir_to_uv(d: Vector3) -> Vector2:
	return Vector2(fposmod(atan2(d.x, d.z) / TAU, 1.0), acos(clampf(d.y, -1.0, 1.0)) / PI)


# Spin the (paused) planet about its axis so a surface feature sits above the ship.
func _face_feature(local_dir: Vector3) -> void:
	var s: Vector3 = (rig._pos - _c()).normalized()
	var ls: Vector3 = body.global_basis.orthonormalized().inverse() * s
	var a := Vector3(local_dir.x, 0.0, local_dir.z)
	var b := Vector3(ls.x, 0.0, ls.z)
	if a.length() < 0.001 or b.length() < 0.001:
		return
	body.rotate_object_local(Vector3.UP, a.signed_angle_to(b, Vector3.UP))


# ---- Lifecycle ----

func begin(b: Node3D, d: Dictionary) -> void:
	body = b
	def = d
	kind = String(d.get("kind", ""))
	_t = 0.0
	mm.action_text = ""
	match kind:
		"thermal": _begin_thermal()
		"descent": _begin_descent()
		"orbit": _begin_orbit()
		"rover": _begin_rover()
		"storm": _begin_storm()
		"rings": _begin_rings()
		"tilt": _begin_tilt()
		"winds": _begin_winds()


func tick(delta: float) -> void:
	_t += delta
	match kind:
		"thermal": _tick_thermal(delta)
		"descent": _tick_descent(delta)
		"orbit": _tick_orbit(delta)
		"rover": _tick_rover(delta)
		"storm": _tick_storm(delta)
		"rings": _tick_rings(delta)
		"tilt": _tick_tilt(delta)
		"winds": _tick_winds(delta)


func action() -> void:
	match kind:
		"orbit": _action_orbit()
		"rover": _action_rover()
		"tilt": _action_tilt()
		"winds": _action_winds()


func end(success: bool) -> void:
	mm.action_text = ""
	if kind == "rover" and mr_phase == 1:
		_leave_rover(success)
	for n in _visuals:
		if is_instance_valid(n):
			n.queue_free()
	_visuals.clear()


# =============================================================================
# Mercury — Temperature Survival
# =============================================================================

func _begin_thermal() -> void:
	th_temp = 20.0
	th_peak = 20.0
	th_low = 20.0
	th_side = 0
	th_cross = 0


func _tick_thermal(delta: float) -> void:
	var c := _c()
	var pos: Vector3 = rig._pos
	var to_ship := (pos - c).normalized()
	var to_sun := Vector3.RIGHT
	if rig._sun != null:
		to_sun = (rig._sun.global_position - c).normalized()
	var lit := to_ship.dot(to_sun)
	var surf := lerpf(TH_COLD, TH_HOT, smoothstep(-0.2, 0.2, lit))
	var near := _alt() < TH_RANGE
	if near:
		th_temp = move_toward(th_temp, surf, TH_RATE * delta)
	else:
		th_temp = move_toward(th_temp, 20.0, 3.0 * delta)
	th_peak = maxf(th_peak, th_temp)
	th_low = minf(th_low, th_temp)

	var side := 0
	if lit > 0.35:
		side = 1
	elif lit < -0.35:
		side = -1
	if near and side != 0 and side != th_side:
		if th_side != 0:
			th_cross += 1
			mm._toast("Crossed to the %s side  (%d / %d)" % ["sunlit" if side > 0 else "night", th_cross, TH_NEED])
		th_side = side

	if th_temp >= TH_MAX:
		mm.fail("hull overheated (%d °C)" % int(th_temp))
		return
	if th_temp <= TH_MIN:
		mm.fail("hull froze (%d °C)" % int(th_temp))
		return
	if th_cross >= TH_NEED:
		mm.finish("Crossed day and night %d times. Hull temperature ranged %+d to %+d °C." % [
			TH_NEED, int(th_low), int(th_peak)])
		return

	var frac := inverse_lerp(TH_MIN, TH_MAX, th_temp)
	mm.set_gauge(0, "SHIP TEMP  %+d °C   (limits %d … %+d)" % [int(th_temp), int(TH_MIN), int(TH_MAX)],
		frac, _danger(absf(frac - 0.5) * 2.0 * 1.15 - 0.15))
	mm.set_gauge(1, "SIDE CROSSINGS  %d / %d" % [th_cross, TH_NEED], float(th_cross) / TH_NEED, Color(0.4, 0.75, 1.0))
	var where := "twilight zone"
	if lit > 0.35:
		where = "SUNLIT"
	elif lit < -0.35:
		where = "NIGHT"
	var hint := "" if near else "\nToo far: stay within %.0f u of the surface" % TH_RANGE
	mm._m_msg = "Surface below: %+d °C (%s)\nNo atmosphere, so heat is not carried away; day and night differ by ~610 °C.%s" % [
		int(surf), where, hint]


# =============================================================================
# Venus — Pressure & Heat Descent
# =============================================================================

func _begin_descent() -> void:
	ve_hull = 60.0
	ve_sample = 0.0
	ve_pmax = 0.0


func _tick_descent(delta: float) -> void:
	var c := _c()
	var pos: Vector3 = rig._pos
	var n := (pos - c).normalized()
	var alt := _alt()
	# Venus gravity (0.9 g) drags the ship down: thrust away from the planet to climb.
	rig._vel -= n * VE_GRAVITY * delta
	var amb_p := VE_P0 * exp(-(alt - 0.5) * 1.6)
	var amb_t := VE_T0 * exp(-(alt - 0.5) * 1.4)
	ve_hull += (amb_t - ve_hull) * minf(1.0, delta / VE_TAU)
	ve_pmax = maxf(ve_pmax, amb_p)
	var deep := alt <= VE_DEEP
	if deep:
		ve_sample += delta

	if amb_p >= VE_P_MAX:
		mm.fail("crushed by %d bar of pressure" % int(amb_p))
		return
	if ve_hull >= VE_H_MAX:
		mm.fail("hull melted at %d °C" % int(ve_hull))
		return
	if ve_sample >= VE_GOAL:
		mm.finish("Sampled at %.2f u altitude. Peak pressure %d bar; ambient up to %d °C." % [
			VE_DEEP, int(ve_pmax), int(amb_t)])
		return

	mm.set_gauge(0, "PRESSURE  %d bar   (limit %d)" % [int(amb_p), int(VE_P_MAX)], amb_p / VE_P_MAX, _danger(amb_p / VE_P_MAX - 0.4))
	mm.set_gauge(1, "HULL  %d °C   (limit %d)" % [int(ve_hull), int(VE_H_MAX)], ve_hull / VE_H_MAX, _danger(ve_hull / VE_H_MAX - 0.4))
	mm.set_gauge(2, "SAMPLING  %.1f / %.0f s" % [ve_sample, VE_GOAL], ve_sample / VE_GOAL, Color(0.4, 0.75, 1.0))
	var status := "SAMPLING" if deep else "descend below %.1f u to sample" % VE_DEEP
	if amb_p > 70.0 or ve_hull > 320.0:
		status = "⚠ PULL UP!  (thrust away from the planet)"
	mm._m_msg = "Altitude %.2f u  •  ambient %d °C, %d bar\n%s\nGravity is pulling you in. Surface: 92 bar, 465 °C." % [alt, int(amb_t), int(amb_p), status]


# =============================================================================
# Earth — Atmosphere & Satellite
# =============================================================================

func _begin_orbit() -> void:
	eo_phase = 0
	eo_stable = 0.0
	eo_seen = {}
	var c := _c()
	var pos: Vector3 = rig._pos
	var radial := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	if radial.length() < 0.01:
		radial = Vector3.RIGHT
	radial = radial.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	# Start in the guide ring's plane, low and a little too slow: the player has to
	# speed up (prograde burn) to reach a stable circular orbit.
	rig._pos = c + radial * (_r() + 1.1)
	rig._vel = tangent * 0.72
	rig._ship_yaw = atan2(-tangent.x, -tangent.z)
	rig._ship_pitch = 0.0
	var ring := _torus(_r() + EO_ALT_CIRC, 0.012, Color(0.3, 0.9, 1.0), 0.7)
	_add_world(ring)
	ring.global_position = c
	# Earth's photo texture is sampled to tell ocean from land under the ship.
	eo_img = null
	var path := String(body.get_meta("data", {}).get("texture", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			eo_img = tex.get_image()
			if eo_img != null and eo_img.is_compressed():
				eo_img.decompress()


# "OCEAN", "LAND" or "ICE" directly beneath the ship.
func _nadir_class() -> String:
	var pos: Vector3 = rig._pos
	var local: Vector3 = body.global_basis.orthonormalized().inverse() * (pos - _c()).normalized()
	if eo_img == null:
		return "OCEAN" if int(_t * 0.4) % 2 == 0 else "LAND"
	var uv := dir_to_uv(local)
	var px := eo_img.get_pixel(clampi(int(uv.x * eo_img.get_width()), 0, eo_img.get_width() - 1),
		clampi(int(uv.y * eo_img.get_height()), 0, eo_img.get_height() - 1))
	if px.r > 0.8 and px.g > 0.8 and px.b > 0.8:
		return "ICE"
	if px.b > px.r + 0.05 and px.b >= px.g - 0.02:
		return "OCEAN"
	return "LAND"


func _limb_aimed() -> bool:
	var cam: Camera3D = rig._left_cam
	var to_c := _c() - cam.global_position
	var dist := to_c.length()
	if dist <= _r() * 1.2:
		return false
	var a := (-cam.global_transform.basis.z).angle_to(to_c)
	return absf(a - asin(clampf(_r() / dist, 0.0, 1.0))) < EO_LIMB_TOL


func _tick_orbit(delta: float) -> void:
	var c := _c()
	var pos: Vector3 = rig._pos
	var rel := pos - c
	var dist := maxf(rel.length(), 0.05)
	var n := rel / dist
	# Orbital dynamics: gravity toward Earth, and no air drag in vacuum.
	rig._vel -= n * (EO_MU / maxf(dist * dist, 0.09)) * delta
	rig._vel += rig._vel * rig.drag_per_sec * delta
	var v: Vector3 = rig._vel
	var vr := v.dot(n)
	var vt := (v - n * vr).length()
	var vc := sqrt(EO_MU / dist)
	eo_alt = dist - _r()
	var stable := eo_alt >= EO_ALT_MIN and eo_alt <= EO_ALT_MAX and absf(vr) < EO_VR_TOL and absf(vt - vc) < EO_V_TOL * vc

	if eo_phase == 0:
		if stable:
			eo_stable = minf(EO_STABLE_T + 1.0, eo_stable + delta)
		else:
			eo_stable = maxf(0.0, eo_stable - delta * 2.0)
		mm.action_text = "🛰 DEPLOY SATELLITE [G]" if eo_stable >= EO_STABLE_T else ""
		mm.set_gauge(0, "ORBIT STABILITY  %.1f / %.0f s" % [minf(eo_stable, EO_STABLE_T), EO_STABLE_T],
			eo_stable / EO_STABLE_T, Color(0.4, 0.9, 0.6) if stable else Color(0.95, 0.6, 0.25))
		mm.set_gauge(1, "SPEED  %.2f u/s   (circular orbit here: %.2f)" % [vt, vc], clampf(vt / (vc * 2.0), 0.0, 1.0),
			Color(0.4, 0.75, 1.0))
		var advice := "Match the ring: altitude %.1f–%.1f u, moving sideways at ≈ %.2f u/s" % [EO_ALT_MIN, EO_ALT_MAX, vc]
		if eo_stable >= EO_STABLE_T:
			advice = "STABLE ORBIT — press G to deploy the satellite"
		elif vt < vc * (1.0 - EO_V_TOL):
			advice = "Too slow — you will fall. Thrust along your direction of travel (prograde)."
		elif vt > vc * (1.0 + EO_V_TOL):
			advice = "Too fast — the orbit stretches outward. Ease off."
		mm._m_msg = "Altitude %.2f u  •  radial speed %+.2f\n%s" % [eo_alt, vr, advice]
	else:
		var nadir := _nadir_class()
		var count := eo_seen.size()
		mm.action_text = "📡 OBSERVE [G]"
		mm.set_gauge(0, "OBSERVATIONS  %d / 3" % count, count / 3.0, Color(0.4, 0.75, 1.0))
		var have := ""
		for k in ["atmosphere", "ocean", "continent"]:
			have += ("✔ " if eo_seen.has(k) else "○ ") + k + "   "
		mm._m_msg = "Satellite deployed. Observe from orbit with G:\n%s\nBelow you: %s  •  Limb aim: %s" % [
			have, nadir, "ON THE EDGE" if _limb_aimed() else "aim at the planet's edge for the atmosphere"]
		if count >= 3:
			mm.finish("Stable orbit at %.1f u altitude; satellite deployed; atmosphere, ocean and continent observed." % eo_alt)


func _action_orbit() -> void:
	if eo_phase == 0:
		if eo_stable >= EO_STABLE_T:
			mm._spawn_probe(body, "satellite")
			eo_phase = 1
			mm._toast("Satellite deployed into orbit")
			mm._flash.color.a = 0.5
		else:
			mm._toast("Orbit not stable yet")
		return
	if not eo_seen.has("atmosphere") and _limb_aimed():
		eo_seen["atmosphere"] = true
		mm._toast("ATMOSPHERE: a thin blue layer, ~78% nitrogen, 21% oxygen")
	else:
		var nadir := _nadir_class()
		if nadir == "OCEAN" and not eo_seen.has("ocean"):
			eo_seen["ocean"] = true
			mm._toast("OCEAN: water covers about 71% of Earth's surface")
		elif nadir == "LAND" and not eo_seen.has("continent"):
			eo_seen["continent"] = true
			mm._toast("CONTINENT: land, ~29% of the surface, visible as brown and green")
		else:
			mm._toast("Nothing new here. Fly over %s or aim at the limb." % ("land" if nadir == "OCEAN" else "ocean"))
			return
	mm._flash.color.a = 0.5


# =============================================================================
# Mars — Rover Exploration
# =============================================================================

func _begin_rover() -> void:
	mr_phase = 0
	mr_i = 0
	mr_scans = 0
	mr_arrived = false
	mr_battery = 100.0
	mr_base = float(body.get_meta("data", {}).get("radius", 0.2))
	var lat := deg_to_rad(18.0)
	var lon := 0.9
	mr_site = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()
	_face_feature(mr_site)
	mr_site_beacon = _beacon(mr_site, 0.45, Color(1.0, 0.6, 0.2))
	_add_body(mr_site_beacon)
	mr_site_label = _label3d("LANDING SITE\n" + MR_SITE_NAME, mr_site * (mr_base + 0.6), Color(1.0, 0.8, 0.5))
	_add_body(mr_site_label)


# A thin vertical beacon standing on the surface at a local direction.
func _beacon(local_dir: Vector3, height: float, color: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0025
	cyl.bottom_radius = 0.0025
	cyl.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _mat(color, 0.9)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, local_dir)), local_dir * (mr_base + height * 0.5))
	return mi


func _tick_rover(delta: float) -> void:
	if mr_phase == 0:
		_tick_landing(delta)
	else:
		_tick_driving(delta)


func _tick_landing(delta: float) -> void:
	var c := _c()
	var pos: Vector3 = rig._pos
	var n := (pos - c).normalized()
	rig._vel -= n * MR_GRAVITY * delta     # Mars: 0.38 g
	var site_w := (body.global_basis * mr_site).normalized()
	var ang := n.angle_to(site_w)
	var alt := _alt()
	var speed: float = (rig._vel as Vector3).length()

	if alt < 0.68 and speed > 1.8:
		mm.fail("hard landing at %.1f u/s" % speed)
		return
	if alt <= MR_LAND_ALT and ang < MR_LAND_ANGLE and speed < MR_LAND_SPEED:
		_start_rover()
		return
	mm.set_gauge(0, "DESCENT SPEED  %.1f u/s   (touchdown < %.1f)" % [speed, MR_LAND_SPEED], speed / 2.0, _danger(speed / 1.8 - 0.4))
	mm.set_gauge(1, "SITE OFFSET  %d°   (need < %d°)" % [int(rad_to_deg(ang)), int(rad_to_deg(MR_LAND_ANGLE))],
		1.0 - clampf(ang / 1.5, 0.0, 1.0), Color(1.0, 0.7, 0.3))
	var hint := "Fly over the orange beacon, then descend below %.2f u altitude, slowly." % MR_LAND_ALT
	if alt < 0.68 and ang >= MR_LAND_ANGLE:
		hint = "Off target: move over the landing site."
	mm._m_msg = "Altitude %.2f u  •  gravity 0.38 g  •  thin CO₂ air\n%s" % [alt, hint]


func _start_rover() -> void:
	mr_phase = 1
	mm.rover_hold = true
	rig._vel = Vector3.ZERO
	rig._ship_root.visible = false
	mr_chase_back = rig.chase_back
	mr_chase_up = rig.chase_up
	rig.chase_back = 0.0
	rig.chase_up = 0.0
	# Rover camera: close, behind the rover.
	var east := Vector3.UP.cross(mr_site).normalized()
	var north := mr_site.cross(east)
	mr_p = mr_site
	mr_h = north
	# Targets in driving order, laid out around the landing site.
	var specs := [
		[0.5, 0.3, "Dust plain", "Fine iron-oxide dust: this is what makes Mars red. Global dust storms can cover the planet."],
		[0.55, 2.4, "Ancient riverbed", "Rounded pebbles and clay minerals: liquid water once flowed here."],
		[0.6, 4.1, "Volcanic rock", "Basalt from volcanic eruptions. Mars has Olympus Mons, the tallest volcano known."],
		[0.5, 5.6, "Sample site", "A rock core is collected and sealed. It could be returned to Earth for study."],
	]
	mr_targets.clear()
	for sp in specs:
		var a: float = sp[0]
		var bearing: float = sp[1]
		var dir := (mr_site * cos(a) + (east * cos(bearing) + north * sin(bearing)) * sin(a)).normalized()
		var beacon := _beacon(dir, 0.05, Color(0.5, 0.5, 0.55))
		_add_body(beacon)
		mr_targets.append({"dir": dir, "name": sp[2], "fact": sp[3], "beacon": beacon})
	_refresh_beacons()
	# The rover itself.
	mr_node = Node3D.new()
	var chassis := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.036, 0.012, 0.054)
	chassis.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.92)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.5, 0.55)
	chassis.material_override = m
	mr_node.add_child(chassis)
	var mast := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(0.005, 0.028, 0.005)
	mast.mesh = mbox
	mast.position = Vector3(0.0, 0.02, -0.012)
	mast.material_override = _mat(Color(1.0, 0.9, 0.3))
	mr_node.add_child(mast)
	_add_body(mr_node)
	_place_rover()
	_set_planet_labels(false)
	mr_site_beacon.visible = false
	mr_site_label.visible = false
	mm.show_controls(true)
	mm._toast("TOUCHDOWN! Drive the rover: W/S drive, A/D turn (or the on-screen buttons)")


func _refresh_beacons() -> void:
	for i in mr_targets.size():
		var bm := mr_targets[i]["beacon"] as MeshInstance3D
		if is_instance_valid(bm):
			bm.visible = i >= mr_i
			bm.material_override = _mat(Color(1.0, 0.85, 0.2) if i == mr_i else Color(0.5, 0.5, 0.6), 0.95)


func _place_rover() -> void:
	var up := mr_p
	var fwd := mr_h
	var right := fwd.cross(up).normalized()
	mr_node.transform = Transform3D(Basis(right, up, -fwd), mr_p * (mr_base + 0.008))


func _drive_input() -> Vector2:
	if use_test_drive:
		return test_drive
	var f := 0.0
	var t := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or mm.ctl_fwd or rig._thrusting:
		f += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		f -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) or mm.ctl_left:
		t += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) or mm.ctl_right:
		t -= 1.0
	t -= mm.vr_drive.x
	f += mm.vr_drive.y
	if rig.mouse_flight and not OS.has_feature("mobile"):
		var vp: Viewport = rig.get_viewport()
		var half := vp.get_visible_rect().size * 0.5
		var mp := vp.get_mouse_position()
		if half.x > 0.0 and Rect2(Vector2.ZERO, half * 2.0).has_point(mp):
			t -= rig._mouse_axis((mp.x - half.x) / half.x)
	return Vector2(clampf(t, -1.0, 1.0), f)


func _tick_driving(delta: float) -> void:
	var inp := _drive_input()
	var moving := absf(inp.y) > 0.01 and mr_battery > 0.0
	if moving:
		var axis := mr_p.cross(mr_h).normalized()
		var q := Quaternion(axis, inp.y * MR_SPEED * delta)
		mr_p = (q * mr_p).normalized()
		mr_h = q * mr_h
		mr_h = (mr_h - mr_p * mr_h.dot(mr_p)).normalized()
		mr_battery = maxf(0.0, mr_battery - 3.5 * delta)
	else:
		mr_battery = minf(100.0, mr_battery + 2.0 * delta)
	if absf(inp.x) > 0.01:
		mr_h = (Basis(mr_p, inp.x * MR_TURN * delta) * mr_h).normalized()
	_place_rover()
	_update_rover_camera()

	var tgt: Dictionary = mr_targets[mr_i]
	var tdir: Vector3 = tgt["dir"]
	var dist_rad := mr_p.angle_to(tdir)
	mr_arrived = dist_rad < MR_HIT
	var last := mr_i == mr_targets.size() - 1
	mm.action_text = ("⛏ COLLECT SAMPLE [G]" if last else "🔬 SCAN ROCK [G]") if mr_arrived else ""
	mm.set_gauge(0, "BATTERY  %d%%   (drains while driving, recharges parked)" % int(mr_battery), mr_battery / 100.0,
		_danger(1.0 - mr_battery / 100.0 - 0.3))
	mm.set_gauge(1, "TARGET %d / %d: %s   %d m" % [mr_i + 1, mr_targets.size(), tgt["name"], int(dist_rad * 3390.0 * 0.05)],
		1.0 - clampf(dist_rad / 1.2, 0.0, 1.0), Color(1.0, 0.8, 0.3))
	mm.set_gauge(2, "SAMPLES  %d scanned" % mr_scans, mr_scans / 3.0, Color(0.4, 0.75, 1.0))
	var hint := "Drive to the yellow beacon." if not mr_arrived else "In range! Press G."
	mm._m_msg = "Rover on Mars  •  gravity 0.38 g  •  −60 °C\n%s" % hint


func _rover_world() -> Vector3:
	return body.to_global(mr_p * (mr_base + 0.008))


func _update_rover_camera() -> void:
	var here := body.to_global(mr_p * mr_base)
	var up_w := (body.to_global(mr_p * (mr_base + 1.0)) - here).normalized()
	var fwd_w := (body.to_global(mr_p * mr_base + mr_h * 0.1) - here).normalized()
	var rw := _rover_world()
	var cam_pos := rw + up_w * 0.22 - fwd_w * 0.30
	var d := (rw + fwd_w * 0.10 - cam_pos).normalized()
	rig._pos = cam_pos
	rig._vel = Vector3.ZERO
	rig._ship_yaw = atan2(-d.x, -d.z)
	rig._ship_pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -1.4, 1.4)


func _action_rover() -> void:
	if mr_phase != 1 or not mr_arrived:
		return
	var tgt: Dictionary = mr_targets[mr_i]
	var last := mr_i == mr_targets.size() - 1
	if last:
		mm._toast("SAMPLE COLLECTED: " + String(tgt["fact"]))
	else:
		mr_scans += 1
		mm._toast("%s: %s" % [String(tgt["name"]).to_upper(), String(tgt["fact"])])
	mm._flash.color.a = 0.6
	mr_i += 1
	if mr_i >= mr_targets.size():
		mm.finish("Landed at %s, scanned %d rock sites and collected 1 sample with the rover." % [MR_SITE_NAME, mr_scans])
	else:
		_refresh_beacons()


# Return the ship to normal flight above the rover.
func _leave_rover(success: bool) -> void:
	var rw := _rover_world()
	var up_w := (rw - _c()).normalized()
	rig.chase_back = mr_chase_back
	rig.chase_up = mr_chase_up
	rig._ship_root.visible = true
	_set_planet_labels(true)
	mm.rover_hold = false
	mm.show_controls(false)
	rig._pos = rw + up_w * 0.9
	rig._vel = Vector3.ZERO
	rig._ship_yaw = atan2(-up_w.x, -up_w.z)
	rig._ship_pitch = 0.0
	if success and mr_node != null:
		# Leave the rover parked on the surface as a permanent marker.
		_visuals.erase(mr_node)
		mm._deployed.append({"node": mr_node, "kind": "rover", "rate": 0.0})
		mm.register_gaze_object(mr_node, 0.3, "Mars rover", "A rover like Perseverance drives across Mars, scans rocks and caches samples that may hold signs of ancient life.")


# =============================================================================
# Jupiter — Great Red Spot
# =============================================================================

func _begin_storm() -> void:
	ju_prog = 0.0
	ju_wind = 0.0
	ju_peak = 0.0
	ju_local = uv_to_dir(JU_UV.x, JU_UV.y)
	_face_feature(ju_local)
	mr_base = float(body.get_meta("data", {}).get("radius", 0.9))
	var ring := _torus(mr_base * sin(JU_ZONE), 0.012, Color(1.0, 0.45, 0.3), 0.85)
	ring.transform = Transform3D(Basis(Quaternion(Vector3.UP, ju_local)), ju_local * (mr_base + 0.02))
	_add_body(ring)
	_add_body(_label3d("GREAT RED SPOT", ju_local * (mr_base + 0.7), Color(1.0, 0.6, 0.45)))


func _tick_storm(delta: float) -> void:
	var c := _c()
	var pos: Vector3 = rig._pos
	var rel := pos - c
	var n := rel.normalized()
	var alt := _alt()
	var nw := (body.global_basis * ju_local).normalized()
	var theta := n.angle_to(nw)
	# Wind profile: calm eye, fastest at the rim, fading outward.
	var x := clampf(theta / JU_INFLUENCE, 0.0, 1.0)
	var prof := 4.0 * x * (1.0 - x)
	var gust := 0.8 + 0.2 * sin(_t * 2.1) + 0.1 * sin(_t * 5.3 + 1.0)
	ju_wind = JU_WIND_KMH * prof * gust
	ju_peak = maxf(ju_peak, ju_wind)
	mm.rumble_extra = maxf(mm.rumble_extra, clampf(ju_wind / JU_WIND_KMH, 0.0, 1.0) * 0.6)
	var lateral := rel - nw * rel.dot(nw)
	if lateral.length() > 0.001:
		# Anticyclonic swirl around the spot, plus Jupiter's strong gravity (2.5 g).
		rig._vel += nw.cross(lateral).normalized() * JU_WIND_ACC * prof * gust * delta
	rig._vel -= n * JU_GRAVITY * delta

	var in_zone := theta < JU_ZONE and alt >= 0.6 and alt <= 1.9
	if in_zone:
		ju_prog += delta
	else:
		ju_prog = maxf(0.0, ju_prog - delta * 0.5)
	if ju_prog >= JU_GOAL:
		mm.finish("Held station in the Great Red Spot for %.0f s. Peak wind measured %d km/h." % [JU_GOAL, int(ju_peak)])
		return

	mm.set_gauge(0, "WIND  %d km/h" % int(ju_wind), ju_wind / JU_WIND_KMH, _danger(ju_wind / JU_WIND_KMH - 0.3))
	mm.set_gauge(1, "MEASUREMENT  %.1f / %.0f s" % [ju_prog, JU_GOAL], ju_prog / JU_GOAL, Color(1.0, 0.55, 0.35) if in_zone else Color(0.5, 0.55, 0.65))
	var hint := "Inside the zone: hold station against the wind!"
	if not in_zone:
		hint = "Fly to the orange ring over the red spot (altitude 0.6–1.9 u)."
	mm._m_msg = "Off-centre %d°  •  altitude %.2f u\n%s\nThe spot is ~1.3× Earth wide. Rim winds ~430 km/h, calm eye." % [
		int(rad_to_deg(theta)), alt, hint]


# =============================================================================
# Saturn — Ring Navigation
# =============================================================================

func _begin_rings() -> void:
	sa_hull = 100.0
	sa_cool = 0.0
	sa_gate_i = 0
	sa_hits = 0
	sa_ref = mm._ref_basis(body)
	var s := body.scale.x
	# Checkpoints along the Cassini Division.
	sa_gates.clear()
	for i in 3:
		var g := _torus(0.5, 0.05, Color(0.3, 1.0, 0.6))
		_add_world(g)
		sa_gates.append(g)
	_position_gates()
	# Ring particles: none inside the gap.
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	sa_multi = MultiMesh.new()
	sa_multi.transform_format = MultiMesh.TRANSFORM_3D
	sa_multi.mesh = mesh
	sa_multi.instance_count = SA_PARTICLES
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = sa_multi
	mmi.material_override = _mat(Color(0.72, 0.75, 0.84))
	_add_world(mmi)
	sa_theta.resize(SA_PARTICLES)
	sa_rad.resize(SA_PARTICLES)
	sa_y.resize(SA_PARTICLES)
	sa_size.resize(SA_PARTICLES)
	for i in SA_PARTICLES:
		var r := randf_range(SA_RING_IN, SA_RING_OUT) * s
		while absf(r / s - SA_GAP_R) < SA_GAP_HALF + 0.03:
			r = randf_range(SA_RING_IN, SA_RING_OUT) * s
		sa_rad[i] = r
		sa_theta[i] = randf() * TAU
		sa_y[i] = randf_range(-0.04, 0.04)
		sa_size[i] = randf_range(0.035, 0.09)
	_update_particles(0.0)


func _gate_point(i: int) -> Vector3:
	var a := (float(i) / 3.0) * TAU
	return _c() + sa_ref * (Vector3(cos(a), 0.0, sin(a)) * SA_GAP_R * body.scale.x)


func _position_gates() -> void:
	var s := body.scale.x
	for i in sa_gates.size():
		var a := (float(i) / 3.0) * TAU
		var radial := sa_ref * Vector3(cos(a), 0.0, sin(a))
		var tangent := sa_ref * Vector3(-sin(a), 0.0, cos(a))
		var g := sa_gates[i]
		g.global_transform = Transform3D(Basis(radial, tangent, radial.cross(tangent)), _c() + radial * SA_GAP_R * s)
		var col := Color(0.3, 1.0, 0.6) if i == sa_gate_i else Color(0.35, 0.4, 0.55)
		g.material_override = _mat(col)
		g.visible = i >= sa_gate_i


func _particle_world(i: int) -> Vector3:
	return _c() + sa_ref * Vector3(cos(sa_theta[i]) * sa_rad[i], sa_y[i], sin(sa_theta[i]) * sa_rad[i])


# Kepler-like: inner particles orbit faster than outer ones.
func _update_particles(delta: float) -> void:
	for i in SA_PARTICLES:
		var r := sa_rad[i] / body.scale.x
		sa_theta[i] += 0.35 * pow(SA_GAP_R / r, 1.5) * delta
		var basis := Basis().scaled(Vector3.ONE * sa_size[i])
		sa_multi.set_instance_transform(i, Transform3D(basis, _particle_world(i)))


func _tick_rings(delta: float) -> void:
	_update_particles(delta)
	_position_gates()
	sa_cool = maxf(0.0, sa_cool - delta)
	var pos: Vector3 = rig._pos
	var loc: Vector3 = sa_ref.inverse() * (pos - _c())
	var r_xz := Vector2(loc.x, loc.z).length() / body.scale.x

	# Particle strikes: only possible in the ring sheet.
	if absf(loc.y) < 0.35 and r_xz > SA_RING_IN - 0.2 and r_xz < SA_RING_OUT + 0.3:
		for i in SA_PARTICLES:
			var pp := _particle_world(i)
			if pos.distance_to(pp) < SA_SHIP_R + sa_size[i] * 0.5 and sa_cool <= 0.0:
				sa_hull -= 8.0
				sa_hits += 1
				sa_cool = 0.35
				rig._vel += (pos - pp).normalized() * 0.6
				mm._toast("Particle strike!  Hull %d%%" % int(maxf(sa_hull, 0.0)))
				mm._flash.color.a = 0.3
				break
	if sa_hull <= 0.0:
		mm.fail("hull breached by ring particles")
		return

	var g := sa_gates[sa_gate_i]
	var d := pos.distance_to(g.global_position)
	if d < SA_GATE_HIT:
		sa_gate_i += 1
		mm._toast("Checkpoint %d / 3 through the Cassini Division" % sa_gate_i)
		if sa_gate_i >= sa_gates.size():
			mm.finish("Flew the Cassini Division through 3 checkpoints with %d%% hull left; %d particle strikes." % [
				int(sa_hull), sa_hits])
			return
		d = pos.distance_to(sa_gates[sa_gate_i].global_position)

	var off := absf(r_xz - SA_GAP_R)
	mm.set_gauge(0, "HULL INTEGRITY  %d%%" % int(sa_hull), sa_hull / 100.0, _danger(1.0 - sa_hull / 100.0))
	mm.set_gauge(1, "CHECKPOINTS  %d / 3" % sa_gate_i, sa_gate_i / 3.0, Color(0.4, 0.75, 1.0))
	mm.set_gauge(2, "GAP ALIGNMENT  ±%.2f u   (gap half-width %.2f)" % [off, SA_GAP_HALF],
		1.0 - clampf(off / 0.6, 0.0, 1.0), _danger(off / 0.4 - 0.5))
	var hint := "Fly into the ring plane at the green ring." if absf(loc.y) > 0.5 else "In the ring plane: stay in the gap, between the dense bands."
	mm._m_msg = "Next checkpoint %.1f u  •  ring radius %.2f u\n%s\nParticles: dust to house-sized ice chunks, ~10 m thick sheet." % [d, r_xz, hint]


# =============================================================================
# Uranus — Axial Tilt
# =============================================================================

func _begin_tilt() -> void:
	ur_seen = {}
	var r_local := float(body.get_meta("data", {}).get("radius", 0.5))
	var length := r_local + 3.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = length * 2.0
	var axis := MeshInstance3D.new()
	axis.mesh = cyl
	axis.material_override = _mat(Color(0.3, 0.9, 1.0), 0.8)
	_add_body(axis)
	_add_body(_label3d("N", Vector3(0.0, length + 0.15, 0.0), Color(0.5, 1.0, 1.0)))
	_add_body(_label3d("S", Vector3(0.0, -length - 0.15, 0.0), Color(0.5, 1.0, 1.0)))
	var eq := _torus(r_local * 1.7, 0.008, Color(0.3, 0.9, 1.0), 0.5)
	_add_body(eq)


func _axis_world() -> Vector3:
	return (body.global_basis * Vector3.UP).normalized()


func _view_angle_deg() -> float:
	var pos: Vector3 = rig._pos
	return rad_to_deg(acos(clampf(((pos - _c()).normalized()).dot(_axis_world()), -1.0, 1.0)))


func _tick_tilt(_delta: float) -> void:
	var ang := _view_angle_deg()
	var sun_dot := 0.0
	if rig._sun != null:
		sun_dot = _axis_world().dot((rig._sun.global_position - _c()).normalized())
	var season := "The Sun is near the equator: an equinox-like season"
	if sun_dot > 0.55:
		season = "North pole faces the Sun: northern summer, ~42 years of daylight"
	elif sun_dot < -0.55:
		season = "South pole faces the Sun: southern summer, ~42 years of daylight"
	var zone := "between views"
	if ang < 25.0:
		zone = "NORTH POLE view"
	elif absf(ang - 90.0) < 15.0:
		zone = "EQUATOR view"
	elif ang > 155.0:
		zone = "SOUTH POLE view"
	var count := ur_seen.size()
	mm.action_text = "📷 SCAN [G]"
	mm.set_gauge(0, "VIEW ANGLE FROM SPIN AXIS  %d°   (0° N pole, 90° equator, 180° S pole)" % int(ang), ang / 180.0, Color(0.4, 0.85, 1.0))
	mm.set_gauge(1, "SCANS  %d / 3" % count, count / 3.0, Color(0.4, 0.75, 1.0))
	var have := ""
	for k in ["north", "equator", "south"]:
		have += ("✔ " if ur_seen.has(k) else "○ ") + k + "   "
	mm._m_msg = "%s  •  axial tilt 97.8°\n%s\n%s" % [zone, have, season]


func _action_tilt() -> void:
	var pos: Vector3 = rig._pos
	var cam: Camera3D = rig._left_cam
	var to_c := _c() - cam.global_position
	if pos.distance_to(_c()) - _r() > UR_RANGE:
		mm._toast("Too far. Get within %.0f u" % UR_RANGE)
		return
	if (-cam.global_transform.basis.z).angle_to(to_c) > 0.28:
		mm._toast("Aim the camera at the planet first")
		return
	var ang := _view_angle_deg()
	var key := ""
	if ang < 25.0:
		key = "north"
	elif absf(ang - 90.0) < 15.0:
		key = "equator"
	elif ang > 155.0:
		key = "south"
	if key.is_empty():
		mm._toast("Line up with the spin axis (N/S poles) or the equator, then scan")
		return
	if ur_seen.has(key):
		mm._toast("Already scanned the %s. Try another angle." % key)
		return
	ur_seen[key] = true
	mm._flash.color.a = 0.7
	mm._toast("%s scan captured  (%d / 3)" % [key.to_upper(), ur_seen.size()])
	if ur_seen.size() >= 3:
		mm.finish("Scanned both poles and the equator of a planet tilted 97.8°, orbiting on its side.")


# =============================================================================
# Neptune — Extreme Winds
# =============================================================================

func _begin_winds() -> void:
	ne_control = 100.0
	ne_r1 = 0.0
	ne_r2 = 0.0
	ne_peak = 0.0
	var c := _c()
	var pos: Vector3 = rig._pos
	var h := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	if h.length() < 0.01:
		h = Vector3.RIGHT
	ne_dir = ((Basis(Vector3.UP, 1.6) * h.normalized()) + Vector3(0.0, 0.2, 0.0)).normalized()
	ne_center = c + ne_dir * (_r() + 1.7)
	var shell := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = NE_RADIUS
	sph.height = NE_RADIUS * 2.0
	shell.mesh = sph
	shell.material_override = _mat(Color(0.35, 0.5, 1.0), 0.16)
	_add_world(shell)
	shell.global_position = ne_center
	ne_tori.clear()
	for i in 3:
		var t := _torus(NE_RADIUS * (0.35 + 0.25 * i), 0.02, Color(0.6, 0.75, 1.0), 0.6)
		_add_world(t)
		t.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, ne_dir)), ne_center + ne_dir * (0.25 * (i - 1)))
		ne_tori.append(t)
	var lbl := _label3d("STORM", ne_center + Vector3(0.0, NE_RADIUS + 0.3, 0.0), Color(0.7, 0.85, 1.0))
	_add_world(lbl)


func _wind_at(pos: Vector3) -> float:
	var x := pos.distance_to(ne_center) / NE_RADIUS
	if x >= 1.0:
		return 0.0
	return NE_WMAX * pow(1.0 - x, 1.2)


func _tick_winds(delta: float) -> void:
	for i in ne_tori.size():
		var t := ne_tori[i]
		t.rotate_object_local(Vector3.UP, (1.5 + i) * delta)
	var pos: Vector3 = rig._pos
	var d := pos.distance_to(ne_center)
	var x := d / NE_RADIUS
	var wind := _wind_at(pos)
	var wf := wind / NE_WMAX
	ne_peak = maxf(ne_peak, wind)
	mm.rumble_extra = maxf(mm.rumble_extra, wf)
	if x < 1.0:
		var gust := 0.85 + 0.15 * sin(_t * 3.1) + 0.1 * sin(_t * 7.7 + 0.5)
		var lat := pos - ne_center
		var swirl := ne_dir.cross(lat)
		if swirl.length() < 0.001:
			swirl = Vector3.RIGHT
		var noise := Vector3(sin(_t * 4.1 + 1.0), sin(_t * 5.3 + 2.0), sin(_t * 3.7 + 3.0)) * 0.5
		rig._vel += (swirl.normalized() + noise).normalized() * NE_ACC * wf * gust * delta
		# Violent gusts shake the hull off heading.
		rig._ship_yaw += sin(_t * 6.2) * 2.4 * wf * delta
		rig._ship_pitch = clampf(rig._ship_pitch + sin(_t * 5.1 + 1.0) * 1.8 * wf * delta, -1.4, 1.4)
		ne_control = maxf(0.0, ne_control - pow(wf, 1.5) * 45.0 * delta)
	else:
		ne_control = minf(100.0, ne_control + 12.0 * delta)
	if ne_control <= 0.0:
		mm.fail("lost control in %d km/h winds" % int(wind))
		return
	var both := ne_r1 > 0.0 and ne_r2 > 0.0
	if both and x > 1.1:
		mm.finish("Logged shear-layer %d km/h and core %d km/h winds, then escaped with %d%% control." % [
			int(ne_r1), int(ne_r2), int(ne_control)])
		return
	mm.action_text = "🌀 MEASURE WIND [G]" if x < 1.0 else ""
	mm.set_gauge(0, "WIND SPEED  %d km/h   (record ≈ 2,100)" % int(wind), wf, _danger(wf - 0.2))
	mm.set_gauge(1, "SHIP CONTROL  %d%%" % int(ne_control), ne_control / 100.0, _danger(1.0 - ne_control / 100.0 - 0.1))
	var readings := (1 if ne_r1 > 0.0 else 0) + (1 if ne_r2 > 0.0 else 0)
	mm.set_gauge(2, "READINGS  %d / 2" % readings, readings / 2.0, Color(0.4, 0.75, 1.0))
	var hint := "Dive into the storm. Press G in the shear layer (>%d km/h), then the core (>%d)." % [int(NE_WMAX * 0.4), int(NE_WMAX * 0.8)]
	if both:
		hint = "Both readings logged. ESCAPE the storm now!"
	elif x < 1.0:
		hint = "Inside the storm: measure with G, but control drains fast in the core."
	mm._m_msg = "Distance to storm centre %.1f u\n%s" % [d, hint]


func _action_winds() -> void:
	var wind := _wind_at(rig._pos)
	if wind >= NE_WMAX * 0.8:
		ne_r2 = wind
		mm._toast("CORE reading: %d km/h" % int(wind))
	elif wind >= NE_WMAX * 0.4:
		ne_r1 = wind
		mm._toast("SHEAR LAYER reading: %d km/h. Go deeper for the core." % int(wind))
	else:
		mm._toast("Only %d km/h here. Fly deeper into the storm." % int(wind))
		return
	mm._flash.color.a = 0.4


# The planet's (and its moons') floating name labels sit right in front of the
# rover camera; hide them while driving. Labels this activity made stay as they are.
func _set_planet_labels(on: bool) -> void:
	for n in body.find_children("*", "Label3D", true, false):
		if not _visuals.has(n):
			(n as Label3D).visible = on
