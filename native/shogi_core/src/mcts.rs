//! Single-threaded PUCT MCTS driven by the policy+value network.
//!
//! Simplifications vs. full AlphaZero:
//!   * no virtual loss (single-threaded)
//!   * no transposition sharing (tree only)
//!   * Dirichlet noise at the root only
//!
//! The tree is stored as an arena (`Vec<Node>` + `usize` indices) to sidestep
//! borrow-checker pain with recursive tree mutation.

use rand::Rng;

use crate::board::Board;
use crate::encode::encode_position;
use crate::move_index::{NUM_SQUARES, encode_move};
use crate::nn::NeuralNet;
use crate::rules::{has_any_legal_move, is_check, legal_drops, legal_moves_from};
use crate::types::{Color, Kind, Move, Square};

const C_PUCT: f32 = 1.5;
const DIRICHLET_ALPHA: f32 = 0.15;
const DIRICHLET_WEIGHT: f32 = 0.25;

#[derive(Clone, Debug)]
struct Child {
    mv: Move,
    node: Option<usize>,
    prior: f32,
}

#[derive(Clone, Debug)]
struct Node {
    n: u32,
    w: f32,
    /// `None` = not yet expanded. Terminal positions expand with an empty
    /// children list and store their deterministic value in `terminal_value`.
    children: Option<Vec<Child>>,
    terminal_value: Option<f32>,
}

impl Node {
    fn new() -> Self {
        Self { n: 0, w: 0.0, children: None, terminal_value: None }
    }
}

pub struct Searcher<'a> {
    nodes: Vec<Node>,
    nn: &'a NeuralNet,
}

impl<'a> Searcher<'a> {
    pub fn new(nn: &'a NeuralNet) -> Self {
        let mut nodes = Vec::with_capacity(1024);
        nodes.push(Node::new());
        Self { nodes, nn }
    }

    /// Run `n_playouts` MCTS iterations from the current board state and
    /// Run `n_playouts` MCTS iterations from the current board state and
    /// pick a root move by sampling from visit counts raised to
    /// `1/temperature`. `temperature == 0.0` → greedy (most-visited).
    /// Higher τ flattens the distribution; τ=1 is proportional to visits.
    /// Gives weaker characters plausible-looking mistakes without retraining.
    pub fn sample_move(
        &mut self,
        board: &mut Board,
        n_playouts: u32,
        temperature: f32,
    ) -> Option<Move> {
        // Expand root first so Dirichlet noise can be applied.
        self.ensure_expanded(0, board).ok()?;
        self.add_root_dirichlet_noise();

        for _ in 0..n_playouts {
            self.playout(board);
        }

        let root = &self.nodes[0];
        let children = root.children.as_ref()?;
        if children.is_empty() {
            return None;
        }

        if temperature <= 1e-6 {
            return children
                .iter()
                .max_by_key(|c| c.node.map(|i| self.nodes[i].n).unwrap_or(0))
                .map(|c| c.mv);
        }

        // visits^(1/τ). Small τ sharpens toward greedy; τ=1 leaves visits as-is.
        let inv_t = 1.0_f32 / temperature;
        let weights: Vec<f64> = children
            .iter()
            .map(|c| {
                let n = c.node.map(|i| self.nodes[i].n).unwrap_or(0) as f32;
                (n.max(1.0).powf(inv_t)) as f64
            })
            .collect();
        let sum: f64 = weights.iter().sum();
        if sum <= 0.0 {
            return children.first().map(|c| c.mv);
        }
        let mut rng = rand::rng();
        let r: f64 = rng.random::<f64>() * sum;
        let mut acc = 0.0;
        for (c, w) in children.iter().zip(weights.iter()) {
            acc += *w;
            if r <= acc {
                return Some(c.mv);
            }
        }
        children.last().map(|c| c.mv)
    }

