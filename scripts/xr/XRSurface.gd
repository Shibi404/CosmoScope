extends Node
## First-person surface exploration for walkable planets (Mercury, Venus, Earth, Mars).
##
## The planets in the solar-system scene are tiny in game units, so the surface is a
## separate human-scale world (metres) built far away from the space scene. On entry
## the space scene is hidden, the sky / light / fog are swapped for the planet's, the
## XR world scale becomes 1.0 and the player is placed beside the parked ship.
##
##   Left stick   walk (relative to where you look)      Right stick   snap turn
##   Grip         pick up glowing sample rocks           A near ship   board and return to the cockpit
##
## Everything from the ship layer (score, mission log, HUD) keeps working: the HUD
## becomes a tablet on the left wrist.

const MissionData := preload("res://data/missions.gd")

const ORIGIN := Vector3(30000.0, 0.0, 0.0)     # far from the space scene
const SIZE := 260.0                            # terrain edge, metres
const GRID := 72
const WALK_RADIUS := 110.0
const WALK_SPEED := 2.4
const SNAP_DEG := 30.0
const BOARD_DIST := 7.0
const SHIP_OFFSET := Vector3(0.0, 0.0, -16.0)  # ship position relative to ORIGIN (x, z used)
const SPAWN := Vector3(0.0, 0.0, -6.0)

var game = null
var rig = null
var mm = null
var player = null

var active: bool = false
var body_name: String = ""
var cfg: Dictionary = {}
var world: Node3D = null
var collected: int = 0
var distance_walked: float = 0.0

var _noise := FastNoiseLite.new()
var _amp: float = 1.0
var _rocks: Array = []               # Vector3(x, z, radius) in world-local metres
var _pois: Array = []                # {node, name, fact, done, grab}
var _ship_node: Node3D = null
var _saved: Dictionary = {}
var _step_t: float = 0.0
var _snap_cool: float = 0.0
var _board_prev: bool = false
var _t: float = 0.0


func setup(g) -> void:
	game = g
	rig = g.rig
	mm = g.mm
	player = g.player


func ground_height(x: float, z: float) -> float:
	var flat := smoothstep(6.0, 40.0, Vector2(x, z).distance_to(Vector2(SHIP_OFFSET.x, SHIP_OFFSET.z)))
	return _noise.get_noise_2d(x, z) * _amp * flat


func ship_position() -> Vector3:
	return ORIGIN + Vector3(SHIP_OFFSET.x, ground_height(SHIP_OFFSET.x, SHIP_OFFSET.z), SHIP_OFFSET.z)


func enter(body: Node3D) -> void:
	if active:
		return
	body_name = mm._pname(body)
	cfg = MissionData.WALKABLE[body_name]
	active = true
	collected = 0
	distance_walked = 0.0
	_t = 0.0
	_noise.seed = hash(body_name)
	_noise.frequency = float(cfg.get("freq", 0.02))
	_noise.fractal_octaves = 3
	_amp = float(cfg.get("amp", 2.0))

	world = Node3D.new()
	world.name = "SurfaceWorld"
	rig._left_viewport.add_child(world)
	world.global_position = ORIGIN
	_build_terrain()
	_build_rocks()
	_build_sky()
	_build_ship()
	_build_samples()

	# Hide the space scene and the cockpit; keep a record so exit() can restore it.
	_saved = {"solar": rig._solar.visible, "hull": rig._ship_root.visible}
	rig._solar.visible = false
	game.cockpit.visible = false
	player.apply_world_scale(1.0)
	game.apply_scale_mode(true)
	# HUD becomes a wrist tablet on the left hand.
	game.hud.mount(player.controller("left"), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-70.0)), Vector3(0.0, 0.08, -0.16)), 0.55)
	# Spawn beside the ship, facing away from it.
	var gy := ground_height(SPAWN.x, SPAWN.z)
	player.global_transform = Transform3D(Basis(Vector3.UP, PI), ORIGIN + Vector3(SPAWN.x, gy, SPAWN.z))
	game.event("surface_enter", {})
	mm._toast("Surface of %s — walk with the left stick, snap-turn with the right" % body_name)


