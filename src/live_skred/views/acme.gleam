//// # Acme / Oberon Live-Coding Workstation (V2 View)
////
//// High-density 3-column tiling architecture with Oberon-style tag bars,
//// active text auditioning, live score document blocks, and plumber telemetry.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import live_skred/presets
import live_skred/skode
import live_skred/types.{
  type Model, type Msg, type VoiceNode, AcmeWorkstation, CardsView, ErrorState,
  Looping, Muted, OneShotting, Ready,
}
import live_skred/views/constellation
import live_skred/views/editor
import lustre/attribute.{class, placeholder, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event

/// Calculates Left and Right audio meter levels from active voice nodes and volume.
fn calculate_vu_levels(
  voices: List(VoiceNode),
  master_volume_db: Float,
) -> #(Float, Float) {
  let #(left_sum, right_sum) =
    list.fold(voices, #(0.0, 0.0), fn(acc, v) {
      case v.active {
        True -> {
          let left_gain = { 1.0 -. v.pan } /. 2.0
          let right_gain = { 1.0 +. v.pan } /. 2.0
          let val = case v.velocity >. 0.0 {
            True -> v.velocity
            False -> 1.0
          }
          #(acc.0 +. { val *. left_gain }, acc.1 +. { val *. right_gain })
        }
        False -> acc
      }
    })
  let vol_factor = case master_volume_db <=. -60.0 {
    True -> 0.0
    False -> float.clamp({ master_volume_db +. 60.0 } /. 66.0, 0.0, 1.2)
  }
  let left_level = float.clamp(left_sum *. vol_factor, 0.0, 1.0)
  let right_level = float.clamp(right_sum *. vol_factor, 0.0, 1.0)
  #(left_level, right_level)
}

/// Renders a 16-segment ASCII/graphical VU bar.
fn render_vu_bar(level: Float) -> String {
  let total_segments = 16
  let filled = float.round(level *. 16.0)
  let filled_clamped = int.clamp(filled, 0, total_segments)
  let bar =
    string.repeat("■", filled_clamped)
    <> string.repeat("□", total_segments - filled_clamped)
  "[" <> bar <> "]"
}

/// Formats level to dB string.
fn level_to_db_text(level: Float) -> String {
  case level <=. 0.02 {
    True -> "-∞ dB"
    False -> {
      let db = float.round({ 1.0 -. level } *. -24.0)
      int.to_string(db) <> " dB"
    }
  }
}

