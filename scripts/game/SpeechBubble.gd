extends PanelContainer

# Comic-style speech balloon: white paper, ink outline, and a tail on the
# top edge pointing up at the opponent's portrait.

const PAPER := Color(1, 1, 1, 1)
const INK := Color(0.08, 0.08, 0.1, 1)
const BORDER := 3
const TAIL_LENGTH := 18.0
const TAIL_HALF_WIDTH := 10.0

var _tail_x: float = 0.0

func _ready() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = INK
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(24)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override("panel", box)

# Where the tail meets the top edge, in local x. Kept clear of the
# rounded corners.
func set_tail_x(x: float) -> void:
	var clamped := clampf(x, 34.0, maxf(34.0, size.x - 34.0))
	if clamped != _tail_x:
		_tail_x = clamped
		queue_redraw()

func _draw() -> void:
	var left := Vector2(_tail_x - TAIL_HALF_WIDTH, 0)
	var right := Vector2(_tail_x + TAIL_HALF_WIDTH, 0)
	var tip := Vector2(_tail_x, -TAIL_LENGTH)
	# The paper reaches past the border so the balloon and tail read as
	# one shape, with no ink line across the join.
	var inner := Vector2(0, BORDER + 1)
	draw_colored_polygon(PackedVector2Array([left + inner, tip, right + inner]), PAPER)
	draw_polyline(PackedVector2Array([left, tip, right]), INK, BORDER, true)
