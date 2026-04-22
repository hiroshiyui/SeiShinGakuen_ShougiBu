//! SFEN serialization. Parser is TODO — full import isn't needed until
//! Phase 5 (AI hookup wants to round-trip positions).

use crate::board::{Board, HAND_ORDER};
use crate::types::{Color, Square};

/// Position key used for sennichite: `"<board> <side> <hand>"` with no
/// move-number field.
pub fn position_key(board: &Board) -> String {
    let side = match board.side_to_move {
        Color::Sente => 'b',
        Color::Gote => 'w',
    };
    format!("{} {} {}", board_sfen(board), side, hand_sfen(board))
}

/// Full SFEN including the ply-counter field.
pub fn to_sfen(board: &Board) -> String {
    format!("{} {}", position_key(board), board.log.len() + 1)
}

fn board_sfen(board: &Board) -> String {
    let mut rows: Vec<String> = Vec::with_capacity(9);
    for r in 1..=9 {
        let mut row = String::new();
        let mut empty = 0u32;
        for f in (1..=9).rev() {
            match board.piece_at(Square::new(f, r)) {
                None => empty += 1,
                Some(p) => {
                    if empty > 0 {
                        row.push_str(&empty.to_string());
                        empty = 0;
                    }
                    if p.kind.is_promoted() {
                        row.push('+');
                    }
                    let letter = p.kind.sfen_letter();
                    if p.color.is_gote() {
                        row.push(letter.to_ascii_lowercase());
                    } else {
                        row.push(letter);
                    }
                }
            }
        }
        if empty > 0 {
            row.push_str(&empty.to_string());
        }
        rows.push(row);
    }
    rows.join("/")
}

fn hand_sfen(board: &Board) -> String {
    let mut s = String::new();
    for color in [Color::Sente, Color::Gote] {
        let h = board.hand(color);
        for &kind in HAND_ORDER.iter() {
            let n = h.get(&kind).copied().unwrap_or(0);
            if n == 0 {
                continue;
            }
            if n > 1 {
                s.push_str(&n.to_string());
            }
            let letter = kind.sfen_letter();
            if color.is_gote() {
                s.push(letter.to_ascii_lowercase());
            } else {
                s.push(letter);
            }
        }
    }
    if s.is_empty() {
        s.push('-');
    }
    s
}
