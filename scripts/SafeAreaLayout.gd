class_name SafeAreaLayout
extends Control

# Drop-in fullscreen container that keeps its content inside the OS
# safe area (status bar, gesture nav, camera cutout). Place it as a
# direct child of the screen Control, anchor it full-rect, and put
# the centred / edge-anchored content inside.
#
# Mirrors the pattern in CharacterPicker / KifuReviewer / Credits but
# self-contained so new screens don't have to wire up _apply_safe_area
# by hand. Settings.apply_safe_area_to is still the single source of
# truth for the inset computation.

func _ready() -> void:
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

func _apply_safe_area() -> void:
	Settings.apply_safe_area_to(self)
