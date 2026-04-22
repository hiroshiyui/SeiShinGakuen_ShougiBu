mod board;
mod encode;
mod move_index;
mod movegen;
mod rules;
mod sfen;
mod types;

#[cfg(test)]
mod parity_tests;
#[cfg(test)]
mod tests;

use godot::prelude::*;

use crate::board::Board;
use crate::rules::{SennichiteStatus, detect_sennichite, is_check, is_checkmate, jishogi_points, king_entered, legal_drops, legal_moves_from};
use crate::types::{Color, Kind, Move, Square};

struct ShogiCoreExt;

#[gdextension]
unsafe impl ExtensionLibrary for ShogiCoreExt {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ShogiCore {
    board: Board,
}

#[godot_api]
impl IRefCounted for ShogiCore {
    fn init(_base: Base<RefCounted>) -> Self {
        Self { board: Board::default() }
    }
}

#[godot_api]
impl ShogiCore {
    // --- queries ------------------------------------------------------------

    #[func]
    fn to_sfen(&self) -> GString {
        sfen::to_sfen(&self.board).into()
    }

    #[func]
    fn position_key(&self) -> GString {
        sfen::position_key(&self.board).into()
    }

    #[func]
    fn side_to_move_gote(&self) -> bool {
        self.board.side_to_move.is_gote()
    }

    #[func]
    fn move_log_size(&self) -> i64 {
        self.board.log.len() as i64
    }

    #[func]
    fn piece_at(&self, file: i64, rank: i64) -> Variant {
        let Some(piece) = self.board.piece_at(Square::new(file as i8, rank as i8)) else {
            return Variant::nil();
        };
        let mut d = Dictionary::new();
        d.set("kind", piece.kind as i64);
        d.set("is_gote", piece.color.is_gote());
        d.to_variant()
    }

    #[func]
    fn hand(&self, is_gote: bool) -> Dictionary {
        let mut d = Dictionary::new();
        for (&k, &n) in self.board.hand(Color::from_gote(is_gote)) {
            d.set(k as i64, n as i64);
        }
        d
    }

    // --- mutations ----------------------------------------------------------

    #[func]
    fn reset_starting(&mut self) {
        self.board.reset_starting();
    }

    #[func]
    fn clear_board(&mut self) {
        self.board.clear();
    }

    #[func]
    fn place(&mut self, file: i64, rank: i64, kind: i64, is_gote: bool) {
        let Some(k) = Kind::from_u8(kind as u8) else { return };
        self.board.place(
            Square::new(file as i8, rank as i8),
            crate::types::Piece::new(k, Color::from_gote(is_gote)),
        );
    }

    #[func]
    fn set_hand_count(&mut self, is_gote: bool, kind: i64, count: i64) {
        let Some(k) = Kind::from_u8(kind as u8) else { return };
        self.board.set_hand_count(Color::from_gote(is_gote), k, count.max(0) as u32);
    }

    #[func]
    fn set_side_to_move_gote(&mut self, is_gote: bool) {
        self.board.side_to_move = Color::from_gote(is_gote);
    }

    #[func]
    fn seal_initial_position(&mut self) {
        self.board.position_counts.clear();
        let key = sfen::position_key(&self.board);
        *self.board.position_counts.entry(key).or_insert(0) += 1;
    }

    #[func]
    fn apply_move(&mut self, move_dict: Dictionary) -> bool {
        let Some(mv) = dict_to_move(&move_dict) else { return false };
        if !self.board.apply_move(mv) {
            return false;
        }
        let was_check = is_check(&self.board, self.board.side_to_move);
        let key = sfen::position_key(&self.board);
        self.board.tag_last_move(was_check, key);
        true
    }

    #[func]
    fn undo_move(&mut self) -> bool {
        self.board.undo_move()
    }

    // --- rules --------------------------------------------------------------

    #[func]
    fn legal_moves_from(&mut self, file: i64, rank: i64) -> Array<Dictionary> {
        let moves = legal_moves_from(&mut self.board, Square::new(file as i8, rank as i8));
        moves.into_iter().map(move_to_dict).collect()
    }

    #[func]
    fn legal_drops(&mut self, kind: i64) -> Array<Dictionary> {
        let Some(k) = Kind::from_u8(kind as u8) else { return Array::new() };
        let moves = legal_drops(&mut self.board, k);
        moves.into_iter().map(move_to_dict).collect()
    }

    #[func]
    fn is_check(&self) -> bool {
        is_check(&self.board, self.board.side_to_move)
    }

    #[func]
    fn is_checkmate(&mut self) -> bool {
        is_checkmate(&mut self.board)
    }

    #[func]
    fn detect_sennichite(&self) -> GString {
        match detect_sennichite(&self.board) {
            SennichiteStatus::None => "none".into(),
            SennichiteStatus::Draw => "draw".into(),
            SennichiteStatus::SenteLoses => "sente_loses".into(),
            SennichiteStatus::GoteLoses => "gote_loses".into(),
        }
    }

    #[func]
    fn king_entered(&self, is_gote: bool) -> bool {
        king_entered(&self.board, Color::from_gote(is_gote))
    }

    #[func]
    fn jishogi_points(&self, is_gote: bool) -> i64 {
        jishogi_points(&self.board, Color::from_gote(is_gote)) as i64
    }
}

// --- move <-> dict conversions ---------------------------------------------

fn move_to_dict(mv: Move) -> Dictionary {
    let mut d = Dictionary::new();
    match mv {
        Move::Board { from, to, promote } => {
            d.set("from", Vector2i::new(from.file as i32, from.rank as i32));
            d.set("to", Vector2i::new(to.file as i32, to.rank as i32));
            d.set("promote", promote);
        }
        Move::Drop { kind, to } => {
            d.set("drop_kind", kind as i64);
            d.set("to", Vector2i::new(to.file as i32, to.rank as i32));
        }
    }
    d
}

fn dict_to_move(d: &Dictionary) -> Option<Move> {
    if let Some(v) = d.get("drop_kind") {
        let kind = Kind::from_u8(v.try_to::<i64>().ok()? as u8)?;
        let to: Vector2i = d.get("to")?.try_to().ok()?;
        return Some(Move::Drop {
            kind,
            to: Square::new(to.x as i8, to.y as i8),
        });
    }
    let from: Vector2i = d.get("from")?.try_to().ok()?;
    let to: Vector2i = d.get("to")?.try_to().ok()?;
    let promote: bool = d.get("promote").and_then(|v| v.try_to().ok()).unwrap_or(false);
    Some(Move::Board {
        from: Square::new(from.x as i8, from.y as i8),
        to: Square::new(to.x as i8, to.y as i8),
        promote,
    })
}
