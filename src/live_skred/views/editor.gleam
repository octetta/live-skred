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