/// Renders the Master Tag Bar at the top of the Acme Workstation.
pub fn view_acme_master_tag_bar(model: Model) -> Element(Msg) {
  let current_beat = { model.clock.tick_count / 4 } % 4 + 1
  let current_bar = { model.clock.tick_count / 16 } + 1

  html.header([class("acme-master-tagbar")], [
    // Brand & Status
    html.div([class("acme-tag-section brand")], [
      html.span([class("acme-tag-title")], [text("LIVE-SKRED")]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class(case model.clock.is_running {
            True -> "acme-tag-btn active"
            False -> "acme-tag-btn"
          }),
          event.on_click(types.TogglePlayPause),
        ],
        [
          text(case model.clock.is_running {
            True -> "⏸ Pause"
            False -> "▶ Play"
          }),
        ],
      ),
      html.span([class("acme-beat-display")], [
        text(
          "BAR "
          <> int.to_string(current_bar)
          <> " : BEAT "
          <> int.to_string(current_beat),
        ),
      ]),
      html.div([class("beat-leds")], [
        html.span(
          [
            class(case model.clock.is_running && current_beat == 1 {
              True -> "beat-led active"
              False -> "beat-led"
            }),
          ],
          [text("1")],
        ),
        html.span(
          [
            class(case model.clock.is_running && current_beat == 2 {
              True -> "beat-led active"
              False -> "beat-led"
            }),
          ],
          [text("2")],
        ),
        html.span(
          [
            class(case model.clock.is_running && current_beat == 3 {
              True -> "beat-led active"
              False -> "beat-led"
            }),
          ],
          [text("3")],
        ),
        html.span(
          [
            class(case model.clock.is_running && current_beat == 4 {
              True -> "beat-led active"
              False -> "beat-led"
            }),
          ],
          [text("4")],
        ),
      ]),
    ]),

    // Executable Acme Tag Commands
    html.div([class("acme-tag-section commands")], [
      html.button([class("acme-tag-btn"), event.on_click(types.AddNewBlock)], [
        text("NewCol"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("??")),
        ],
        [text("Dump")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.LoadPreset(presets.default_starter_set())),
        ],
        [text("Load")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.LoopAllBlocks(16.0)),
        ],
        [text("Quant 1bar")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.StopAllBlocks)], [
        text("StopAll"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [class("acme-tag-btn panic"), event.on_click(types.PanicStop)],
        [text("Panic")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.ToggleHelp)], [
        text("Help (F1)"),
      ]),
    ]),

    // Interactive Tag Bar Command Box
    html.div([class("acme-tag-section input-box")], [
      html.input([
        class("acme-tagbar-input"),
        type_("text"),
        placeholder("Type command | Click to exec"),
        value(model.tagbar_input),
        event.on_input(types.UpdateTagBarInput),
        event.on("keydown", editor.key_down_console_decoder()),
      ]),
      html.button(
        [class("acme-tag-btn run"), event.on_click(types.SubmitTagBarCommand)],
        [text("Run")],
      ),
    ]),

    // Tempo, Volume & Mode Switcher
    html.div([class("acme-tag-section right-controls")], [
      // BPM
      html.div([class("acme-inline-ctrl")], [
        html.label([], [text("Tempo")]),
        html.input([
          type_("number"),
          attribute.min("30"),
          attribute.max("300"),
          value(float.to_string(model.clock.bpm)),
          event.on_input(fn(val_str) {
            case float.parse(val_str) {
              Ok(b) -> types.SetBpm(b)
              Error(_) -> types.SetBpm(120.0)
            }
          }),
        ]),
      ]),

      // Preset Selector
      html.div([class("acme-inline-ctrl")], [
        html.select(
          [
            event.on_input(fn(name) {
              let selected =
                presets.all_presets()
                |> list.find(fn(p) { p.name == name })
                |> fn(res) {
                  case res {
                    Ok(p) -> p
                    Error(_) -> presets.default_starter_set()
                  }
                }
              types.LoadPreset(selected)
            }),
          ],
          list.map(presets.all_presets(), fn(p) {
            html.option([value(p.name)], p.name)
          }),
        ),
      ]),

      // Layout Switcher
      html.div([class("acme-layout-switcher")], [
        html.button(
          [
            class("acme-switch-btn active"),
            event.on_click(types.SetLayoutMode(AcmeWorkstation)),
          ],
          [text("ACME V2")],
        ),
        html.button(
          [
            class("acme-switch-btn"),
            event.on_click(types.SetLayoutMode(CardsView)),
          ],
          [text("CARDS")],
        ),
      ]),
    ]),
  ])
}

