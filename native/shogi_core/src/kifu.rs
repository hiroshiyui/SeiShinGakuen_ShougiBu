//! 棋譜 (game-record) formatting + compact move-log packing for save/resume.
//!
//! v1 omits the disambiguator suffix (右/左/直/上/寄/引) — when two pieces of
//! the same kind can reach the destination, the rendered line is still
//! unambiguous in human reading because the player saw the move on the
//! board. Disambiguator is a follow-up.

use crate::board::{Board, LogEntry};
use crate::types::{Color, Kind, Move, Square};

const FILE_DIGITS: [&str; 10] = ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"];
const RANK_KANJI: [&str; 10] = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];

fn piece_kanji(k: Kind) -> &'static str {
    match k {
        Kind::Pawn => "歩",
        Kind::Lance => "香",
        Kind::Knight => "桂",
        Kind::Silver => "銀",
        Kind::Gold => "金",
        Kind::Bishop => "角",
        Kind::Rook => "飛",
        Kind::King => "玉",
        Kind::PromotedPawn => "と",
        Kind::PromotedLance => "成香",
        Kind::PromotedKnight => "成桂",
        Kind::PromotedSilver => "成銀",
        Kind::Horse => "馬",
        Kind::Dragon => "龍",
    }
}

fn side_marker(c: Color) -> &'static str {
    if c.is_gote() { "☖" } else { "☗" }
}

/// One human-readable kifu row per log entry, in 1-based ply order.
/// Adjacent same-square recaptures collapse to 同 (per standard 棋譜).
pub fn log_to_lines(board: &Board) -> Vec<String> {
    let mut out = Vec::with_capacity(board.log.len());
    let mut prev_dest: Option<Square> = None;
    for (i, entry) in board.log.iter().enumerate() {
        let ply = board.starting_ply + i as u32;
        let mover = entry.by();
        let (to, piece, suffix) = match entry {
            LogEntry::Board { to, prev_kind, promoted, .. } => {
                let suf = if *promoted { "成" } else { "" };
                (*to, piece_kanji(*prev_kind), suf)
            }
            LogEntry::Drop { to, kind, .. } => (*to, piece_kanji(*kind), "打"),
        };
        let dest = if Some(to) == prev_dest {
            "同　".to_string()
        } else {
            format!("{}{}", FILE_DIGITS[to.file as usize], RANK_KANJI[to.rank as usize])
        };
        out.push(format!("{} {}{}{}{}", ply, side_marker(mover), dest, piece, suffix));
        prev_dest = Some(to);
    }
    out
}

// --- packing ---------------------------------------------------------------
//
// One i32 per move:
//   bit  0    : 1 = drop, 0 = board
//   bits 1-7  : (board) from-square index 0..80    | (drop) Kind 0..13
//   bits 8-14 : to-square index 0..80
//   bit  15   : (board) promote flag

#[inline]
fn sq_to_idx(sq: Square) -> u32 {
    ((sq.file - 1) as u32) * 9 + ((sq.rank - 1) as u32)
}

#[inline]
fn idx_to_sq(idx: u32) -> Square {
    Square::new((idx / 9 + 1) as i8, (idx % 9 + 1) as i8)
}

pub fn pack_move(mv: &Move) -> i32 {
    let bits: u32 = match *mv {
        Move::Board { from, to, promote } => {
            (sq_to_idx(from) & 0x7f) << 1
                | (sq_to_idx(to) & 0x7f) << 8
                | if promote { 1u32 << 15 } else { 0 }
        }
        Move::Drop { kind, to } => {
            1u32 | ((kind as u32 & 0x0f) << 1) | ((sq_to_idx(to) & 0x7f) << 8)
        }
    };
    bits as i32
}

pub fn unpack_move(packed: i32) -> Option<Move> {
    let bits = packed as u32;
    if bits & 1 != 0 {
        let kind = Kind::from_u8(((bits >> 1) & 0x0f) as u8)?;
        let to = idx_to_sq((bits >> 8) & 0x7f);
        if !to.in_bounds() {
            return None;
        }
        Some(Move::Drop { kind, to })
    } else {
        let from = idx_to_sq((bits >> 1) & 0x7f);
        let to = idx_to_sq((bits >> 8) & 0x7f);
        let promote = (bits >> 15) & 1 != 0;
        if !from.in_bounds() || !to.in_bounds() {
            return None;
        }
        Some(Move::Board { from, to, promote })
    }
}

