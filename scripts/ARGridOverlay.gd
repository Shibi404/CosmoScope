extends Control
## Draws a subtle perspective grid on the simulated AR background to give
## the impression of a flat surface (table / floor) detected by AR.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	var grid_color := Color(0.3, 0.35, 0.4, 0.08)
	var accent_color := Color(0.4, 0.5, 0.7, 0.12)

	# Horizontal lines with perspective convergence.
	var horizon_y := sz.y * 0.35
	var num_lines := 18
	for i in num_lines:
		var t := float(i) / float(num_lines - 1)
		var y := horizon_y + (sz.y - horizon_y) * t * t  # quadratic for perspective
		var col := grid_color if i % 4 != 0 else accent_color
		var width := 0.5 + t * 0.8
		draw_line(Vector2(0, y), Vector2(sz.x, y), col, width, true)

	# Vertical lines converging toward the vanishing point.
	var vp_x := sz.x * 0.5
	var num_vlines := 14
	for i in num_vlines:
		var t := float(i) / float(num_vlines - 1)
		var bottom_x := t * sz.x
		var top_x := lerpf(vp_x, bottom_x, 0.4)
		var col := grid_color if i % 3 != 0 else accent_color
		draw_line(Vector2(top_x, horizon_y), Vector2(bottom_x, sz.y), col, 0.6, true)

	# Faint "surface detected" reticle in the centre.
	var cx := sz.x * 0.5
	var cy := sz.y * 0.65
	var reticle_r := 30.0
	var ret_col := Color(0.3, 0.7, 0.4, 0.25)
	_draw_circle_outline(Vector2(cx, cy), reticle_r, ret_col)
	draw_line(Vector2(cx - reticle_r * 0.5, cy), Vector2(cx + reticle_r * 0.5, cy), ret_col, 1.0)
	draw_line(Vector2(cx, cy - reticle_r * 0.5), Vector2(cx, cy + reticle_r * 0.5), ret_col, 1.0)

func _draw_circle_outline(center: Vector2, radius: float, color: Color) -> void:
	var segments := 32
	var prev := center + Vector2(radius, 0)
	for i in range(1, segments + 1):
		var a := TAU * float(i) / float(segments)
		var next := center + Vector2(cos(a) * radius, sin(a) * radius)
		draw_line(prev, next, color, 1.0, true)
		prev = next
