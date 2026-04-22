extends Control

const FONT_PATH := "res://assets/fonts/fude-goshirae/fude-goshirae.otf"

var text: String = "":
	set(v):
		text = v
		queue_redraw()

var is_gote: bool = false:
	set(v):
		is_gote = v
		queue_redraw()

var wood_color_top := Color("#f1d4a0")
var wood_color_main := Color("#e1b570")
var wood_color_side := Color("#b08d58") # Darker for the thickness/side
var grain_color := Color("#c69d5a", 0.3)
var line_color := Color("#2c1e10", 0.4)
var text_color := Color("#1a1a1a")

@onready var _font: FontFile = load(FONT_PATH)

func _draw() -> void:
	if text.is_empty():
		return

	var s := size
	var center := s * 0.5
	var margin := s.x * 0.08
	var w := s.x - margin * 2
	var h := s.y - margin * 2
	
	# Thickness offset (in pixels)
	var thickness := 4.0

	# 1. Define Base Shape (Top Surface)
	var points := PackedVector2Array([
		Vector2(0, -h * 0.48),           # Tip
		Vector2(w * 0.4, -h * 0.2),      # Right Shoulder
		Vector2(w * 0.48, h * 0.48),     # Bottom Right
		Vector2(-w * 0.48, h * 0.48),    # Bottom Left
		Vector2(-w * 0.4, -h * 0.2),     # Left Shoulder
	])

	if is_gote:
		for i in range(points.size()):
			points[i] = -points[i]

	for i in range(points.size()):
		points[i] += center

	# 2. Draw Realistic Soft Shadow
	var shadow_offset := Vector2(2, 4)
	var shadow_points := PackedVector2Array()
	for p in points:
		shadow_points.append(p + shadow_offset)
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.2))

	# 3. Draw "Thickness" (Side Face)
	# We offset the base shape slightly down to create the 3D side effect
	var thick_offset := Vector2(0, thickness)
	var thick_points := PackedVector2Array()
	for p in points:
		thick_points.append(p + thick_offset)
	
	# Draw the "extrusion" by filling the area between top and thick points
	# For simplicity in 2D, we draw the thick base polygon first
	draw_colored_polygon(thick_points, wood_color_side)
	
	# 4. Draw Main Top Surface
	draw_colored_polygon(points, wood_color_main)
	
	# 5. Draw Wood Grain on Top
	seed(text.hash())
	for i in range(10):
		var gx := randf_range(center.x - w*0.4, center.x + w*0.4)
		var g_top := center.y - h*0.4
		var g_bot := center.y + h*0.4
		draw_line(Vector2(gx, g_top), Vector2(gx + randf_range(-1, 1), g_bot), grain_color, randf_range(1.0, 2.0), true)

	# 6. Highlights & Bevel
	# Top-left highlight to suggest light source
	var highlight_color := Color(1, 1, 1, 0.25)
	draw_polyline(PackedVector2Array([points[4], points[0], points[1]]), highlight_color, 1.5, true)
	
	# Bottom edge shadow (where it meets the thickness)
	var edge_shadow := Color(0, 0, 0, 0.1)
	draw_polyline(PackedVector2Array([points[1], points[2], points[3], points[4]]), edge_shadow, 1.0, true)

	# 7. Draw Outline
	draw_polyline(points + PackedVector2Array([points[0]]), line_color, 1.2, true)

	# 8. Draw Text
	if _font == null:
		return

	var font_size := int(h * 0.62)
	var x_offset := -_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x * 0.5
	var y_offset := font_size * 0.32
	
	if is_gote:
		draw_set_transform(center, PI, Vector2.ONE)
		draw_string(_font, Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_string(_font, center + Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
