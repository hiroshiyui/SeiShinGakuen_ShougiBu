//! Unit tests mirroring the GDScript fixtures + a small perft sanity.

use crate::board::Board;
use crate::movegen::generate_moves_from;
use crate::rules::{is_check, legal_drops, legal_moves_from};
use crate::sfen::to_sfen;
use crate::types::{Color, Kind, Move, Piece, Square};

fn placed(pieces: &[(i8, i8, Kind, Color)], hands: &[(Color, Kind, u32)], side: Color) -> Board {
    let mut b = Board::empty();
    b.clear();
    for &(f, r, kind, col) in pieces {
        b.place(Square::new(f, r), Piece::new(kind, col));
    }
    for &(c, k, n) in hands {
        b.set_hand_count(c, k, n);
    }
    b.side_to_move = side;
    b.position_counts.clear();
    let key = crate::sfen::position_key(&b);
    *b.position_counts.entry(key).or_insert(0) += 1;
    b
}

#[test]
fn starting_not_check_and_has_moves() {
    let mut b = Board::default();
    assert!(!is_check(&b, Color::Sente));
    assert!(!is_check(&b, Color::Gote));
    assert!(crate::rules::has_any_legal_move(&mut b));
}

#[test]
fn pinned_silver_has_no_legal_moves() {
    // Gote silver at 3-5 pinned between gote king at 5-5 and sente rook at 1-5.
    let mut b = placed(
        &[
            (5, 9, Kind::King, Color::Sente),
            (5, 5, Kind::King, Color::Gote),
            (3, 5, Kind::Silver, Color::Gote),
            (1, 5, Kind::Rook, Color::Sente),
        ],
        &[],
        Color::Gote,
    );
    let moves = legal_moves_from(&mut b, Square::new(3, 5));
    assert!(moves.is_empty(), "pinned silver produced {:?}", moves);
}

#[test]
fn nifu_blocks_pawn_drop_on_file_5() {
    let mut b = placed(
        &[
            (5, 9, Kind::King, Color::Sente),
            (5, 1, Kind::King, Color::Gote),
            (5, 7, Kind::Pawn, Color::Sente),
        ],
        &[(Color::Sente, Kind::Pawn, 1)],
        Color::Sente,
    );
    let drops = legal_drops(&mut b, Kind::Pawn);
    for m in drops {
        if let Move::Drop { to, .. } = m {
            assert_ne!(to.file, 5, "pawn drop allowed on file 5 despite own pawn");
        }
    }
}

fn uchifuzume_fixture() -> Board {
    placed(
        &[
            (9, 9, Kind::King, Color::Sente),
            (5, 1, Kind::King, Color::Gote),
            (4, 1, Kind::Gold, Color::Gote),
            (6, 1, Kind::Knight, Color::Gote),
            (4, 2, Kind::Pawn, Color::Gote),
            (6, 2, Kind::Pawn, Color::Gote),
            (1, 1, Kind::Rook, Color::Sente),
            (4, 3, Kind::Bishop, Color::Sente),
        ],
        &[
            (Color::Sente, Kind::Pawn, 1),
            (Color::Sente, Kind::Silver, 1),
        ],
        Color::Sente,
    )
}

#[test]
fn uchifuzume_refuses_pawn_mate_drop() {
    let mut b = uchifuzume_fixture();
    assert!(!is_check(&b, Color::Gote), "fixture precondition: gote not in check");
    let drops = legal_drops(&mut b, Kind::Pawn);
    for m in drops {
        if let Move::Drop { to, .. } = m {
            assert_ne!(to, Square::new(5, 2), "pawn drop at 5-2 should be uchifuzume");
        }
    }
}

#[test]
fn silver_drop_mate_is_legal() {
    let mut b = uchifuzume_fixture();
    let drops = legal_drops(&mut b, Kind::Silver);
    let found = drops.iter().any(|m| matches!(m, Move::Drop { to, .. } if *to == Square::new(5, 2)));
    assert!(found, "silver drop at 5-2 should be legal (only pawn drops trigger uchifuzume)");
}

#[test]
fn undo_restores_sfen_after_capture_promote() {
    let mut b = placed(
        &[
            (5, 9, Kind::King, Color::Sente),
            (5, 1, Kind::King, Color::Gote),
            (3, 4, Kind::Pawn, Color::Sente),
            (3, 3, Kind::Silver, Color::Gote),
        ],
        &[],
        Color::Sente,
    );
    let before = to_sfen(&b);
    let ok = b.apply_move(Move::Board {
        from: Square::new(3, 4),
        to: Square::new(3, 3),
        promote: true,
    });
    assert!(ok);
    assert!(b.undo_move());
    assert_eq!(before, to_sfen(&b));
}

#[test]
fn perft_starting_depth_1_is_30() {
    // From the starting position, sente has 30 legal first moves.
    let mut b = Board::default();
    assert_eq!(perft(&mut b, 1), 30);
}

#[test]
fn perft_starting_depth_2_is_900() {
    let mut b = Board::default();
    assert_eq!(perft(&mut b, 2), 30 * 30);
}

fn perft(board: &mut Board, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let mut total = 0u64;
    // Enumerate all legal moves for side-to-move.
    let side = board.side_to_move;
    let mut moves: Vec<Move> = Vec::new();
    for r in 1..=9 {
        for f in 1..=9 {
            let sq = Square::new(f, r);
            if let Some(p) = board.piece_at(sq) {
                if p.color == side {
                    moves.extend(legal_moves_from(board, sq));
                }
            }
        }
    }
    let hand_kinds: Vec<Kind> = board.hand(side).keys().copied().collect();
    for k in hand_kinds {
        moves.extend(legal_drops(board, k));
    }
    if depth == 1 {
        return moves.len() as u64;
    }
    for mv in moves {
        board.apply_move(mv);
        total += perft(board, depth - 1);
        board.undo_move();
    }
    total
}

#[test]
fn generate_moves_from_empty_returns_none() {
    let b = Board::default();
    let mut out = Vec::new();
    generate_moves_from(&b, Square::new(5, 5), &mut out);
    assert!(out.is_empty());
}
