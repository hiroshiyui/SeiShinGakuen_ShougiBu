extends PanelContainer

# Comic-style speech balloon: white paper and an ink outline, drawn as
# one continuous shape so the tail flows out of one edge. The
# opponent's balloon sits above their portrait with the tail pointing
# down at it; the player's (`tail_up`) sits below theirs, pointing up.

const PAPER := Color(1, 1, 1, 1)
const INK := Color(0.08, 0.08, 0.1, 1)
const LINE_WIDTH := 3.0
const CORNER_RADIUS := 24.0
const CORNER_STEPS := 24
const TAIL_LENGTH := 18.0
const TAIL_HALF_WIDTH := 14.0
const TAIL_STEPS := 12

var _tail_x: float = 0.0
@export var tail_up: bool = false
# Thought balloon: a cloud with a scalloped edge and, instead of a
# tail, a trail of two small bubbles drifting down to the thinker.
# The trail occupies the same TAIL_LENGTH below the box.
@export var thought: bool = false

# The cloud's lobes sit on a rounded rectangle inset by CLOUD_INSET and
# bulge back out by at most that much, so the ink stays in bounds.
const CLOUD_INSET := 11.0
const CLOUD_CORNER := 26.0
const CLOUD_LOBE := 30.0          # typical lobe width along the edge
const CLOUD_BULGE := 0.68         # lobe height as a fraction of its half-width
const CLOUD_LOBE_STEPS := 10
# Uneven widths, so it reads as hand-drawn rather than as a gear.
const CLOUD_RHYTHM: Array[float] = [1.0, 0.78, 1.18, 0.86, 1.08]

func _ready() -> void:
	var box := StyleBoxEmpty.new()
	# The cloud's lobes eat into the box, so it needs more padding.
	box.content_margin_left = 30 if thought else 22
	box.content_margin_right = 30 if thought else 22
	box.content_margin_top = 20 if thought else 10
	box.content_margin_bottom = 20 if thought else 10
	add_theme_stylebox_override("panel", box)
	resized.connect(queue_redraw)

# Where the tail meets its edge, in local x. Kept clear of the
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
	var outline := _cloud_outline() if thought else _outline()
	draw_colored_polygon(outline, PAPER)
	var closed := outline.duplicate()
	closed.append(outline[0])
	closed.append(outline[1])  # overlap so the start has no visible seam
	draw_polyline(closed, INK, LINE_WIDTH, true)
	if thought:
		_draw_puff(Vector2(_tail_x, size.y + 6.0), 5.0)
		_draw_puff(Vector2(_tail_x - 3.0, size.y + 15.0), 3.0)

func _draw_puff(center: Vector2, r: float) -> void:
	draw_circle(center, r, PAPER)
	draw_arc(center, r, 0.0, TAU, 24, INK, LINE_WIDTH * 0.75, true)

# Clockwise from the top-left corner, inset so the ink stays in bounds.
func _outline() -> PackedVector2Array:
	var inset := LINE_WIDTH * 0.5
	var rect := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var r := minf(CORNER_RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	_add_arc(pts, rect.position + Vector2(r, r), r, PI)
	if tail_up and not thought:
		_add_tail(pts, rect.position.y, -1.0)
	_add_arc(pts, Vector2(rect.end.x - r, rect.position.y + r), r, PI * 1.5)
	_add_arc(pts, rect.end - Vector2(r, r), r, 0.0)
	if not tail_up and not thought:
		_add_tail(pts, rect.end.y, 1.0)
	_add_arc(pts, Vector2(rect.position.x + r, rect.end.y - r), r, PI * 0.5)
	return pts

# Lobes strung clockwise along an inset rounded rectangle: each spans
# two neighbouring anchor points on it and bulges outward as half an
# ellipse, meeting the next lobe in an inward cusp.
func _cloud_outline() -> PackedVector2Array:
	var rect := Rect2(Vector2.ZERO, size).grow(-CLOUD_INSET)
	var r := minf(CLOUD_CORNER, minf(rect.size.x, rect.size.y) * 0.5)
	var path := PackedVector2Array()
	_add_arc(path, rect.position + Vector2(r, r), r, PI)
	_add_arc(path, Vector2(rect.end.x - r, rect.position.y + r), r, PI * 1.5)
	_add_arc(path, rect.end - Vector2(r, r), r, 0.0)
	_add_arc(path, Vector2(rect.position.x + r, rect.end.y - r), r, PI * 0.5)
	path.append(path[0])
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + path[i - 1].distance_to(path[i]))
	var total := cum[cum.size() - 1]
	var count := maxi(6, roundi(total / CLOUD_LOBE))
	var weights: Array[float] = []
	var weight_sum := 0.0
	for i in count:
		weights.append(CLOUD_RHYTHM[i % CLOUD_RHYTHM.size()])
		weight_sum += weights[i]
	var anchors := PackedVector2Array()
	var seg := 1
	var at := 0.0
	for i in count:
		var d := at / weight_sum * total
		while seg < cum.size() - 1 and cum[seg] < d:
			seg += 1
		var span := cum[seg] - cum[seg - 1]
		anchors.append(path[seg - 1].lerp(path[seg], (d - cum[seg - 1]) / span if span > 0.0 else 0.0))
		at += weights[i]
	var pts := PackedVector2Array()
	for i in count:
		var a := anchors[i]
		var b := anchors[(i + 1) % count]
		var mid := (a + b) * 0.5
		var half := (b - a) * 0.5
		# Clockwise on screen (y down), so outward is the chord turned left.
		var out := Vector2(half.y, -half.x) * CLOUD_BULGE
		for j in CLOUD_LOBE_STEPS:  # stops short of b: the next lobe starts there
			var t := PI * j / CLOUD_LOBE_STEPS
			pts.append(mid - half * cos(t) + out * sin(t))
	return pts

func _add_arc(pts: PackedVector2Array, center: Vector2, r: float, start: float) -> void:
	for i in CORNER_STEPS + 1:
		var a := start + PI * 0.5 * i / CORNER_STEPS
		pts.append(center + Vector2(cos(a), sin(a)) * r)

# Two concave curves, tangent to the edge at `y`, meeting at the tip
# (`dir` -1 points up, +1 down). Traced in the direction the clockwise
# outline runs along that edge: left to right on top, right to left on
# the bottom.
func _add_tail(pts: PackedVector2Array, y: float, dir: float) -> void:
	var left := Vector2(_tail_x - TAIL_HALF_WIDTH, y)
	var right := Vector2(_tail_x + TAIL_HALF_WIDTH, y)
	var tip := Vector2(_tail_x, y + dir * TAIL_LENGTH)
	var control_left := Vector2(_tail_x - 2.0, y)
	var control_right := Vector2(_tail_x + 2.0, y)
	var first := [left, control_left] if dir < 0.0 else [right, control_right]
	var second := [control_right, right] if dir < 0.0 else [control_left, left]
	for i in TAIL_STEPS + 1:
		pts.append(_quadratic(first[0], first[1], tip, float(i) / TAIL_STEPS))
	for i in range(1, TAIL_STEPS + 1):
		pts.append(_quadratic(tip, second[0], second[1], float(i) / TAIL_STEPS))

func _quadratic(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
