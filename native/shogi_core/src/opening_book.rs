//! Hand-curated opening book.
//!
//! Format: JSON object keyed by `sfen::position_key(board)` (= board SFEN
//! + side-to-move letter + hand SFEN, no move-number suffix), value is an
//! array of weighted candidate moves:
//!
//! ```json
//! {
//!   "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -": [
//!     { "usi": "7g7f", "weight": 60 },
//!     { "usi": "2g2f", "weight": 30 }
//!   ]
//! }
//! ```
//!
//! Moves are USI (`<from-square><to-square>[+]` for board moves;
//! `<piece>*<to-square>` for drops). Weights are positive integers,
//! sampled proportionally; greedy at temperature τ = 0 (mode of the
//! distribution).
//!
//! v1 is hand-authored — see `assets/opening_book.json`. Lookup is a
//! single HashMap probe, so growing the book is just appending JSON
//! entries.

use std::collections::HashMap;

use rand::Rng;
use serde_json::Value;

use crate::board::Board;
use crate::sfen;
use crate::types::{Color, Kind, Move, Square};

#[derive(Clone, Debug)]
struct Entry {
    mv: Move,
    weight: u32,
}

#[derive(Clone, Debug, Default)]
pub struct OpeningBook {
    /// position_key → candidate moves at that position.
    entries: HashMap<String, Vec<Entry>>,
}

impl OpeningBook {
    pub fn load_from_str(json: &str) -> Result<Self, String> {
        let root: Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
        let obj = root
            .as_object()
            .ok_or_else(|| "opening book must be a top-level JSON object".to_string())?;
        let mut entries: HashMap<String, Vec<Entry>> = HashMap::new();
        for (key, value) in obj {
            let arr = value.as_array().ok_or_else(|| {
                format!("entry for `{key}` must be an array of {{usi, weight}} objects")
            })?;
            let mut moves: Vec<Entry> = Vec::with_capacity(arr.len());
            for entry in arr {
                let usi = entry
                    .get("usi")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| format!("entry under `{key}` missing string `usi`"))?;
                let weight = entry
                    .get("weight")
                    .and_then(|v| v.as_u64())
                    .ok_or_else(|| format!("entry `{usi}` under `{key}` missing positive integer `weight`"))?
                    as u32;
                let mv = parse_usi(usi).ok_or_else(|| format!("cannot parse USI move `{usi}` under `{key}`"))?;
                moves.push(Entry { mv, weight });
            }
            entries.insert(key.clone(), moves);
        }
        Ok(Self { entries })
    }

    pub fn len(&self) -> usize { self.entries.len() }

    /// Sample a candidate from the book at the current position. Returns
    /// `None` if the position isn't in the book or all candidates have
    /// weight 0. `temperature ≤ 1e-6` is greedy (highest-weighted move,
    /// ties broken by JSON order).
    pub fn pick(&self, board: &Board, temperature: f32) -> Option<Move> {
        let key = sfen::position_key(board);
        let candidates = self.entries.get(&key)?;
        if candidates.is_empty() {
            return None;
        }

        // Validate the move parses geometrically against the current
        // board. USI is position-agnostic so a typo in the JSON could
        // produce a syntactically-valid move that doesn't match a real
        // piece — fail open (skip the bad entry, try the rest) rather
        // than poison the AI's whole turn.
        let valid: Vec<&Entry> = candidates
            .iter()
            .filter(|e| board.piece_at(e.mv.destination()).map_or(true, |_| true) && validate_move_on(board, e.mv))
            .collect();
        if valid.is_empty() {
            return None;
        }

        if temperature <= 1e-6 {
            return valid.iter().max_by_key(|e| e.weight).map(|e| e.mv);
        }

        // weight^(1/τ): small τ sharpens, τ = 1 leaves weights as-is.
        let inv_t = 1.0_f32 / temperature;
        let weights: Vec<f64> = valid
            .iter()
            .map(|e| (e.weight.max(1) as f32).powf(inv_t) as f64)
            .collect();
        let sum: f64 = weights.iter().sum();
        if sum <= 0.0 {
            return valid.first().map(|e| e.mv);
        }
        let mut rng = rand::rng();
        let r: f64 = rng.random::<f64>() * sum;
        let mut acc = 0.0;
        for (e, w) in valid.iter().zip(weights.iter()) {
            acc += *w;
            if r <= acc {
                return Some(e.mv);
            }
        }
        valid.last().map(|e| e.mv)
    }
}

// --- USI parsing ----------------------------------------------------------

fn file_from_digit(c: u8) -> Option<i8> {
    if (b'1'..=b'9').contains(&c) { Some((c - b'0') as i8) } else { None }
}

fn rank_from_letter(c: u8) -> Option<i8> {
    if (b'a'..=b'i').contains(&c) { Some((c - b'a' + 1) as i8) } else { None }
}

