//! Forced-mate (詰将棋) solver.
//!
//! Tsume rules: the attacker (side to move) must give check with every
//! move and mate within the budget; the defender may play any legal
//! move and picks the longest defence. Plain depth-first search with
//! iterative deepening — fine for the 1 / 3 / 5-move problems the game
//! ships, not meant for long classical compositions. 無駄合 (futile
//! interpositions) are *not* discounted: a position only counts as mate
//! in N if every legal defence, interpositions included, is mated
//! within N. That is stricter than the composing convention and keeps
//! the generated problems unambiguous.

use crate::board::Board;
use crate::mcts::all_legal_moves;
use crate::rules::is_check;
use crate::types::{Color, Kind, Move, Piece, Square};

/// Search effort cap: positions visited before the solver gives up and
/// reports "no mate". Keeps a pathological position from stalling the
/// UI thread or the puzzle generator.
pub const DEFAULT_NODE_BUDGET: u64 = 200_000;

pub struct Solver {
    nodes: u64,
    budget: u64,
}

/// What the defender can do after an attacker move in a puzzle.
pub enum Defense {
    /// The attacker's move was not a check — illegal in tsume.
    NotCheck,
    /// Checkmate on the board.
    Mate,
    /// Forced mate remains; this is the longest-lasting reply.
    Continue(Move),
    /// The defender has a reply that survives the remaining budget.
    Escaped,
}

impl Solver {
    pub fn new(budget: u64) -> Self {
        Self { nodes: 0, budget }
    }

    fn exhausted(&self) -> bool {
        self.nodes >= self.budget
    }

    /// Shortest forced mate for the side to move within `max_plies`
    /// (attacker moves + defender replies; odd). Returns the principal
    /// variation with the defender's longest defence, or `None`.
    pub fn solve(&mut self, board: &mut Board, max_plies: u32) -> Option<Vec<Move>> {
        let mut n = 1;
        while n <= max_plies {
            if let Some(pv) = self.attack(board, n) {
                return Some(pv);
            }
            if self.exhausted() {
                return None;
            }
            n += 2;
        }
        None
    }

    /// Number of distinct first moves that force mate within exactly
    /// `plies`. A well-formed problem has one (no 余詰 at move one).
    pub fn count_first_moves(&mut self, board: &mut Board, plies: u32) -> usize {
        let mut count = 0;
        for mv in checking_moves(board) {
            let applied = board.apply_move(mv);
            debug_assert!(applied, "solver move rejected");
            let mated = self.defend(board, plies - 1).is_some();
            board.undo_move();
            if mated {
                count += 1;
            }
        }
        count
    }

    /// Judge the position after an attacker move, with `plies_left`
    /// plies of budget remaining for the rest of the solution.
    pub fn defense(&mut self, board: &mut Board, plies_left: u32) -> Defense {
        if !is_check(board, board.side_to_move) {
            return Defense::NotCheck;
        }
        match self.defend(board, plies_left) {
            None => Defense::Escaped,
            Some(pv) => match pv.first() {
                None => Defense::Mate,
                Some(&reply) => Defense::Continue(reply),
            },
        }
    }

    /// Attacker to move with `n` plies left: a checking move after
    /// which the defender is mated within `n - 1`.
    fn attack(&mut self, board: &mut Board, n: u32) -> Option<Vec<Move>> {
        if n == 0 {
            return None;
        }
        for mv in checking_moves(board) {
            if self.exhausted() {
                return None;
            }
            self.nodes += 1;
            let applied = board.apply_move(mv);
            debug_assert!(applied, "solver move rejected");
            let line = self.defend(board, n - 1);
            board.undo_move();
            if let Some(mut pv) = line {
                pv.insert(0, mv);
                return Some(pv);
            }
        }
        None
    }

    /// Defender to move (in check) with `n` plies left. `Some(pv)` when
    /// every reply is mated within `n`, holding the longest defence
    /// (empty = already checkmate); `None` when some reply survives.
    fn defend(&mut self, board: &mut Board, n: u32) -> Option<Vec<Move>> {
        let replies = all_legal_moves(board);
        if replies.is_empty() {
            return Some(Vec::new());
        }
        if n < 2 {
            return None;
        }
        let mut longest: Option<Vec<Move>> = None;
        for reply in replies {
            if self.exhausted() {
                return None;
            }
            self.nodes += 1;
            let applied = board.apply_move(reply);
            debug_assert!(applied, "solver move rejected");
            // Shortest mate against this reply, so the PV reflects best
            // play by both sides.
            let mut line = None;
            let mut m = 1;
            while m < n {
                line = self.attack(board, m);
                if line.is_some() {
                    break;
                }
                m += 2;
            }
            board.undo_move();
            let mut pv = line?;
            pv.insert(0, reply);
            if longest.as_ref().is_none_or(|l| pv.len() > l.len()) {
                longest = Some(pv);
            }
        }
        longest
    }
}

/// Legal moves for the side to move that put the opponent in check.
fn checking_moves(board: &mut Board) -> Vec<Move> {
    let defender = board.side_to_move.flip();
    all_legal_moves(board)
        .into_iter()
        .filter(|&mv| {
            let applied = board.apply_move(mv);
            debug_assert!(applied, "solver move rejected");
            let check = is_check(board, defender);
            board.undo_move();
            check
        })
        .collect()
}

