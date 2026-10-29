//// # Voice & Telemetry Parameter Inspector
////
//// Uses the typed Skode AST parser to transform raw Forth-style status strings
//// from Skred (e.g. `v0 w82 f440 n69,0 a3 vc1 b0 B0 p-0.5 t0,0.3,0,0`)
//// into clean, human-readable inspection cards for musicians.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import live_skred/skode.{type Element, Atom, Chunk, Num, Script}

/// Structured inspection record for an individual synthesis voice.
pub type VoiceInspection {
  VoiceInspection(
    voice_id: Int,
    wave_id: Int,
    wave_name: String,
    freq_hz: Float,
    midi_note: Float,
    cents: Float,
    amp_db: Float,
    pan: Float,
    loop_mode: Int,
    attack_ms: Float,
    decay_ms: Float,
    sustain_level: Float,
    release_ms: Float,
    events_active: Bool,
  )
}

/// Resolves human-readable instrument names for Skred's wavetables (0..99).
pub fn wave_display_name(wave_id: Int) -> String {
  case wave_id {
    82 -> "808 Kick Drum (300ms)"
    83 -> "Acoustic Snare (280ms)"
    84 -> "Closed Hi-Hat (200ms)"
    85 -> "Open Hi-Hat (750ms)"
    86 -> "Hand Clap (200ms)"
    87 -> "Rimshot (60ms)"
    88 -> "Low Tom (350ms)"
    89 -> "Mid-Low Tom (300ms)"
    90 -> "Mid Tom (250ms)"
    91 -> "High Tom (200ms)"
    92 -> "Synth Tom (300ms)"
    93 -> "Electro Tom (280ms)"
    94 -> "Crash Cymbal (1.2s)"
    95 -> "Ride Cymbal (1.0s)"
    96 -> "808 Cowbell (900ms)"
    97 -> "Clave / Stick (80ms)"
    98 -> "Cabasa / Shaker (180ms)"
    99 -> "Industrial Metallic FX"
    0 -> "Sine Wave"
    1 -> "Triangle Wave"
    2 -> "Sawtooth Wave"
    3 -> "Pulse / Square Wave"
    w if w >= 4 && w <= 81 -> "DWGS Wave " <> int.to_string(w) <> " (DW-8000)"
    w -> "Wavetable " <> int.to_string(w)
  }
}

/// Formats stereo panning into intuitive text (-1.0 to 1.0).
pub fn format_pan(pan: Float) -> String {
  case pan {
    p if p <. -0.05 ->
      int.to_string(float.round(float.absolute_value(p) *. 100.0))
      <> "% Left (p"
      <> float.to_string(p)
      <> ")"
    p if p >. 0.05 ->
      int.to_string(float.round(p *. 100.0))
      <> "% Right (p"
      <> float.to_string(p)
      <> ")"
    _ -> "Center (p0.0)"
  }
}

/// Converts a MIDI note number into standard musical note notation (e.g. 60 -> C4, 69 -> A4).
pub fn note_name(midi_note: Float) -> String {
  let note_int = float.round(midi_note)
  let semitone = note_int % 12
  let octave = { note_int / 12 } - 1
  let name = case semitone {
    0 -> "C"
    1 -> "C#"
    2 -> "D"
    3 -> "D#"
    4 -> "E"
    5 -> "F"
    6 -> "F#"
    7 -> "G"
    8 -> "G#"
    9 -> "A"
    10 -> "A#"
    11 -> "B"
    _ -> "?"
  }
  name <> int.to_string(octave) <> " (" <> int.to_string(note_int) <> ")"
}

/// Attempts to parse a single line of Skred voice diagnostic tokens into a `VoiceInspection`.
pub fn parse_voice_line(line: String) -> Result(VoiceInspection, Nil) {
  let trimmed = string.trim(line)
  case string.starts_with(trimmed, "v") {
    False -> Error(Nil)
    True -> {
      case skode.parse(trimmed) {
        Ok(Script([Chunk(elements), ..])) -> {
          option.to_result(extract_voice_inspection(elements), Nil)
        }
        _ -> Error(Nil)
      }
    }
  }
}

fn extract_voice_inspection(
  elements: List(Element),
) -> Option(VoiceInspection) {
  let voice_opt = find_atom_int(elements, "v")
  case voice_opt {
    None -> None
    Some(v_id) -> {
      let wave_id = find_atom_int(elements, "w") |> option.unwrap(0)
      let freq = find_atom_float(elements, "f") |> option.unwrap(440.0)
      let #(note, cents) = case find_atom_args(elements, "n") {
        Some([Num(n), Num(c), ..]) -> #(n, c)
        Some([Num(n)]) -> #(n, 0.0)
        _ -> #(69.0, 0.0)
      }
      let amp = find_atom_float(elements, "a") |> option.unwrap(0.0)
      let pan = find_atom_float(elements, "p") |> option.unwrap(0.0)
      let loop_m = find_atom_int(elements, "B") |> option.unwrap(0)
      let events = case find_atom_int(elements, "vc") {
        Some(1) -> True
        _ -> False
      }

      let #(att_ms, dec_ms, sus, rel_ms) = case find_atom_args(elements, "t") {
        Some([Num(a), Num(d), Num(s), Num(r), ..]) -> #(
          a *. 1000.0,
          d *. 1000.0,
          s *. 100.0,
          r *. 1000.0,
        )
        _ -> #(0.0, 300.0, 0.0, 0.0)
      }

      Some(VoiceInspection(
        voice_id: v_id,
        wave_id: wave_id,
        wave_name: wave_display_name(wave_id),
        freq_hz: freq,
        midi_note: note,
        cents: cents,
        amp_db: amp,
        pan: pan,
        loop_mode: loop_m,
        attack_ms: att_ms,
        decay_ms: dec_ms,
        sustain_level: sus,
        release_ms: rel_ms,
        events_active: events,
      ))
    }
  }
}

