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

# Strength tier 1..8, mirrors Settings.LEVEL_PARAMS / LEVEL_NAMES.
# Picking a character also sets Settings.ai_level to this value, so the
# player chooses *who* they want to play and the strength comes with
# them (rather than picking strength and getting an opaque tier name).
@export_range(1, 8) var level: int = 1

# MCTS strength dials (the character's baseline).
#   playouts    — search budget per move. Sized for Bonanza v2; 256 is
#                 already a few seconds per move on arm64, so keep it
#                 there or below.
#   temperature — 0.0 greedy (strongest), ~0.5 occasional slips,
#                 >= 1.0 frequent mistakes.
@export_range(16, 4096, 16) var playouts: int = 128
@export_range(0.0, 2.0, 0.05) var temperature: float = 0.0

# Optional per-move "moods". Each entry is
#   {weight: float, playouts: int, temperature: float}
# and one is rolled at random (weighted) every AI move, so a weak
# character mostly plays loosely but now and then produces a sharp move.
# Empty => always the baseline dials above. Entries missing a key fall
# back to the baseline value for that key.
@export var moods: Array[Dictionary] = []

# Dials for the next AI move: a weighted roll over `moods`, or the
# baseline when there are none. Always returns {playouts, temperature}.
func roll_dials() -> Dictionary:
	var base := base_dials()
	if moods.is_empty():
		return base
	var total := 0.0
	for m in moods:
		total += maxf(0.0, float(m.get("weight", 0.0)))
	if total <= 0.0:
		return base
	var r := randf() * total
	for m in moods:
		r -= maxf(0.0, float(m.get("weight", 0.0)))
		if r <= 0.0:
			return _mood_dials(m, base)
	return _mood_dials(moods[moods.size() - 1], base)

func base_dials() -> Dictionary:
	return {playouts = playouts, temperature = temperature}

func _mood_dials(m: Dictionary, base: Dictionary) -> Dictionary:
	return {
		playouts = maxi(1, int(m.get("playouts", base["playouts"]))),
		temperature = maxf(0.0, float(m.get("temperature", base["temperature"]))),
	}

# Shown in the picker next to the portrait (初級 / 中級 / 上級 / 師範).
@export var strength_label: String = "中級"

# Optional one-line tagline for the picker card.
@export var tagline: String = ""

# Longer-form character background, shown on a profile / detail view.
# Free-form Japanese prose — line breaks with \n are honoured.
@export_multiline var introduction: String = ""
