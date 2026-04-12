/// Biquad filter coefficients (RBJ Audio EQ Cookbook).
///
/// State (`x1`, `x2`, `y1`, `y2`) is kept on the `Voice` that owns each filter
/// so that voices can be cloned / stolen without carrying mutable borrows.
#[derive(Clone, Copy, Debug)]
pub struct BiquadCoeffs {
    pub b0: f32,
    pub b1: f32,
    pub b2: f32,
    pub a1: f32, // already divided by a0
    pub a2: f32,
}

impl BiquadCoeffs {
    /// Low-pass filter.
    ///
    /// `cutoff_norm` 0..=1 → 20 Hz..20 kHz (log scale).
    /// `resonance`   0..=1 → Q 0.5..20.
    pub fn low_pass(cutoff_norm: f32, resonance: f32, sample_rate: f64) -> Self {
        let (b0, b1, b2, a1, a2) = lpf_coeffs(cutoff_norm, resonance, sample_rate);
        Self { b0, b1, b2, a1, a2 }
    }

    /// High-pass filter (same interface).
    #[allow(dead_code)]
    pub fn high_pass(cutoff_norm: f32, resonance: f32, sample_rate: f64) -> Self {
        let fc = cutoff_hz(cutoff_norm, sample_rate);
        let q  = norm_to_q(resonance);
        let w0 = std::f64::consts::TAU * fc / sample_rate;
        let alpha   = w0.sin() / (2.0 * q);
        let cos_w0  = w0.cos();
        let a0_inv  = 1.0 / (1.0 + alpha);
        Self {
            b0: ((1.0 + cos_w0) * 0.5 * a0_inv) as f32,
            b1: (-(1.0 + cos_w0) * a0_inv) as f32,
            b2: ((1.0 + cos_w0) * 0.5 * a0_inv) as f32,
            a1: ((-2.0 * cos_w0) * a0_inv) as f32,
            a2: ((1.0 - alpha) * a0_inv) as f32,
        }
    }

    /// Apply this filter to one sample, updating the delay-line state.
    #[inline(always)]
    pub fn tick(&self, x: f32, x1: &mut f32, x2: &mut f32, y1: &mut f32, y2: &mut f32) -> f32 {
        let y = self.b0 * x + self.b1 * *x1 + self.b2 * *x2
              - self.a1 * *y1 - self.a2 * *y2;
        *x2 = *x1;  *x1 = x;
        *y2 = *y1;  *y1 = y;
        y
    }
}

impl Default for BiquadCoeffs {
    /// Identity (pass-through): b0=1, everything else 0.
    fn default() -> Self {
        Self { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn cutoff_hz(norm: f32, sample_rate: f64) -> f64 {
    // Logarithmic mapping: 0 → 20 Hz, 1 → 20 000 Hz
    let hz = 20.0 * 1000.0_f64.powf(norm as f64);
    hz.min(sample_rate * 0.45) // stay well below Nyquist for stability
}

fn norm_to_q(norm: f32) -> f64 {
    // 0 → Q=0.5 (Butterworth-ish), 1 → Q=20 (very resonant)
    0.5 + norm as f64 * 19.5
}

fn lpf_coeffs(cutoff_norm: f32, resonance: f32, sample_rate: f64) -> (f32, f32, f32, f32, f32) {
    let fc     = cutoff_hz(cutoff_norm, sample_rate);
    let q      = norm_to_q(resonance);
    let w0     = std::f64::consts::TAU * fc / sample_rate;
    let alpha   = w0.sin() / (2.0 * q);
    let cos_w0  = w0.cos();
    let a0_inv  = 1.0 / (1.0 + alpha);
    (
        ((1.0 - cos_w0) * 0.5 * a0_inv) as f32, // b0
        ((1.0 - cos_w0) * a0_inv) as f32,        // b1
        ((1.0 - cos_w0) * 0.5 * a0_inv) as f32, // b2
        ((-2.0 * cos_w0) * a0_inv) as f32,       // a1
        ((1.0 - alpha) * a0_inv) as f32,          // a2
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_passthrough() {
        let c = BiquadCoeffs::default();
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        let out = c.tick(1.0, &mut x1, &mut x2, &mut y1, &mut y2);
        assert!((out - 1.0).abs() < 1e-6, "identity filter should pass through");
    }

    #[test]
    fn lpf_dc_passes() {
        let c = BiquadCoeffs::low_pass(0.5, 0.0, 44100.0);
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        // Run DC signal for 200 samples; output should settle near 1.0
        let mut out = 0.0f32;
        for _ in 0..200 {
            out = c.tick(1.0, &mut x1, &mut x2, &mut y1, &mut y2);
        }
        assert!(out > 0.9, "LPF should pass DC (got {out})");
    }
}
