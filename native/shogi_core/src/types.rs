//! Primitive types: color, piece kind, piece, square, move.
//!
//! `Kind` discriminants match the GDScript `Piece.Kind` enum (0..=13) so
//! integer kinds cross the FFI boundary without translation.

use std::fmt;

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Color {
    Sente, // 先手 / black
    Gote,  // 後手 / white
}

impl Color {
    #[inline]
    pub fn flip(self) -> Self {
        match self {
            Color::Sente => Color::Gote,
            Color::Gote => Color::Sente,
        }
    }

    #[inline]
    pub fn is_gote(self) -> bool {
        matches!(self, Color::Gote)
    }

    #[inline]
    pub fn from_gote(is_gote: bool) -> Self {
        if is_gote { Color::Gote } else { Color::Sente }
    }

    /// Rank-delta sign: sente advances toward rank 1 (negative), gote
    /// toward rank 9 (positive). Movement tables are written in sente's
    /// frame and flipped via this multiplier.
    #[inline]
    pub fn forward_sign(self) -> i8 {
        match self {
            Color::Sente => 1,
            Color::Gote => -1,
        }
    }
}

/// All 14 piece kinds. Discriminants are stable and match the GDScript
/// `Piece.Kind` enum — do not reorder.
#[repr(u8)]
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    Pawn = 0,
    Lance = 1,
    Knight = 2,
    Silver = 3,
    Gold = 4,
    Bishop = 5,
    Rook = 6,
    King = 7,
    PromotedPawn = 8,
    PromotedLance = 9,
    PromotedKnight = 10,
    PromotedSilver = 11,
    Horse = 12,  // 馬 — promoted bishop
    Dragon = 13, // 龍 — promoted rook
}

impl Kind {
    pub fn from_u8(v: u8) -> Option<Self> {
        use Kind::*;
        Some(match v {
            0 => Pawn,
            1 => Lance,
            2 => Knight,
            3 => Silver,
            4 => Gold,
            5 => Bishop,
            6 => Rook,
            7 => King,
            8 => PromotedPawn,
            9 => PromotedLance,
            10 => PromotedKnight,
            11 => PromotedSilver,
            12 => Horse,
            13 => Dragon,
            _ => return None,
        })
    }

    #[inline]
    pub fn is_promoted(self) -> bool {
        matches!(
            self,
            Kind::PromotedPawn
                | Kind::PromotedLance
                | Kind::PromotedKnight
                | Kind::PromotedSilver
                | Kind::Horse
                | Kind::Dragon
        )
    }

    #[inline]
    pub fn can_promote(self) -> bool {
        matches!(
            self,
            Kind::Pawn | Kind::Lance | Kind::Knight | Kind::Silver | Kind::Bishop | Kind::Rook
        )
    }

    pub fn promoted(self) -> Self {
        match self {
            Kind::Pawn => Kind::PromotedPawn,
            Kind::Lance => Kind::PromotedLance,
            Kind::Knight => Kind::PromotedKnight,
            Kind::Silver => Kind::PromotedSilver,
            Kind::Bishop => Kind::Horse,
            Kind::Rook => Kind::Dragon,
            k => k,
        }
    }

    pub fn base(self) -> Self {
        match self {
            Kind::PromotedPawn => Kind::Pawn,
            Kind::PromotedLance => Kind::Lance,
            Kind::PromotedKnight => Kind::Knight,
            Kind::PromotedSilver => Kind::Silver,
            Kind::Horse => Kind::Bishop,
            Kind::Dragon => Kind::Rook,
            k => k,
        }
    }

    /// Single-letter SFEN encoding (promoted pieces return the base letter;
    /// the `+` prefix is the caller's responsibility).
    pub fn sfen_letter(self) -> char {
        match self {
            Kind::Pawn | Kind::PromotedPawn => 'P',
            Kind::Lance | Kind::PromotedLance => 'L',
            Kind::Knight | Kind::PromotedKnight => 'N',
            Kind::Silver | Kind::PromotedSilver => 'S',
            Kind::Gold => 'G',
            Kind::Bishop | Kind::Horse => 'B',
            Kind::Rook | Kind::Dragon => 'R',
            Kind::King => 'K',
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub struct Piece {
    pub kind: Kind,
    pub color: Color,
}

impl Piece {
    #[inline]
    pub fn new(kind: Kind, color: Color) -> Self {
        Self { kind, color }
    }
}

/// A board coordinate in Shogi notation: file 1..=9, rank 1..=9.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub struct Square {
    pub file: i8,
    pub rank: i8,
}

impl Square {
    #[inline]
    pub fn new(file: i8, rank: i8) -> Self {
        Self { file, rank }
    }

    #[inline]
    pub fn in_bounds(self) -> bool {
        self.file >= 1 && self.file <= 9 && self.rank >= 1 && self.rank <= 9
    }

    /// Index 0..=80, row-major with rank advancing first (rank 1 file 9 = 0).
    #[inline]
    pub fn index(self) -> usize {
        ((self.rank - 1) * 9 + (9 - self.file)) as usize
    }
}

impl fmt::Display for Square {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", self.file, self.rank)
    }
}

/// A move — either a board move (with optional promotion) or a hand drop.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Move {
    Board { from: Square, to: Square, promote: bool },
    Drop { kind: Kind, to: Square },
}

impl Move {
    #[inline]
    pub fn destination(&self) -> Square {
        match *self {
            Move::Board { to, .. } => to,
            Move::Drop { to, .. } => to,
        }
    }
}