func exit() -> void:
	if not active:
		return
	active = false
	for p in _pois:
		mm.unregister_gaze_object(p["node"])
		game.remove_grabbable(p["node"])
	_pois.clear()
	if _saved.has("env") and _saved["env"] != null:
		var we := _world_env()
		if we != null:
			we.environment = _saved["env"]
	if world != null:
		world.queue_free()
		world = null
	rig._solar.visible = bool(_saved.get("solar", true))
	game.cockpit.visible = true
	player.apply_world_scale(game.cockpit_scale)
	game.apply_scale_mode(false)
	game.hud.mount(game.cockpit, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0, 1.5, -1.5)), 1.9)
	game.event("surface_exit", {})
	mm._toast("Back aboard the ship")


func _world_env() -> WorldEnvironment:
	for c in rig._left_viewport.get_children():
		if c is WorldEnvironment:
			return c
	return null


# ---- World construction ----

func _build_terrain() -> void:
	var base: Color = cfg.get("ground", Color(0.5, 0.4, 0.35))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / float(GRID)
	var half := SIZE * 0.5
	for iz in GRID:
		for ix in GRID:
			var x0 := -half + ix * step
			var z0 := -half + iz * step
			var pts := [
				Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0, z0 + step),
				Vector2(x0 + step, z0), Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step),
			]
			for p in pts:
				var shade := 0.82 + 0.3 * (_noise.get_noise_2d(p.x * 2.3 + 91.0, p.y * 2.3) * 0.5 + 0.5)
				st.set_color(Color(base.r * shade, base.g * shade, base.b * shade))
				st.add_vertex(Vector3(p.x, ground_height(p.x, p.y), p.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	mi.name = "Terrain"
	world.add_child(mi)


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(body_name) + 7
	var count := int(cfg.get("rocks", 100))
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	_rocks.clear()
	var rock_col: Color = cfg.get("rock", Color(0.35, 0.3, 0.28))
	for i in count:
		var x := rng.randf_range(-WALK_RADIUS - 20.0, WALK_RADIUS + 20.0)
		var z := rng.randf_range(-WALK_RADIUS - 20.0, WALK_RADIUS + 20.0)
		while Vector2(x, z).distance_to(Vector2(SPAWN.x, SPAWN.z)) < 5.0 or Vector2(x, z).distance_to(Vector2(SHIP_OFFSET.x, SHIP_OFFSET.z)) < 9.0:
			x = rng.randf_range(-WALK_RADIUS - 20.0, WALK_RADIUS + 20.0)
			z = rng.randf_range(-WALK_RADIUS - 20.0, WALK_RADIUS + 20.0)
		var r := rng.randf_range(0.3, 1.6)
		var b := Basis().scaled(Vector3(r * rng.randf_range(0.8, 1.6), r * rng.randf_range(0.5, 1.0), r * rng.randf_range(0.8, 1.6)))
		multi.set_instance_transform(i, Transform3D(b, Vector3(x, ground_height(x, z) + r * 0.2, z)))
		_rocks.append(Vector3(x, z, r * 0.8))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multi
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rock_col
	mat.roughness = 1.0
	mmi.material_override = mat
	mmi.name = "Rocks"
	world.add_child(mmi)


func _build_sky() -> void:
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = cfg.get("sky_top", Color(0.3, 0.5, 0.9))
	psm.sky_horizon_color = cfg.get("sky_horizon", Color(0.7, 0.8, 0.95))
	psm.ground_horizon_color = cfg.get("sky_horizon", Color(0.7, 0.8, 0.95))
	psm.ground_bottom_color = cfg.get("ground", Color(0.3, 0.3, 0.3))
	var sky := Sky.new()
	sky.sky_material = psm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(cfg.get("ambient", 0.7))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var fog := float(cfg.get("fog", 0.0))
	if fog > 0.0:
		env.fog_enabled = true
		env.fog_light_color = cfg.get("sky_horizon", Color(0.7, 0.8, 0.95))
		env.fog_density = fog
	var we := _world_env()
	if we != null:
		_saved["env"] = we.environment
		we.environment = env
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 40.0, 0.0)
	sun.light_energy = float(cfg.get("sun", 1.0))
	sun.light_color = cfg.get("sun_color", Color(1, 1, 1))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.name = "Sun"
	world.add_child(sun)


func _build_ship() -> void:
	_ship_node = Node3D.new()
	_ship_node.name = "ParkedShip"
	world.add_child(_ship_node)
	_ship_node.position = Vector3(SHIP_OFFSET.x, ground_height(SHIP_OFFSET.x, SHIP_OFFSET.z) + 1.4, SHIP_OFFSET.z)
	var packed := load(rig.ship_model_path) as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		inst.scale = Vector3.ONE * 4.0
		_ship_node.add_child(inst)
	else:
		var hull := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 1.6, 6.0)
		hull.mesh = bm
		_ship_node.add_child(hull)
	var lbl := Label3D.new()
	lbl.text = "YOUR SHIP\nstand close and press A to board"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.006
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.position = Vector3(0, 3.0, 0)
	_ship_node.add_child(lbl)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = BOARD_DIST - 0.06
	tm.outer_radius = BOARD_DIST
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.3, 1.0, 0.6, 0.6)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rmat
	ring.position = Vector3(0, -1.2, 0)
	_ship_node.add_child(ring)