fn find_atom_args(
  elements: List(Element),
  name: String,
) -> Option(List(skode.Value)) {
  case elements {
    [] -> None
    [Atom(n, args), ..rest] ->
      case n == name {
        True -> Some(args)
        False -> find_atom_args(rest, name)
      }
    [_, ..rest] -> find_atom_args(rest, name)
  }
}

fn find_atom_int(elements: List(Element), name: String) -> Option(Int) {
  case find_atom_args(elements, name) {
    Some([Num(f), ..]) -> Some(float.round(f))
    _ -> None
  }
}

fn find_atom_float(elements: List(Element), name: String) -> Option(Float) {
  case find_atom_args(elements, name) {
    Some([Num(f), ..]) -> Some(f)
    _ -> None
  }
}

/// Renders a single `VoiceInspection` into an aligned ASCII inspector card.
pub fn format_inspection_card(v: VoiceInspection) -> String {
  let amp_sign = case v.amp_db >=. 0.0 {
    True -> "+"
    False -> ""
  }
  let amp_str = amp_sign <> float.to_string(v.amp_db) <> " dB"
  let freq_str = float.to_string(v.freq_hz) <> " Hz"
  let note_str = note_name(v.midi_note)
  let loop_str = case v.loop_mode {
    0 -> "One-Shot (B0)"
    _ -> "Infinite Loop (B1)"
  }
  let events_str = case v.events_active {
    True -> "Telemetry Active (vc1)"
    False -> "Silent (vc0)"
  }

  let env_str =
    "A: "
    <> float.to_string(v.attack_ms)
    <> "ms | D: "
    <> float.to_string(v.decay_ms)
    <> "ms | S: "
    <> float.to_string(v.sustain_level)
    <> "% | R: "
    <> float.to_string(v.release_ms)
    <> "ms"

  let title = "── [VOICE " <> int.to_string(v.voice_id) <> " PARAMETERS] "
  let header = "┌" <> string.pad_end(title, 58, "─") <> "┐"
  let footer = "└" <> string.repeat("─", 58) <> "┘"

  let l1 =
    "│ Instrument:  Wave "
    <> int.to_string(v.wave_id)
    <> " ["
    <> v.wave_name
    <> "]"
  let l2 = "│ Tuning:      " <> freq_str <> "  •  " <> note_str
  let l3 = "│ Volume/Pan:  " <> amp_str <> "  •  " <> format_pan(v.pan)
  let l4 = "│ Envelope:    " <> env_str
  let l5 = "│ Playback:    " <> loop_str <> "  •  " <> events_str

  header
  <> "\n"
  <> string.pad_end(l1, 59, " ")
  <> "│\n"
  <> string.pad_end(l2, 59, " ")
  <> "│\n"
  <> string.pad_end(l3, 59, " ")
  <> "│\n"
  <> string.pad_end(l4, 59, " ")
  <> "│\n"
  <> string.pad_end(l5, 59, " ")
  <> "│\n"
  <> footer
}

/// Inspects a raw stdout block from Skred.
/// If it contains voice diagnostics (like `v0 w82 ...`), formats it into a clean inspector view.
/// Otherwise, returns the original output.
pub fn format_console_output(cmd: String, stdout: String) -> String {
  let lines =
    stdout
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(l) { l != "" })

  let parsed_voices = list.filter_map(lines, parse_voice_line)

  case parsed_voices {
    [] ->
      case stdout {
        "" -> "> " <> cmd <> " -> OK"
        _ -> "> " <> cmd <> "\n" <> stdout
      }
    [single] -> "> " <> cmd <> "\n" <> format_inspection_card(single)
    multiple -> {
      let rows =
        list.map(multiple, fn(v) {
          let v_tag = string.pad_end("v" <> int.to_string(v.voice_id), 5, " ")
          let w_tag =
            string.pad_end(
              "w" <> int.to_string(v.wave_id) <> " [" <> v.wave_name <> "]",
              30,
              " ",
            )
          let pitch_tag = string.pad_end(note_name(v.midi_note), 14, " ")
          let amp_sign = case v.amp_db >=. 0.0 {
            True -> "+"
            False -> ""
          }
          let amp_tag =
            string.pad_end(
              amp_sign <> float.to_string(v.amp_db) <> "dB",
              9,
              " ",
            )
          let pan_tag = string.pad_end("p" <> float.to_string(v.pan), 8, " ")
          let loop_tag = case v.loop_mode {
            0 -> "1-Shot"
            _ -> "Loop"
          }
          "│ " <> v_tag <> w_tag <> pitch_tag <> amp_tag <> pan_tag <> loop_tag
        })

      let header =
        "┌── [ACTIVE VOICE POOL] ──────────────────────────────────────────────┐\n"
        <> "│ VOICE INSTRUMENT                    PITCH         VOL      PAN     MODE│\n"
        <> "├────────────────────────────────────────────────────────────────────┤"
      let footer =
        "└────────────────────────────────────────────────────────────────────┘"

      "> "
      <> cmd
      <> "\n"
      <> header
      <> "\n"
      <> string.join(rows, "\n")
      <> "\n"
      <> footer
    }
  }
}
