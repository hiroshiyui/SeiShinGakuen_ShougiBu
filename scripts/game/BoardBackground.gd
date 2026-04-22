extends Control

var wood_texture_path := "res://assets/textures/shogi-ban-wood-texture.png"
var _wood_texture: Texture2D

var wood_color := Color("#e6be75")
var grain_color := Color("#d4a75e", 0.4)
var line_color := Color("#1a1a1a")
var hoshi_color := Color("#1a1a1a")

# Traditional Shogi board margins (percentage of total size)
const MARGIN_PERCENT := 0.04 

func _ready() -> void:
	resized.connect(queue_redraw)
	_load_texture()

func _load_texture() -> void:
	if FileAccess.file_exists(wood_texture_path):
		_wood_texture = load(wood_texture_path)
		if _wood_texture:
			queue_redraw()

func _draw() -> void:
	var s := size
	
	# 1. Draw Wood Background
	if _wood_texture:
		draw_texture_rect(_wood_texture, Rect2(Vector2.ZERO, s), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, s), wood_color)
		seed(42)
		for i in range(40):
			var x_base := i * (s.x / 40.0)
			var points := PackedVector2Array()
			for j in range(11):
				var y := (float(j) / 10.0) * s.y
				var wave := sin(y * 0.02 + i) * 2.0 + (randf() - 0.5) * 1.5
				points.append(Vector2(x_base + wave, y))
			draw_polyline(points, grain_color, randf_range(1.0, 3.0), true)

	# 2. Calculate Grid Area with Margins
	var margin_x := s.x * MARGIN_PERCENT
	var margin_y := s.y * MARGIN_PERCENT
	var grid_w := s.x - (margin_x * 2.0)
	var grid_h := s.y - (margin_y * 2.0)
	var grid_rect := Rect2(margin_x, margin_y, grid_w, grid_h)

	# 3. Draw Grid Lines
	var cell_w := grid_w / 9.0
	var cell_h := grid_h / 9.0
	
	var grid_width := 1.5
	var border_width := 3.0
	
	for i in range(10):
		var line_w := grid_width
		if i == 0 or i == 9:
			line_w = border_width
		
		# Vertical
		var x := grid_rect.position.x + i * cell_w
		draw_line(Vector2(x, grid_rect.position.y), Vector2(x, grid_rect.end.y), line_color, line_w, true)
		
		# Horizontal
		var y := grid_rect.position.y + i * cell_h
		draw_line(Vector2(grid_rect.position.x, y), Vector2(grid_rect.end.x, y), line_color, line_w, true)

	# 4. Draw Hoshi (Star Points)
	var hoshi_indices := [3, 6]
	var hoshi_radius := 3.5
	for r in hoshi_indices:
		for c in hoshi_indices:
			var hoshi_pos := grid_rect.position + Vector2(c * cell_w, r * cell_h)
			draw_circle(hoshi_pos, hoshi_radius, hoshi_color)
