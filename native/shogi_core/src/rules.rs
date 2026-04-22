//! Rule filters and end-state detection.

use crate::board::Board;
use crate::movegen::{generate_drops, generate_moves_from};
use crate::types::{Color, Kind, Move, Square};

pub fn is_square_attacked(board: &Board, target: Square, attacker: Color) -> bool {
    let mut buf = Vec::with_capacity(16);
    for r in 1..=9 {
        for f in 1..=9 {
            let sq = Square::new(f, r);
            let Some(piece) = board.piece_at(sq) else { continue };
            if piece.color != attacker {
                continue;
            }
            buf.clear();
            generate_moves_from(board, sq, &mut buf);
            if buf.iter().any(|m| m.destination() == target) {
                return true;
            }
        }
    }
    false
}

pub fn is_check(board: &Board, color: Color) -> bool {
    let Some(king) = board.find_king(color) else { return false };
    is_square_attacked(board, king, color.flip())
}

/// True if `mv`, applied by the side-to-move, does not leave that side
/// in check. Mutates `board` internally (apply + undo); leaves it as it
/// was on entry.
fn leaves_king_safe(board: &mut Board, mv: Move) -> bool {
    let side = board.side_to_move;
    if !board.apply_move(mv) {
        return false;
    }
    let safe = !is_check(board, side);
    board.undo_move();
    safe
}

pub fn legal_moves_from(board: &mut Board, from: Square) -> Vec<Move> {
    let Some(piece) = board.piece_at(from) else { return vec![] };
    if piece.color != board.side_to_move {
        return vec![];
    }
    let mut pseudo = Vec::new();
    generate_moves_from(board, from, &mut pseudo);
    pseudo.retain_mut(|m| leaves_king_safe(board, *m));
    pseudo
}

fn has_own_unpromoted_pawn_on_file(board: &Board, color: Color, file: i8) -> bool {
    for r in 1..=9 {
        if let Some(p) = board.piece_at(Square::new(file, r)) {
            if p.color == color && p.kind == Kind::Pawn {
                return true;
            }
        }
    }
    false
}

pub fn legal_drops(board: &mut Board, kind: Kind) -> Vec<Move> {
    let color = board.side_to_move;
    if board.hand(color).get(&kind).copied().unwrap_or(0) == 0 {
        return vec![];
    }
    let mut pseudo = Vec::new();
    generate_drops(board, color, kind, &mut pseudo);
    let mut out = Vec::with_capacity(pseudo.len());
    for mv in pseudo {
        let Move::Drop { to, .. } = mv else { unreachable!() };
        if kind == Kind::Pawn && has_own_unpromoted_pawn_on_file(board, color, to.file) {
            continue;
        }
        if !leaves_king_safe(board, mv) {
            continue;
        }
        if kind == Kind::Pawn && is_uchifuzume(board, mv) {
            continue;
        }
        out.push(mv);
    }
    out
}

fn is_uchifuzume(board: &mut Board, drop_move: Move) -> bool {
    // Drop is assumed self-check-safe already. If the resulting position
    // leaves the opponent in check AND they have no legal response, it is
    // a pawn-drop mate — illegal.
    if !board.apply_move(drop_move) {
        return false;
    }
    let opp = board.side_to_move;
    let mate = is_check(board, opp) && !has_any_legal_move(board);
    board.undo_move();
    mate
}

pub fn has_any_legal_move(board: &mut Board) -> bool {
    let side = board.side_to_move;
    for r in 1..=9 {
        for f in 1..=9 {
            let sq = Square::new(f, r);
            if let Some(p) = board.piece_at(sq) {
                if p.color == side && !legal_moves_from(board, sq).is_empty() {
                    return true;
                }
            }
        }
    }
    let kinds: Vec<Kind> = board.hand(side).keys().copied().collect();
    for k in kinds {
        if !legal_drops(board, k).is_empty() {
            return true;
        }
    }
    false
}

pub fn is_checkmate(board: &mut Board) -> bool {
    let side = board.side_to_move;
    is_check(board, side) && !has_any_legal_move(board)
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum SennichiteStatus {
    None,
    Draw,
    SenteLoses,
    GoteLoses,
}

pub fn detect_sennichite(board: &Board) -> SennichiteStatus {
    let key = crate::sfen::position_key(board);
    if board.position_counts.get(&key).copied().unwrap_or(0) < 4 {
        return SennichiteStatus::None;
    }
    // Find the first log index whose position-key-after equals the current
    // key — the moves after that form the repeating cycle.
    let Some(start_idx) = board
        .log
        .iter()
        .position(|e| e.position_key_after() == key)
    else {
        return SennichiteStatus::Draw;
    };
    let mut sente_moved = false;
    let mut gote_moved = false;
    let mut sente_all_checks = true;
    let mut gote_all_checks = true;
    for entry in &board.log[start_idx + 1..] {
        let was_check = entry.was_check();
        match entry.by() {
            Color::Sente => {
                sente_moved = true;
                if !was_check {
                    sente_all_checks = false;
                }
            }
            Color::Gote => {
                gote_moved = true;
                if !was_check {
                    gote_all_checks = false;
                }
            }
        }
    }
    match (
        sente_moved && sente_all_checks,
        gote_moved && gote_all_checks,
    ) {
        (true, false) => SennichiteStatus::SenteLoses,
        (false, true) => SennichiteStatus::GoteLoses,
        _ => SennichiteStatus::Draw,
    }
}

// ---- jishogi / 入玉 ---------------------------------------------------------

pub fn king_entered(board: &Board, color: Color) -> bool {
    let Some(k) = board.find_king(color) else { return false };
    match color {
        Color::Sente => k.rank <= 3,
        Color::Gote => k.rank >= 7,
    }
}

fn jishogi_value(kind: Kind) -> u32 {
    match kind {
        Kind::Rook | Kind::Bishop | Kind::Dragon | Kind::Horse => 5,
        Kind::King => 0,
        _ => 1,
    }
}

pub fn jishogi_points(board: &Board, color: Color) -> u32 {
    let mut total: u32 = 0;
    for r in 1..=9 {
        for f in 1..=9 {
            let sq = Square::new(f, r);
            let Some(p) = board.piece_at(sq) else { continue };
            if p.color != color || p.kind == Kind::King {
                continue;
            }
            let in_opp_camp = match color {
                Color::Sente => r <= 3,
                Color::Gote => r >= 7,
            };
            if in_opp_camp {
                total += jishogi_value(p.kind);
            }
        }
    }
    for (&k, &n) in board.hand(color) {
        total += jishogi_value(k) * n;
    }
    total
}
