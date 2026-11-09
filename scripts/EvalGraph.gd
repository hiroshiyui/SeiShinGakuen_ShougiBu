extends Control

# 形勢グラフ for the 棋譜検討 reviewer: one bar per move showing the
# engine's 先手勝率 before that move (up = 先手 ahead, down = 後手
# ahead), a dot on 疑問手 / 悪手, and a cursor at the move being viewed.
# Tap or drag to jump to a move.

signal ply_selected(ply: int)

const _PAD := Vector2(10, 8)
const _BG := Color(0.05, 0.05, 0.07, 0.78)
const _MIDLINE := Color(1, 1, 1, 0.35)
const _SENTE := Color(0.96, 0.9, 0.7, 0.95)
const _GOTE := Color(0.45, 0.62, 0.85, 0.95)
const _CURSOR := Color(1.0, 0.45, 0.2, 1.0)
const _QUESTIONABLE := Color(0.98, 0.82, 0.3, 1)
const _BLUNDER := Color(1.0, 0.42, 0.38, 1)

# One entry per played move; {} / null for moves without an analysis.
var _analyses: Array = []
# 1-based move currently shown on the board (0 = starting position).
var _ply: int = 0

func set_analyses(analyses: Array) -> void:
	_analyses = analyses
	queue_redraw()

func set_ply(ply: int) -> void:
	_ply = ply
	queue_redraw()

func _plot_rect() -> Rect2:
	return Rect2(_PAD, size - _PAD * 2.0)

func _draw() -> void:
	draw_style_box(_panel_box(), Rect2(Vector2.ZERO, size))
	var plot := _plot_rect()
	var n := _analyses.size()
	if n == 0 or plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return
	var mid_y := plot.position.y + plot.size.y * 0.5
	var step := plot.size.x / float(n)
	var bar_w: float = max(1.0, step - 1.0)
	for i in n:
		var e = _analyses[i]
		if e == null or (e as Dictionary).is_empty():
			continue
		var wr: float = clampf(float(e["sente_winrate"]), 0.0, 1.0)
		var h: float = (wr - 0.5) * plot.size.y
		var x: float = plot.position.x + step * i
		if h >= 0.0:
			draw_rect(Rect2(x, mid_y - h, bar_w, max(h, 1.0)), _SENTE)
		else:
			draw_rect(Rect2(x, mid_y, bar_w, -h), _GOTE)
		var cls := String(e["classification"])
		if cls == "questionable" or cls == "blunder":
			var dot_y: float = clampf(mid_y - h + (-6.0 if h >= 0.0 else 6.0),
				plot.position.y + 3.0, plot.end.y - 3.0)
			draw_circle(Vector2(x + bar_w * 0.5, dot_y), 3.5,
				_BLUNDER if cls == "blunder" else _QUESTIONABLE)
	draw_line(Vector2(plot.position.x, mid_y), Vector2(plot.end.x, mid_y), _MIDLINE, 1.0)
	if _ply >= 1 and _ply <= n:
		var cx: float = plot.position.x + step * (_ply - 1) + bar_w * 0.5
		# Dark casing so the cursor stays visible over the pale bars.
		draw_line(Vector2(cx, plot.position.y - 2.0), Vector2(cx, plot.end.y + 2.0), Color(0, 0, 0, 0.85), 6.0)
		draw_line(Vector2(cx, plot.position.y - 2.0), Vector2(cx, plot.end.y + 2.0), _CURSOR, 2.5)

func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _BG
	box.set_corner_radius_all(8)
	return box

func _gui_input(event: InputEvent) -> void:
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pressed = true
		pos = event.position
	elif event is InputEventScreenDrag:
		pressed = true
		pos = event.position
	if not pressed or _analyses.is_empty():
		return
	var plot := _plot_rect()
	var t: float = clampf((pos.x - plot.position.x) / max(plot.size.x, 1.0), 0.0, 0.9999)
	ply_selected.emit(int(t * _analyses.size()) + 1)
	accept_event()
