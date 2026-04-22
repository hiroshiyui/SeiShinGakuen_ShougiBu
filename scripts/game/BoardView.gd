class_name BoardView
extends AspectRatioContainer

const SquareScene := preload("res://scenes/game/Square.tscn")
const SquareScript := preload("res://scripts/game/Square.gd")

# [file, rank, kanji, is_gote]
const STARTING_POSITION := [
	[9, 1, "香", true], [8, 1, "桂", true], [7, 1, "銀", true], [6, 1, "金", true],
	[5, 1, "王", true], [4, 1, "金", true], [3, 1, "銀", true], [2, 1, "桂", true], [1, 1, "香", true],
	[8, 2, "飛", true], [2, 2, "角", true],
	[9, 3, "歩", true], [8, 3, "歩", true], [7, 3, "歩", true], [6, 3, "歩", true], [5, 3, "歩", true],
	[4, 3, "歩", true], [3, 3, "歩", true], [2, 3, "歩", true], [1, 3, "歩", true],
	[9, 7, "歩", false], [8, 7, "歩", false], [7, 7, "歩", false], [6, 7, "歩", false], [5, 7, "歩", false],
	[4, 7, "歩", false], [3, 7, "歩", false], [2, 7, "歩", false], [1, 7, "歩", false],
	[8, 8, "角", false], [2, 8, "飛", false],
	[9, 9, "香", false], [8, 9, "桂", false], [7, 9, "銀", false], [6, 9, "金", false],
	[5, 9, "玉", false], [4, 9, "金", false], [3, 9, "銀", false], [2, 9, "桂", false], [1, 9, "香", false],
]

const RANK_KANJI := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

@onready var _grid: GridContainer = $Grid

var _squares: Dictionary = {}
var _selected_key: Vector2i = Vector2i(0, 0)

func _ready() -> void:
	_build_grid()
	_place_starting_position()

func _build_grid() -> void:
	for row in 9:
		for col in 9:
			var file := 9 - col
			var rank := row + 1
			var sq: SquareScript = SquareScene.instantiate()
			sq.file = file
			sq.rank = rank
			sq.tapped.connect(_on_square_tapped)
			_grid.add_child(sq)
			_squares[Vector2i(file, rank)] = sq

func _place_starting_position() -> void:
	for entry in STARTING_POSITION:
		var key := Vector2i(entry[0], entry[1])
		_squares[key].set_piece(entry[2], entry[3])

func _on_square_tapped(file: int, rank: int) -> void:
	var key := Vector2i(file, rank)
	if _selected_key == key:
		_squares[key].set_highlight(false)
		_selected_key = Vector2i(0, 0)
		print("[board] deselect %d%s" % [file, RANK_KANJI[rank]])
		return
	if _selected_key != Vector2i(0, 0):
		_squares[_selected_key].set_highlight(false)
	_squares[key].set_highlight(true)
	_selected_key = key
	print("[board] tap %d%s" % [file, RANK_KANJI[rank]])
