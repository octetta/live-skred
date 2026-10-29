//// # Curated Live Coding Presets for Live-Skred
////
//// Built-in starter sets that demonstrate beats, acid basslines,
//// physical modeling, and deferred generative arpeggios.

import gleam/option.{None}
import live_skred/types.{type PresetSet, CodeBlock, Looping, PresetSet, Ready}

/// The default starter set loaded on first launch: Minimal Techno Groove.
pub fn default_starter_set() -> PresetSet {
  PresetSet(
    name: "4/4 Minimal Techno Groove",
    description: "Classic four-on-the-floor beat with offbeat hats and an acid bassline stepping through a stream.",
    blocks: [
      CodeBlock(
        id: 0,
        name: "01: Four-on-the-Floor Kick",
        code: "# Kick drum pulse on voice 0\nv0 a0 f60 t1 0 0.2 0.2 B1 ;\nv0 l1 ; +0.5 v0 l1 ; +0.5 v0 l1 ; +0.5 v0 l1",
        status: Looping(interval_ticks: 4.0),
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 1,
        name: "02: Offbeat Hats",
        code: "# Metallic noise hat on voice 1\nv1 a-6 f8000 t1 0 0.05 0.05 B1 ;\n+0.25 v1 l1 ; +0.5 v1 l1 ; +0.5 v1 l1 ; +0.5 v1 l1",
        status: Looping(interval_ticks: 4.0),
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 2,
        name: "03: Acid 303 Bassline Stream",
        code: "# Acid bassline stepping through stream 0\n( 36 39 43 46 48 ) /SS 0 ;\nv2 a-3 f900 q3.5 n&0 l1 +0.25 l0",
        status: Looping(interval_ticks: 1.0),
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 3,
        name: "04: Space Arp Chords",
        code: "# Stereophonic arp across voices 8 & 9\n( 60 63 67 70 72 75 ) /SS 1 ;\nv8 p-0.6 n&1 a-6 l1 ; +0.125 v9 p0.6 n&1 a-6 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
    ],
  )
}

/// Ambient & physical synthesis starter set.
pub fn ambient_ksynth_set() -> PresetSet {
  PresetSet(
    name: "Generative K-Synth Ambient Clouds",
    description: "Sub drone with plucked waveguide voices and variable deferred timing.",
    blocks: [
      CodeBlock(
        id: 0,
        name: "01: Deep Sub Drone",
        code: "# Continuous low drone\nv4 p-0.5 a-6 n48 t1 2 2 4 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 1,
        name: "02: Plucked Waveguide Arp",
        code: "# Physical plucks with variable delay in $0\n0.125 0 = ;\n( 60 62 65 67 72 74 ) /SS 2 ;\nv5 p0.5 a-4 n&2 l1 ; +$0 v6 n&2 l1 ; +$0 v7 n&2 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
    ],
  )
}

/// All available presets.
pub fn all_presets() -> List(PresetSet) {
  [default_starter_set(), ambient_ksynth_set()]
}
