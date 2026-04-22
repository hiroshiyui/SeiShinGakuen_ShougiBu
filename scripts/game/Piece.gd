class_name Piece
extends RefCounted

enum Kind {
	PAWN, LANCE, KNIGHT, SILVER, GOLD, BISHOP, ROOK, KING,
	PROMOTED_PAWN, PROMOTED_LANCE, PROMOTED_KNIGHT, PROMOTED_SILVER,
	HORSE, DRAGON,
}

const KANJI := {
	Kind.PAWN: "歩", Kind.LANCE: "香", Kind.KNIGHT: "桂", Kind.SILVER: "銀",
	Kind.GOLD: "金", Kind.BISHOP: "角", Kind.ROOK: "飛", Kind.KING: "玉",
	Kind.PROMOTED_PAWN: "と", Kind.PROMOTED_LANCE: "杏",
	Kind.PROMOTED_KNIGHT: "圭", Kind.PROMOTED_SILVER: "全",
	Kind.HORSE: "馬", Kind.DRAGON: "龍",
}

const PROMOTES_TO := {
	Kind.PAWN: Kind.PROMOTED_PAWN,
	Kind.LANCE: Kind.PROMOTED_LANCE,
	Kind.KNIGHT: Kind.PROMOTED_KNIGHT,
	Kind.SILVER: Kind.PROMOTED_SILVER,
	Kind.BISHOP: Kind.HORSE,
	Kind.ROOK: Kind.DRAGON,
}

const BASE_OF := {
	Kind.PROMOTED_PAWN: Kind.PAWN,
	Kind.PROMOTED_LANCE: Kind.LANCE,
	Kind.PROMOTED_KNIGHT: Kind.KNIGHT,
	Kind.PROMOTED_SILVER: Kind.SILVER,
	Kind.HORSE: Kind.BISHOP,
	Kind.DRAGON: Kind.ROOK,
}

const SFEN_LETTER := {
	Kind.PAWN: "P", Kind.LANCE: "L", Kind.KNIGHT: "N", Kind.SILVER: "S",
	Kind.GOLD: "G", Kind.BISHOP: "B", Kind.ROOK: "R", Kind.KING: "K",
	Kind.PROMOTED_PAWN: "+P", Kind.PROMOTED_LANCE: "+L",
	Kind.PROMOTED_KNIGHT: "+N", Kind.PROMOTED_SILVER: "+S",
	Kind.HORSE: "+B", Kind.DRAGON: "+R",
}

var kind: int
var is_gote: bool

func _init(p_kind: int, p_is_gote: bool) -> void:
	kind = p_kind
	is_gote = p_is_gote

func can_promote() -> bool:
	return kind in PROMOTES_TO

func is_promoted() -> bool:
	return kind in BASE_OF

func base_kind() -> int:
	return BASE_OF.get(kind, kind)

func kanji_text() -> String:
	if kind == Kind.KING:
		return "王" if is_gote else "玉"
	return KANJI[kind]
