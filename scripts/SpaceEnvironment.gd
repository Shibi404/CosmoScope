extends WorldEnvironment
## Procedurally builds a starfield "space" backdrop as an equirectangular
## panorama sky — no texture files, so the repo stays self-contained.
##
## Reusable by every scene (test, AR, VR) that wants the universe background.

@export var star_count: int = 4000
@export var texture_size: Vector2i = Vector2i(2048, 1024)
## 0 disables the faint nebula clouds.
@export var nebula_strength: float = 0.5

const MILKY_WAY := "res://assets/textures/2k_stars_milky_way.jpg"

func _ready() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	# Use the real Milky Way panorama when present; otherwise generate stars.
	if ResourceLoader.exists(MILKY_WAY):
		sky_mat.panorama = load(MILKY_WAY)
	else:
		sky_mat.panorama = _generate_star_texture()

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25

	# ACES tonemapping for filmic highlight roll-off (the Sun / rim glow no
	# longer clip to flat white), with exposure lifted to keep midtones bright.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.3
	env.tonemap_white = 1.0

	# Bloom so the Sun and emissive surfaces glow like real light sources;
	# the HDR threshold keeps only genuinely bright pixels blooming.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	# A touch more contrast and colour for a richer, less washed-out look.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.15

	environment = env

func _generate_star_texture() -> ImageTexture:
	# RGBA8 so the nebula (which carries alpha) can be blended in via blend_rect,
	# which requires matching source/destination formats.
	var img := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.003, 0.003, 0.01, 1.0))

	if nebula_strength > 0.0:
		_add_nebula(img)
	_scatter_stars(img)

	return ImageTexture.create_from_image(img)

func _add_nebula(img: Image) -> void:
	# Build a small nebula, then upscale + blend (both C++ ops) so we never
	# loop over the full-resolution image in GDScript.
	var nw := 256
	var nh := 128
	var neb := Image.create(nw, nh, false, Image.FORMAT_RGBA8)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 4

	var tint_a := Color(0.20, 0.10, 0.35)  # purple
	var tint_b := Color(0.05, 0.12, 0.28)  # blue
	for y in nh:
		for x in nw:
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			n = pow(n, 3.0)  # tighten into wispy clouds
			var col := tint_a.lerp(tint_b, float(x) / float(nw))
			neb.set_pixel(x, y, Color(col.r, col.g, col.b, n * nebula_strength))

	neb.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	img.blend_rect(neb, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)

func _scatter_stars(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in star_count:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var b := pow(rng.randf_range(0.35, 1.0), 2.0)  # many dim, few bright

		var c := Color(b, b, b)
		var tint := rng.randf()
		if tint < 0.15:
			c = Color(b * 0.7, b * 0.8, b)   # blue-white star
		elif tint > 0.85:
			c = Color(b, b * 0.85, b * 0.7)  # warm star
		img.set_pixel(x, y, c)

		# A few of the brightest stars get a small halo.
		if rng.randf() > 0.98:
			var halo := Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 1.0)
			_plot(img, x + 1, y, halo)
			_plot(img, x - 1, y, halo)
			_plot(img, x, y + 1, halo)
			_plot(img, x, y - 1, halo)

func _plot(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)
