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

func _ready() -> void:
	_chars = Settings.list_characters()
	_populate_grid()
	_back_btn.pressed.connect(_on_back)
	_confirm_btn.pressed.connect(_on_confirm)
	_apply_safe_area()
	get_tree().root.size_changed.connect(_apply_safe_area)
	# Restore the previously-chosen card if any, else default to the
	# character whose level matches Settings.ai_level (so the picker
	# opens on a sensible default rather than the first cell).
	var initial := _index_of_id(Settings.selected_character_id)
	if initial < 0:
		initial = _index_of_level(Settings.ai_level)
	if initial < 0 and _chars.size() > 0:
		initial = 0
	if initial >= 0:
		_highlight(initial)

func _populate_grid() -> void:
	# Clear any leftover children (defensive — scene ships with empty grid).
	for c in _grid.get_children():
		c.queue_free()
	_card_buttons.clear()
	for i in _chars.size():
		var profile: CharacterProfile = _chars[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 110)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "Lv.%d\n%s" % [profile.level, profile.display_name]
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_card_pressed.bind(i))
		_grid.add_child(btn)
		_card_buttons.append(btn)

func _on_card_pressed(idx: int) -> void:
	_highlight(idx)

func _highlight(idx: int) -> void:
	if idx < 0 or idx >= _chars.size():
		return
	_highlighted = idx
	# Visual selection cue: tint the chosen card. Reset others.
	for i in _card_buttons.size():
		var b := _card_buttons[i]
		if i == idx:
			b.modulate = Color(1.2, 1.1, 0.7, 1)
		else:
			b.modulate = Color(1, 1, 1, 1)
	_update_detail(_chars[idx])

func _update_detail(profile: CharacterProfile) -> void:
	_name.text = profile.display_name
	_level_strength.text = "Lv.%d  %s" % [profile.level, profile.strength_label]
	_tagline.text = profile.tagline
	_intro.text = profile.introduction
	# Try to load <portrait_dir>/neutral.webp; fall back to placeholder
	# if missing so the layout stays stable for unfilled characters.
	var tex: Texture2D = null
	if profile.portrait_dir != "":
		var path := profile.portrait_dir.path_join("neutral.webp")
		if ResourceLoader.exists(path):
			tex = load(path)
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

func _apply_safe_area() -> void:
	# Mirror GameController's pattern: keep content clear of camera
	# notches at the top and gesture-nav at the bottom. Horizontal
	# stays on a fixed margin to avoid sideways drift on phones with
	# non-zero safe.position.x (folds, gesture nav).
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