/// Column 0: Patches & Synthesis (synth.sk)
pub fn view_column_patches(model: Model) -> Element(Msg) {
  let ast_status = case skode.parse(model.synth_code) {
    Ok(skode.Script(chunks)) ->
      html.span([class("ast-valid")], [
        text(
          "✓ Valid Synthesis ("
          <> int.to_string(list.length(chunks))
          <> " chunks)",
        ),
      ])
    Error(skode.ParseError(msg, pos)) ->
      html.span([class("ast-error")], [
        text("✗ Pos " <> int.to_string(pos) <> ": " <> msg),
      ])
  }

  html.section([class("acme-column column-patches")], [
    // Column Tag Bar
    html.div([class("acme-col-tagbar")], [
      html.span([class("acme-col-title")], [text("synth.sk")]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.EvalSynthCode)], [
        text("Put"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.EvalSynthCode)], [
        text("EvalAll"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("v0 w82 f440 a3 B0 l1")),
        ],
        [text("Audition 808")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.UpdateSynthCode("")),
        ],
        [text("Clear")],
      ),
      html.span([class("acme-col-indicator")], [ast_status]),
    ]),

    // Active Text Audition Toolbar ("The Whole Screen is an Instrument")
    html.div([class("acme-active-tokens-bar")], [
      html.span([class("active-tokens-label")], [text("ACTIVE TOKENS:")]),
      html.button(
        [
          class("active-token-chip chip-kick"),
          event.on_click(types.AuditionCommand("v0 w82 f440 a3 B0 l1")),
        ],
        [text("w82 Kick")],
      ),
      html.button(
        [
          class("active-token-chip chip-hat"),
          event.on_click(types.AuditionCommand("v1 w84 f440 a-3 B0 l1")),
        ],
        [text("w84 Hat")],
      ),
      html.button(
        [
          class("active-token-chip chip-hat"),
          event.on_click(types.AuditionCommand("v4 w85 f440 a-3 B0 l1")),
        ],
        [text("w85 OpenHat")],
      ),
      html.button(
        [
          class("active-token-chip chip-snare"),
          event.on_click(types.AuditionCommand("v1 w83 f440 a0 B0 l1")),
        ],
        [text("w83 Snare")],
      ),
      html.button(
        [
          class("active-token-chip chip-clap"),
          event.on_click(types.AuditionCommand("v2 w86 f440 a-1 B0 l1")),
        ],
        [text("w86 Clap")],
      ),
      html.button(
        [
          class("active-token-chip chip-cowbell"),
          event.on_click(types.AuditionCommand("v5 w96 f440 a-2 B0 l1")),
        ],
        [text("w96 Cowbell")],
      ),
      html.button(
        [
          class("active-token-chip chip-lead"),
          event.on_click(types.AuditionCommand(
            "v3 w15 a-2 f800 q3.5 t0,0.22,0,0 B0 n48 l1",
          )),
        ],
        [text("w15 303 Saw")],
      ),
    ]),

    // Unified Editor Buffer
    html.div([class("acme-editor-container")], [
      html.textarea(
        [
          class("acme-document-textarea"),
          placeholder("# Synthesis & Patches buffer"),
          value(model.synth_code),
          event.on_input(types.UpdateSynthCode),
        ],
        model.synth_code,
      ),
    ]),

    // Footer actions
    html.div([class("acme-col-footer")], [
      html.button(
        [class("btn btn-sm btn-primary"), event.on_click(types.EvalSynthCode)],
        [text("▶ Eval Patches (synth.sk)")],
      ),
      html.span([class("acme-footer-hint")], [
        text("Configure K-synth models & DWGS wavetables for voices 0–15"),
      ]),
    ]),
  ])
}

