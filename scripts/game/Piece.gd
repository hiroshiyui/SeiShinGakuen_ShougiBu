class_name Piece
extends RefCounted

# Piece kinds — integer discriminants match the Rust `Kind` enum.
# The native ShogiCore owns all state; this class is now a pure namespace
# for UI-side labeling (kanji text, SFEN letters, promotion tables).

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

const HAND_ORDER := [
	Kind.ROOK, Kind.BISHOP, Kind.GOLD, Kind.SILVER,
	Kind.KNIGHT, Kind.LANCE, Kind.PAWN,
]

static func kanji_for(kind: int, is_gote: bool) -> String:
	if kind == Kind.KING:
		return "王" if is_gote else "玉"
	return KANJI[kind]