// --- KIF export ------------------------------------------------------------
//
// Standard 柿木将棋 KIF text. Plays in any KIF viewer (Kifu for Windows,
// 81Dojo, Shogi GUI). Per-move time tracking is omitted — we don't keep
// clocks — and the trailing line is always 中断 because exporting mid-
// game is the common case (post-mortem review). On a finished game the
// caller is welcome to swap 中断 for 投了 / 詰み but viewers handle 中断
// as an in-progress save without complaint.

const FILE_DIGIT_ASCII: [&str; 10] = ["", "1", "2", "3", "4", "5", "6", "7", "8", "9"];

fn move_line(entry: &LogEntry, prev_dest: Option<Square>) -> String {
    let (to, piece, promote, from_or_drop) = match entry {
        LogEntry::Board { from, to, prev_kind, promoted, .. } => (
            *to,
            piece_kanji(*prev_kind),
            *promoted,
            format!("({}{})", FILE_DIGIT_ASCII[from.file as usize], from.rank),
        ),
        LogEntry::Drop { to, kind, .. } => (*to, piece_kanji(*kind), false, "打".to_string()),
    };
    let dest = if Some(to) == prev_dest {
        // KIF spells "same square" as `同　` (kanji + ZENKAKU space) so
        // the column alignment with `２四` etc. survives ASCII counting.
        "同　".to_string()
    } else {
        format!("{}{}", FILE_DIGITS[to.file as usize], RANK_KANJI[to.rank as usize])
    };
    let promo_marker = if promote { "成" } else { "" };
    format!("{}{}{}{}", dest, piece, promo_marker, from_or_drop)
}

pub fn to_kif(
    board: &Board,
    sente_name: &str,
    gote_name: &str,
    started_at: &str,
) -> String {
    let mut out = String::new();
    out.push_str("# ---- 清正学園将棋部 棋譜ファイル ----\n");
    out.push_str(&format!("開始日時：{}\n", started_at));
    out.push_str(&format!("先手：{}\n", sente_name));
    out.push_str(&format!("後手：{}\n", gote_name));
    out.push_str("手合割：平手\n");
    out.push_str("手数----指手---------消費時間--\n");

    let mut prev_dest: Option<Square> = None;
    for (i, entry) in board.log.iter().enumerate() {
        let ply = board.starting_ply + i as u32;
        out.push_str(&format!("{:>4} {}\n", ply, move_line(entry, prev_dest)));
        let to = match entry {
            LogEntry::Board { to, .. } | LogEntry::Drop { to, .. } => *to,
        };
        prev_dest = Some(to);
    }
    let next_ply = board.starting_ply + board.log.len() as u32;
    out.push_str(&format!("{:>4} 中断\n", next_ply));
    out
}

// --- KIF parser ------------------------------------------------------------
//
// Tolerates the export format we emit plus the common Kifu-for-Windows
// variants: per-move time annotation `( H:MM/HH:MM:SS)`, 不成 suffix,
// and trailing terminators (中断 / 投了 / 詰み / 千日手 / 持将棋). Everything
// before the `手数----` header line is treated as metadata and skipped.

#[derive(Debug, PartialEq, Eq)]
pub enum KifError {
    HeaderMissing,
    BadMoveLine(String),
    UnknownPiece(String),
}

impl std::fmt::Display for KifError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            KifError::HeaderMissing => write!(f, "kifu: missing 手数---- header"),
            KifError::BadMoveLine(s) => write!(f, "kifu: cannot parse move line: {s}"),
            KifError::UnknownPiece(s) => write!(f, "kifu: unknown piece kanji: {s}"),
        }
    }
}

fn file_from_zenkaku(c: char) -> Option<i8> {
    match c {
        '１' => Some(1), '２' => Some(2), '３' => Some(3),
        '４' => Some(4), '５' => Some(5), '６' => Some(6),
        '７' => Some(7), '８' => Some(8), '９' => Some(9),
        _ => None,
    }
}