    fn playout(&mut self, board: &mut Board) {
        // Descent.
        let mut path: Vec<usize> = vec![0];
        let mut moves_applied: Vec<Move> = Vec::new();
        let mut cur = 0usize;
        loop {
            if self.nodes[cur].terminal_value.is_some() {
                break;
            }
            if self.nodes[cur].children.is_none() {
                // Leaf — expand below.
                break;
            }
            let Some(chosen_idx) = self.select_child(cur) else { break };
            let (mv, child_slot) = {
                let c = &self.nodes[cur].children.as_ref().unwrap()[chosen_idx];
                (c.mv, c.node)
            };
            board.apply_move(mv);
            moves_applied.push(mv);
            let next = match child_slot {
                Some(idx) => idx,
                None => {
                    let idx = self.push_node();
                    self.nodes[cur].children.as_mut().unwrap()[chosen_idx].node = Some(idx);
                    idx
                }
            };
            path.push(next);
            cur = next;
        }

        // Evaluate leaf.
        let value_from_leaf_side = if self.nodes[cur].terminal_value.is_none() {
            match self.ensure_expanded(cur, board) {
                Ok(v) => v,
                Err(_) => 0.0,
            }
        } else {
            self.nodes[cur].terminal_value.unwrap()
        };

        // Backup — values alternate sign up the tree (each step flips
        // perspective to the ancestor's side-to-move).
        let mut v = value_from_leaf_side;
        for &idx in path.iter().rev() {
            self.nodes[idx].n += 1;
            self.nodes[idx].w += v;
            v = -v;
        }

        // Restore board.
        for _ in 0..moves_applied.len() {
            board.undo_move();
        }
    }

    /// Expand an unexpanded node. Returns the value (from the side-to-move's
    /// perspective at the node) that should be backed up.
    fn ensure_expanded(&mut self, idx: usize, board: &mut Board) -> Result<f32, ()> {
        if self.nodes[idx].children.is_some() || self.nodes[idx].terminal_value.is_some() {
            // Already expanded — fall back to a single NN eval.
            let (_, v) = self.nn.forward(&encode_position(board)).map_err(|_| ())?;
            return Ok(v);
        }
        let legal = all_legal_moves(board);
        if legal.is_empty() {
            // No legal moves — terminal. Checkmated side loses from its POV.
            let terminal = if is_check(board, board.side_to_move) { -1.0 } else { 0.0 };
            self.nodes[idx].children = Some(Vec::new());
            self.nodes[idx].terminal_value = Some(terminal);
            return Ok(terminal);
        }
        let (policy, value) = self.nn.forward(&encode_position(board)).map_err(|_| ())?;
        let stm = board.side_to_move;
        let children = build_child_priors(&legal, &policy, stm);
        self.nodes[idx].children = Some(children);
        Ok(value)
    }

    fn select_child(&self, node_idx: usize) -> Option<usize> {
        let node = &self.nodes[node_idx];
        let children = node.children.as_ref()?;
        if children.is_empty() {
            return None;
        }
        let sum_n: u32 = children.iter().map(|c| c.node.map(|i| self.nodes[i].n).unwrap_or(0)).sum();
        let sqrt_sum = (sum_n as f32).max(1.0).sqrt();
        let mut best_idx = 0usize;
        let mut best_score = f32::NEG_INFINITY;
        for (i, c) in children.iter().enumerate() {
            let (n_c, q_c) = match c.node {
                Some(idx) => {
                    let ch = &self.nodes[idx];
                    let q = if ch.n == 0 { 0.0 } else { -ch.w / ch.n as f32 };
                    (ch.n, q)
                }
                None => (0, 0.0),
            };
            let u = C_PUCT * c.prior * sqrt_sum / (1.0 + n_c as f32);
            let score = q_c + u;
            if score > best_score {
                best_score = score;
                best_idx = i;
            }
        }
        Some(best_idx)
    }

    fn push_node(&mut self) -> usize {
        self.nodes.push(Node::new());
        self.nodes.len() - 1
    }

