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
var wood_color_bottom := Color("#e1b570")
var grain_color := Color("#c69d5a", 0.3)
var line_color := Color("#2c1e10", 0.3)
var text_color := Color("#1a1a1a")

@onready var _font: FontFile = load(FONT_PATH)

func _draw() -> void:
	if text.is_empty():
		return

	var s := size
	var center := s * 0.5
	var margin := s.x * 0.05
	var w := s.x - margin * 2
	var h := s.y - margin * 2

	# Piece Shape Points (relative to center)
	var points := PackedVector2Array([
		Vector2(0, -h * 0.48),           # Tip
		Vector2(w * 0.4, -h * 0.2),      # Right Shoulder
		Vector2(w * 0.48, h * 0.48),     # Bottom Right
		Vector2(-w * 0.48, h * 0.48),    # Bottom Left
		Vector2(-w * 0.4, -h * 0.2),     # Left Shoulder
	])

	# Rotate if Gote
	if is_gote:
		for i in range(points.size()):
			points[i] = -points[i]

	# Offset to center
	for i in range(points.size()):
		points[i] += center

	# 1. Draw Shadow
	var shadow_offset := Vector2(2, 2)
	var shadow_points := PackedVector2Array()
	for p in points:
		shadow_points.append(p + shadow_offset)
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.2))

	# 2. Draw Body
	draw_colored_polygon(points, wood_color_bottom)
	
	# 2b. Draw Piece Wood Grain
	seed(text.hash())
	for i in range(8):
		var gx := randf_range(center.x - w*0.4, center.x + w*0.4)
		var g_top := center.y - h*0.4
		var g_bot := center.y + h*0.4
		draw_line(Vector2(gx, g_top), Vector2(gx + randf_range(-2, 2), g_bot), grain_color, randf_range(1.0, 2.0), true)
	
	# Draw a slight inner highlight/bevel
	var bevel_points := PackedVector2Array()
	for p in points:
		bevel_points.append(lerp(p, center, 0.05))
	draw_colored_polygon(bevel_points, wood_color_top)

	# 3. Draw Outline
	draw_polyline(points + PackedVector2Array([points[0]]), line_color, 1.5, true)

	# 4. Draw Text
	if _font == null:
		return

	var font_size := int(h * 0.65)
	if text.length() > 1:
		font_size = int(h * 0.5)
	
	var x_offset := -_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x * 0.5
	var y_offset := font_size * 0.3 # Vertically center approximately
	
	if is_gote:
		draw_set_transform(center, PI, Vector2.ONE)
		draw_string(_font, Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_string(_font, center + Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
