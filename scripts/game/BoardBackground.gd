extends Control

var wood_color := Color("#e6be75")
var grain_color := Color("#d4a75e", 0.4)
var line_color := Color("#1a1a1a")
var hoshi_color := Color("#1a1a1a")

func _ready() -> void:
	# Use a consistent seed for the board wood grain
	seed(42)
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := size
	
	# 1. Draw Wood Background Base
	draw_rect(Rect2(Vector2.ZERO, s), wood_color)
	
	# 1b. Draw Procedural Wood Grain
	# We simulate "Kaya" wood which has long, slightly wavy vertical grains.
	var grain_count := 40
	var spacing := s.x / grain_count
	for i in range(grain_count + 1):
		var x_base := i * spacing
		var points := PackedVector2Array()
		var segments := 10
		for j in range(segments + 1):
			var y := (float(j) / segments) * s.y
			# Add some waviness to the grain
			var wave := sin(y * 0.02 + i) * 2.0 + (randf() - 0.5) * 1.5
			points.append(Vector2(x_base + wave, y))
		draw_polyline(points, grain_color, randf_range(1.0, 3.0), true)

	# 2. Draw Grid
	# Grid is 9x9 squares, which means 10 lines.
	var cell_w := s.x / 9.0
	var cell_h := s.y / 9.0
	
	var grid_width := 1.5
	var border_width := 3.0
	
	for i in range(10):
		var line_w := grid_width
		if i == 0 or i == 9:
			line_w = border_width
			
		# Vertical lines
		var x := i * cell_w
		draw_line(Vector2(x, 0), Vector2(x, s.y), line_color, line_w, true)
		
		# Horizontal lines
		var y := i * cell_h
		draw_line(Vector2(0, y), Vector2(s.x, y), line_color, line_w, true)

	# 3. Draw Hoshi (Star Points)
	var hoshi_indices := [3, 6]
	var hoshi_radius := 3.5
	for r in hoshi_indices:
		for c in hoshi_indices:
			var hoshi_pos := Vector2(c * cell_w, r * cell_h)
			draw_circle(hoshi_pos, hoshi_radius, hoshi_color)
