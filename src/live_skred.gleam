//// # Live-Skred Main Application
////
//// Live coding musical environment combining Skred 0.80.0,
//// the typed Skode AST, and reactive Lustre UI with an SVG Voice Constellation.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import live_skred/clock
import live_skred/presets
import live_skred/skred
import live_skred/types.{
  type Model, type Msg, type VoiceNode, CodeBlock, ConsoleLog, Looping, Model,
  Muted, OneShotting, QuantizedClock, Ready, ReplState, VoiceNode,
}
import live_skred/views/constellation
import live_skred/views/editor
import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event

fn make_range(start: Int, end: Int) -> List(Int) {
  case start <= end {
    True -> [start, ..make_range(start + 1, end)]
    False -> []
  }
}

/// Initializes the 16 voice nodes for the orbital constellation.
fn init_voices() -> List(VoiceNode) {
  make_range(0, 15)
  |> list.map(fn(i) {
    VoiceNode(
      id: i,
      active: False,
      velocity: 0.0,
      note: 60.0,
      pan: case i % 2 == 0 {
        True -> -1.0
        False -> 1.0
      },
      level: 0.0,
    )
  })
}

pub fn init(_) -> #(Model, Effect(Msg)) {
  let default_preset = presets.default_starter_set()
  let model =
    Model(
      blocks: default_preset.blocks,
      selected_block_id: 0,
      repl: ReplState(input: "", history: [], history_index: -1, logs: [
        ConsoleLog(
          id: "init",
          text: "live-skred initialized.\n• Press ▶ PLAY to run the quantized clock.\n• Built-in drums: w82=kick, w84=hat, w86=clap, w96=cowbell at f440/n69.\n• Defers (+0.5, +1.0) schedule tempo-relative beats; Shift+Enter evals block.\n• Use diagnostic buttons below or click any orbit voice to inspect engine status.",
          is_error: False,
        ),
      ]),
      voices: init_voices(),
      streams: [],
      clock: QuantizedClock(
        bpm: 120.0,
        is_running: False,
        tick_count: 0,
        quantum_ticks: 4,
      ),
      is_engine_ready: False,
      master_volume_db: 0.0,
      panic_active: False,
      show_help: False,
    )

  let effects =
    effect.batch([
      skred.init_engine_effect(),
      skred.subscribe_control_plane(types.ControlEventsReceived),
      clock.subscribe_clock(
        model.clock.bpm,
        model.clock.is_running,
        types.ClockTick,
      ),
    ])

  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.EngineInitialized(success) -> {
      let log = case success {
        True -> "Skred 0.80.0 WASM engine started successfully. Audio ready."
        False -> "Failed to initialize Skred WASM audio engine."
      }
      let new_repl =
        ReplState(..model.repl, logs: [
          ConsoleLog(id: "engine_ready", text: log, is_error: !success),
          ..model.repl.logs
        ])
      #(Model(..model, is_engine_ready: success, repl: new_repl), effect.none())
    }

    types.ControlEventsReceived(events) -> {
      let updated_voices =
        list.fold(events, model.voices, fn(current_voices, evt) {
          case evt {
            types.VoiceTrigger(v, vel) ->
              list.map(current_voices, fn(node) {
                case node.id == v {
                  True ->
                    VoiceNode(..node, active: True, velocity: vel, level: 1.0)
                  False -> node
                }
              })
            types.VoiceRelease(v) | types.VoiceFinished(v) ->
              list.map(current_voices, fn(node) {
                case node.id == v {
                  True -> VoiceNode(..node, active: False, level: 0.0)
                  False -> node
                }
              })
            _ -> current_voices
          }
        })
      #(Model(..model, voices: updated_voices), effect.none())
    }

    types.ClockTick -> {
      let next_tick = model.clock.tick_count + 1
      let updated_clock = QuantizedClock(..model.clock, tick_count: next_tick)

      // Find blocks scheduled to evaluate on this tick
      let #(updated_blocks, eval_cmds) =
        list.map(model.blocks, fn(block) {
          case block.status {
            Looping(interval_ticks) -> {
              let interval_int = float.round(interval_ticks)
              let should_eval = case interval_int > 0 {
                True -> next_tick % interval_int == 0
                False -> False
              }
              case should_eval {
                True -> #(
                  CodeBlock(..block, active_pulse: True),
                  Some(block.code),
                )
                False -> #(CodeBlock(..block, active_pulse: False), None)
              }
            }
            _ -> #(CodeBlock(..block, active_pulse: False), None)
          }
        })
        |> list.unzip

      let effects =
        eval_cmds
        |> list.filter_map(fn(cmd_opt) {
          case cmd_opt {
            Some(code) -> Ok(skred.send_command(code))
            None -> Error(Nil)
          }
        })
        |> effect.batch

      #(Model(..model, clock: updated_clock, blocks: updated_blocks), effects)
    }

    types.TogglePlayPause -> {
      let new_running = !model.clock.is_running
      let updated_clock = case new_running {
        True -> QuantizedClock(..model.clock, is_running: True, tick_count: 0)
        False -> QuantizedClock(..model.clock, is_running: False)
      }
      let eff = case new_running {
        True -> clock.subscribe_clock(model.clock.bpm, True, types.ClockTick)
        False -> effect.batch([clock.stop_clock_effect(), skred.panic_effect()])
      }
      #(Model(..model, clock: updated_clock), eff)
    }

    types.SetBpm(new_bpm) -> {
      let clamped = float.clamp(new_bpm, 30.0, 300.0)
      let updated_clock = QuantizedClock(..model.clock, bpm: clamped)
      let eff =
        effect.batch([
          skred.send_command("T" <> float.to_string(clamped)),
          clock.subscribe_clock(
            clamped,
            model.clock.is_running,
            types.ClockTick,
          ),
        ])
      #(Model(..model, clock: updated_clock), eff)
    }

    types.SetMasterVolume(new_db) -> {
      let clamped = float.clamp(new_db, -60.0, 6.0)
      #(
        Model(..model, master_volume_db: clamped),
        skred.set_master_volume_effect(clamped),
      )
    }

    types.SelectBlock(id) -> #(
      Model(..model, selected_block_id: id),
      effect.none(),
    )

    types.UpdateBlockCode(id, new_code) -> {
      let updated_blocks =
        list.map(model.blocks, fn(b) {
          case b.id == id {
            True -> CodeBlock(..b, code: new_code)
            False -> b
          }
        })
      #(Model(..model, blocks: updated_blocks), effect.none())
    }

    types.UpdateBlockName(id, new_name) -> {
      let updated_blocks =
        list.map(model.blocks, fn(b) {
          case b.id == id {
            True -> CodeBlock(..b, name: new_name)
            False -> b
          }
        })
      #(Model(..model, blocks: updated_blocks), effect.none())
    }

    types.EvalBlockImmediate(id) -> {
      case list.find(model.blocks, fn(b) { b.id == id }) {
        Ok(block) -> {
          let updated_blocks =
            list.map(model.blocks, fn(b) {
              case b.id == id {
                True -> CodeBlock(..b, active_pulse: True, status: OneShotting)
                False -> b
              }
            })
          #(
            Model(..model, blocks: updated_blocks),
            skred.eval_command_effect(block.code),
          )
        }
        _ -> #(model, effect.none())
      }
    }

    types.EvalBlockQuantized(id, interval_ticks) -> {
      case list.find(model.blocks, fn(b) { b.id == id }) {
        Ok(block) -> {
          let updated_blocks =
            list.map(model.blocks, fn(b) {
              case b.id == id {
                True ->
                  CodeBlock(
                    ..b,
                    active_pulse: False,
                    status: Looping(interval_ticks),
                  )
                False -> b
              }
            })
          // If clock was paused, start it automatically at tick 0 so blocks launch in phase
          let #(new_clock, clock_eff) = case model.clock.is_running {
            True -> #(model.clock, effect.none())
            False -> {
              let c =
                QuantizedClock(..model.clock, is_running: True, tick_count: 0)
              #(c, clock.subscribe_clock(c.bpm, True, types.ClockTick))
            }
          }
          let log =
            ConsoleLog(
              id: "armed_" <> int.to_string(id),
              text: "> Armed ["
                <> block.name
                <> "] for quantized loop (~"
                <> float.to_string(interval_ticks)
                <> " ticks)",
              is_error: False,
            )
          let updated_repl =
            ReplState(..model.repl, logs: [log, ..model.repl.logs])
          #(
            Model(
              ..model,
              blocks: updated_blocks,
              clock: new_clock,
              repl: updated_repl,
            ),
            clock_eff,
          )
        }
        _ -> #(model, effect.none())
      }
    }

    types.ToggleBlockMute(id) -> {
      let updated_blocks =
        list.map(model.blocks, fn(b) {
          case b.id == id {
            True -> {
              let new_status = case b.status {
                Muted -> Ready
                _ -> Muted
              }
              CodeBlock(..b, status: new_status)
            }
            False -> b
          }
        })
      #(Model(..model, blocks: updated_blocks), effect.none())
    }

    types.DeleteBlock(id) -> {
      let updated_blocks = list.filter(model.blocks, fn(b) { b.id != id })
      #(Model(..model, blocks: updated_blocks), effect.none())
    }

    types.AddNewBlock -> {
      let next_id =
        list.fold(model.blocks, 0, fn(acc, b) { int.max(acc, b.id + 1) })
      let new_block =
        CodeBlock(
          id: next_id,
          name: "Block " <> int.to_string(next_id + 1),
          code: "# New block\nv0 w82 f440 a3 B0 l1 ; +0.5 v0 l1",
          status: Ready,
          active_pulse: False,
          last_error: None,
        )
      #(
        Model(
          ..model,
          blocks: list.append(model.blocks, [new_block]),
          selected_block_id: next_id,
        ),
        effect.none(),
      )
    }

    types.UpdateReplInput(str) -> {
      let updated_repl = ReplState(..model.repl, input: str)
      #(Model(..model, repl: updated_repl), effect.none())
    }

    types.SubmitReplCommand -> {
      let cmd = string.trim(model.repl.input)
      case cmd != "" {
        True -> {
          let updated_repl =
            ReplState(..model.repl, input: "", history_index: -1, history: [
              cmd,
              ..model.repl.history
            ])
          #(Model(..model, repl: updated_repl), skred.eval_command_effect(cmd))
        }
        False -> #(model, effect.none())
      }
    }

    types.ExecuteReplCommand(cmd) -> {
      let updated_repl =
        ReplState(..model.repl, history_index: -1, history: [
          cmd,
          ..model.repl.history
        ])
      #(Model(..model, repl: updated_repl), skred.eval_command_effect(cmd))
    }

    types.ReplHistoryPrev -> {
      let count = list.length(model.repl.history)
      let next_index = model.repl.history_index + 1
      case next_index < count {
        True -> {
          let item =
            model.repl.history
            |> list.drop(next_index)
            |> list.first
            |> result.unwrap(model.repl.input)
          let updated_repl =
            ReplState(..model.repl, input: item, history_index: next_index)
          #(Model(..model, repl: updated_repl), effect.none())
        }
        False -> #(model, effect.none())
      }
    }

    types.ReplHistoryNext -> {
      let next_index = model.repl.history_index - 1
      case next_index >= 0 {
        True -> {
          let item =
            model.repl.history
            |> list.drop(next_index)
            |> list.first
            |> result.unwrap("")
          let updated_repl =
            ReplState(..model.repl, input: item, history_index: next_index)
          #(Model(..model, repl: updated_repl), effect.none())
        }
        False -> {
          let updated_repl =
            ReplState(..model.repl, input: "", history_index: -1)
          #(Model(..model, repl: updated_repl), effect.none())
        }
      }
    }

    types.ConsoleResultReceived(cmd, ret, stdout) -> {
      let formatted_text = case stdout {
        "" ->
          case ret == 0 {
            True -> "> " <> cmd <> " -> OK"
            False ->
              "> "
              <> cmd
              <> " -> Error (exit code "
              <> int.to_string(ret)
              <> ")"
          }
        _ -> "> " <> cmd <> "\n" <> stdout
      }
      let log =
        ConsoleLog(
          id: int.to_string(model.clock.tick_count) <> "_" <> cmd,
          text: formatted_text,
          is_error: ret != 0,
        )
      let new_logs = list.take([log, ..model.repl.logs], 50)
      let updated_repl = ReplState(..model.repl, logs: new_logs)
      #(Model(..model, repl: updated_repl), effect.none())
    }

    types.LoadPreset(preset) -> {
      #(
        Model(..model, blocks: preset.blocks, selected_block_id: 0),
        skred.panic_effect(),
      )
    }

    types.PanicStop -> {
      let stopped_blocks =
        list.map(model.blocks, fn(b) { CodeBlock(..b, status: Ready) })
      #(
        Model(..model, blocks: stopped_blocks, panic_active: True),
        skred.panic_effect(),
      )
    }

    types.ToggleHelp -> #(
      Model(..model, show_help: !model.show_help),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let active_voices_count = list.count(model.voices, fn(v) { v.active })

  html.div([class("live-skred-app")], [
    // Top Transport Bar
    editor.view_transport_bar(model),

    // Main 2-Column Live Workspace
    html.main([class("live-workspace")], [
      // Left Column: The Code Space
      html.section([class("code-space-panel")], [
        html.div([class("panel-header")], [
          html.h2([], [text("LIVE CODE BLOCKS")]),
          html.button(
            [class("btn btn-sm btn-success"), event.on_click(types.AddNewBlock)],
            [text("+ Add Block")],
          ),
        ]),
        html.div(
          [class("blocks-container")],
          list.map(model.blocks, fn(block) {
            editor.view_code_block(block, model.selected_block_id)
          }),
        ),
      ]),

      // Right Column: The Visual Reactor
      html.section([class("visual-reactor-panel")], [
        html.div([class("panel-header")], [
          html.h2([], [text("ORBITAL VOICE CONSTELLATION")]),
          html.span([class("telemetry-tag")], [
            text(int.to_string(active_voices_count) <> " VOICES ACTIVE"),
          ]),
        ]),

        // Constellation SVG
        html.div([class("constellation-container")], [
          constellation.view_constellation(
            model.voices,
            active_voices_count,
            model.master_volume_db,
          ),
        ]),

        // Stream & Variable Quick Status
        html.div([class("telemetry-card")], [
          html.h3([], [text("STREAM & TIMING INSPECTOR")]),
          html.p([class("telemetry-hint")], [
            text(
              "Streams pop via (array) /SS <slot> | Scheduled via +0.25 or +$0 | Quantized via ~4",
            ),
          ]),
        ]),
      ]),
    ]),

    // Bottom REPL Bar
    editor.view_repl_bar(model),

    // Help & Syntax Modal
    case model.show_help {
      True -> editor.view_help_modal()
      False -> element.none()
    },
  ])
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
