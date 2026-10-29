import gleeunit
import gleeunit/should
import live_skred/clock
import live_skred/inspector
import live_skred/presets
import live_skred/skode
import live_skred/types.{type CodeBlock}

pub fn main() {
  gleeunit.main()
}

pub fn clock_tick_interval_test() {
  // At 120 BPM, 1 beat = 500ms; 4 ticks/beat = 125ms per tick
  clock.tick_interval_ms(120.0)
  |> should.equal(125)

  // At 60 BPM, 1 beat = 1000ms; 4 ticks/beat = 250ms per tick
  clock.tick_interval_ms(60.0)
  |> should.equal(250)

  // At 240 BPM, 1 beat = 250ms; 4 ticks/beat = 62.5ms ~ 63ms
  clock.tick_interval_ms(240.0)
  |> should.equal(63)
}

pub fn preset_blocks_parse_cleanly_test() {
  let techno = presets.default_starter_set()
  techno.name |> should.equal("4/4 Minimal Techno Groove")

  // Ensure all starter blocks parse into valid Skode scripts
  list_all_blocks_valid(techno.blocks)
  |> should.equal(True)

  let ambient = presets.ambient_ksynth_set()
  list_all_blocks_valid(ambient.blocks)
  |> should.equal(True)
}

fn list_all_blocks_valid(blocks: List(CodeBlock)) -> Bool {
  case blocks {
    [] -> True
    [b, ..rest] -> {
      let parsed_whole = case skode.parse(b.code) {
        Ok(_) -> True
        Error(_) -> False
      }
      let #(setup, pattern) = skode.split_setup_and_pattern(b.code)
      let parsed_setup = case setup {
        "" -> True
        _ ->
          case skode.parse(setup) {
            Ok(_) -> True
            Error(_) -> False
          }
      }
      let parsed_pattern = case skode.parse(pattern) {
        Ok(_) -> True
        Error(_) -> False
      }
      case parsed_whole && parsed_setup && parsed_pattern {
        True -> list_all_blocks_valid(rest)
        False -> False
      }
    }
  }
}

pub fn skode_stream_and_defer_parsing_test() {
  // Test array stream creation via /SS
  let assert Ok(script_stream) = skode.parse("( 60 63 67 70 ) /SS 0")
  let assert skode.Script([
    skode.Chunk([
      skode.Arr([
        skode.Num(60.0),
        skode.Num(63.0),
        skode.Num(67.0),
        skode.Num(70.0),
      ]),
      skode.Atom("/SS", [skode.Num(0.0)]),
    ]),
  ]) = script_stream

  // Test deferrals with variables and streams
  let assert Ok(script_defer) = skode.parse("+$0 v0 l1 ; ~&1 v1 l0")
  let assert skode.Script([skode.Chunk([d1]), skode.Chunk([d2])]) = script_defer
  d1
  |> should.equal(
    skode.Defer(skode.RelativeSeconds, skode.Variable(0), [
      skode.Atom("v", [skode.Num(0.0)]),
      skode.Atom("l", [skode.Num(1.0)]),
    ]),
  )
  d2
  |> should.equal(
    skode.Defer(skode.TempoTicks, skode.Stream(1), [
      skode.Atom("v", [skode.Num(1.0)]),
      skode.Atom("l", [skode.Num(0.0)]),
    ]),
  )
}

pub fn skode_array_with_variables_test() {
  let assert Ok(script) = skode.parse("($0 &1 42)")
  let assert skode.Script([skode.Chunk([skode.Arr(vals)])]) = script
  vals
  |> should.equal([
    skode.Variable(0),
    skode.Stream(1),
    skode.Num(42.0),
  ])
}

pub fn skode_atom_multi_arg_and_names_test() {
  // Atoms cannot contain numbers in their names
  let assert Ok(el_v0) = skode.parse_element("v0")
  el_v0 |> should.equal(skode.Atom("v", [skode.Num(0.0)]))

  let assert Ok(el_f440) = skode.parse_element("f440.5")
  el_f440 |> should.equal(skode.Atom("f", [skode.Num(440.5)]))

  // Multiple arguments postfix
  let assert Ok(el_args) = skode.parse_element("t 1.0, 0.0, 0.2, 0.2")
  el_args
  |> should.equal(
    skode.Atom("t", [
      skode.Num(1.0),
      skode.Num(0.0),
      skode.Num(0.2),
      skode.Num(0.2),
    ]),
  )
}

pub fn ast_voice_inspector_test() {
  let line = "v0 w82 f440 n69,0 a3 vc1 b0 B0 p-0.5 t0,0.3,0,0"
  let parsed_res = inspector.parse_voice_line(line)
  let assert Ok(v) = parsed_res

  v.voice_id |> should.equal(0)
  v.wave_id |> should.equal(82)
  v.wave_name |> should.equal("808 Kick Drum (300ms)")
  v.freq_hz |> should.equal(440.0)
  v.amp_db |> should.equal(3.0)
  v.pan |> should.equal(-0.5)
  v.loop_mode |> should.equal(0)
  v.decay_ms |> should.equal(300.0)
  v.events_active |> should.equal(True)

  let formatted = inspector.format_console_output("v0 \\", line)
  formatted |> should.not_equal("")
}
