class_name CharacterProfile
extends Resource

# AI opponent profile. Each character is a `.tres` under
# `assets/characters/{teachers,students}/…`. The MainMenu will list
# every .tres it finds; GameController uses the selected profile's
# playouts + temperature when running MCTS.

@export var id: String = ""
@export var display_name: String = ""

# Directory containing portrait images keyed by expression name
# (`neutral.webp`, `thinking.webp`, `happy.webp`, `worried.webp`,
# `defeat.webp`, `victory.webp`). Missing files fall back to `neutral`.
@export_dir var portrait_dir: String = ""

# MCTS strength dials.
#   playouts    — search budget per move. 16=学習中, 128=部員, 512=主将, 2048=師範.
#   temperature — 0.0 greedy (strongest), 0.5 occasional 緩手, 1.0 frequent mistakes.
@export_range(16, 4096, 16) var playouts: int = 128
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.0

# Shown in the picker next to the portrait (初級 / 中級 / 上級 / 師範).
@export var strength_label: String = "中級"

# Optional one-line tagline for the picker card.
@export var tagline: String = ""
