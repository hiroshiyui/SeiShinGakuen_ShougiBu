//! ONNX inference via `tract` (pure-Rust, no C++ runtime dep).
//!
//! The Bonanza network is tiny (~1.3 MB) and tract handles its ops natively,
//! so we trade a bit of inference throughput for zero shared-library plumbing
//! on Android. Session load time is ~50 ms on desktop; per-call forward-pass
//! on an idle CPU is ~2 ms.

use std::path::Path;

use tract_onnx::prelude::*;

use crate::encode::{NUM_FILES, NUM_INPUT_CHANNELS, NUM_RANKS};
use crate::move_index::{NUM_MOVE_PLANES, NUM_SQUARES};

pub struct NeuralNet {
    model: RunnableModel<TypedFact, Box<dyn TypedOp>, TypedModel>,
}

impl NeuralNet {
    /// Load the ONNX model from `path` and optimise it for repeated calls
    /// with batch size 1 and fixed input shape `(1, 45, 9, 9)`.
    pub fn load(path: &Path) -> TractResult<Self> {
        let model = tract_onnx::onnx()
            .model_for_path(path)?
            .with_input_fact(
                0,
                InferenceFact::dt_shape(
                    f32::datum_type(),
                    tvec!(1, NUM_INPUT_CHANNELS as i64, NUM_RANKS as i64, NUM_FILES as i64),
                ),
            )?
            .into_optimized()?
            .into_runnable()?;
        Ok(Self { model })
    }

    /// Run a forward pass on a single `(45, 9, 9)` input.
    /// Returns (flat policy logits of length 139*81 = 11259, value scalar in [-1, 1]).
    pub fn forward(&self, planes: &[f32]) -> TractResult<(Vec<f32>, f32)> {
        assert_eq!(planes.len(), NUM_INPUT_CHANNELS * NUM_RANKS * NUM_FILES);
        let input = tract_ndarray::Array4::from_shape_vec(
            (1, NUM_INPUT_CHANNELS, NUM_RANKS, NUM_FILES),
            planes.to_vec(),
        )?
        .into_tensor();
        let outputs = self.model.run(tvec!(input.into()))?;
        // Model outputs (policy_logits (1,139,9,9), value (1,1)); order is
        // preserved from the ONNX graph definition.
        let policy = outputs[0].to_array_view::<f32>()?;
        let value = outputs[1].to_array_view::<f32>()?;
        let policy_vec: Vec<f32> = policy.as_slice().unwrap_or(&[]).to_vec();
        debug_assert_eq!(policy_vec.len(), NUM_MOVE_PLANES * NUM_SQUARES);
        let v = value.iter().copied().next().unwrap_or(0.0);
        Ok((policy_vec, v.clamp(-1.0, 1.0)))
    }
}

