//! Mutable position: 9x9 mailbox + two hands + side-to-move + move log
//! with enough information to reverse every move.

use std::collections::HashMap;

use crate::types::{Color, Kind, Move, Piece, Square};

/// Hand-piece slot ordering used for SFEN serialization (heaviest first).
pub const HAND_ORDER: [Kind; 7] = [
    Kind::Rook,
    Kind::Bishop,
    Kind::Gold,
    Kind::Silver,
    Kind::Knight,
    Kind::Lance,
    Kind::Pawn,
];

/// Reversible log entry produced by `apply_move`.
#[derive(Clone, Debug)]
pub enum LogEntry {
    Board {
        from: Square,
        to: Square,
        prev_kind: Kind,
        captured: Option<Piece>,
        by: Color,
        was_check: bool,
        position_key_after: String,
    },
    Drop {
        kind: Kind,
        to: Square,
        by: Color,
        was_check: bool,
        position_key_after: String,
    },
}

impl LogEntry {
    pub fn by(&self) -> Color {
        match self {
            LogEntry::Board { by, .. } | LogEntry::Drop { by, .. } => *by,
        }
    }
    pub fn was_check(&self) -> bool {
        match self {
            LogEntry::Board { was_check, .. } | LogEntry::Drop { was_check, .. } => *was_check,
        }
    }
    pub fn position_key_after(&self) -> &str {
        match self {
            LogEntry::Board { position_key_after, .. }
            | LogEntry::Drop { position_key_after, .. } => position_key_after.as_str(),
        }
    }
}

/// Count of a single kind in a side's hand. Missing = 0.
pub type Hand = HashMap<Kind, u32>;

#[derive(Clone, Debug)]
pub struct Board {
    squares: [Option<Piece>; 81],
    sente_hand: Hand,
    gote_hand: Hand,
    pub side_to_move: Color,
    pub log: Vec<LogEntry>,
    pub position_counts: HashMap<String, u32>,
    /// Ply number of the first move reachable from this instance. For a
    /// default starting position this is `1`; for a position imported via
    /// SFEN it is the SFEN's trailing move number. `current_ply()` is
    /// `starting_ply + log.len()`.
    pub starting_ply: u32,
}

impl Default for Board {
    fn default() -> Self {
        let mut b = Self::empty();
        b.reset_starting();
        b
    }
}

impl Board {
    pub fn empty() -> Self {
        Self {
            squares: [None; 81],
            sente_hand: Hand::new(),
            gote_hand: Hand::new(),
            side_to_move: Color::Sente,
            log: Vec::new(),
            position_counts: HashMap::new(),
            starting_ply: 1,
        }
    }

    #[inline]
    pub fn current_ply(&self) -> u32 {
        self.starting_ply + self.log.len() as u32
    }

    /// Number of times the *current* position has previously occurred —
    /// i.e. the sennichite counter minus one (the current occurrence).
    pub fn repetition_count(&self) -> u32 {
        let key = crate::sfen::position_key(self);
        self.position_counts.get(&key).copied().unwrap_or(0).saturating_sub(1)
    }

    pub fn reset_starting(&mut self) {
        self.clear();
        let back = [
            Kind::Lance, Kind::Knight, Kind::Silver, Kind::Gold,
            Kind::King,  Kind::Gold,   Kind::Silver, Kind::Knight, Kind::Lance,
        ];
        for i in 0..9 {
            let f = (9 - i) as i8;
            self.place(Square::new(f, 1), Piece::new(back[i], Color::Gote));
            self.place(Square::new(f, 9), Piece::new(back[i], Color::Sente));
            self.place(Square::new(f, 3), Piece::new(Kind::Pawn, Color::Gote));
            self.place(Square::new(f, 7), Piece::new(Kind::Pawn, Color::Sente));
        }
        self.place(Square::new(8, 2), Piece::new(Kind::Rook, Color::Gote));
        self.place(Square::new(2, 2), Piece::new(Kind::Bishop, Color::Gote));
        self.place(Square::new(8, 8), Piece::new(Kind::Bishop, Color::Sente));
        self.place(Square::new(2, 8), Piece::new(Kind::Rook, Color::Sente));
        self.side_to_move = Color::Sente;
        self.log.clear();
        self.position_counts.clear();
        self.bump_position();
    }

    pub fn clear(&mut self) {
        self.squares = [None; 81];
        self.sente_hand.clear();
        self.gote_hand.clear();
        self.side_to_move = Color::Sente;
        self.log.clear();
        self.position_counts.clear();
        self.starting_ply = 1;
    }

    #[inline]
    pub fn piece_at(&self, sq: Square) -> Option<Piece> {
        if !sq.in_bounds() {
            return None;
        }
        self.squares[sq.index()]
    }

    #[inline]
    pub fn place(&mut self, sq: Square, piece: Piece) {
        self.squares[sq.index()] = Some(piece);
    }

    #[inline]
    pub fn remove(&mut self, sq: Square) -> Option<Piece> {
        self.squares[sq.index()].take()
    }

