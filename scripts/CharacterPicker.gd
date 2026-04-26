extends Control

@onready var _grid: GridContainer = %Grid
@onready var _portrait: TextureRect = %Portrait
@onready var _portrait_placeholder: ColorRect = %PortraitPlaceholder
@onready var _portrait_missing: Label = %PortraitMissingLabel
@onready var _name: Label = %DisplayName
@onready var _level_strength: Label = %LevelStrength
@onready var _tagline: Label = %Tagline
@onready var _intro: Label = %Introduction
@onready var _back_btn: Button = %BackButton
@onready var _confirm_btn: Button = %ConfirmButton
@onready var _root: VBoxContainer = %Root

var _chars: Array[CharacterProfile] = []
var _highlighted: int = -1
var _card_buttons: Array[Button] = []
var _card_group: ButtonGroup = ButtonGroup.new()
var _selected_style: StyleBoxFlat

func _ready() -> void:
	_selected_style = _make_selected_stylebox()
	_chars = Settings.list_characters()
	_populate_grid()
	_back_btn.pressed.connect(_on_back)
	_confirm_btn.pressed.connect(_on_confirm)
	_apply_safe_area()
	get_tree().root.size_changed.connect(_apply_safe_area)
	# Restore the previously-chosen card if any, else default to the
	# character whose level matches Settings.ai_level so the picker
	# opens on a sensible default rather than the first cell.
	var initial := _index_of_id(Settings.selected_character_id)
	if initial < 0:
		initial = _index_of_level(Settings.ai_level)
	if initial < 0 and _chars.size() > 0:
		initial = 0
	if initial >= 0:
		_highlight(initial)

func _make_selected_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.55, 0.42, 0.12, 0.85)
	s.border_color = Color(1.0, 0.85, 0.3, 1)
	s.border_width_top = 4
	s.border_width_bottom = 4
	s.border_width_left = 4
	s.border_width_right = 4
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s

func _populate_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_card_buttons.clear()
	for i in _chars.size():
		var btn := _make_card(_chars[i], i)
		_grid.add_child(btn)
		_card_buttons.append(btn)

func _make_card(profile: CharacterProfile, idx: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 210)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.text = ""
	btn.toggle_mode = true
	btn.button_group = _card_group
	btn.add_theme_stylebox_override("pressed", _selected_style)
	btn.add_theme_stylebox_override("hover_pressed", _selected_style)

	# All children render on top of the Button. mouse_filter=IGNORE on
	# every one so the click reaches the Button itself.
	var holder := Control.new()
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = 4
	holder.offset_top = 4
	holder.offset_right = -4
	holder.offset_bottom = -4
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(holder)

	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(v)

	# Level label sits above the portrait so the row stays scannable
	# even when the name wraps to two lines underneath.
	var lvl_label := Label.new()
	lvl_label.text = "Lv.%d" % profile.level
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_label.add_theme_font_size_override("font_size", 18)
	lvl_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	lvl_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lvl_label.add_theme_constant_override("outline_size", 4)
	lvl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lvl_label)

	# Portrait area — fills available vertical space above the label.
	var portrait_holder := Control.new()
	portrait_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_holder.clip_contents = true
	portrait_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(portrait_holder)

	var placeholder_rect := ColorRect.new()
	placeholder_rect.anchor_right = 1.0
	placeholder_rect.anchor_bottom = 1.0
	placeholder_rect.color = Color(0.15, 0.15, 0.18, 0.75)
	placeholder_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(placeholder_rect)

	var placeholder_q := Label.new()
	placeholder_q.anchor_right = 1.0
	placeholder_q.anchor_bottom = 1.0
	placeholder_q.text = "?"
	placeholder_q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_q.add_theme_font_size_override("font_size", 56)
	placeholder_q.add_theme_color_override(
		"font_color", Color(0.45, 0.45, 0.50))
	placeholder_q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(placeholder_q)

	var portrait_tex := TextureRect.new()
	portrait_tex.anchor_right = 1.0
	portrait_tex.anchor_bottom = 1.0
	portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVERED so the head fills the cell; clip_contents on the holder
	# trims overflow. KEEP_ASPECT_CENTERED would leave dead space.
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _try_load_portrait(profile)
	portrait_tex.texture = tex
	portrait_holder.add_child(portrait_tex)
	placeholder_rect.visible = tex == null
	placeholder_q.visible = tex == null

	var name_label := Label.new()
	name_label.text = profile.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ARBITRARY because Japanese has no spaces; WORD modes leave long
	# katakana names like テリー・クラーク unbroken and clip them.
	name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_label)

	btn.pressed.connect(_on_card_pressed.bind(idx))
	return btn

func _try_load_portrait(profile: CharacterProfile) -> Texture2D:
	if profile.portrait_dir == "":
		return null
	var path := profile.portrait_dir.path_join("neutral.webp")
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _on_card_pressed(idx: int) -> void:
	# Tap-to-confirm shortcut: re-tapping the highlighted card commits.
	if idx == _highlighted:
		_on_confirm()
		return
	_highlight(idx)

func _highlight(idx: int) -> void:
	if idx < 0 or idx >= _chars.size():
		return
	_highlighted = idx
	# Setting button_pressed in a button_group auto-deselects siblings.
	_card_buttons[idx].button_pressed = true
	_update_detail(_chars[idx])

func _update_detail(profile: CharacterProfile) -> void:
	_name.text = profile.display_name
	_level_strength.text = "Lv.%d  %s" % [profile.level, profile.strength_label]
	_tagline.text = profile.tagline
	_intro.text = profile.introduction
	var tex := _try_load_portrait(profile)
	_portrait.texture = tex
	_portrait_placeholder.visible = tex == null
	_portrait_missing.visible = tex == null

func _index_of_id(cid: String) -> int:
	if cid == "":
		return -1
	for i in _chars.size():
		if _chars[i].id == cid:
			return i
	return -1

func _index_of_level(lvl: int) -> int:
	for i in _chars.size():
		if _chars[i].level == lvl:
			return i
	return -1

func _apply_safe_area() -> void:
	const EXTRA_TOP := 12.0
	const EXTRA_BOTTOM := 12.0
	const EXTRA_H := 12.0
	var top := EXTRA_TOP
	var bottom := EXTRA_BOTTOM
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	if safe.size != Vector2i.ZERO and screen_size != Vector2i.ZERO:
		var vp: Vector2 = get_viewport_rect().size
		var sy: float = vp.y / float(screen_size.y)
		top += float(safe.position.y) * sy
		bottom += float(screen_size.y - safe.position.y - safe.size.y) * sy
	_root.offset_left = EXTRA_H
	_root.offset_top = top
	_root.offset_right = -EXTRA_H
	_root.offset_bottom = -bottom

func _on_confirm() -> void:
	if _highlighted < 0 or _highlighted >= _chars.size():
		_on_back()
		return
	Settings.select_character(_chars[_highlighted])
	_back_btn.disabled = true
	_confirm_btn.disabled = true
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_back() -> void:
	_back_btn.disabled = true
	_confirm_btn.disabled = true
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
