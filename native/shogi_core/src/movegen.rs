//! Pseudo-legal move generation (geometry + must-promote pruning).
//! Self-check, nifu, and uchifuzume filters live in `rules`.
//!
//! Deltas are written in sente's frame (forward = -rank). The gote frame
//! is obtained by negating the rank delta via `Color::forward_sign`.

use crate::board::Board;
use crate::types::{Color, Kind, Move, Piece, Square};

// ---- movement tables (all in sente's frame) ----

const GOLD_STEPS: &[(i8, i8)] = &[
    (0, -1), (1, -1), (-1, -1),
    (1, 0),  (-1, 0),
    (0, 1),
];
const KING_STEPS: &[(i8, i8)] = &[
    (-1, -1), (0, -1), (1, -1),
    (-1, 0),           (1, 0),
    (-1, 1),  (0, 1),  (1, 1),
];
const SILVER_STEPS: &[(i8, i8)] = &[
    (0, -1), (1, -1), (-1, -1),
    (1, 1),  (-1, 1),
];
const DIAG: &[(i8, i8)] = &[(1, -1), (-1, -1), (1, 1), (-1, 1)];
const ORTHO: &[(i8, i8)] = &[(0, -1), (0, 1), (1, 0), (-1, 0)];

fn steps_for(kind: Kind) -> &'static [(i8, i8)] {
    match kind {
        Kind::Pawn => &[(0, -1)],
        Kind::Knight => &[(1, -2), (-1, -2)],
        Kind::Silver => SILVER_STEPS,
        Kind::Gold
        | Kind::PromotedPawn
        | Kind::PromotedLance
        | Kind::PromotedKnight
        | Kind::PromotedSilver => GOLD_STEPS,
        Kind::King => KING_STEPS,
        Kind::Horse => ORTHO,
        Kind::Dragon => DIAG,
        _ => &[],
    }
}

fn rays_for(kind: Kind) -> &'static [(i8, i8)] {
    match kind {
        Kind::Lance => &[(0, -1)],
        Kind::Bishop | Kind::Horse => DIAG,
        Kind::Rook | Kind::Dragon => ORTHO,
        _ => &[],
    }
}

#[inline]
fn flip_delta(delta: (i8, i8), color: Color) -> (i8, i8) {
    (delta.0, delta.1 * color.forward_sign())
}

#[inline]
pub fn in_promo_zone(color: Color, rank: i8) -> bool {
    match color {
        Color::Sente => rank <= 3,
        Color::Gote => rank >= 7,
    }
}

/// A piece landing on `to` with no promotion would be unable to move on
/// its next turn — triggers the must-promote rule.
pub fn would_be_dead(piece: Piece, to: Square) -> bool {
    match (piece.color, piece.kind) {
        (Color::Sente, Kind::Pawn | Kind::Lance) => to.rank == 1,
        (Color::Sente, Kind::Knight) => to.rank <= 2,
        (Color::Gote, Kind::Pawn | Kind::Lance) => to.rank == 9,
        (Color::Gote, Kind::Knight) => to.rank >= 8,
        _ => false,
    }
}

/// Pseudo-legal moves originating at `from`. No self-check filtering.
pub fn generate_moves_from(board: &Board, from: Square, out: &mut Vec<Move>) {
    let Some(piece) = board.piece_at(from) else { return };
    // Single-step destinations.
    for &d in steps_for(piece.kind) {
        let (df, dr) = flip_delta(d, piece.color);
        let to = Square::new(from.file + df, from.rank + dr);
        if !to.in_bounds() {
            continue;
        }
        match board.piece_at(to) {
            Some(p) if p.color == piece.color => continue,
            _ => {}
        }
        emit_with_promotions(piece, from, to, out);
    }
    // Sliding destinations.
    for &d in rays_for(piece.kind) {
        let (df, dr) = flip_delta(d, piece.color);
        let mut to = Square::new(from.file + df, from.rank + dr);
        while to.in_bounds() {
            match board.piece_at(to) {
                None => emit_with_promotions(piece, from, to, out),
                Some(p) => {
                    if p.color != piece.color {
                        emit_with_promotions(piece, from, to, out);
                    }
                    break;
                }
            }
            to = Square::new(to.file + df, to.rank + dr);
        }
    }
}

fn emit_with_promotions(piece: Piece, from: Square, to: Square, out: &mut Vec<Move>) {
    let can_promote = piece.kind.can_promote()
        && (in_promo_zone(piece.color, from.rank) || in_promo_zone(piece.color, to.rank));
    let dead_unless_promote = would_be_dead(piece, to);
    if !dead_unless_promote {
        out.push(Move::Board { from, to, promote: false });
    }
    if can_promote {
        out.push(Move::Board { from, to, promote: true });
    }
}

/// Legal-geometry drop squares for a hand piece of `kind`. Does not
/// enforce nifu / uchifuzume / self-check — those are rule filters.
pub fn generate_drops(board: &Board, color: Color, kind: Kind, out: &mut Vec<Move>) {
    let dummy = Piece::new(kind, color);
    for r in 1..=9 {
        for f in 1..=9 {
            let to = Square::new(f, r);
            if board.piece_at(to).is_some() {
                continue;
            }
            if would_be_dead(dummy, to) {
                continue;
            }
            out.push(Move::Drop { kind, to });
        }
    }
}
