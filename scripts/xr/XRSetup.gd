extends RefCounted
## OpenXR bootstrap. Initialised at runtime (not via project settings), so on a
## machine with no headset / runtime the game simply keeps running in its normal
## desktop / phone mode.

## Player scale in the ship: game units per real metre. The solar system's planets
## are small in game units (Earth radius 0.3 u), so the cockpit and the player are
## made tiny (1 m of real space = 0.05 u) and the planets feel enormous.
const COCKPIT_WORLD_SCALE := 0.05
## On a planet's surface everything is authored in metres.
const SURFACE_WORLD_SCALE := 1.0


## Initialise OpenXR once for the whole app. Returns true when a live session is running.
static func ensure_openxr(vp: Viewport) -> bool:
	if Engine.has_meta("xr_openxr"):
		return bool(Engine.get_meta("xr_openxr"))
	var ok := false
	var xr := XRServer.find_interface("OpenXR")
	if xr != null:
		if xr.is_initialized() or xr.initialize():
			ok = true
	if ok:
		vp.use_xr = true
		# The headset paces frames; a desktop vsync on top only adds latency.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.set_meta("xr_openxr", ok)
	return ok