fn rank_from_kanji(c: char) -> Option<i8> {
    match c {
        '一' => Some(1), '二' => Some(2), '三' => Some(3),
        '四' => Some(4), '五' => Some(5), '六' => Some(6),
        '七' => Some(7), '八' => Some(8), '九' => Some(9),
        _ => None,
    }
}

fn kind_from_kanji(s: &str) -> Option<Kind> {
    match s {
        "歩" => Some(Kind::Pawn),
        "香" => Some(Kind::Lance),
        "桂" => Some(Kind::Knight),
        "銀" => Some(Kind::Silver),
        "金" => Some(Kind::Gold),
        "角" => Some(Kind::Bishop),
        "飛" => Some(Kind::Rook),
        "玉" | "王" => Some(Kind::King),
        "と" => Some(Kind::PromotedPawn),
        "成香" | "杏" => Some(Kind::PromotedLance),
        "成桂" | "圭" => Some(Kind::PromotedKnight),
        "成銀" | "全" => Some(Kind::PromotedSilver),
        "馬" => Some(Kind::Horse),
        "龍" | "竜" => Some(Kind::Dragon),
        _ => None,
    }
}

const TERMINATORS: &[&str] = &["中断", "投了", "詰み", "千日手", "持将棋", "反則勝ち", "反則負け"];

/// Parse a KIF document into the same packed-i32 log shape `pack_log`
/// produces, ready to feed into `apply_packed`.
pub fn parse_kif(text: &str) -> Result<Vec<i32>, KifError> {
    let mut lines = text.lines();
    // Find the move-list header.
    let mut found_header = false;
    for line in lines.by_ref() {
        if line.starts_with("手数") {
            found_header = true;
            break;
        }
    }
    if !found_header {
        return Err(KifError::HeaderMissing);
    }

    let mut packed: Vec<i32> = Vec::new();
    let mut prev_dest: Option<Square> = None;
    for raw in lines {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with('*') {
            continue;
        }
        // Drop the leading ply number ("   3 ７六歩(77)" → "７六歩(77)").
        let after_ply = match line.split_once(char::is_whitespace) {
            Some((_, rest)) => rest.trim_start(),
            None => continue,
        };
        // Strip trailing "( H:MM/HH:MM:SS)" time annotation if present.
        // Kifu-for-Windows pads the move text with spaces before the time
        // block so the timestamp lines up in fixed-width columns; trim
        // those off before handing the move to parse_move().
        let move_text = match after_ply.split_once(" (") {
            Some((m, _time)) => m.trim_end(),
            None => after_ply.trim_end(),
        };
        if TERMINATORS.iter().any(|t| move_text.starts_with(t)) {
            break;
        }
        let mv = parse_move(move_text, prev_dest)?;
        packed.push(pack_move(&mv));
        prev_dest = Some(mv.destination());
    }
    Ok(packed)
}