    fn add_root_dirichlet_noise(&mut self) {
        let Some(children) = self.nodes[0].children.as_mut() else { return };
        if children.is_empty() {
            return;
        }
        let mut rng = rand::rng();
        let noise: Vec<f32> = (0..children.len())
            .map(|_| sample_gamma(&mut rng, DIRICHLET_ALPHA))
            .collect();
        let sum: f32 = noise.iter().sum();
        if sum <= 0.0 {
            return;
        }
        for (c, g) in children.iter_mut().zip(noise.iter()) {
            let dirichlet = g / sum;
            c.prior = (1.0 - DIRICHLET_WEIGHT) * c.prior + DIRICHLET_WEIGHT * dirichlet;
        }
    }
}

fn build_child_priors(legal: &[Move], policy_logits: &[f32], stm: Color) -> Vec<Child> {
    // Softmax over only the legal moves' logits — the net's tensor is dense
    // but we only care about legal indices.
    let mut logits = Vec::with_capacity(legal.len());
    for &mv in legal {
        let idx = encode_move(mv, stm).unwrap_or(0);
        logits.push(policy_logits.get(idx).copied().unwrap_or(f32::MIN));
    }
    let m = logits.iter().copied().fold(f32::MIN, f32::max);
    let mut exps: Vec<f32> = logits.iter().map(|&l| (l - m).exp()).collect();
    let sum: f32 = exps.iter().sum();
    if sum > 0.0 {
        for e in &mut exps {
            *e /= sum;
        }
    } else {
        let uniform = 1.0 / legal.len() as f32;
        exps.iter_mut().for_each(|e| *e = uniform);
    }
    legal
        .iter()
        .zip(exps.iter())
        .map(|(&mv, &p)| Child { mv, node: None, prior: p })
        .collect()
}

pub fn all_legal_moves(board: &mut Board) -> Vec<Move> {
    let side = board.side_to_move;
    let mut out = Vec::new();
    for r in 1..=9i8 {
        for f in 1..=9i8 {
            let sq = Square::new(f, r);
            if let Some(p) = board.piece_at(sq) {
                if p.color == side {
                    out.extend(legal_moves_from(board, sq));
                }
            }
        }
    }
    let kinds: Vec<Kind> = board.hand(side).keys().copied().collect();
    for k in kinds {
        out.extend(legal_drops(board, k));
    }
    let _ = has_any_legal_move; // keep Rules export visible
    let _ = NUM_SQUARES; // silence unused
    out
}

// --- Gamma(α, 1) via Marsaglia-Tsang for α >= 1, fallback sqrt trick for α < 1
fn sample_gamma<R: Rng + ?Sized>(rng: &mut R, alpha: f32) -> f32 {
    if alpha >= 1.0 {
        return sample_gamma_geq1(rng, alpha);
    }
    let g = sample_gamma_geq1(rng, alpha + 1.0);
    let u: f32 = rng.random();
    g * u.powf(1.0 / alpha)
}

fn sample_gamma_geq1<R: Rng + ?Sized>(rng: &mut R, alpha: f32) -> f32 {
    let d = alpha - 1.0 / 3.0;
    let c = 1.0 / (9.0 * d).sqrt();
    loop {
        let (x, v) = loop {
            let x: f32 = sample_standard_normal(rng);
            let v = 1.0 + c * x;
            if v > 0.0 {
                break (x, v);
            }
        };
        let v = v * v * v;
        let u: f32 = rng.random();
        if u < 1.0 - 0.0331 * x.powi(4) {
            return d * v;
        }
        if u.ln() < 0.5 * x * x + d * (1.0 - v + v.ln()) {
            return d * v;
        }
    }
}

fn sample_standard_normal<R: Rng + ?Sized>(rng: &mut R) -> f32 {
    // Box-Muller
    let u1: f32 = rng.random_range(1e-9..1.0);
    let u2: f32 = rng.random();
    (-2.0 * u1.ln()).sqrt() * (2.0 * std::f32::consts::PI * u2).cos()
}