/// Column 1: The Live Score (score.sk)
pub fn view_column_score(model: Model) -> Element(Msg) {
  html.section([class("acme-column column-score")], [
    // Column Tag Bar
    html.div([class("acme-col-tagbar")], [
      html.span([class("acme-col-title")], [text("score.sk")]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.EvalAllBlocks)], [
        text("Put"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.EvalAllBlocks)], [
        text("EvalAll"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.LoopAllBlocks(16.0)),
        ],
        [text("Quant ~16")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.LoopAllBlocks(16.0)),
        ],
        [text("LoopAll")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.StopAllBlocks)], [
        text("StopAll"),
      ]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [class("acme-tag-btn panic"), event.on_click(types.PanicStop)],
        [text("Panic")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button([class("acme-tag-btn"), event.on_click(types.AddNewBlock)], [
        text("+ Track"),
      ]),
    ]),

    // Track blocks partitioned by ## headers
    html.div(
      [class("acme-score-tracks-container")],
      list.map(model.blocks, fn(block) {
        let ast_status = case skode.parse(block.code) {
          Ok(skode.Script(chunks)) ->
            html.span([class("ast-valid")], [
              text(
                "✓ Valid (" <> int.to_string(list.length(chunks)) <> " chunks)",
              ),
            ])
          Error(skode.ParseError(msg, pos)) ->
            html.span([class("ast-error")], [
              text("✗ Pos " <> int.to_string(pos) <> ": " <> msg),
            ])
        }

        let is_selected = block.id == model.selected_block_id
        let pulse_class = case block.active_pulse {
          True -> "pulse-highlight"
          False -> ""
        }

        html.article(
          [
            class(
              "acme-track-section "
              <> case is_selected {
                True -> "selected "
                False -> ""
              }
              <> pulse_class,
            ),
            event.on_click(types.SelectBlock(block.id)),
          ],
          [
            // Section Tag Bar Header
            html.div([class("acme-track-tagbar")], [
              html.span([class("acme-track-sigil")], [text("##")]),
              html.input([
                class("acme-track-title-input"),
                type_("text"),
                value(block.name),
                event.on_input(fn(n) { types.UpdateBlockName(block.id, n) }),
              ]),

              // State Badge
              html.span(
                [
                  class(case block.status {
                    Ready -> "badge badge-ready"
                    Looping(_) -> "badge badge-looping"
                    OneShotting -> "badge badge-oneshot"
                    Muted -> "badge badge-muted"
                    ErrorState(_) -> "badge badge-muted"
                  }),
                ],
                [
                  text(case block.status {
                    Ready -> "Ready"
                    Looping(i) -> "Loop ~" <> float.to_string(i)
                    OneShotting -> "1-Shot"
                    Muted -> "Muted"
                    ErrorState(_) -> "Error"
                  }),
                ],
              ),

              // Action Buttons
              html.button(
                [
                  class("btn btn-sm btn-primary"),
                  event.on_click(types.EvalBlockImmediate(block.id)),
                ],
                [text("▶ Run")],
              ),
              html.button(
                [
                  class(case block.status {
                    Looping(_) -> "btn btn-sm btn-success active"
                    _ -> "btn btn-sm btn-outline"
                  }),
                  event.on_click(types.EvalBlockQuantized(block.id, 16.0)),
                ],
                [text("🔁 Loop ~16")],
              ),
              html.button(
                [
                  class(case block.status {
                    Muted -> "btn btn-sm btn-danger active"
                    _ -> "btn btn-sm btn-outline"
                  }),
                  event.on_click(types.ToggleBlockMute(block.id)),
                ],
                [
                  text(case block.status {
                    Muted -> "Unmute"
                    _ -> "Mute"
                  }),
                ],
              ),
              html.button(
                [
                  class("btn btn-sm btn-danger"),
                  event.on_click(types.DeleteBlock(block.id)),
                ],
                [text("✕")],
              ),
            ]),

            // Textarea
            html.div([class("acme-track-code-container")], [
              html.textarea(
                [
                  class("acme-track-textarea"),
                  value(block.code),
                  event.on_input(fn(c) { types.UpdateBlockCode(block.id, c) }),
                  event.on("keydown", editor.key_down_block_decoder(block.id)),
                ],
                block.code,
              ),
            ]),

            // AST Indicator
            html.div([class("acme-track-ast-bar")], [
              ast_status,
              html.span([class("key-hint")], [
                text("Shift+Enter = 1-Shot | Ctrl+Enter = Loop ~16"),
              ]),
            ]),
          ],
        )
      }),
    ),
  ])
}