fn parse_move(text: &str, prev_dest: Option<Square>) -> Result<Move, KifError> {
    let bad = || KifError::BadMoveLine(text.to_string());
    let mut chars = text.chars().peekable();
    let first = chars.next().ok_or_else(bad)?;
    let to: Square;
    if first == '同' {
        // KIF spells same-square as `同　` (with a ZENKAKU space). Drop
        // one optional whitespace-ish char before the piece kanji.
        if let Some(&next) = chars.peek() {
            if next == '　' || next.is_whitespace() {
                chars.next();
            }
        }
        to = prev_dest.ok_or_else(bad)?;
    } else {
        let file = file_from_zenkaku(first).ok_or_else(bad)?;
        let rank_char = chars.next().ok_or_else(bad)?;
        let rank = rank_from_kanji(rank_char).ok_or_else(bad)?;
        to = Square::new(file, rank);
    }

    // Remaining: piece kanji [+ 成 | 不成] + (NN) | 打.
    let rest: String = chars.collect();
    let (piece_str, after_piece) = split_piece_and_tail(&rest)?;
    let piece = kind_from_kanji(piece_str).ok_or_else(|| KifError::UnknownPiece(piece_str.to_string()))?;

    let (promoted, tail) = if let Some(rest) = after_piece.strip_prefix("成") {
        (true, rest)
    } else if let Some(rest) = after_piece.strip_prefix("不成") {
        (false, rest)
    } else {
        (false, after_piece)
    };

    if let Some(rest) = tail.strip_prefix('打') {
        if !rest.is_empty() {
            return Err(bad());
        }
        // Drops can't promote, and the kanji must be the unpromoted base.
        if promoted || piece.is_promoted() {
            return Err(bad());
        }
        Ok(Move::Drop { kind: piece, to })
    } else if let Some(rest) = tail.strip_prefix('(') {
        let rest = rest.strip_suffix(')').ok_or_else(bad)?;
        if rest.len() != 2 {
            return Err(bad());
        }
        let bytes = rest.as_bytes();
        let from_file = (bytes[0] as char).to_digit(10).ok_or_else(bad)? as i8;
        let from_rank = (bytes[1] as char).to_digit(10).ok_or_else(bad)? as i8;
        Ok(Move::Board {
            from: Square::new(from_file, from_rank),
            to,
            promote: promoted,
        })
    } else {
        Err(bad())
    }
}

// Split off the piece kanji at the start of `s`. Multi-char pieces
// (成香 / 成桂 / 成銀) get matched first so they don't degrade to "成" + "香".
fn split_piece_and_tail(s: &str) -> Result<(&str, &str), KifError> {
    for prefix in ["成香", "成桂", "成銀"] {
        if s.starts_with(prefix) {
            return Ok((&s[..prefix.len()], &s[prefix.len()..]));
        }
    }
    let first = s.chars().next().ok_or_else(|| KifError::BadMoveLine(s.to_string()))?;
    let len = first.len_utf8();
    Ok((&s[..len], &s[len..]))
}