/// The same position seen from the other side of the board: rotated
/// 180°, colours and hands swapped, side to move flipped. Tsume problems
/// are always presented with the attacker as 先手 at the bottom.
pub fn flipped(board: &Board) -> Board {
    const HAND_KINDS: [Kind; 7] = [
        Kind::Pawn, Kind::Lance, Kind::Knight, Kind::Silver,
        Kind::Gold, Kind::Bishop, Kind::Rook,
    ];
    let mut out = Board::empty();
    out.clear();
    for r in 1..=9i8 {
        for f in 1..=9i8 {
            if let Some(p) = board.piece_at(Square::new(f, r)) {
                out.place(Square::new(10 - f, 10 - r), Piece::new(p.kind, p.color.flip()));
            }
        }
    }
    for color in [Color::Sente, Color::Gote] {
        for kind in HAND_KINDS {
            let n = board.hand(color).get(&kind).copied().unwrap_or(0);
            out.set_hand_count(color.flip(), kind, n);
        }
    }
    out.side_to_move = board.side_to_move.flip();
    out.position_counts.clear();
    let key = crate::sfen::position_key(&out);
    *out.position_counts.entry(key).or_insert(0) += 1;
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sfen::{parse_sfen, position_key};

    fn board(sfen: &str) -> Board {
        parse_sfen(sfen).expect("valid sfen")
    }

    // 頭金: gote king on 5a, sente pawn on 5c supporting a gold drop on 5b.
    const ATAMA_KIN: &str = "4k4/9/4P4/9/9/9/9/9/9 b G 1";

    #[test]
    fn mate_in_one_gold_on_the_head() {
        let mut b = board(ATAMA_KIN);
        let pv = Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 1).expect("mate in 1");
        assert_eq!(pv, vec![Move::Drop { kind: Kind::Gold, to: Square::new(5, 2) }]);
        assert_eq!(Solver::new(DEFAULT_NODE_BUDGET).count_first_moves(&mut b, 1), 1);
    }

    #[test]
    fn solver_leaves_the_board_untouched() {
        let mut b = board(ATAMA_KIN);
        let before = position_key(&b);
        let _ = Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 5);
        assert_eq!(position_key(&b), before);
        assert!(b.log.is_empty());
    }

    #[test]
    fn no_mate_when_the_king_has_room() {
        // A lone gold in hand against a king in the open: no mate in 3.
        let mut b = board("9/9/9/4k4/9/9/9/9/4K4 b G 1");
        assert!(Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 3).is_none());
    }

    // King on 1b, sente pawn on 1d, two golds in hand:
    // G*1c (backed by the pawn), K-1a or K-2a, then G*1b / G*2b mates.
    const MATE_IN_THREE: &str = "9/8k/9/8P/9/9/9/9/9 b 2G 1";
    // One move earlier: S*1b sacrifices the silver to pull the king up.
    const MATE_IN_FIVE: &str = "8k/9/9/8P/9/9/9/9/9 b 2GS 1";

    #[test]
    fn mate_in_three_is_not_reported_as_mate_in_one() {
        let mut b = board(MATE_IN_THREE);
        assert!(Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 1).is_none());
        let pv = Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 3).expect("mate in 3");
        assert_eq!(pv.len(), 3);
        assert_eq!(pv[0], Move::Drop { kind: Kind::Gold, to: Square::new(1, 3) });
    }

    #[test]
    fn mate_in_five_with_a_sacrifice() {
        let mut b = board(MATE_IN_FIVE);
        assert!(Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 3).is_none());
        let pv = Solver::new(DEFAULT_NODE_BUDGET).solve(&mut b, 5).expect("mate in 5");
        assert_eq!(pv.len(), 5);
        assert_eq!(pv[0], Move::Drop { kind: Kind::Silver, to: Square::new(1, 2) });
        assert_eq!(Solver::new(DEFAULT_NODE_BUDGET).count_first_moves(&mut b, 5), 1);
    }

    #[test]
    fn defense_continues_with_the_longest_reply() {
        let mut b = board(MATE_IN_THREE);
        b.apply_move(Move::Drop { kind: Kind::Gold, to: Square::new(1, 3) });
        // Two plies remain after the first move of a three-ply problem.
        assert!(matches!(
            Solver::new(DEFAULT_NODE_BUDGET).defense(&mut b, 2),
            Defense::Continue(Move::Board { .. })
        ));
        // With no budget left the same check is not yet mate.
        assert!(matches!(Solver::new(DEFAULT_NODE_BUDGET).defense(&mut b, 0), Defense::Escaped));
    }

    #[test]
    fn exhausted_budget_reports_no_mate() {
        let mut b = board(MATE_IN_FIVE);
        assert!(Solver::new(10).solve(&mut b, 5).is_none());
    }

    #[test]
    fn defense_classifies_attacker_moves() {
        let mut b = board(ATAMA_KIN);
        // Correct: G*5b is mate.
        b.apply_move(Move::Drop { kind: Kind::Gold, to: Square::new(5, 2) });
        assert!(matches!(Solver::new(DEFAULT_NODE_BUDGET).defense(&mut b, 0), Defense::Mate));
        b.undo_move();
        // A quiet move is not a check.
        b.apply_move(Move::Drop { kind: Kind::Gold, to: Square::new(9, 9) });
        assert!(matches!(Solver::new(DEFAULT_NODE_BUDGET).defense(&mut b, 0), Defense::NotCheck));
        b.undo_move();
        // A check the king simply walks away from.
        b.apply_move(Move::Drop { kind: Kind::Gold, to: Square::new(4, 2) });
        assert!(matches!(Solver::new(DEFAULT_NODE_BUDGET).defense(&mut b, 0), Defense::Escaped));
    }

    #[test]
    fn flipping_twice_is_the_identity() {
        let b = board("ln1g1k1nl/1r4gs1/p1pppp1pp/6p2/1p7/2P4P1/PPSPPPP1P/1B5R1/LN1GKGSNL w Bp 20");
        let once = flipped(&b);
        assert_ne!(position_key(&once), position_key(&b));
        assert_eq!(once.side_to_move, Color::Sente);
        assert_eq!(position_key(&flipped(&once)), position_key(&b));
    }
}
