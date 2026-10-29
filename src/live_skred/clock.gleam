//// # Quantized Tempo Clock & Loop Scheduler
////
//// Calculates tick timings, measures intervals, and provides subscriptions
//// to drive live coding block loops in synchronization with the musical tempo.

import gleam/float
import lustre/effect.{type Effect}

@external(javascript, "../skred_ffi.mjs", "subscribeClock")
fn js_subscribe_clock(interval_ms: Int, on_tick: fn() -> Nil) -> fn() -> Nil

/// Calculates the duration of one tempo tick in milliseconds.
/// Assuming standard 4 ticks per beat (16th notes) or 1 tick per beat.
/// At 120 BPM, 1 beat (quarter note) = 500ms. 1 tick (16th note) = 125ms.
pub fn tick_interval_ms(bpm: Float) -> Int {
  let safe_bpm = float.clamp(bpm, 20.0, 300.0)
  // 60,000 ms / (bpm * 4 ticks)
  let ms = 60_000.0 /. {safe_bpm *. 4.0}
  float.round(ms)
}

/// Dispatches an effect subscription to trigger `on_tick` at musical intervals.
pub fn subscribe_clock(
  bpm: Float,
  is_running: Bool,
  on_tick: msg,
) -> Effect(msg) {
  case is_running {
    False -> effect.none()
    True -> {
      let interval = tick_interval_ms(bpm)
      effect.from(fn(dispatch) {
        let _cleanup =
          js_subscribe_clock(interval, fn() { dispatch(on_tick) })
        Nil
      })
    }
  }
}
