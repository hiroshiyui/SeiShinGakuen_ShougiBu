//! (9, 9, 139) policy-tensor move index, byte-parity with ShogiDojo's
//! `encode_move` / `decode_move`.
//!
//! Plane decomposition of the 139-plane stack:
//!   0..=63    queen-like sliding: direction_idx * 8 + (distance - 1)
//!             directions (forward = -y):
//!               0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW
//!             distances 1..=8 inclusive
//!   64..=65   knight moves (Shogi knight, forward-only)
//!             64 = (-2, -1), 65 = (-2, +1)
//!   66..=129  promoting variants of 0..63 (same geometry, +promote)
//!   130..=131 promoting variants of 64..65
//!   132..=138 drops — one plane per droppable kind
//!             in ShogiDojo's HAND_PIECE_TYPES order: P, L, N, S, G, B, R
//!
//! For board moves the spatial (y, x) holds the FROM square (after
//! perspective flip). For drops it holds the TO square.

use crate::types::{Color, Kind, Move, Square};

pub const NUM_SQUARES: usize = 81;
#[allow(dead_code)]
pub const NUM_MOVE_PLANES: usize = 139;
#[allow(dead_code)]
pub const POLICY_DIM: usize = NUM_MOVE_PLANES * NUM_SQUARES; // 11259

const QUEEN_BASE: usize = 0;
const KNIGHT_BASE: usize = 64;
const PROMOTING_QUEEN_BASE: usize = 66;
const PROMOTING_KNIGHT_BASE: usize = 130;
const DROP_BASE: usize = 132;

const NUM_QUEEN_DISTANCES: i32 = 8;

/// Queen directions in ShogiDojo's frame: forward (north) = -y.
const QUEEN_DIRS: [(i32, i32); 8] = [
    (-1,  0), // 0 N
    (-1,  1), // 1 NE
    ( 0,  1), // 2 E
    ( 1,  1), // 3 SE
    ( 1,  0), // 4 S
    ( 1, -1), // 5 SW
    ( 0, -1), // 6 W
    (-1, -1), // 7 NW
];

const KNIGHT_OFFSETS: [(i32, i32); 2] = [(-2, -1), (-2, 1)];

/// ShogiDojo's HAND_PIECE_TYPES order used for the 7 drop planes.
const DROP_ORDER: [Kind; 7] = [
    Kind::Pawn, Kind::Lance, Kind::Knight, Kind::Silver,
    Kind::Gold, Kind::Bishop, Kind::Rook,
];

#[inline]
fn square_to_yx_canonical(sq: Square) -> (i32, i32) {
    ((sq.rank - 1) as i32, (9 - sq.file) as i32)
}

#[inline]
fn flip_yx(y: i32, x: i32) -> (i32, i32) {
    (8 - y, 8 - x)
}

fn match_knight_offset(dy: i32, dx: i32) -> Option<usize> {
    KNIGHT_OFFSETS.iter().position(|&(ky, kx)| ky == dy && kx == dx)
}

/// Return `Some((direction_idx, distance))` if the delta is a queen-like
/// move (same direction repeated 1..=8 times).
fn match_queen_move(dy: i32, dx: i32) -> Option<(usize, i32)> {
    if dy == 0 && dx == 0 {
        return None;
    }
    let step_y = dy.signum();
    let step_x = dx.signum();
    let dist_y = dy.abs();
    let dist_x = dx.abs();
    // Must be pure horizontal, vertical, or diagonal.
    if dist_y != 0 && dist_x != 0 && dist_y != dist_x {
        return None;
    }
    let distance = dist_y.max(dist_x);
    if distance < 1 || distance > NUM_QUEEN_DISTANCES {
        return None;
    }
    let dir_idx = QUEEN_DIRS
        .iter()
        .position(|&(ry, rx)| ry == step_y && rx == step_x)?;
    Some((dir_idx, distance))
}

/// Encode a move into a flat policy index in `[0, POLICY_DIM)`.
pub fn encode_move(mv: Move, stm: Color) -> Option<usize> {
    let flip = stm == Color::Gote;
    match mv {
        Move::Drop { kind, to } => {
            let drop_offset = DROP_ORDER.iter().position(|&k| k == kind)?;
            let (mut y, mut x) = square_to_yx_canonical(to);
            if flip {
                (y, x) = flip_yx(y, x);
            }
            let plane = DROP_BASE + drop_offset;
            Some(plane * NUM_SQUARES + (y as usize) * 9 + (x as usize))
        }
        Move::Board { from, to, promote } => {
            let (mut fy, mut fx) = square_to_yx_canonical(from);
            let (mut ty, mut tx) = square_to_yx_canonical(to);
            if flip {
                (fy, fx) = flip_yx(fy, fx);
                (ty, tx) = flip_yx(ty, tx);
            }
            let dy = ty - fy;
            let dx = tx - fx;
            let plane = if let Some(k) = match_knight_offset(dy, dx) {
                if promote { PROMOTING_KNIGHT_BASE + k } else { KNIGHT_BASE + k }
            } else {
                let (dir, dist) = match_queen_move(dy, dx)?;
                let base = if promote { PROMOTING_QUEEN_BASE } else { QUEEN_BASE };
                base + dir * (NUM_QUEEN_DISTANCES as usize) + (dist as usize - 1)
            };
            Some(plane * NUM_SQUARES + (fy as usize) * 9 + (fx as usize))
        }
    }
}
