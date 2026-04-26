class_name CharacterCard
extends Button

# Picker grid cell: portrait thumbnail + Lv + name. Extends Button so
# the picker still uses `pressed` / `button_group` / `button_pressed`
# without wrapper plumbing — see CharacterPicker for the integration.

@onready var _lvl_label: Label = %LvLabel
@onready var _name_label: Label = %NameLabel
@onready var _portrait: TextureRect = %CardPortrait
@onready var _placeholder: ColorRect = %CardPlaceholder
@onready var _missing_glyph: Label = %CardMissingGlyph

var profile: CharacterProfile

func setup(p: CharacterProfile) -> void:
	profile = p
	# Defer until @onready vars resolve when called pre-_ready.
	if is_node_ready():
		_render()
	else:
		ready.connect(_render, CONNECT_ONE_SHOT)

func _render() -> void:
	if profile == null:
		return
	_lvl_label.text = "Lv.%d" % profile.level
	_name_label.text = profile.display_name
	var tex: Texture2D = null
	if profile.portrait_dir != "":
		var path := profile.portrait_dir.path_join("neutral.webp")
		if ResourceLoader.exists(path):
			tex = load(path)
	_portrait.texture = tex
	_placeholder.visible = tex == null
	_missing_glyph.visible = tex == null
