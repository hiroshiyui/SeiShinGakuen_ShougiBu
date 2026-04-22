//! SFEN (Shogi Forsyth-Edwards Notation) parser and serializer.
//!
//! Format: `<board> <side> <hand> <ply>`
//!
//! - board: 9 rank-strings separated by `/`, rank 1 first; within each rank
//!   files run 9..=1. Uppercase = sente, lowercase = gote, `+` prefix =
//!   promoted, digit 1..9 = run of empty squares.
//! - side: `b` (sente / black) or `w` (gote / white).
//! - hand: concatenated `(count)(letter)` groups, or `-` if empty. Count
//!   defaults to 1 when absent.
//! - ply: 1-based move number — number of the move about to be played.

use crate::board::{Board, HAND_ORDER};
use crate::types::{Color, Kind, Piece, Square};

/// Position key used for sennichite: `"<board> <side> <hand>"` with no
/// move-number field.
pub fn position_key(board: &Board) -> String {
    let side = match board.side_to_move {
        Color::Sente => 'b',
        Color::Gote => 'w',
    };
    format!("{} {} {}", board_sfen(board), side, hand_sfen(board))
}

/// Full SFEN including the ply-counter field.
pub fn to_sfen(board: &Board) -> String {
    format!("{} {}", position_key(board), board.current_ply())
}

fn board_sfen(board: &Board) -> String {
    let mut rows: Vec<String> = Vec::with_capacity(9);
    for r in 1..=9 {
        let mut row = String::new();
        let mut empty = 0u32;
        for f in (1..=9).rev() {
            match board.piece_at(Square::new(f, r)) {
                None => empty += 1,
                Some(p) => {
                    if empty > 0 {
                        row.push_str(&empty.to_string());
                        empty = 0;
                    }
                    if p.kind.is_promoted() {
                        row.push('+');
                    }
                    let letter = p.kind.sfen_letter();
                    if p.color.is_gote() {
                        row.push(letter.to_ascii_lowercase());
                    } else {
                        row.push(letter);
                    }
                }
            }
        }
        if empty > 0 {
            row.push_str(&empty.to_string());
        }
        rows.push(row);
    }
    rows.join("/")
}

// ----- parser --------------------------------------------------------------

#[derive(Debug)]
pub struct SfenError(pub String);

impl std::fmt::Display for SfenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "sfen: {}", self.0)
    }
}

fn kind_from_letter(letter: char) -> Option<Kind> {
    Some(match letter.to_ascii_uppercase() {
        'P' => Kind::Pawn,
        'L' => Kind::Lance,
        'N' => Kind::Knight,
        'S' => Kind::Silver,
        'G' => Kind::Gold,
        'B' => Kind::Bishop,
        'R' => Kind::Rook,
        'K' => Kind::King,
        _ => return None,
    })
}

/// Parse a full SFEN string into a `Board`. Board state is fully initialised:
/// side-to-move, hands, starting_ply, and position_counts are set (the
/// starting position is sealed with count 1 so sennichite counters work).
pub fn parse_sfen(s: &str) -> Result<Board, SfenError> {
    let parts: Vec<&str> = s.split_whitespace().collect();
    if parts.len() != 4 {
        return Err(SfenError(format!(
            "expected 4 whitespace-separated fields, got {}",
            parts.len()
        )));
    }
    let (board_str, side_str, hand_str, ply_str) = (parts[0], parts[1], parts[2], parts[3]);

    let mut board = Board::empty();
    parse_board_field(board_str, &mut board)?;

    board.side_to_move = match side_str {
        "b" => Color::Sente,
        "w" => Color::Gote,
        other => return Err(SfenError(format!("side-to-move must be b or w, got {other:?}"))),
    };

    parse_hand_field(hand_str, &mut board)?;

    let ply: u32 = ply_str
        .parse()
        .map_err(|_| SfenError(format!("ply: not an integer: {ply_str:?}")))?;
    board.starting_ply = ply.max(1);

    // Seal the loaded position as count=1 so repetition detection is correct.
    board.position_counts.clear();
    let key = position_key(&board);
    *board.position_counts.entry(key).or_insert(0) += 1;

    Ok(board)
}