func _build_samples() -> void:
	_pois.clear()
	var samples: Array = cfg.get("samples", [])
	var angles := [0.35, 2.3, 4.2]
	var radii := [24.0, 41.0, 58.0]
	for i in samples.size():
		var s: Dictionary = samples[i]
		var x: float = SPAWN.x + cos(angles[i]) * radii[i]
		var z: float = SPAWN.z + sin(angles[i]) * radii[i]
		var node := Node3D.new()
		node.name = "Sample_%d" % i
		world.add_child(node)
		node.position = Vector3(x, ground_height(x, z) + 0.3, z)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.2)
		mat.emission_energy_multiplier = 1.6
		mi.material_override = mat
		node.add_child(mi)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 8.0
		beam.mesh = cm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color(1.0, 0.85, 0.3, 0.4)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.material_override = bmat
		beam.position = Vector3(0, 4.0, 0)
		node.add_child(beam)
		var poi := {"node": node, "name": s["name"], "fact": s["fact"], "done": false}
		_pois.append(poi)
		mm.register_gaze_object(node, 1.4, String(s["name"]), String(s["fact"]))
		game.add_grabbable({
			"name": "sample", "node": node, "radius": 0.55, "follow": true, "enabled": Callable(),
			"on_grab": func(h): _on_sample_grab(poi, h),
			"on_hold": func(_h, _d): pass,
			"on_release": func(_h): _on_sample_release(poi),
		})


func _on_sample_grab(poi: Dictionary, h: String) -> void:
	game.event("grab", {"hand": h, "at": poi["node"]})
	if bool(poi["done"]):
		return
	poi["done"] = true
	collected += 1
	mm.score += 25
	mm.add_surface_find(body_name, String(poi["name"]), String(poi["fact"]))
	game.event("sample", {"hand": h, "at": poi["node"]})
	mm._card_label.text = "✔ SAMPLE COLLECTED\n%s — %s\n\n%s\n\n+25 score  (recorded in the mission log)" % [
		body_name.to_upper(), poi["name"], poi["fact"]]
	mm._card.visible = true
	mm._card_timer = 14.0


func _on_sample_release(poi: Dictionary) -> void:
	var n: Node3D = poi["node"]
	var lp := n.position
	n.position = Vector3(lp.x, ground_height(lp.x, lp.z) + 0.3, lp.z)
	game.event("release", {"hand": "right", "at": n})


