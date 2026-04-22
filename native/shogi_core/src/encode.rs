//! (45,9,9) board-to-tensor encoder, byte-parity with ShogiDojo's
//! `shogi_dojo.alphazero.encoding.encode_position`.
//!
//! Plane layout:
//!   0..=13   own 14 piece kinds (Pawn..Dragon, in Kind-discriminant order)
//!   14..=27  opponent 14 piece kinds
//!   28..=34  own hand piece counts (7 droppable kinds, normalised by max)
//!   35..=41  opponent hand piece counts
//!   42       repetition count (min(r, 3) / 3.0)
//!   43       side-to-move constant (always 1.0 after perspective flip)
//!   44       move-number (min(ply, 200) / 200.0)
//!
//! ShogiDojo applies a 180° perspective flip whenever the side-to-move is
//! white/gote, so the network always sees "my king at the bottom, forward
//! = decreasing y". We reproduce that exactly.

use crate::board::Board;
use crate::types::{Color, Kind, Square};

pub const NUM_INPUT_CHANNELS: usize = 45;
pub const NUM_RANKS: usize = 9;
pub const NUM_FILES: usize = 9;
pub const PLANE_STRIDE: usize = NUM_RANKS * NUM_FILES; // 81

const OWN_PIECE_BASE: usize = 0;
const OPP_PIECE_BASE: usize = 14;
const OWN_HAND_BASE: usize = 28;
const OPP_HAND_BASE: usize = 35;
const REP_PLANE: usize = 42;
const STM_PLANE: usize = 43;
const PLY_PLANE: usize = 44;

const REPETITION_CAP: u32 = 3;
const PLY_CAP: u32 = 200;

/// Droppable kinds in ShogiDojo's order (matches python-shogi hand order).
const HAND_KINDS: [Kind; 7] = [
    Kind::Pawn, Kind::Lance, Kind::Knight, Kind::Silver,
    Kind::Gold, Kind::Bishop, Kind::Rook,
];
/// Max hand count per kind — the denominator of the normalised count plane.
const HAND_MAX: [f32; 7] = [18.0, 4.0, 4.0, 4.0, 4.0, 2.0, 2.0];

/// Convert an in-bounds `Square` to ShogiDojo's (y, x) pair *before* any
/// perspective flip. ShogiDojo follows python-shogi: square 0 = "9a" =
/// our (file=9, rank=1).
#[inline]
fn square_to_yx_canonical(sq: Square) -> (usize, usize) {
    debug_assert!(sq.in_bounds());
    let y = (sq.rank - 1) as usize;
    let x = (9 - sq.file) as usize;
    (y, x)
}

/// Produce a `(45, 9, 9)` f32 tensor flattened in row-major order
/// `[plane, y, x]`. Output length is `NUM_INPUT_CHANNELS * PLANE_STRIDE`.
pub fn encode_position(board: &Board) -> Vec<f32> {
    let mut tensor = vec![0.0f32; NUM_INPUT_CHANNELS * PLANE_STRIDE];
    let stm = board.side_to_move;
    let flip = stm == Color::Gote;

    // Per-piece planes.
    for rank in 1..=9i8 {
        for file in 1..=9i8 {
            let sq = Square::new(file, rank);
            let Some(piece) = board.piece_at(sq) else { continue };
            let (mut y, mut x) = square_to_yx_canonical(sq);
            if flip {
                y = NUM_RANKS - 1 - y;
                x = NUM_FILES - 1 - x;
            }
            let owner_is_stm = piece.color == stm;
            let plane_offset = piece.kind as usize; // 0..13, matches ShogiDojo
            let plane = if owner_is_stm {
                OWN_PIECE_BASE + plane_offset
            } else {
                OPP_PIECE_BASE + plane_offset
            };
            tensor[plane * PLANE_STRIDE + y * NUM_FILES + x] = 1.0;
        }
    }

    // Hand planes (broadcast normalised count across 9x9).
    let (own, opp) = (stm, stm.flip());
    for (i, &kind) in HAND_KINDS.iter().enumerate() {
        let own_count = board.hand(own).get(&kind).copied().unwrap_or(0) as f32;
        let opp_count = board.hand(opp).get(&kind).copied().unwrap_or(0) as f32;
        let own_norm = own_count / HAND_MAX[i];
        let opp_norm = opp_count / HAND_MAX[i];
        fill_plane(&mut tensor, OWN_HAND_BASE + i, own_norm);
        fill_plane(&mut tensor, OPP_HAND_BASE + i, opp_norm);
    }

    let rep = board.repetition_count().min(REPETITION_CAP) as f32 / REPETITION_CAP as f32;
    let ply = board.current_ply().min(PLY_CAP) as f32 / PLY_CAP as f32;
    fill_plane(&mut tensor, REP_PLANE, rep);
    fill_plane(&mut tensor, STM_PLANE, 1.0);
    fill_plane(&mut tensor, PLY_PLANE, ply);

    tensor
}

#[inline]
fn fill_plane(tensor: &mut [f32], plane: usize, value: f32) {
    let start = plane * PLANE_STRIDE;
    tensor[start..start + PLANE_STRIDE].fill(value);
}
