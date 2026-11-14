class_name BoardFit
extends RefCounted

# Shared shogi-ban sizing for every screen that stacks a square board in
# a VBoxContainer Layout between rows of fixed-height controls (対局,
# 詰将棋, 棋譜検討).
#
# The side is measured, not estimated: the viewport minus the
# safe-area insets (camera cutout, gesture bar — the same insets
# Settings.apply_safe_area_to puts on the Layout), minus every visible
# row's combined minimum size and the VBox separations. Hard-coded row
# heights against the bare viewport height overestimated the room on
# tall phones (the board then pushed the bottom rows off-screen) and
# had to be kept in sync by hand with each scene.
#
# get_combined_minimum_size() is valid before a row's first layout pass
# (size.y is still 0 until the container has sorted it), so this works
# right after a row is shown or filled.

const PAD := 16.0  # breathing room left under the rows

# `h_margin`: total horizontal room to leave beside the board.
# `shown_override`: {Control: bool} to measure as if a row's visibility
# had already flipped (e.g. a panel that is mid-fade-out).
static func side(layout: VBoxContainer, board_holder: Control, h_margin: float,
		shown_override: Dictionary = {}) -> float:
	var vp: Vector2 = layout.get_viewport_rect().size
	var insets: Rect2 = Settings.safe_area_insets(vp)
	var avail: float = vp.y - insets.position.y - insets.size.y - PAD
	var sep: float = float(layout.get_theme_constant("separation"))
	var visible_items := 0
	for child in layout.get_children():
		var c := child as Control
		if c == null or c.top_level:
			continue
		var shown: bool = bool(shown_override.get(c, c.visible))
		if not shown:
			continue
		visible_items += 1
		if c == board_holder:
			continue
		avail -= c.get_combined_minimum_size().y
	avail -= sep * max(0, visible_items - 1)
	return clampf(minf(vp.x - h_margin, avail), 240.0, 1600.0)
