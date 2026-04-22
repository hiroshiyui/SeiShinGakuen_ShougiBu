//! Parity tests against Python fixtures dumped by `tools/gen_fixtures.py`.
//!
//! The fixture file (`tools/fixtures/fixtures.bin`) is ground truth from
//! ShogiDojo's real `encode_position` / `encode_move`. These tests load
//! each fixture, re-parse the SFEN into our Board, run our encoder /
//! move-index, and assert byte-exact equality.

use std::path::PathBuf;

use crate::encode::{NUM_INPUT_CHANNELS, PLANE_STRIDE, encode_position};
use crate::move_index::encode_move;
use crate::sfen::parse_sfen;
use crate::types::{Color, Kind, Move, Square};

struct FixtureMove {
    policy_idx: u32,
    is_drop: bool,
    promote: bool,
    from_file: i8,
    from_rank: i8,
    to_file: i8,
    to_rank: i8,
    drop_kind: u8,
}

struct Fixture {
    sfen: String,
    tensor: Vec<f32>,
    moves: Vec<FixtureMove>,
}

fn fixtures_path() -> PathBuf {
    let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    crate_dir.join("../../tools/fixtures/fixtures.bin")
}

fn read_u16(bytes: &[u8], pos: &mut usize) -> u16 {
    let v = u16::from_le_bytes([bytes[*pos], bytes[*pos + 1]]);
    *pos += 2;
    v
}
fn read_u32(bytes: &[u8], pos: &mut usize) -> u32 {
    let v = u32::from_le_bytes([bytes[*pos], bytes[*pos + 1], bytes[*pos + 2], bytes[*pos + 3]]);
    *pos += 4;
    v
}
fn read_u8(bytes: &[u8], pos: &mut usize) -> u8 {
    let v = bytes[*pos];
    *pos += 1;
    v
}
fn read_i8(bytes: &[u8], pos: &mut usize) -> i8 {
    let v = bytes[*pos] as i8;
    *pos += 1;
    v
}

fn load_fixtures() -> Vec<Fixture> {
    let path = fixtures_path();
    let bytes = std::fs::read(&path).unwrap_or_else(|e| {
        panic!(
            "failed to read {}: {e}. Regenerate with `python tools/gen_fixtures.py`.",
            path.display()
        )
    });
    let mut p = 0;
    let magic = &bytes[p..p + 8];
    assert_eq!(magic, b"SHGFIX\0\0", "bad fixture magic");
    p += 8;
    let version = read_u32(&bytes, &mut p);
    assert_eq!(version, 1, "unsupported fixture version");
    let n = read_u32(&bytes, &mut p) as usize;
    let tensor_bytes = NUM_INPUT_CHANNELS * PLANE_STRIDE * 4;

    let mut fixtures = Vec::with_capacity(n);
    for _ in 0..n {
        let sfen_len = read_u16(&bytes, &mut p) as usize;
        let sfen = String::from_utf8(bytes[p..p + sfen_len].to_vec()).expect("sfen utf-8");
        p += sfen_len;
        let tensor = bytemuck_f32_le_slice(&bytes[p..p + tensor_bytes]);
        p += tensor_bytes;
        let m = read_u32(&bytes, &mut p) as usize;
        let mut moves = Vec::with_capacity(m);
        for _ in 0..m {
            let policy_idx = read_u32(&bytes, &mut p);
            let is_drop = read_u8(&bytes, &mut p) != 0;
            let promote = read_u8(&bytes, &mut p) != 0;
            let from_file = read_i8(&bytes, &mut p);
            let from_rank = read_i8(&bytes, &mut p);
            let to_file = read_i8(&bytes, &mut p);
            let to_rank = read_i8(&bytes, &mut p);
            let drop_kind = read_u8(&bytes, &mut p);
            moves.push(FixtureMove {
                policy_idx, is_drop, promote,
                from_file, from_rank, to_file, to_rank, drop_kind,
            });
        }
        fixtures.push(Fixture { sfen, tensor, moves });
    }
    assert_eq!(p, bytes.len(), "trailing bytes in fixture file");
    fixtures
}

/// Little-endian f32 slice — avoid pulling in bytemuck for a single use.
fn bytemuck_f32_le_slice(bytes: &[u8]) -> Vec<f32> {
    assert_eq!(bytes.len() % 4, 0);
    bytes
        .chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

#[test]
fn encoder_matches_shogidojo_byte_exact() {
    let fixtures = load_fixtures();
    assert!(!fixtures.is_empty(), "no fixtures found");
    for (i, fx) in fixtures.iter().enumerate() {
        let board = parse_sfen(&fx.sfen).unwrap_or_else(|e| panic!("parse {}: {e}", fx.sfen));
        let ours = encode_position(&board);
        assert_eq!(ours.len(), fx.tensor.len(), "fixture {i}: length mismatch");
        for (j, (&a, &b)) in ours.iter().zip(fx.tensor.iter()).enumerate() {
            // The fixture uses float32 exact equality — both sides should
            // produce identical bit patterns since the operations are just
            // integer division by small constants and plane fills.
            if a != b {
                let plane = j / PLANE_STRIDE;
                let y = (j % PLANE_STRIDE) / 9;
                let x = j % 9;
                panic!(
                    "fixture {i} ({}): tensor mismatch at plane {plane} y={y} x={x}: ours={a} theirs={b}",
                    fx.sfen
                );
            }
        }
    }
}

#[test]
fn move_index_matches_shogidojo() {
    let fixtures = load_fixtures();
    for (i, fx) in fixtures.iter().enumerate() {
        let board = parse_sfen(&fx.sfen).unwrap();
        let stm = board.side_to_move;
        for fm in &fx.moves {
            let mv = if fm.is_drop {
                Move::Drop {
                    kind: Kind::from_u8(fm.drop_kind).expect("drop kind"),
                    to: Square::new(fm.to_file, fm.to_rank),
                }
            } else {
                Move::Board {
                    from: Square::new(fm.from_file, fm.from_rank),
                    to: Square::new(fm.to_file, fm.to_rank),
                    promote: fm.promote,
                }
            };
            let got = encode_move(mv, stm)
                .unwrap_or_else(|| panic!("fixture {i}: encode_move returned None for {mv:?}"));
            assert_eq!(
                got as u32, fm.policy_idx,
                "fixture {i} ({}): move {mv:?} encoded to {got} but expected {}",
                fx.sfen, fm.policy_idx
            );
        }
    }
    // silence unused-Color warning if nothing in this function happens to use it
    let _ = Color::Sente;
}