    pub fn hand(&self, color: Color) -> &Hand {
        match color {
            Color::Sente => &self.sente_hand,
            Color::Gote => &self.gote_hand,
        }
    }

    pub fn hand_mut(&mut self, color: Color) -> &mut Hand {
        match color {
            Color::Sente => &mut self.sente_hand,
            Color::Gote => &mut self.gote_hand,
        }
    }

    pub fn set_hand_count(&mut self, color: Color, kind: Kind, count: u32) {
        let h = self.hand_mut(color);
        if count == 0 {
            h.remove(&kind);
        } else {
            h.insert(kind, count);
        }
    }

    fn hand_add(&mut self, color: Color, kind: Kind) {
        *self.hand_mut(color).entry(kind).or_insert(0) += 1;
    }

    fn hand_remove(&mut self, color: Color, kind: Kind) -> bool {
        let h = self.hand_mut(color);
        match h.get_mut(&kind) {
            Some(n) if *n > 1 => {
                *n -= 1;
                true
            }
            Some(_) => {
                h.remove(&kind);
                true
            }
            None => false,
        }
    }

    /// Apply a move. Returns `false` and leaves state unchanged on rejection.
    /// This checks geometry-level validity only; higher-level rule filters
    /// (self-check, nifu, uchifuzume) live in `rules`.
    pub fn apply_move(&mut self, mv: Move) -> bool {
        let ok = match mv {
            Move::Board { from, to, promote } => self.apply_board_move(from, to, promote),
            Move::Drop { kind, to } => self.apply_drop(kind, to),
        };
        if ok {
            self.bump_position();
        }
        ok
    }

    fn apply_board_move(&mut self, from: Square, to: Square, promote: bool) -> bool {
        let Some(piece) = self.piece_at(from) else { return false };
        if piece.color != self.side_to_move {
            return false;
        }
        let captured = self.piece_at(to);
        if let Some(cap) = captured {
            if cap.color == piece.color {
                return false;
            }
        }
        if promote && !piece.kind.can_promote() {
            return false;
        }
        let mover = self.side_to_move;
        if let Some(cap) = captured {
            self.hand_add(mover, cap.kind.base());
        }
        self.remove(from);
        let new_kind = if promote { piece.kind.promoted() } else { piece.kind };
        self.squares[to.index()] = Some(Piece::new(new_kind, mover));
        self.side_to_move = mover.flip();
        self.log.push(LogEntry::Board {
            from,
            to,
            prev_kind: piece.kind,
            captured,
            by: mover,
            was_check: false,
            position_key_after: String::new(),
        });
        let _ = promote; // encoded into `prev_kind -> new_kind`; keep param readable
        true
    }

    fn apply_drop(&mut self, kind: Kind, to: Square) -> bool {
        if self.piece_at(to).is_some() {
            return false;
        }
        let mover = self.side_to_move;
        if !self.hand_remove(mover, kind) {
            return false;
        }
        self.squares[to.index()] = Some(Piece::new(kind, mover));
        self.side_to_move = mover.flip();
        self.log.push(LogEntry::Drop {
            kind,
            to,
            by: mover,
            was_check: false,
            position_key_after: String::new(),
        });
        true
    }

    pub fn undo_move(&mut self) -> bool {
        self.unbump_position();
        let Some(entry) = self.log.pop() else {
            // bump back because we pre-decremented
            self.bump_position();
            return false;
        };
        match entry {
            LogEntry::Board { from, to, prev_kind, captured, by, .. } => {
                self.squares[to.index()] = captured;
                self.squares[from.index()] = Some(Piece::new(prev_kind, by));
                if let Some(cap) = captured {
                    self.hand_remove(by, cap.kind.base());
                }
                self.side_to_move = by;
            }
            LogEntry::Drop { kind, to, by, .. } => {
                self.squares[to.index()] = None;
                self.hand_add(by, kind);
                self.side_to_move = by;
            }
        }
        true
    }

    /// Tag the most recently applied move with check status and the
    /// position-key fingerprint (used by sennichite detection).
    pub fn tag_last_move(&mut self, was_check: bool, position_key: String) {
        if let Some(last) = self.log.last_mut() {
            match last {
                LogEntry::Board { was_check: wc, position_key_after, .. }
                | LogEntry::Drop { was_check: wc, position_key_after, .. } => {
                    *wc = was_check;
                    *position_key_after = position_key;
                }
            }
        }
    }

    fn bump_position(&mut self) {
        let key = crate::sfen::position_key(self);
        *self.position_counts.entry(key).or_insert(0) += 1;
    }

    fn unbump_position(&mut self) {
        let key = crate::sfen::position_key(self);
        match self.position_counts.get_mut(&key) {
            Some(n) if *n > 1 => *n -= 1,
            Some(_) => { self.position_counts.remove(&key); }
            None => {}
        }
    }

    pub fn find_king(&self, color: Color) -> Option<Square> {
        for r in 1..=9 {
            for f in 1..=9 {
                let sq = Square::new(f, r);
                if let Some(p) = self.piece_at(sq) {
                    if p.kind == Kind::King && p.color == color {
                        return Some(sq);
                    }
                }
            }
        }
        None
    }
}
