extends Node3D
## Spatial 3D audio for the VR game. Every sound is synthesised here (no asset
## files) and played through AudioStreamPlayer3D, so it is positioned in the
## cockpit / on the surface and the XR camera acts as the listener.
##
## One-shot sounds are created at a node (a cockpit button, the scanner tool,
## a satellite…). Three continuous beds run all the time: engine rumble that
## follows the throttle, wind / storm noise that follows the mission's wind
## strength, and a low planetary hum that follows the nearest planet.

const RATE := 22050

var game = null
var played: Dictionary = {}            # sound id -> count (for tests / debugging)
var engine_player: AudioStreamPlayer3D
var wind_player: AudioStreamPlayer3D
var hum_player: AudioStreamPlayer3D
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


# ---- Synthesis ----

static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	var d := PackedByteArray()
	d.resize(samples.size() * 2)
	for i in samples.size():
		d.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	s.data = d
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func _tone(freq: float, dur: float, vol: float, decay: float, second: float = 0.0) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * freq * t)
		if second > 0.0:
			v = (v + 0.6 * sin(TAU * second * t)) / 1.6
		out[i] = v * vol * exp(-decay * t / maxf(dur, 0.001))
	return out


func _noise(dur: float, vol: float, smooth: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var r := _rng.randf_range(-1.0, 1.0)
		prev = prev + (r - prev) * smooth
		out[i] = prev * vol * exp(-decay * float(i) / maxf(n, 1.0))
	return out


static func _concat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	out.append_array(b)
	return out


func _stream(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	_rng.seed = hash(id)
	var s: AudioStreamWAV = null
	match id:
		"click":
			s = _wav(_tone(1400.0, 0.05, 0.6, 5.0, 2100.0))
		"clunk":
			s = _wav(_concat(_tone(90.0, 0.12, 0.9, 4.0), _noise(0.05, 0.4, 0.3, 4.0)))
		"grab":
			s = _wav(_tone(520.0, 0.07, 0.5, 4.0, 780.0))
		"release":
			s = _wav(_tone(400.0, 0.07, 0.4, 4.0))
		"beep":
			s = _wav(_tone(1200.0, 0.08, 0.5, 2.0))
		"scan_done":
			s = _wav(_concat(_tone(880.0, 0.09, 0.5, 2.0), _tone(1320.0, 0.16, 0.5, 3.0)))
		"dock":
			s = _wav(_concat(_tone(70.0, 0.25, 1.0, 3.0), _noise(0.4, 0.35, 0.15, 3.0)))
		"undock":
			s = _wav(_noise(0.5, 0.4, 0.1, 2.5))
		"chime":
			var c := _tone(659.0, 0.18, 0.5, 2.5)
			c = _concat(c, _tone(831.0, 0.18, 0.5, 2.5))
			c = _concat(c, _tone(988.0, 0.4, 0.55, 3.0, 1976.0))
			s = _wav(c)
		"buzz":
			s = _wav(_concat(_tone(110.0, 0.2, 0.7, 1.5, 165.0), _tone(90.0, 0.3, 0.7, 2.5, 135.0)))
		"shutter":
			s = _wav(_concat(_noise(0.03, 0.8, 0.6, 3.0), _noise(0.05, 0.6, 0.4, 4.0)))
		"ping":
			s = _wav(_tone(1760.0, 0.5, 0.4, 5.0))
		"step":
			s = _wav(_noise(0.11, 0.7, 0.12, 5.0))
		"sample":
			s = _wav(_concat(_tone(600.0, 0.08, 0.5, 3.0), _tone(900.0, 0.2, 0.5, 4.0)))
		"engine_loop":
			# Low rumble: filtered noise + a 48 Hz sine, sample-exact loop.
			var n := RATE
			var e := PackedFloat32Array()
			e.resize(n)
			var prev := 0.0
			for i in n:
				prev = prev + (_rng.randf_range(-1.0, 1.0) - prev) * 0.05
				e[i] = prev * 1.6 + 0.35 * sin(TAU * 48.0 * float(i) / RATE)
			s = _wav(e, true)
		"wind_loop":
			var w := PackedFloat32Array()
			w.resize(RATE * 2)
			var p2 := 0.0
			for i in w.size():
				p2 = p2 + (_rng.randf_range(-1.0, 1.0) - p2) * 0.2
				w[i] = p2 * (0.7 + 0.3 * sin(TAU * float(i) / w.size() * 2.0))
			s = _wav(w, true)
		"hum_loop":
			var h := PackedFloat32Array()
			h.resize(RATE)
			for i in h.size():
				var t := float(i) / RATE
				h[i] = 0.5 * sin(TAU * 55.0 * t) + 0.25 * sin(TAU * 82.5 * t)
			s = _wav(h, true)
	if s == null:
		s = _wav(_tone(440.0, 0.05, 0.3, 3.0))
	_cache[id] = s
	return s


# ---- Playback ----

func build(g) -> void:
	game = g
	name = "XRAudio"
	engine_player = _bed("engine_loop", -60.0)
	wind_player = _bed("wind_loop", -60.0)
	hum_player = _bed("hum_loop", -60.0)


func _bed(id: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(id)
	p.volume_db = db
	p.unit_size = game.audio_unit
	p.max_distance = 0.0
	add_child(p)
	p.play()
	return p


## Play a one-shot sound at a node (optionally offset in that node's local space).
func play(id: String, at: Node3D = null, offset: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> void:
	played[id] = int(played.get(id, 0)) + 1
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(id)
	p.volume_db = volume_db
	p.unit_size = game.audio_unit
	p.max_distance = 0.0
	var parent: Node = at if at != null else game.player
	parent.add_child(p)
	p.position = offset
	p.finished.connect(p.queue_free)
	p.play()


## Continuous beds: called every frame.
func update(delta: float) -> void:
	var rig = game.rig
	var mm = game.mm
	# Engine + wind emitters sit at the ship (engine at the tail).
	var sb: Basis = rig._ship_basis()
	engine_player.global_position = rig._pos + sb * (Vector3(0.0, 0.4, 1.4) * game.cockpit_scale)
	wind_player.global_position = rig._pos + sb * (Vector3(0.0, 0.8, -0.5) * game.cockpit_scale)
	# Engine: rumble follows the throttle while thrusting.
	var thrust: float = 0.0
	if rig._thrusting and rig._fuel > 0.0 and not mm.hold_ship:
		thrust = clampf(rig._throttle, 0.0, 1.0)
	engine_player.volume_db = lerpf(engine_player.volume_db, lerpf(-48.0, -8.0, thrust), minf(1.0, delta * 6.0))
	engine_player.pitch_scale = 0.75 + 0.7 * thrust
	# Wind / storm noise follows the mission's wind strength (rumble_extra 0..1).
	var wind: float = clampf(game.wind_level, 0.0, 1.0)
	wind_player.volume_db = lerpf(wind_player.volume_db, lerpf(-60.0, -6.0, wind), minf(1.0, delta * 4.0))
	wind_player.pitch_scale = 0.8 + 0.6 * wind
	# Planetary hum: at the nearest planet, louder the closer you are.
	var best: Node3D = null
	var bd := INF
	for b in mm._targets:
		var d: float = rig._pos.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = b
	if best != null and not game.in_surface():
		hum_player.global_position = best.global_position
		var near := clampf(1.0 - bd / 12.0, 0.0, 1.0)
		hum_player.volume_db = lerpf(hum_player.volume_db, lerpf(-60.0, -14.0, near), minf(1.0, delta * 3.0))
		hum_player.pitch_scale = 0.6 + 0.8 / maxf(1.0, mm._radius(best) * 2.0)
	else:
		hum_player.volume_db = lerpf(hum_player.volume_db, -60.0, minf(1.0, delta * 3.0))
