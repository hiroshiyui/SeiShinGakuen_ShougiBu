extends PanelContainer

# Comic-style speech balloon: white paper and an ink outline, drawn as
# one continuous shape so the tail flows out of the top edge. The tail
# points up at the opponent's portrait.

const PAPER := Color(1, 1, 1, 1)
const INK := Color(0.08, 0.08, 0.1, 1)
const LINE_WIDTH := 3.0
const CORNER_RADIUS := 24.0
const CORNER_STEPS := 24
const TAIL_LENGTH := 18.0
const TAIL_HALF_WIDTH := 14.0
const TAIL_STEPS := 12

var _tail_x: float = 0.0

func _ready() -> void:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override("panel", box)
	resized.connect(queue_redraw)

# Where the tail meets the top edge, in local x. Kept clear of the
# rounded corners.
func set_tail_x(x: float) -> void:
	var margin := CORNER_RADIUS + TAIL_HALF_WIDTH + 2.0
	var clamped := clampf(x, margin, maxf(margin, size.x - margin))
	if clamped != _tail_x:
		_tail_x = clamped
		queue_redraw()

func _draw() -> void:
	# Before the first line is placed the balloon has no usable size or
	# tail position, and the outline would be a degenerate polygon.
	if _tail_x <= 0.0 or size.y <= CORNER_RADIUS * 2.0:
		return
	var outline := _outline()
	draw_colored_polygon(outline, PAPER)
	var closed := outline.duplicate()
	closed.append(outline[0])
	closed.append(outline[1])  # overlap so the start has no visible seam
	draw_polyline(closed, INK, LINE_WIDTH, true)

# Clockwise from the top-left corner, inset so the ink stays in bounds.
func _outline() -> PackedVector2Array:
	var inset := LINE_WIDTH * 0.5
	var rect := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var r := minf(CORNER_RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	_add_arc(pts, rect.position + Vector2(r, r), r, PI)
	_add_tail(pts, rect.position.y)
	_add_arc(pts, Vector2(rect.end.x - r, rect.position.y + r), r, PI * 1.5)
	_add_arc(pts, rect.end - Vector2(r, r), r, 0.0)
	_add_arc(pts, Vector2(rect.position.x + r, rect.end.y - r), r, PI * 0.5)
	return pts

func _add_arc(pts: PackedVector2Array, center: Vector2, r: float, start: float) -> void:
	for i in CORNER_STEPS + 1:
		var a := start + PI * 0.5 * i / CORNER_STEPS
		pts.append(center + Vector2(cos(a), sin(a)) * r)

# Two concave curves, tangent to the top edge, meeting at the tip.
func _add_tail(pts: PackedVector2Array, top: float) -> void:
	var left := Vector2(_tail_x - TAIL_HALF_WIDTH, top)
	var right := Vector2(_tail_x + TAIL_HALF_WIDTH, top)
	var tip := Vector2(_tail_x, top - TAIL_LENGTH)
	var control_left := Vector2(_tail_x - 2.0, top)
	var control_right := Vector2(_tail_x + 2.0, top)
	for i in TAIL_STEPS + 1:
		pts.append(_quadratic(left, control_left, tip, float(i) / TAIL_STEPS))
	for i in range(1, TAIL_STEPS + 1):
		pts.append(_quadratic(tip, control_right, right, float(i) / TAIL_STEPS))

func _quadratic(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