pub fn pack_log(board: &Board) -> Vec<i32> {
    board
        .log
        .iter()
        .map(|entry| {
            let mv = match entry {
                LogEntry::Board { from, to, promoted, .. } => Move::Board {
                    from: *from,
                    to: *to,
                    promote: *promoted,
                },
                LogEntry::Drop { kind, to, .. } => Move::Drop { kind: *kind, to: *to },
            };
            pack_move(&mv)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::board::Board;

    #[test]
    fn pack_unpack_round_trip_board_move() {
        let mv = Move::Board {
            from: Square::new(7, 7),
            to: Square::new(7, 6),
            promote: false,
        };
        assert_eq!(unpack_move(pack_move(&mv)), Some(mv));
    }

    #[test]
    fn pack_unpack_round_trip_promotion() {
        let mv = Move::Board {
            from: Square::new(2, 8),
            to: Square::new(2, 2),
            promote: true,
        };
        assert_eq!(unpack_move(pack_move(&mv)), Some(mv));
    }

    #[test]
    fn pack_unpack_round_trip_drop() {
        let mv = Move::Drop { kind: Kind::Pawn, to: Square::new(5, 5) };
        assert_eq!(unpack_move(pack_move(&mv)), Some(mv));
    }

    #[test]
    fn replay_packed_log_reproduces_position() {
        // Walk a few opening moves, pack the log, replay on a fresh board,
        // and assert the SFEN matches.
        let mut a = Board::default();
        let plies = [
            Move::Board { from: Square::new(7, 7), to: Square::new(7, 6), promote: false },
            Move::Board { from: Square::new(3, 3), to: Square::new(3, 4), promote: false },
            Move::Board { from: Square::new(2, 7), to: Square::new(2, 6), promote: false },
            Move::Board { from: Square::new(8, 3), to: Square::new(8, 4), promote: false },
        ];
        for &mv in &plies {
            assert!(a.apply_move(mv));
        }
        let packed = pack_log(&a);
        assert_eq!(packed.len(), plies.len());

        let mut b = Board::default();
        for &p in &packed {
            let mv = unpack_move(p).expect("unpack");
            assert!(b.apply_move(mv));
        }
        assert_eq!(crate::sfen::to_sfen(&a), crate::sfen::to_sfen(&b));
    }

    #[test]
    fn kifu_lines_format_correctly() {
        let mut b = Board::default();
        // 1. ☗7六歩
        b.apply_move(Move::Board {
            from: Square::new(7, 7),
            to: Square::new(7, 6),
            promote: false,
        });
        // 2. ☖3四歩
        b.apply_move(Move::Board {
            from: Square::new(3, 3),
            to: Square::new(3, 4),
            promote: false,
        });
        let lines = log_to_lines(&b);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0], "1 ☗７六歩");
        assert_eq!(lines[1], "2 ☖３四歩");
    }

    #[test]
    fn parse_kif_round_trips_through_to_kif() {
        let mut a = Board::default();
        let plies = [
            // ７六歩 / ３四歩 / ２二角成 / 同銀 (capture-promote then recapture)
            Move::Board { from: Square::new(7, 7), to: Square::new(7, 6), promote: false },
            Move::Board { from: Square::new(3, 3), to: Square::new(3, 4), promote: false },
            Move::Board { from: Square::new(8, 8), to: Square::new(2, 2), promote: true },
            Move::Board { from: Square::new(3, 1), to: Square::new(2, 2), promote: false },
        ];
        for &mv in &plies {
            assert!(a.apply_move(mv));
        }
        let kif_text = to_kif(&a, "プレイヤー", "加藤", "2026/04/28 12:00:00");
        let parsed = parse_kif(&kif_text).expect("parse");
        let original = pack_log(&a);
        assert_eq!(parsed, original, "round-trip diverged");
    }

    #[test]
    fn parse_kif_handles_drops_and_terminator() {
        // Synthetic minimum KIF — single drop, then 中断.
        let kif = "\
手数----指手---------消費時間--
   1 ５五歩打
   2 中断
";
        let packed = parse_kif(kif).expect("parse");
        assert_eq!(packed.len(), 1);
        let mv = unpack_move(packed[0]).unwrap();
        assert_eq!(mv, Move::Drop { kind: Kind::Pawn, to: Square::new(5, 5) });
    }

    #[test]
    fn parse_kif_tolerates_time_annotation() {
        let kif = "\
手数----指手---------消費時間--
   1 ７六歩(77)        ( 0:01/00:00:01)
   2 投了
";
        let packed = parse_kif(kif).expect("parse");
        assert_eq!(packed.len(), 1);
    }

    #[test]
    fn to_kif_emits_header_moves_and_chuudan() {
        let mut b = Board::default();
        b.apply_move(Move::Board {
            from: Square::new(7, 7),
            to: Square::new(7, 6),
            promote: false,
        });
        b.apply_move(Move::Board {
            from: Square::new(3, 3),
            to: Square::new(3, 4),
            promote: false,
        });
        let kif = to_kif(&b, "プレイヤー", "加藤よしこ", "2026/04/28 12:00:00");
        assert!(kif.contains("先手：プレイヤー"));
        assert!(kif.contains("後手：加藤よしこ"));
        assert!(kif.contains("手合割：平手"));
        assert!(kif.contains("   1 ７六歩(77)"));
        assert!(kif.contains("   2 ３四歩(33)"));
        assert!(kif.trim_end().ends_with("中断"));
    }

    #[test]
    fn kifu_collapses_recapture_to_dou() {
        let mut b = Board::default();
        // Force a recapture: 7六歩 7六... actually let's just construct
        // synthetically by checking the collapse rule via two moves to the
        // same square. We use the only easy path: Sente moves a piece to
        // 5五, Gote moves a piece to 5五 capturing — same destination.
        b.apply_move(Move::Board {
            from: Square::new(8, 8),
            to: Square::new(2, 2),
            promote: false,
        });
        // After ☗2二角 (capture-bishop), the same-dest follow-up:
        b.apply_move(Move::Board {
            from: Square::new(3, 1),
            to: Square::new(2, 2),
            promote: false,
        });
        let lines = log_to_lines(&b);
        assert!(lines[1].contains("同"), "expected 同 in line 2: {}", lines[1]);
    }
}