fn parse_board_field(board_str: &str, board: &mut Board) -> Result<(), SfenError> {
    let ranks: Vec<&str> = board_str.split('/').collect();
    if ranks.len() != 9 {
        return Err(SfenError(format!(
            "board: expected 9 ranks separated by '/', got {}",
            ranks.len()
        )));
    }
    for (rank_idx, rank_str) in ranks.iter().enumerate() {
        let rank = (rank_idx as i8) + 1; // SFEN: first rank in string is rank 1
        let mut file = 9i8; // Files run 9..=1 within a rank string.
        let mut promoted_next = false;
        let mut chars = rank_str.chars();
        while let Some(c) = chars.next() {
            if c == '+' {
                if promoted_next {
                    return Err(SfenError("board: double '+' in rank".into()));
                }
                promoted_next = true;
                continue;
            }
            if let Some(d) = c.to_digit(10) {
                if promoted_next {
                    return Err(SfenError("board: '+' followed by digit".into()));
                }
                let n = d as i8;
                if n < 1 || n > 9 {
                    return Err(SfenError(format!("board: empty run {n} out of range")));
                }
                file -= n;
                continue;
            }
            let color = if c.is_ascii_uppercase() { Color::Sente } else { Color::Gote };
            let Some(base) = kind_from_letter(c) else {
                return Err(SfenError(format!("board: unknown piece letter {c:?}")));
            };
            let kind = if promoted_next {
                if !base.can_promote() {
                    return Err(SfenError(format!(
                        "board: piece {c:?} cannot be promoted"
                    )));
                }
                base.promoted()
            } else {
                base
            };
            promoted_next = false;
            if file < 1 || file > 9 {
                return Err(SfenError("board: rank overflowed file range".into()));
            }
            board.place(Square::new(file, rank), Piece::new(kind, color));
            file -= 1;
        }
        if promoted_next {
            return Err(SfenError("board: trailing '+' with no piece".into()));
        }
        if file != 0 {
            return Err(SfenError(format!(
                "board: rank {rank} did not fill 9 files (file index left at {file})"
            )));
        }
    }
    Ok(())
}

fn parse_hand_field(hand_str: &str, board: &mut Board) -> Result<(), SfenError> {
    if hand_str == "-" {
        return Ok(());
    }
    let mut chars = hand_str.chars().peekable();
    while let Some(&c) = chars.peek() {
        let count: u32 = if c.is_ascii_digit() {
            let mut s = String::new();
            while let Some(&d) = chars.peek() {
                if d.is_ascii_digit() {
                    s.push(d);
                    chars.next();
                } else {
                    break;
                }
            }
            s.parse().map_err(|_| SfenError(format!("hand: bad count {s:?}")))?
        } else {
            1
        };
        let Some(letter) = chars.next() else {
            return Err(SfenError("hand: count without letter".into()));
        };
        let color = if letter.is_ascii_uppercase() { Color::Sente } else { Color::Gote };
        let Some(kind) = kind_from_letter(letter) else {
            return Err(SfenError(format!("hand: unknown piece letter {letter:?}")));
        };
        if !matches!(
            kind,
            Kind::Pawn | Kind::Lance | Kind::Knight | Kind::Silver
                | Kind::Gold | Kind::Bishop | Kind::Rook
        ) {
            return Err(SfenError(format!("hand: non-droppable piece {letter:?}")));
        }
        let entry = board.hand_mut(color).entry(kind).or_insert(0);
        *entry += count;
    }
    Ok(())
}

// ----- serializer helpers --------------------------------------------------

fn hand_sfen(board: &Board) -> String {
    let mut s = String::new();
    for color in [Color::Sente, Color::Gote] {
        let h = board.hand(color);
        for &kind in HAND_ORDER.iter() {
            let n = h.get(&kind).copied().unwrap_or(0);
            if n == 0 {
                continue;
            }
            if n > 1 {
                s.push_str(&n.to_string());
            }
            let letter = kind.sfen_letter();
            if color.is_gote() {
                s.push(letter.to_ascii_lowercase());
            } else {
                s.push(letter);
            }
        }
    }
    if s.is_empty() {
        s.push('-');
    }
    s
}