/// Column 2: Plumber & Monitor (monitor.sk)
pub fn view_column_monitor(model: Model) -> Element(Msg) {
  let #(left_lvl, right_lvl) =
    calculate_vu_levels(model.voices, model.master_volume_db)
  let active_voices_count = list.count(model.voices, fn(v) { v.active })

  html.section([class("acme-column column-monitor")], [
    // Column Tag Bar
    html.div([class("acme-col-tagbar")], [
      html.span([class("acme-col-title")], [text("monitor.sk")]),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.ClearMonitorLogs),
        ],
        [text("Clear")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("??")),
        ],
        [text("?? Voices")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("\\")),
        ],
        [text("\\ Details")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("/s 2")),
        ],
        [text("/s 2 Audio")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [
          class("acme-tag-btn"),
          event.on_click(types.AuditionCommand("?ws")),
        ],
        [text("?ws Waves")],
      ),
      html.span([class("acme-tag-divider")], [text("|")]),
      html.button(
        [class("acme-tag-btn panic"), event.on_click(types.PanicStop)],
        [text("S-1 Panic")],
      ),
    ]),

    // 1. Master Stereo VU Meter
    html.div([class("acme-vu-meter-card")], [
      html.div([class("vu-header")], [
        html.span([class("vu-title")], [text("MASTER STEREO VU")]),
        html.span([class("vu-vol-tag")], [
          text("Vol: " <> float.to_string(model.master_volume_db) <> " dB"),
        ]),
      ]),
      html.div([class("vu-meter-row")], [
        html.span([class("vu-channel-lbl")], [text("L:")]),
        html.pre([class("vu-bar-pre")], [text(render_vu_bar(left_lvl))]),
        html.span([class("vu-db-readout")], [text(level_to_db_text(left_lvl))]),
      ]),
      html.div([class("vu-meter-row")], [
        html.span([class("vu-channel-lbl")], [text("R:")]),
        html.pre([class("vu-bar-pre")], [text(render_vu_bar(right_lvl))]),
        html.span([class("vu-db-readout")], [text(level_to_db_text(right_lvl))]),
      ]),
    ]),

    // 2. Active Voice Pool & Orbit Constellation Container
    html.div([class("acme-visual-section")], [
      html.div([class("visual-header")], [
        html.span([class("visual-title")], [
          text(
            "VOICE CONSTELLATION ("
            <> int.to_string(active_voices_count)
            <> " / 16 ACTIVE)",
          ),
        ]),
      ]),
      html.div([class("constellation-embed")], [
        constellation.view_constellation(
          model.voices,
          active_voices_count,
          model.master_volume_db,
        ),
      ]),
    ]),

    // 3. The Plumber Telemetry Stream
    html.div([class("acme-plumber-stream-card")], [
      html.div([class("plumber-header")], [
        html.span([class("plumber-title")], [text("PLUMBER TELEMETRY & LOGS")]),
        html.button(
          [class("btn btn-xs"), event.on_click(types.ClearMonitorLogs)],
          [text("Clear")],
        ),
      ]),
      html.div(
        [class("plumber-logs-stream")],
        list.map(model.repl.logs, fn(log) {
          html.pre(
            [
              class(case log.is_error {
                True -> "plumber-log-entry error"
                False -> "plumber-log-entry"
              }),
            ],
            [text(log.text)],
          )
        }),
      ),
    ]),

    // 4. Bottom Terminal Console REPL
    html.div([class("acme-repl-input-card")], [
      html.span([class("repl-prompt")], [text("skred>")]),
      html.input([
        class("repl-input"),
        type_("text"),
        placeholder("?? for voices, \\ for details, S-1 for panic"),
        value(model.repl.input),
        event.on_input(types.UpdateReplInput),
        event.on("keydown", editor.key_down_console_decoder()),
      ]),
      html.button(
        [
          class("btn btn-sm btn-primary"),
          event.on_click(types.SubmitReplCommand),
        ],
        [text("Enter")],
      ),
    ]),
  ])
}

/// Root Acme Workstation View
pub fn view_acme_workstation(model: Model) -> Element(Msg) {
  html.div([class("acme-workstation-app")], [
    // Full-width Master Acme Tag Bar
    view_acme_master_tag_bar(model),

    // 3-Column Tiling Columns (100% Viewport)
    html.main([class("acme-tiling-columns")], [
      view_column_patches(model),
      view_column_score(model),
      view_column_monitor(model),
    ]),

    // Help Modal
    case model.show_help {
      True -> editor.view_help_modal()
      False -> element.none()
    },
  ])
}
