#!/usr/bin/env python3
"""Dump byte-exact (45,9,9) tensor + move-index fixtures from ShogiDojo's
Python encoder so Rust can assert parity.

Run with ShogiDojo's venv interpreter, not the system Python:

    /home/yhh/MyProjects/ShogiDojo/virtualenv/bin/python tools/gen_fixtures.py

Outputs one binary file `tools/fixtures/fixtures.bin` with the layout
documented at the bottom of this module. The Rust side is in
`native/shogi_core/src/fixtures.rs` (test-only).
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# Add ShogiDojo to sys.path.
SHOGI_DOJO_ROOT = Path("/home/yhh/MyProjects/ShogiDojo")
sys.path.insert(0, str(SHOGI_DOJO_ROOT / "src"))

import shogi  # type: ignore
from shogi_dojo.alphazero.encoding import (  # type: ignore
    Move,
    POLICY_DIM,
    encode_move,
    encode_position,
    position_from_sfen,
)
from shogi_dojo.nnue.constants import (  # type: ignore
    BISHOP,
    BLACK,
    DRAGON,
    GOLD,
    HORSE,
    KING,
    KNIGHT,
    LANCE,
    PAWN,
    PRO_KNIGHT,
    PRO_LANCE,
    PRO_PAWN,
    PRO_SILVER,
    ROOK,
    SILVER,
    WHITE,
)

# Map ShogiDojo piece-type IDs → our Rust Kind discriminants (0..13).
# Our Rust order: Pawn=0, Lance=1, Knight=2, Silver=3, Gold=4, Bishop=5,
# Rook=6, King=7, PromotedPawn=8, PromotedLance=9, PromotedKnight=10,
# PromotedSilver=11, Horse=12, Dragon=13.
SHOGIDOJO_TO_RUST_KIND = {
    PAWN: 0, LANCE: 1, KNIGHT: 2, SILVER: 3, GOLD: 4, BISHOP: 5, ROOK: 6,
    KING: 7,
    PRO_PAWN: 8, PRO_LANCE: 9, PRO_KNIGHT: 10, PRO_SILVER: 11,
    HORSE: 12, DRAGON: 13,
}

# Map python-shogi piece-type IDs (PAWN=1..PROM_ROOK=14) → our Rust Kind.
# python-shogi's promoted IDs: PROM_PAWN=9, PROM_LANCE=10, PROM_KNIGHT=11,
# PROM_SILVER=12, PROM_BISHOP=13, PROM_ROOK=14.
PYSHOGI_TO_RUST_KIND = {
    shogi.PAWN: 0,
    shogi.LANCE: 1,
    shogi.KNIGHT: 2,
    shogi.SILVER: 3,
    shogi.GOLD: 4,
    shogi.BISHOP: 5,
    shogi.ROOK: 6,
    shogi.KING: 7,
    shogi.PROM_PAWN: 8,
    shogi.PROM_LANCE: 9,
    shogi.PROM_KNIGHT: 10,
    shogi.PROM_SILVER: 11,
    shogi.PROM_BISHOP: 12,  # Horse
    shogi.PROM_ROOK: 13,    # Dragon
}


def pyshogi_square_to_file_rank(sq: int) -> tuple[int, int]:
    """python-shogi: sq 0 = "9a" = our (file=9, rank=1); sq 80 = "1i" = (1,9)."""
    return 9 - (sq % 9), (sq // 9) + 1


def pyshogi_move_to_rust(m: shogi.Move) -> tuple:
    """Convert a python-shogi Move into the Rust-side tuple
    (is_drop, from_file, from_rank, to_file, to_rank, promote, drop_kind).

    Squares are 1-indexed file/rank in sente-bottom coordinates.
    drop_kind is our Rust Kind discriminant (only meaningful if is_drop).
    """
    to_file, to_rank = pyshogi_square_to_file_rank(m.to_square)
    if m.from_square is not None:
        from_file, from_rank = pyshogi_square_to_file_rank(m.from_square)
        return (False, from_file, from_rank, to_file, to_rank, bool(m.promotion), 0)
    # drop
    drop_kind = PYSHOGI_TO_RUST_KIND[m.drop_piece_type]
    return (True, 0, 0, to_file, to_rank, False, drop_kind)


def shogidojo_move_from_pyshogi(m: shogi.Move) -> Move:
    """Build the ShogiDojo Move dataclass from a python-shogi Move."""
    if m.from_square is not None:
        return Move(
            from_square=m.from_square,
            to_square=m.to_square,
            promote=bool(m.promotion),
        )
    # python-shogi's drop_piece_type IDs are 1..7 (PAWN..ROOK); ShogiDojo
    # uses 0..6 for the same, shifted by one.
    pyshogi_drop = m.drop_piece_type
    shogidojo_drop = pyshogi_drop - 1
    return Move(
        from_square=None,
        to_square=m.to_square,
        drop_piece=shogidojo_drop,
        promote=False,
    )


def collect_fixtures() -> list[str]:
    """Return a list of SFENs covering diverse board states."""
    sfens = [
        # 1. starting position, sente to move
        "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1",
        # 2. starting position, gote to move (exercises the flip)
        "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL w - 1",
    ]
    # Play a handful of moves to create additional diverse positions.
    board = shogi.Board()
    play_lines = [
        # Opening moves — exercise promotion zone, captures later
        ["2g2f", "3c3d", "7g7f", "4c4d", "2f2e", "8b4b", "3i4h", "3a3b"],
    ]
    for line in play_lines:
        board.reset()
        for usi in line:
            board.push_usi(usi)
            sfens.append(board.sfen())
    # A position with promoted pieces and pieces in hand.
    # Construct by editing SFEN — sente has a dragon on 2八, a horse on 8八,
    # and a pawn in hand; gote has silver + gold in hand.
    sfens.append(
        "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1+B5+R1/LNSGKGSNL b PSGps 5"
    )
    # Edge-rank case: a lance about to promote (both kings required).
    sfens.append("9/9/9/9/4k4/9/9/9/4K3L b - 1")
    # Both kings in corner quadrants.
    sfens.append("k8/9/9/9/9/9/9/9/8K b - 1")
    return sfens


def dump() -> None:
    out_dir = Path(__file__).resolve().parent / "fixtures"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "fixtures.bin"

    sfens = collect_fixtures()

    with out_path.open("wb") as f:
        # magic
        f.write(b"SHGFIX\0\0")
        f.write(struct.pack("<II", 1, len(sfens)))  # version, count

        for sfen in sfens:
            pos = position_from_sfen(sfen)
            tensor = encode_position(pos).contiguous()
            tensor_bytes = tensor.numpy().tobytes()
            assert len(tensor_bytes) == 45 * 9 * 9 * 4

            # Collect legal moves for parity via python-shogi.
            board = shogi.Board(sfen)
            moves = list(board.legal_moves)
            stm = BLACK if pos.side_to_move == 0 else WHITE

            # Encode each move with ShogiDojo.
            move_records: list[tuple] = []
            for m in moves:
                sdm = shogidojo_move_from_pyshogi(m)
                idx = encode_move(sdm, stm)
                assert 0 <= idx < POLICY_DIM
                rust_tuple = pyshogi_move_to_rust(m)
                move_records.append((idx,) + rust_tuple)

            # Write fixture.
            sfen_bytes = sfen.encode("utf-8")
            f.write(struct.pack("<H", len(sfen_bytes)))
            f.write(sfen_bytes)
            f.write(tensor_bytes)
            f.write(struct.pack("<I", len(move_records)))
            for rec in move_records:
                # rec = (policy_idx, is_drop, from_f, from_r, to_f, to_r, promote, drop_kind)
                idx, is_drop, ff, fr, tf, tr, promote, dk = rec
                f.write(
                    struct.pack(
                        "<I B B b b b b B",
                        idx,
                        1 if is_drop else 0,
                        1 if promote else 0,
                        ff, fr, tf, tr,
                        dk,
                    )
                )

    print(f"Wrote {len(sfens)} fixtures to {out_path}")
    print(f"Size: {out_path.stat().st_size} bytes")


if __name__ == "__main__":
    dump()

# -----------------------------------------------------------------------------
# Binary layout (all little-endian):
#
#   magic            : 8 bytes  "SHGFIX\0\0"
#   version          : u32       (= 1)
#   num_fixtures     : u32
#
# Then for each fixture:
#   sfen_len         : u16
#   sfen             : <sfen_len> bytes (UTF-8, no NUL terminator)
#   tensor           : 45 * 9 * 9 f32 = 14580 bytes
#   num_moves        : u32
#   moves            : num_moves * 12 bytes, each:
#                        policy_idx : u32     (ShogiDojo's flat index, 0..11258)
#                        is_drop    : u8      (0 | 1)
#                        promote    : u8      (0 | 1)
#                        from_file  : i8      (1..9, or 0 if is_drop)
#                        from_rank  : i8      (1..9, or 0 if is_drop)
#                        to_file    : i8      (1..9)
#                        to_rank    : i8      (1..9)
#                        drop_kind  : u8      (Rust Kind discriminant 0..6, else 0)
# -----------------------------------------------------------------------------
