//// # Live Code Block Editor & REPL Views
////
//// Renders the live coding blocks, AST diagnostic indicators,
//// transport header, preset selector, and interactive REPL console.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import live_skred/presets
import live_skred/skode
import live_skred/types.{
  type CodeBlock, type Model, type Msg, type PresetSet, ErrorState, Looping,
  Muted, OneShotting, Ready,
}
import lustre/attribute.{class, placeholder, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event

/// Decodes Enter and Arrow navigation inside the REPL input field.
pub fn key_down_console_decoder() -> decode.Decoder(Msg) {
  use key <- decode.field("key", decode.string)
  case key {
    "Enter" -> decode.success(types.SubmitReplCommand)
    "ArrowUp" -> decode.success(types.ReplHistoryPrev)
    "ArrowDown" -> decode.success(types.ReplHistoryNext)
    _ -> decode.failure(types.SubmitReplCommand, "Not handled")
  }
}

/// Decodes Shift+Enter (eval) and Ctrl/Cmd+Enter (loop 16 ticks) in code block textarea.
pub fn key_down_block_decoder(id: Int) -> decode.Decoder(Msg) {
  use key <- decode.field("key", decode.string)
  use shift_key <- decode.field("shiftKey", decode.bool)
  use ctrl_key <- decode.field("ctrlKey", decode.bool)
  use meta_key <- decode.field("metaKey", decode.bool)
  case key {
    "Enter" if shift_key -> decode.success(types.EvalBlockImmediate(id))
    "Enter" if ctrl_key || meta_key ->
      decode.success(types.EvalBlockQuantized(id, 16.0))
    _ -> decode.failure(types.EvalBlockImmediate(id), "Not handled")
  }
}

/// Renders the top transport control bar.
pub fn view_transport_bar(model: Model) -> Element(Msg) {
  html.header([class("transport-bar")], [
    // Brand & Engine Status
    html.div([class("brand-section")], [
      html.span([class("logo-title")], [text("live-skred")]),
      html.span(
        [
          class(case model.is_engine_ready {
            True -> "status-tag ready"
            False -> "status-tag initializing"
          }),
        ],
        [
          text(case model.is_engine_ready {
            True -> "ENGINE READY"
            False -> "INITIALIZING..."
          }),
        ],
      ),
    ]),

    // Transport Controls
    html.div([class("transport-controls")], [
      html.button(
        [
          class(case model.clock.is_running {
            True -> "btn btn-primary active"
            False -> "btn btn-primary"
          }),
          event.on_click(types.TogglePlayPause),
        ],
        [
          text(case model.clock.is_running {
            True -> "⏸ PAUSE"
            False -> "▶ PLAY"
          }),
        ],
      ),

      // Bar & Beat Counter
      html.div([class("beat-counter")], [
        html.span([class("counter-tag")], [
          text(
            "BAR "
            <> int.to_string({ model.clock.tick_count / 16 } + 1)
            <> " : BEAT "
            <> int.to_string({ { model.clock.tick_count / 4 } % 4 } + 1),
          ),
        ]),
        html.div(
          [class("beat-leds")],
          list.map([1, 2, 3, 4], fn(b) {
            html.span(
              [
                class(
                  case
                    model.clock.is_running
                    && { { model.clock.tick_count / 4 } % 4 } + 1 == b
                  {
                    True -> "beat-led active"
                    False -> "beat-led"
                  },
                ),
              ],
              [text(int.to_string(b))],
            )
          }),
        ),
      ]),

      // BPM Control
      html.div([class("bpm-control")], [
        html.label([], [text("BPM:")]),
        html.input([
          type_("number"),
          attribute.min("40"),
          attribute.max("240"),
          value(float.to_string(model.clock.bpm)),
          event.on_input(fn(str) {
            case float.parse(str) {
              Ok(b) -> types.SetBpm(b)
              _ -> types.SetBpm(model.clock.bpm)
            }
          }),
        ]),
      ]),

      // Master Volume Control
      html.div([class("volume-control")], [
        html.label([], [text("VOL (dB):")]),
        html.input([
          type_("range"),
          attribute.min("-60"),
          attribute.max("6"),
          attribute.step("1"),
          value(float.to_string(model.master_volume_db)),
          event.on_input(fn(str) {
            case float.parse(str) {
              Ok(v) -> types.SetMasterVolume(v)
              _ -> types.SetMasterVolume(model.master_volume_db)
            }
          }),
        ]),
        html.span([class("db-label")], [
          text(float.to_string(model.master_volume_db) <> " dB"),
        ]),
      ]),

      // Preset Selector
      html.div([class("preset-selector")], [
        html.label([], [text("PRESET:")]),
        html.select(
          [
            event.on_input(fn(name) {
              case list.find(presets.all_presets(), fn(p) { p.name == name }) {
                Ok(p) -> types.LoadPreset(p)
                _ -> types.TogglePlayPause
              }
            }),
          ],
          list.map(presets.all_presets(), fn(p: PresetSet) {
            html.option([value(p.name)], p.name)
          }),
        ),
      ]),

      // Emergency Panic Button
      html.button(
        [class("btn btn-danger panic-btn"), event.on_click(types.PanicStop)],
        [
          text("⏹ ALL OFF (S-1)"),
        ],
      ),
    ]),
  ])
}

/// Renders a single editable code block.
pub fn view_code_block(block: CodeBlock, selected_id: Int) -> Element(Msg) {
  let is_selected = block.id == selected_id
  let ast_status = skode.parse(block.code)

  html.div(
    [
      class(
        "code-block"
        <> case is_selected {
          True -> " selected"
          False -> ""
        }
        <> case block.active_pulse {
          True -> " pulse-highlight"
          False -> ""
        },
      ),
      event.on_click(types.SelectBlock(block.id)),
    ],
    [
      // Block Header
      html.div([class("block-header")], [
        html.input([
          class("block-title-input"),
          value(block.name),
          event.on_input(types.UpdateBlockName(block.id, _)),
        ]),
        html.div([class("block-status-badge")], [
          html.span(
            [
              class(case block.status {
                Ready -> "badge badge-ready"
                Looping(_) -> "badge badge-looping"
                OneShotting -> "badge badge-oneshot"
                Muted -> "badge badge-muted"
                ErrorState(_) -> "badge badge-error"
              }),
            ],
            [
              text(case block.status {
                Ready -> "READY"
                Looping(t) -> "LOOPING (~" <> float.to_string(t) <> ")"
                OneShotting -> "ONE-SHOT"
                Muted -> "MUTED"
                ErrorState(e) -> "ERROR: " <> e
              }),
            ],
          ),
        ]),
        html.div([class("block-actions")], [
          html.button(
            [
              class("btn btn-sm btn-eval"),
              event.on_click(types.EvalBlockImmediate(block.id)),
            ],
            [text("▶ Eval (Shift+Enter)")],
          ),
          html.button(
            [
              class("btn btn-sm btn-loop"),
              event.on_click(types.EvalBlockQuantized(block.id, 16.0)),
            ],
            [text("🔁 Loop ~16 (1 Bar)")],
          ),
          html.button(
            [
              class("btn btn-sm btn-loop"),
              event.on_click(types.EvalBlockQuantized(block.id, 4.0)),
            ],
            [text("🔁 Loop ~4 (1 Beat)")],
          ),
          html.button(
            [
              class("btn btn-sm btn-mute"),
              event.on_click(types.ToggleBlockMute(block.id)),
            ],
            [
              text(case block.status {
                Muted -> "🔊 Unmute"
                _ -> "🔇 Mute"
              }),
            ],
          ),
          html.button(
            [
              class("btn btn-sm btn-delete"),
              event.on_click(types.DeleteBlock(block.id)),
            ],
            [text("✕")],
          ),
        ]),
      ]),

      // Code Editor Area
      html.textarea(
        [
          class("block-textarea"),
          rows(5),
          value(block.code),
          event.on_input(types.UpdateBlockCode(block.id, _)),
          event.on("keydown", key_down_block_decoder(block.id)),
        ],
        block.code,
      ),

      // AST Feedback Indicator
      html.div([class("ast-indicator-bar")], [
        case ast_status {
          Ok(skode.Script(chunks)) ->
            html.span([class("ast-valid")], [
              text(
                "✓ Valid Skode ("
                <> int.to_string(list.length(chunks))
                <> " chunks)",
              ),
            ])
          Error(skode.ParseError(msg, pos)) ->
            html.span([class("ast-error")], [
              text("⚠ Parse error at pos " <> int.to_string(pos) <> ": " <> msg),
            ])
        },
      ]),
    ],
  )
}

fn rows(n: Int) -> attribute.Attribute(a) {
  attribute.attribute("rows", int.to_string(n))
}

fn quick_diag_btn(label: String, cmd: String, tooltip: String) -> Element(Msg) {
  html.button(
    [
      class("btn btn-xs btn-diag"),
      attribute.attribute("title", tooltip),
      event.on_click(types.ExecuteReplCommand(cmd)),
    ],
    [text(label)],
  )
}

/// Renders the interactive REPL bar at the bottom.
pub fn view_repl_bar(model: Model) -> Element(Msg) {
  html.footer([class("repl-bar")], [
    // Diagnostic Toolbar
    html.div([class("repl-toolbar")], [
      html.span([class("repl-toolbar-label")], [text("DIAGNOSTICS:")]),
      quick_diag_btn(
        "?? Voices",
        "??",
        "List all active voices and frequencies",
      ),
      quick_diag_btn(
        "/s 2 Audio",
        "/s 2",
        "Show audio engine status & voice pool",
      ),
      quick_diag_btn(
        "\\ Details",
        "\\",
        "Show detailed parameters for current voice",
      ),
      quick_diag_btn("?ws Waves", "?ws", "List wavetables (drum samples 82-99)"),
      quick_diag_btn("?S Streams", "?S", "List array stream buffers"),
      quick_diag_btn(
        "GS Status",
        "GS",
        "Show global system, tempo, volume status",
      ),
      quick_diag_btn("⏹ S-1 Stop", "S-1", "Silence and reset all voices"),
      html.button(
        [
          class("btn btn-xs btn-help"),
          event.on_click(types.ToggleHelp),
        ],
        [text("📖 Skode Syntax & Help")],
      ),
    ]),

    // Prominent Console Header
    html.div([class("repl-console-header")], [
      html.span([class("repl-console-title")], [
        text("⚡ CONSOLE OUTPUT & DIAGNOSTIC LOGS"),
      ]),
      html.span([class("repl-console-hint")], [
        text(
          "Responses from typed commands (??, \\, /s 2) and block evaluations appear below:",
        ),
      ]),
    ]),

    // Output Logs
    html.div([class("repl-logs")], [
      html.div(
        [class("repl-logs-inner")],
        list.map(model.repl.logs, fn(log) {
          html.pre(
            [
              class(case log.is_error {
                True -> "repl-log-pre error"
                False -> "repl-log-pre"
              }),
            ],
            [text(log.text)],
          )
        }),
      ),
    ]),

    // Input Prompt
    html.div([class("repl-input-row")], [
      html.span([class("repl-prompt")], [text("skred>")]),
      html.input([
        class("repl-input"),
        placeholder(
          "Type Skode command (e.g. ?? for voices, /s 2 for engine, v0 w82 n69 l1) and press Enter...",
        ),
        value(model.repl.input),
        event.on_input(types.UpdateReplInput),
        event.on("keydown", key_down_console_decoder()),
      ]),
      html.button(
        [
          class("btn btn-sm btn-primary"),
          event.on_click(types.SubmitReplCommand),
        ],
        [text("Send (Enter)")],
      ),
    ]),
  ])
}

/// Renders the interactive Skode Syntax, Help, and Quick Reference modal.
pub fn view_help_modal() -> Element(Msg) {
  html.div([class("modal-backdrop"), event.on_click(types.ToggleHelp)], [
    html.div(
      [
        class("modal-content help-modal"),
        // Stop click propagation on the modal card itself
        event.stop_propagation(event.on_click(types.SetBpm(120.0))),
      ],
      [
        html.div([class("modal-header")], [
          html.h2([], [text("📖 Skode Syntax, Drum Map & Live-Sync Cheat Sheet")]),
          html.button(
            [class("btn btn-sm btn-close"), event.on_click(types.ToggleHelp)],
            [text("✕ Close")],
          ),
        ]),
        html.div([class("modal-body help-body")], [
          // Section 1: Drum Samples Map
          html.section([class("help-section")], [
            html.h3([], [
              text("🥁 Built-in One-Shot Drum Waves (Slots 82–99 at f440 / n69)"),
            ]),
            html.p([class("help-desc")], [
              text(
                "Self-contained 44.1 kHz one-shot models synthesized via K-synth. Play at standard frequency f440 (or n69) with loop B0:",
              ),
            ]),
            html.table([class("help-table")], [
              html.thead([], [
                html.tr([], [
                  html.th([], [text("Wave Slot")]),
                  html.th([], [text("Instrument")]),
                  html.th([], [text("Usage Example")]),
                ]),
              ]),
              html.tbody([], [
                html.tr([], [
                  html.td([], [text("w82")]),
                  html.td([], [text("Kick Drum (300ms)")]),
                  html.td([], [text("v0 w82 f440 a3 B0 l1 ; +1.0 v0 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w83")]),
                  html.td([], [text("Snare (280ms)")]),
                  html.td([], [text("v1 w83 f440 a0 B0 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w84")]),
                  html.td([], [text("Closed Hat (200ms)")]),
                  html.td([], [text("v1 w84 f440 a-3 B0 ; +0.5 v1 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w85")]),
                  html.td([], [text("Open Hat (750ms)")]),
                  html.td([], [text("v1 w85 f440 a-3 B0 ; +0.75 v1 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w86")]),
                  html.td([], [text("Hand Clap (200ms)")]),
                  html.td([], [
                    text("v2 w86 f440 a-1 B0 ; +1.0 v2 l1 ; +3.0 v2 l1"),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("w87")]),
                  html.td([], [text("Rimshot (60ms)")]),
                  html.td([], [text("v2 w87 f440 a0 B0 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w88-w93")]),
                  html.td([], [text("Toms (lo, mid, hi)")]),
                  html.td([], [text("v3 w88 f440 a0 B0 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w94-w95")]),
                  html.td([], [text("Crash & Ride Cymbals")]),
                  html.td([], [text("v4 w94 f440 a-3 B0 l1")]),
                ]),
                html.tr([], [
                  html.td([], [text("w96")]),
                  html.td([], [text("808 Cowbell (900ms)")]),
                  html.td([], [
                    text("v5 w96 f440 a-2 B0 ; +0.5 v5 l1 ; +1.0 v5 l1"),
                  ]),
                ]),
              ]),
            ]),
          ]),

          // Section 2: Defers & Quantized Sync
          html.section([class("help-section")], [
            html.h3([], [text("⏱ How Defers (+) & Quantized Clock Sync Work")]),
            html.ul([class("help-list")], [
              html.li([], [
                html.strong([], [text("+delay (Tempo-Relative): ")]),
                text(
                  "Multiplies delay by 1 beat. +1.0 = 1 beat (quarter note), +0.5 = 8th note, +0.25 = 16th note, +4.0 = 1 bar (4 beats).",
                ),
              ]),
              html.li([], [
                html.strong([], [text("~delay (Seconds-Relative): ")]),
                text("Specifies raw wall-clock delay in seconds."),
              ]),
              html.li([], [
                html.strong([], [text("Semicolon (;) Chunk Reset: ")]),
                text(
                  "Each chunk separated by ; resets the defer accumulator to 0. So 'v0 l1 ; +1.0 v0 l1 ; +2.0 v0 l1' schedules events at exact bar offsets 0.0, 1.0, and 2.0.",
                ),
              ]),
              html.li([], [
                html.strong([], [text("Quantized Loop (~16 & ~4): ")]),
                text(
                  "Clicking '🔁 Loop ~16' arms the block to launch at the start of the next 4/4 bar downbeat (tick 0). All tracks lock to the exact same phase grid.",
                ),
              ]),
            ]),
          ]),

          // Section 3: Essential Commands & Voice Inspection
          html.section([class("help-section")], [
            html.h3([], [text("🔍 Voice Inspection & REPL Diagnostic Commands")]),
            html.table([class("help-table")], [
              html.thead([], [
                html.tr([], [
                  html.th([], [text("Command")]),
                  html.th([], [text("Action")]),
                  html.th([], [text("Description")]),
                ]),
              ]),
              html.tbody([], [
                html.tr([], [
                  html.td([], [text("??")]),
                  html.td([], [text("Show Active Voices")]),
                  html.td([], [
                    text(
                      "Prints active voice indices, pitches, notes, amplitudes, and wavetables",
                    ),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("/s 2")]),
                  html.td([], [text("Audio Status")]),
                  html.td([], [
                    text(
                      "Shows audio driver, buffer size, active voice count, and allocations",
                    ),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("\\")]),
                  html.td([], [text("Selected Voice Details")]),
                  html.td([], [
                    text(
                      "Prints full ADSR, wave, filter mode, resonance, pan, and loop flag",
                    ),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("?ws")]),
                  html.td([], [text("Show Wavetables")]),
                  html.td([], [
                    text(
                      "Lists all loaded waves (0..14 classic, 15..49 DWGS, 82..99 drums)",
                    ),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("(1 2 3) /SS 0")]),
                  html.td([], [text("Array Stream")]),
                  html.td([], [
                    text(
                      "Loads an array into stream 0; pops next item with &0 (e.g. n&0)",
                    ),
                  ]),
                ]),
                html.tr([], [
                  html.td([], [text("S-1")]),
                  html.td([], [text("Stop All Voices")]),
                  html.td([], [
                    text(
                      "Immediate panic button that silences and resets all 256 voices",
                    ),
                  ]),
                ]),
              ]),
            ]),
          ]),

          // Section 4: Keyboard Shortcuts
          html.section([class("help-section")], [
            html.h3([], [text("⌨ Keyboard Shortcuts")]),
            html.ul([class("help-list")], [
              html.li([], [
                html.strong([], [text("Shift+Enter (in code block): ")]),
                text(
                  "Evaluates block once immediately and logs output to console.",
                ),
              ]),
              html.li([], [
                html.strong([], [
                  text("Ctrl+Enter / Cmd+Enter (in code block): "),
                ]),
                text("Arms block for quantized looping (~16 ticks = 1 bar)."),
              ]),
              html.li([], [
                html.strong([], [text("Enter (in REPL prompt): ")]),
                text("Submits ASCII Skode command and prints response."),
              ]),
              html.li([], [
                html.strong([], [text("ArrowUp / ArrowDown (in REPL): ")]),
                text("Navigates previous command history."),
              ]),
              html.li([], [
                html.strong([], [text("Click Voice Circle (in Orbit): ")]),
                text(
                  "Inspects that voice's parameters in the terminal (dispatches v<id> \\).",
                ),
              ]),
            ]),
          ]),
        ]),
      ],
    ),
  ])
}