# ---- Per-frame ----

func update(delta: float) -> void:
	if not active:
		return
	_t += delta
	_snap_cool = maxf(0.0, _snap_cool - delta)
	_locomotion(delta)
	# Board the ship: A near it.
	var near := _near_ship()
	var a_now: bool = player.button("right", "ax")
	if near and a_now and not _board_prev:
		board()
	_board_prev = a_now
	var ship_d := _ship_distance()
	var status := "SURFACE OF %s\n%s\nGravity %.2f g  •  %s\nSamples %d / %d  •  Ship %d m %s" % [
		body_name.to_upper(), cfg.get("info", ""), float(cfg.get("gravity", 1.0)), cfg.get("temp", ""),
		collected, _pois.size(), int(ship_d), "— press A to board" if near else "away"]
	mm.surface_info = status


func _ship_distance() -> float:
	var p: Vector3 = player.global_position
	var s := ship_position()
	return Vector2(p.x - s.x, p.z - s.z).length()


func _near_ship() -> bool:
	return _ship_distance() < BOARD_DIST


func board() -> void:
	if not active:
		return
	game.event("board", {})
	mm.exit_surface()


func _locomotion(delta: float) -> void:
	var st: Vector2 = player.stick("left")
	var sr: Vector2 = player.stick("right")
	var moved := 0.0
	if st.length() > 0.15:
		var yaw: float = player.camera.global_rotation.y
		var dir := Basis(Vector3.UP, yaw) * Vector3(st.x, 0.0, -st.y)
		var speed := WALK_SPEED * clampf(st.length(), 0.0, 1.0)
		var pos: Vector3 = player.global_position
		var np := pos + dir * speed * delta
		np = _collide(np)
		moved = Vector2(np.x - pos.x, np.z - pos.z).length()
		np.y = ORIGIN.y + ground_height(np.x - ORIGIN.x, np.z - ORIGIN.z)
		player.global_position = np
		distance_walked += moved
	else:
		var p: Vector3 = player.global_position
		p.y = ORIGIN.y + ground_height(p.x - ORIGIN.x, p.z - ORIGIN.z)
		player.global_position = p
	# Snap turn about the head.
	if absf(sr.x) > 0.7 and _snap_cool <= 0.0:
		_snap_cool = 0.3
		var ang := -deg_to_rad(SNAP_DEG) * signf(sr.x)
		var pivot: Vector3 = player.camera.global_position
		var rel: Vector3 = player.global_position - pivot
		player.global_position = pivot + rel.rotated(Vector3.UP, ang)
		player.rotate_y(ang)
	elif absf(sr.x) < 0.3:
		_snap_cool = 0.0
	# Footsteps.
	if moved > 0.0:
		_step_t += delta
		if _step_t > 0.55:
			_step_t = 0.0
			game.audio.play("step", player, Vector3(0, 0.05, 0))
			game.pulse_both(0.08, 0.02)


# Keep the player inside the walkable disc and out of rocks / the ship.
func _collide(p: Vector3) -> Vector3:
	var lx := p.x - ORIGIN.x
	var lz := p.z - ORIGIN.z
	var v := Vector2(lx, lz)
	if v.length() > WALK_RADIUS:
		v = v.normalized() * WALK_RADIUS
	for r in _rocks:
		var c := Vector2(r.x, r.y)
		var d := v.distance_to(c)
		var min_d: float = r.z + 0.35
		if d < min_d and d > 0.0001:
			v = c + (v - c).normalized() * min_d
	var sc := Vector2(SHIP_OFFSET.x, SHIP_OFFSET.z)
	var sd := v.distance_to(sc)
	if sd < 3.4 and sd > 0.0001:
		v = sc + (v - sc).normalized() * 3.4
	return Vector3(ORIGIN.x + v.x, p.y, ORIGIN.z + v.y)
