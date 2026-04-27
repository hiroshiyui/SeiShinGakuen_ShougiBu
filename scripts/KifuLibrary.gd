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
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
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
	open_btn.text = "%s\n%s" % [entry.name, _format_mtime(entry.mtime)]
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_btn.custom_minimum_size = Vector2(0, 64)
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.add_theme_font_size_override("font_size", 18)
	open_btn.pressed.connect(_on_open.bind(entry.path))
	row.add_child(open_btn)

	var del_btn := Button.new()
	del_btn.text = "削除"
	del_btn.custom_minimum_size = Vector2(96, 64)
	del_btn.add_theme_font_size_override("font_size", 18)
	del_btn.pressed.connect(_on_delete_request.bind(entry.path))
	row.add_child(del_btn)

	return row

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
