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
