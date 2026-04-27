mod board;
mod encode;
mod kifu;
mod mcts;
mod move_index;
mod movegen;
mod nn;
mod rules;
mod sfen;
mod types;

#[cfg(test)]
mod parity_tests;
#[cfg(test)]
mod tests;

use std::path::PathBuf;

use godot::prelude::*;

use crate::board::Board;
use crate::encode::encode_position;
use crate::mcts::{Searcher, all_legal_moves};
use crate::move_index::encode_move;
use crate::nn::NeuralNet;
use crate::rules::{SennichiteStatus, detect_sennichite, is_check, is_checkmate, jishogi_points, king_entered, legal_drops, legal_moves_from};
use crate::sfen::parse_sfen;
use crate::types::{Color, Kind, Move, Square};

struct ShogiCoreExt;

#[gdextension]
unsafe impl ExtensionLibrary for ShogiCoreExt {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ShogiCore {
    board: Board,
    nn: Option<NeuralNet>,
}

#[godot_api]
impl IRefCounted for ShogiCore {
    fn init(_base: Base<RefCounted>) -> Self {
        Self { board: Board::default(), nn: None }
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
    fn move_log_kifu_lines(&self) -> PackedStringArray {
        let mut arr = PackedStringArray::new();
        for s in kifu::log_to_lines(&self.board) {
            arr.push(&GString::from(s));
        }
        arr
    }

    /// Parse a KIF document into the same packed-i32 log shape
    /// `move_log_packed()` produces. Returns an empty array on failure
    /// (caller should treat as "could not parse — show error").
    #[func]
    fn parse_kif_to_packed(&self, text: GString) -> PackedInt32Array {
        let mut out = PackedInt32Array::new();
        match kifu::parse_kif(&text.to_string()) {
            Ok(packed) => {
                for v in packed {
                    out.push(v);
                }
            }
            Err(e) => godot_warn!("parse_kif: {}", e),
        }
        out
    }

    #[func]
    fn to_kif(&self, sente_name: GString, gote_name: GString, started_at: GString) -> GString {
        kifu::to_kif(
            &self.board,
            &sente_name.to_string(),
            &gote_name.to_string(),
            &started_at.to_string(),
        )
        .into()
    }

    #[func]
    fn move_log_packed(&self) -> PackedInt32Array {
        let mut arr = PackedInt32Array::new();
        for v in kifu::pack_log(&self.board) {
            arr.push(v);
        }
        arr
    }

    /// Reset to the standard starting position and replay each packed move
    /// in turn (with sennichite + check tags). Returns false if any move
    /// fails to apply — caller should `reset_starting()` and treat as a
    /// fresh game.
    #[func]
    fn apply_packed(&mut self, packed: PackedInt32Array) -> bool {
        self.board.reset_starting();
        let key = sfen::position_key(&self.board);
        *self.board.position_counts.entry(key).or_insert(0) += 1;
        for i in 0..packed.len() {
            let Some(mv) = kifu::unpack_move(packed.get(i).unwrap_or(0)) else {
                return false;
            };
            if !self.board.apply_move(mv) {
                return false;
            }
            let was_check = is_check(&self.board, self.board.side_to_move);
            let key = sfen::position_key(&self.board);
            self.board.tag_last_move(was_check, key);
        }
        true
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

    // --- SFEN import --------------------------------------------------------

    #[func]
    fn load_sfen(&mut self, sfen: GString) -> bool {
        match parse_sfen(&sfen.to_string()) {
            Ok(b) => {
                self.board = b;
                true
            }
            Err(e) => {
                godot_warn!("load_sfen failed: {e}");
                false
            }
        }
    }

    // --- AI -----------------------------------------------------------------

    #[func]
    fn load_model(&mut self, path: GString) -> bool {
        match NeuralNet::load(&PathBuf::from(path.to_string())) {
            Ok(nn) => {
                self.nn = Some(nn);
                true
            }
            Err(e) => {
                godot_warn!("load_model failed: {e}");
                false
            }
        }
    }

    #[func]
    fn has_model(&self) -> bool {
        self.nn.is_some()
    }

    /// Run MCTS from the current position and return the best move as a
    /// `Dictionary` (same shape as `legal_moves_from`). Returns `null` if
    /// no model is loaded or the search found no legal moves.
    ///
    /// This is synchronous and will block for the duration of the search.
    /// GDScript is expected to call it from a `Thread` to avoid UI stalls.
    /// Policy-only move suggestions for 先生 (teacher) mode. Runs a single
    /// NN forward pass, softmaxes the policy logits over legal moves, and
    /// returns the top `top_k` as move dicts with an added `score` field
    /// (prior probability, 0..1). Cheap (~few ms) so safe to call on the
    /// main thread. Empty if no model / no legal moves.
    #[func]
    fn suggest_moves(&mut self, top_k: i64) -> Array<Dictionary> {
        let Some(nn) = self.nn.as_ref() else {
            godot_warn!("suggest_moves called before load_model");
            return Array::new();
        };
        let legal = all_legal_moves(&mut self.board);
        if legal.is_empty() {
            return Array::new();
        }
        let (policy, _value) = match nn.forward(&encode_position(&self.board)) {
            Ok(p) => p,
            Err(e) => {
                godot_warn!("suggest_moves: nn.forward failed: {e}");
                return Array::new();
            }
        };
        let stm = self.board.side_to_move;
        let mut logits: Vec<f32> = legal
            .iter()
            .map(|&mv| {
                let idx = encode_move(mv, stm).unwrap_or(0);
                policy.get(idx).copied().unwrap_or(f32::MIN)
            })
            .collect();
        let m = logits.iter().copied().fold(f32::MIN, f32::max);
        for l in &mut logits {
            *l = (*l - m).exp();
        }
        let sum: f32 = logits.iter().sum();
        if sum > 0.0 {
            for l in &mut logits {
                *l /= sum;
            }
        }
        let mut scored: Vec<(Move, f32)> =
            legal.iter().zip(logits.iter()).map(|(&mv, &p)| (mv, p)).collect();
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        let k = (top_k.max(1) as usize).min(scored.len());
        let mut out = Array::new();
        for (mv, p) in scored.into_iter().take(k) {
            let mut d = move_to_dict(mv);
            d.set("score", p as f64);
            out.push(&d);
        }
        out
    }

    /// MCTS-backed move suggestions for 先生 (teacher) mode. Runs a full
    /// search for `playouts` iterations, then returns the top `top_k` root
    /// moves sorted by visit count. Each dict has the same fields as
    /// `legal_moves_from` plus `visits` (i64) and `win_rate` (f64, 0..1 from
    /// the current player's perspective — search-backed, not policy-only).
    /// Blocks for the duration of the search — call from a Godot `Thread`.
    #[func]
    fn suggest_moves_mcts(&mut self, top_k: i64, playouts: i64) -> Array<Dictionary> {
        let Some(nn) = self.nn.as_ref() else {
            godot_warn!("suggest_moves_mcts called before load_model");
            return Array::new();
        };
        let n = playouts.max(1) as u32;
        let k = top_k.max(1) as usize;
        let mut searcher = Searcher::new(nn);
        // Temperature is irrelevant for suggestions — we only consume the
        // populated tree, not the sampled move.
        let _ = searcher.sample_move(&mut self.board, n, 0.0);
        let mut out = Array::new();
        for (mv, visits, q) in searcher.top_k_root_children(k) {
            let mut d = move_to_dict(mv);
            d.set("visits", visits as i64);
            let win_rate = ((q + 1.0) / 2.0).clamp(0.0, 1.0) as f64;
            d.set("win_rate", win_rate);
            out.push(&d);
        }
        out
    }

    #[func]
    fn think_best_move(&mut self, playouts: i64) -> Variant {
        self.think_sampled(playouts, 0.0)
    }

    /// MCTS with visit-count sampling. `temperature == 0.0` is greedy
    /// (most-visited root move); larger values flatten the
    /// distribution for weaker / more varied play. Blocks for the duration
    /// of the search — call from a Godot `Thread`.
    #[func]
    fn think_sampled(&mut self, playouts: i64, temperature: f64) -> Variant {
        let Some(nn) = self.nn.as_ref() else {
            godot_warn!("think_sampled called before load_model");
            return Variant::nil();
        };
        let n = playouts.max(1) as u32;
        let t = temperature.max(0.0) as f32;
        let mut searcher = Searcher::new(nn);
        match searcher.sample_move(&mut self.board, n, t) {
            Some(m) => move_to_dict(m).to_variant(),
            None => Variant::nil(),
        }
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
