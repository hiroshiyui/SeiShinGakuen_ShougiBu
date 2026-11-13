class_name RoundedPortrait
extends TextureRect

# A portrait with rounded corners, the look of the opponent strip's
# portrait in Main.tscn. Each instance owns its ShaderMaterial, because
# the shader's `size` uniform is that rect's rendered size and a shared
# material would carry only the last one.

const _SHADER := preload("res://assets/shaders/rounded_corners.gdshader")

@export var radius: float = 6.0

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("radius", radius)
	material = mat
	resized.connect(_sync_size)
	# Layout hasn't sized the rect yet in _ready; a (0, 0) size would
	# discard every fragment until the first `resized`.
	_sync_size.call_deferred()

func _sync_size() -> void:
	(material as ShaderMaterial).set_shader_parameter("size", size)

# The portrait at `path` scaled down to `width` px wide, so a grid of
# them doesn't keep a dozen full 880×1168 textures in memory. null when
# the file is missing.
static func thumbnail(path: String, width: int) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var height := int(round(float(img.get_height()) * width / img.get_width()))
	img.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
