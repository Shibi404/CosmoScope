extends Node3D
## The existing 2D HUD, shown on a floating 3D panel.
##
## ShipRig / ShipMissions build their HUD as CanvasLayers. In VR those layers are
## parented under `viewport` (a SubViewport) instead of the screen, and the
## SubViewport's texture is drawn on `quad`. A controller laser that hits the quad
## is converted to a pixel position and pushed into the SubViewport as mouse
## events, so every existing button (dock, mission, autopilot dialog…) works.

const VIEW_SIZE := Vector2i(1152, 648)

var viewport: SubViewport
var quad: MeshInstance3D
var width_m: float = 1.9
var _last_px: Vector2 = Vector2(-1, -1)
var _down: bool = false


func build() -> void:
	name = "HudPanel"
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width_m, width_m * float(VIEW_SIZE.y) / float(VIEW_SIZE.x))
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = mat
	add_child(quad)


func set_width(w: float) -> void:
	width_m = w
	(quad.mesh as QuadMesh).size = Vector2(w, w * float(VIEW_SIZE.y) / float(VIEW_SIZE.x))


## Move the panel under another node (cockpit, wrist…) with a local transform in metres.
func mount(parent: Node3D, local_xf: Transform3D, width: float) -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	parent.add_child(self)
	transform = local_xf
	set_width(width)


## Ray vs the panel. Returns {"ok": bool, "px": Vector2, "dist": float} (dist in world units).
func raycast(origin: Vector3, dir: Vector3) -> Dictionary:
	var o := to_local(origin)
	var d := to_local(origin + dir) - o
	if absf(d.z) < 0.000001 or o.z <= 0.0:
		return {"ok": false}
	var t := -o.z / d.z
	if t <= 0.0:
		return {"ok": false}
	var hit := o + d * t
	var h := width_m * float(VIEW_SIZE.y) / float(VIEW_SIZE.x)
	if absf(hit.x) > width_m * 0.5 or absf(hit.y) > h * 0.5:
		return {"ok": false}
	var px := Vector2((hit.x / width_m + 0.5) * VIEW_SIZE.x, (0.5 - hit.y / h) * VIEW_SIZE.y)
	return {"ok": true, "px": px, "dist": origin.distance_to(to_global(hit))}


func push_motion(px: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	ev.relative = px - (_last_px if _last_px.x >= 0.0 else px)
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _down else 0
	_last_px = px
	viewport.push_input(ev, true)


func push_button(px: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = px
	ev.global_position = px
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_down = pressed
	viewport.push_input(ev, true)


## The pointer left the panel.
func push_leave() -> void:
	if _down:
		_down = false
	_last_px = Vector2(-1, -1)
