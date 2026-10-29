//// # Domain Types for Live-Skred
////
//// Defines models for live coding blocks, AST validation state,
//// control plane telemetry, voice constellations, and REPL interactions.

import gleam/option.{type Option}

/// Status of an individual live code block.
pub type BlockStatus {
  /// Block is idle and ready for evaluation
  Ready
  /// Block is actively scheduled on a repeating tempo loop (ticks interval)
  Looping(interval_ticks: Float)
  /// Block was fired once and is running non-looping
  OneShotting
  /// Block loop is muted
  Muted
  /// Block has an AST or execution error
  ErrorState(message: String)
}

/// An editable live coding block.
pub type CodeBlock {
  CodeBlock(
    id: Int,
    name: String,
    code: String,
    status: BlockStatus,
    active_pulse: Bool,
    last_error: Option(String),
  )
}

/// Control plane events emitted by Skred's WASM engine.
pub type SkredEvent {
  VoiceTrigger(voice: Int, velocity: Float)
  VoiceRelease(voice: Int)
  VoiceFinished(voice: Int)
  PatternStep(pattern: Int, step: Int)
  PatternStart(pattern: Int)
  PatternEnd(pattern: Int)
  TempoChange(tempo: Float)
  MuteChange(pattern: Int, muted: Bool)
  UserEvent(id: Int, a: Float, b: Float, c: Float)
  OtherEvent(type_id: Int)
}

/// State of an individual voice node in the Orbital Constellation (0..15).
pub type VoiceNode {
  VoiceNode(
    id: Int,
    active: Bool,
    velocity: Float,
    note: Float,
    pan: Float,
    level: Float,
  )
}

/// State of an array stream slot (&0..&7).
pub type StreamState {
  StreamState(slot: Int, values: List(Float), active_step: Int)
}

/// Console REPL log line.
pub type ConsoleLog {
  ConsoleLog(id: String, text: String, is_error: Bool)
}

/// REPL interactive state.
pub type ReplState {
  ReplState(
    input: String,
    history: List(String),
    history_index: Int,
    logs: List(ConsoleLog),
  )
}

/// Quantized musical tempo clock.
pub type QuantizedClock {
  QuantizedClock(
    bpm: Float,
    is_running: Bool,
    tick_count: Int,
    quantum_ticks: Int,
  )
}

/// Pre-curated jam set template.
pub type PresetSet {
  PresetSet(name: String, description: String, blocks: List(CodeBlock))
}

/// Root Model for the Lustre Live-Skred application.
pub type Model {
  Model(
    blocks: List(CodeBlock),
    selected_block_id: Int,
    repl: ReplState,
    voices: List(VoiceNode),
    streams: List(StreamState),
    clock: QuantizedClock,
    is_engine_ready: Bool,
    master_volume_db: Float,
    panic_active: Bool,
    show_help: Bool,
  )
}

/// Messages handled by the Lustre update loop.
pub type Msg {
  EngineInitialized(success: Bool)
  ControlEventsReceived(events: List(SkredEvent))
  ClockTick
  TogglePlayPause
  SetBpm(bpm: Float)
  SetMasterVolume(db: Float)
  ToggleHelp

  // Block Editing & Execution
  SelectBlock(id: Int)
  UpdateBlockCode(id: Int, code: String)
  UpdateBlockName(id: Int, name: String)
  EvalBlockImmediate(id: Int)
  EvalBlockSetup(id: Int)
  EvalBlockQuantized(id: Int, interval_ticks: Float)
  ToggleBlockMute(id: Int)
  DeleteBlock(id: Int)
  AddNewBlock

  // REPL
  UpdateReplInput(input: String)
  SubmitReplCommand
  ExecuteReplCommand(command: String)
  ReplHistoryPrev
  ReplHistoryNext
  ConsoleResultReceived(cmd: String, ret: Int, stdout: String)

  // Presets & Emergency
  LoadPreset(preset: PresetSet)
  PanicStop
}
