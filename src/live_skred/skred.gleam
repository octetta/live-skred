//// # Skred Audio Engine FFI Bridge & Effect Dispatcher for Live-Skred
////
//// Wraps WASM communication, command evaluation, and control plane event decoding.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/list
import gleam/result
import live_skred/skode.{type SkodeCommand}
import live_skred/types.{type Msg, type SkredEvent}
import lustre/effect.{type Effect}

@external(javascript, "../skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "subscribeEvents")
fn js_subscribe_events(callback: fn(Dynamic) -> Nil) -> fn() -> Nil

@external(javascript, "../skred_ffi.mjs", "sendCommand")
fn js_send_command(cmd: String) -> Nil

@external(javascript, "../skred_ffi.mjs", "evalCommand")
fn js_eval_command(cmd: String, callback: fn(String, Int, String) -> Nil) -> Nil

/// Dispatches engine initialization effect.
pub fn init_engine_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_init_engine(fn(success) { dispatch(types.EngineInitialized(success)) })
  })
}

/// Sends a raw string command to the audio engine.
pub fn send_command(cmd: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_send_command(cmd) })
}

/// Sends a typed AST Skode command to the audio engine.
pub fn send(cmd: SkodeCommand) -> Effect(Msg) {
  send_command(skode.command_to_string(cmd))
}

/// Evaluates an ad-hoc command string and returns its status code and stdout logs.
pub fn eval_command_effect(cmd: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_eval_command(cmd, fn(c, ret, resp) {
      dispatch(types.ConsoleResultReceived(c, ret, resp))
    })
  })
}

/// Sends the panic command: S-1 to reset all active voices.
pub fn panic_effect() -> Effect(Msg) {
  send_command("S-1")
}

/// Sets the master volume in decibels (e.g. 0.0 for unity, -6.0, etc.)
pub fn set_master_volume_effect(db: Float) -> Effect(Msg) {
  send_command(";V" <> float.to_string(db) <> ";")
}

// ---------------------------------------------------------------------------
// Control Plane Event Decoders & Subscription
// ---------------------------------------------------------------------------

/// Intermediate representation of an unpacked binary Skred control event received across FFI.
pub type RawEvent {
  RawEvent(t: Int, seq: Int, v: Int, p: Int, s: Int, id: Int, vals: List(Float))
}

/// Dynamic decoder for JSON-like objects emitted by the WASM control plane poller.
pub fn raw_event_decoder() -> decode.Decoder(RawEvent) {
  use t <- decode.field("t", decode.int)
  use seq <- decode.optional_field("seq", 0, decode.int)
  use v <- decode.field("v", decode.int)
  use p <- decode.field("p", decode.int)
  use s <- decode.field("s", decode.int)
  use id <- decode.field("id", decode.int)
  use vals <- decode.field("vals", decode.list(decode.float))
  decode.success(RawEvent(t:, seq:, v:, p:, s:, id:, vals:))
}

/// Converts a decoded `RawEvent` into a typed domain `SkredEvent`.
pub fn to_skred_event(raw: RawEvent) -> SkredEvent {
  case raw.t {
    // SKRED_CONTROL_EVENT_VOICE_TRIGGER = 1
    1 -> {
      let vel = list.first(raw.vals) |> result.unwrap(0.8)
      types.VoiceTrigger(voice: raw.v, velocity: vel)
    }
    // SKRED_CONTROL_EVENT_VOICE_RELEASE = 2
    2 -> types.VoiceRelease(voice: raw.v)
    // SKRED_CONTROL_EVENT_VOICE_FINISHED = 3
    3 -> types.VoiceFinished(voice: raw.v)
    // SKRED_CONTROL_EVENT_USER = 4
    4 -> {
      let #(a, b, c) = case raw.vals {
        [x, y, z, ..] -> #(x, y, z)
        [x, y] -> #(x, y, 0.0)
        [x] -> #(x, 0.0, 0.0)
        [] -> #(0.0, 0.0, 0.0)
      }
      types.UserEvent(id: raw.id, a:, b:, c:)
    }
    // SKRED_CONTROL_EVENT_PATTERN_START = 5
    5 -> types.PatternStart(pattern: raw.p)
    // SKRED_CONTROL_EVENT_PATTERN_END = 6
    6 -> types.PatternEnd(pattern: raw.p)
    // SKRED_CONTROL_EVENT_PATTERN_STEP = 9
    9 -> types.PatternStep(pattern: raw.p, step: raw.s)
    // SKRED_CONTROL_EVENT_TEMPO_CHANGE = 11
    11 -> {
      let bpm = list.first(raw.vals) |> result.unwrap(120.0)
      types.TempoChange(tempo: bpm)
    }
    // SKRED_CONTROL_EVENT_MUTE_CHANGE = 13
    13 -> {
      let muted = list.first(raw.vals) |> result.unwrap(0.0) >. 0.5
      types.MuteChange(pattern: raw.p, muted:)
    }
    other -> types.OtherEvent(type_id: other)
  }
}

/// Decodes a Dynamic JS array of raw event objects into a list of typed `SkredEvent`s.
pub fn decode_events(
  dynamic_array: Dynamic,
) -> Result(List(SkredEvent), List(decode.DecodeError)) {
  decode.run(
    dynamic_array,
    decode.list(raw_event_decoder())
      |> decode.map(fn(raw_list) { list.map(raw_list, to_skred_event) }),
  )
}

/// Subscribes to the 60Hz batched control plane event stream from Skred.
pub fn subscribe_control_plane(
  on_batch: fn(List(SkredEvent)) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let _cleanup =
      js_subscribe_events(fn(raw_dynamic) {
        case decode_events(raw_dynamic) {
          Ok(events) if events != [] -> dispatch(on_batch(events))
          _ -> Nil
        }
      })
    Nil
  })
}
