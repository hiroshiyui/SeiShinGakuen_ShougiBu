class_name SpeechBank
extends Resource

# Lines for the player's avatar, one bank per speech style (Settings
# .avatar_voice picks it from the avatar). Same moments as
# CharacterProfile.lines, seen from the player's side: `start`, `check`
# (the player gives check), `lose_piece` (the player loses a 飛 / 角),
# `win` and `lose`. Shown on this device only; never sent to a 通信対戦
# peer. Keep lines short enough for one line of the speech balloon.
@export var lines: Dictionary = {}

# A random line for `moment`, or "" when the bank has none.
func random_line(moment: String) -> String:
	var options: Array = lines.get(moment, [])
	return "" if options.is_empty() else str(options.pick_random())
