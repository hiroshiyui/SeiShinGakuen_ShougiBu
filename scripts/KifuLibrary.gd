extends Control

# Library of saved .kif files. Lists everything in the same Documents
# dir GameController._save_kif() writes to (app-private external on
# Android, ~/Documents on Linux), plus the user:// fallback so a save
# that landed there during a permission glitch isn't orphaned.

@onready var _list: VBoxContainer = %RowList
@onready var _empty_hint: Label = %EmptyHint
@onready var _back_btn: Button = %BackButton
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog

var _pending_delete_path: String = ""

func _ready() -> void:
	_back_btn.pressed.connect(_on_back)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	ModalBlur.attach(_delete_dialog)
	_refresh()

var _back_handled_frame: int = -1

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_handle_back()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> void:
	var f: int = Engine.get_process_frames()
	if _back_handled_frame == f:
		return
	_back_handled_frame = f
	if _delete_dialog.visible:
		_delete_dialog.hide()
		return
	_on_back()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# Walk the candidate dirs once, gather every .kif by absolute path, sort
# newest-first by mtime, render rows. Re-runnable after a delete.
func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var entries := _scan_kif_files()
	if entries.is_empty():
		_empty_hint.visible = true
	else:
		_empty_hint.visible = false
		for entry in entries:
			_list.add_child(_build_row(entry))

func _scan_kif_files() -> Array:
	var seen := {}  # absolute path → true (dedupe in case the same dir
	                # surfaces via two roots)
	var out: Array = []
	var roots: Array[String] = []
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false)
	if docs != "":
		roots.append(docs)
	roots.append(ProjectSettings.globalize_path("user://"))
	for root in roots:
		var d := DirAccess.open(root)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if not d.current_is_dir() and name.to_lower().ends_with(".kif"):
				var abs_path := "%s/%s" % [root, name]
				if not seen.has(abs_path):
					seen[abs_path] = true
					out.append({
						path = abs_path,
						name = name,
						mtime = FileAccess.get_modified_time(abs_path),
					})
			name = d.get_next()
		d.list_dir_end()
	out.sort_custom(func(a, b): return a.mtime > b.mtime)
	return out

func _build_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var open_btn := Button.new()
	open_btn.text = _describe(entry)
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_btn.custom_minimum_size = Vector2(0, 120)
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.add_theme_font_size_override("font_size", 24)
	open_btn.pressed.connect(_on_open.bind(entry.path))
	row.add_child(open_btn)

	var del_btn := Button.new()
	del_btn.text = "削除"
	del_btn.custom_minimum_size = Vector2(110, 88)
	del_btn.add_theme_font_size_override("font_size", 24)
	del_btn.pressed.connect(_on_delete_request.bind(entry.path))
	row.add_child(del_btn)

	return row

# Three-line summary for a row:
#   2026-10-29 18:51
#   先手 プレイヤー  対  後手 伊藤明 (Lv.4)
#   詰み 先手の勝ち・42手
# Header keys come from the KIF we write (開始日時 / 先手 / 後手 / 結果);
# files from other apps fall back to the file mtime, generic names, and a
# winner derived from the closing line + ply parity.
func _describe(entry: Dictionary) -> String:
	var info := _read_kif_summary(entry.path)
	var when: String = info.get("started_at", "")
	if when == "":
		when = _format_mtime(entry.mtime)
	var sente: String = info.get("sente", "")
	var gote: String = info.get("gote", "")
	if sente == "":
		sente = "？"
	if gote == "":
		gote = "？"
	var outcome: String = info.get("result", "")
	var terminator: String = info.get("terminator", "")
	var plies: int = int(info.get("plies", 0))
	if outcome == "":
		outcome = _outcome_from_terminator(terminator, plies)
	return "%s\n先手 %s  対  後手 %s\n%s・%d手" % [when, sente, gote, outcome, plies]

# Reads only what the row needs. KIF files are a few KB, and the list is
# rebuilt only on enter / delete, so a full read per file is fine.
func _read_kif_summary(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var in_moves := false
	var plies := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("*"):
			continue
		if not in_moves:
			if line.begins_with("手数"):
				in_moves = true
			elif line.begins_with("開始日時："):
				out["started_at"] = _format_kif_datetime(line.trim_prefix("開始日時："))
			elif line.begins_with("先手："):
				out["sente"] = line.trim_prefix("先手：")
			elif line.begins_with("後手："):
				out["gote"] = line.trim_prefix("後手：")
			elif line.begins_with("結果："):
				out["result"] = line.trim_prefix("結果：")
			continue
		# Move list: "<ply> <move or terminator> [(time)]".
		var parts := line.split(" ", false, 1)
		if parts.size() < 2:
			continue
		var body := parts[1].strip_edges()
		var is_term := false
		for t in _TERMINATORS:
			if body.begins_with(t):
				out["terminator"] = t
				is_term = true
				break
		if is_term:
			break
		plies += 1
	out["plies"] = plies
	return out

const _TERMINATORS: Array[String] = [
	"中断", "投了", "詰み", "千日手", "持将棋", "入玉勝ち", "反則勝ち", "反則負け", "不戦勝", "不戦敗",
]

# Winner for files without a 結果 header. The terminator's ply number
# is the move that was *not* played, so the last mover is the previous
# ply: odd plies are 先手's.
func _outcome_from_terminator(term: String, plies: int) -> String:
	var last_mover := "先手" if plies % 2 == 1 else "後手"
	var side_to_move := "後手" if plies % 2 == 1 else "先手"
	match term:
		"詰み", "投了", "反則負け", "不戦敗":
			return "%s %sの勝ち" % [term, last_mover]
		"入玉勝ち", "反則勝ち", "不戦勝":
			return "%s %sの勝ち" % [term, side_to_move]
		"千日手", "持将棋":
			return "%s 引き分け" % term
		"中断":
			return "中断"
		_:
			return "対局中"

# "2026/10/29 18:51:14" → "2026-10-29 18:51"; anything else passes through.
func _format_kif_datetime(raw: String) -> String:
	var r := raw.strip_edges()
	var m := r.split(" ", false)
	if m.size() >= 2:
		var hm := m[1].split(":")
		if hm.size() >= 2:
			return "%s %s:%s" % [m[0].replace("/", "-"), hm[0], hm[1]]
	return r

func _format_mtime(unix_ts: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_ts)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func _on_open(path: String) -> void:
	Settings.review_kif_path = path
	get_tree().change_scene_to_file("res://scenes/KifuReviewer.tscn")

func _on_delete_request(path: String) -> void:
	_pending_delete_path = path
	_delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if _pending_delete_path == "":
		return
	var err := DirAccess.remove_absolute(_pending_delete_path)
	if err != OK:
		push_warning("delete_kif: removal failed (%d) for %s" % [err, _pending_delete_path])
	_pending_delete_path = ""
	_refresh()
