extends Control

const FONT_PATH := "res://assets/fonts/fude-goshirae/fude-goshirae.otf"
const TEXTURE_PATH := "res://assets/textures/shogi-piece-wood-texture.png"

var text: String = "":
	set(v):
		text = v
		queue_redraw()

var is_gote: bool = false:
	set(v):
		is_gote = v
		queue_redraw()

var _wood_texture: Texture2D

var wood_color_top := Color("#f1d4a0")
var wood_color_main := Color("#e1b570")
var wood_color_side := Color("#a67c45") # Darker side for better depth
var line_color := Color("#2c1e10", 0.5)
var text_color := Color("#1a1a1a")

@onready var _font: FontFile = load(FONT_PATH)

func _ready() -> void:
	_load_texture()

func _load_texture() -> void:
	if FileAccess.file_exists(TEXTURE_PATH):
		_wood_texture = load(TEXTURE_PATH)
		if _wood_texture:
			queue_redraw()

func _draw() -> void:
	if text.is_empty():
		return

	var s := size
	var center := s * 0.5
	var margin := s.x * 0.08
	var w := s.x - margin * 2
	var h := s.y - margin * 2
	var thickness := 4.0

	# 1. Define Shape (Top Surface)
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

	# 2. Realistic Shadow
	var shadow_offset := Vector2(2, 4)
	var shadow_points := PackedVector2Array()
	for p in points:
		shadow_points.append(p + shadow_offset)
	draw_colored_polygon(shadow_points, Color(0, 0, 0, 0.25))

	# 3. Side Face (Thickness)
	# We create a polygon for the bottom thickness to make it look solid
	var thick_offset := Vector2(0, thickness)
	var thick_points := PackedVector2Array()
	for p in points:
		thick_points.append(p + thick_offset)
	
	# Draw the "extrusion" sides
	draw_colored_polygon(thick_points, wood_color_side)

	# 4. Top Face with Normalized UV Texture Cropping
	if _wood_texture:
		seed(text.hash())
		var tex_size := _wood_texture.get_size()
		# Pick a sub-rect (random part of the wood)
		var crop_w := tex_size.x * 0.3
		var crop_h := tex_size.y * 0.3
		var crop_x := randf_range(0, tex_size.x - crop_w)
		var crop_y := randf_range(0, tex_size.y - crop_h)
		var region := Rect2(crop_x, crop_y, crop_w, crop_h)
		
		var uvs := PackedVector2Array()
		for p in points:
			# Map piece local coordinates to 0..1 relative to the piece bounding box
			var rel_x := (p.x - (center.x - w*0.5)) / w
			var rel_y := (p.y - (center.y - h*0.5)) / h
			# Normalize UVs to 0..1 range of the ENTIRE texture
			uvs.append(Vector2(
				(region.position.x + rel_x * region.size.x) / tex_size.x,
				(region.position.y + rel_y * region.size.y) / tex_size.y
			))
		
		draw_polygon(points, [Color.WHITE], uvs, _wood_texture)
	else:
		draw_colored_polygon(points, wood_color_main)

	# 5. Visual Polish
	# Subtle top highlight
	var highlight_color := Color(1, 1, 1, 0.3)
	if is_gote:
		draw_polyline(PackedVector2Array([points[1], points[2], points[3]]), highlight_color, 1.5, true)
	else:
		draw_polyline(PackedVector2Array([points[4], points[0], points[1]]), highlight_color, 1.5, true)
		
	# Dark Outline
	draw_polyline(points + PackedVector2Array([points[0]]), line_color, 1.2, true)

	# 6. Calligraphy Text
	if _font == null: return
	var font_size := int(h * 0.62)
	var x_offset := -_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x * 0.5
	var y_offset := font_size * 0.32
	
	if is_gote:
		draw_set_transform(center, PI, Vector2.ONE)
		draw_string(_font, Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_string(_font, center + Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