fn drop_kind_from_letter(c: u8) -> Option<Kind> {
    match c {
        b'P' => Some(Kind::Pawn),
        b'L' => Some(Kind::Lance),
        b'N' => Some(Kind::Knight),
        b'S' => Some(Kind::Silver),
        b'G' => Some(Kind::Gold),
        b'B' => Some(Kind::Bishop),
        b'R' => Some(Kind::Rook),
        _ => None,
    }
}

/// USI: `<file><rank><file><rank>[+]` for board moves, `<piece>*<file><rank>`
/// for drops. Returns None on any syntax error — caller treats as "this
/// entry is invalid, skip it".
pub fn parse_usi(s: &str) -> Option<Move> {
    let bytes = s.as_bytes();
    if bytes.len() < 4 {
        return None;
    }
    if bytes[1] == b'*' {
        // Drop.
        if bytes.len() != 4 {
            return None;
        }
        let kind = drop_kind_from_letter(bytes[0])?;
        let to = Square::new(file_from_digit(bytes[2])?, rank_from_letter(bytes[3])?);
        return Some(Move::Drop { kind, to });
    }
    // Board move.
    if bytes.len() < 4 || bytes.len() > 5 {
        return None;
    }
    let from = Square::new(file_from_digit(bytes[0])?, rank_from_letter(bytes[1])?);
    let to = Square::new(file_from_digit(bytes[2])?, rank_from_letter(bytes[3])?);
    let promote = bytes.len() == 5 && bytes[4] == b'+';
    Some(Move::Board { from, to, promote })
}

fn validate_move_on(board: &Board, mv: Move) -> bool {
    match mv {
        Move::Board { from, to, .. } => {
            if !from.in_bounds() || !to.in_bounds() {
                return false;
            }
            // Must have an own piece at `from`.
            let Some(p) = board.piece_at(from) else { return false };
            p.color == board.side_to_move
        }
        Move::Drop { kind, to } => {
            if !to.in_bounds() {
                return false;
            }
            // Must hold at least one of `kind` in hand.
            board.hand(board.side_to_move).get(&kind).copied().unwrap_or(0) > 0
        }
    }
}

// `Color` is referenced by validate_move_on above; bring it in scope explicitly
// so the test module's `use super::*` doesn't need a separate import.
#[allow(unused_imports)]
use Color as _ColorBrand;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_usi_board_move() {
        let mv = parse_usi("7g7f").unwrap();
        assert_eq!(mv, Move::Board {
            from: Square::new(7, 7),
            to: Square::new(7, 6),
            promote: false,
        });
    }

    #[test]
    fn parse_usi_promotion() {
        let mv = parse_usi("2b3a+").unwrap();
        assert_eq!(mv, Move::Board {
            from: Square::new(2, 2),
            to: Square::new(3, 1),
            promote: true,
        });
    }

    #[test]
    fn parse_usi_drop() {
        let mv = parse_usi("P*5e").unwrap();
        assert_eq!(mv, Move::Drop {
            kind: Kind::Pawn,
            to: Square::new(5, 5),
        });
    }

    #[test]
    fn parse_usi_rejects_garbage() {
        assert!(parse_usi("").is_none());
        assert!(parse_usi("abc").is_none());
        assert!(parse_usi("Z*5e").is_none());
        assert!(parse_usi("9z9z").is_none());
    }

    #[test]
    fn book_picks_only_legal_candidate() {
        // Two USI candidates at the starting position: a real one (7g7f)
        // and a malformed one referring to an empty square (5e5d). Book
        // should silently drop the bogus one and return only the valid pick.
        let json = r#"{
            "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -": [
                {"usi": "5e5d", "weight": 50},
                {"usi": "7g7f", "weight": 50}
            ]
        }"#;
        let book = OpeningBook::load_from_str(json).expect("parse");
        let board = Board::default();
        let mv = book.pick(&board, 0.0).expect("pick");
        assert_eq!(mv, Move::Board {
            from: Square::new(7, 7),
            to: Square::new(7, 6),
            promote: false,
        });
    }

    #[test]
    fn book_returns_none_outside_known_positions() {
        let json = r#"{}"#;
        let book = OpeningBook::load_from_str(json).expect("parse");
        let board = Board::default();
        assert!(book.pick(&board, 0.0).is_none());
    }

    #[test]
    fn book_greedy_picks_highest_weight() {
        let json = r#"{
            "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b -": [
                {"usi": "7g7f", "weight": 30},
                {"usi": "2g2f", "weight": 70}
            ]
        }"#;
        let book = OpeningBook::load_from_str(json).expect("parse");
        let board = Board::default();
        let mv = book.pick(&board, 0.0).expect("pick");
        assert_eq!(mv, Move::Board {
            from: Square::new(2, 7),
            to: Square::new(2, 6),
            promote: false,
        });
    }
}
