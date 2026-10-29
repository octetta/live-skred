//// # Curated Live Coding Presets for Live-Skred
////
//// Built-in starter sets that demonstrate beats, acid basslines,
//// physical modeling, and deferred generative arpeggios.

import gleam/option.{None}
import live_skred/types.{type PresetSet, CodeBlock, PresetSet, Ready}

/// The default starter set loaded on first launch: Minimal Techno Groove.
pub fn default_starter_set() -> PresetSet {
  PresetSet(
    name: "4/4 Minimal Techno Groove",
    description: "Classic four-on-the-floor beat with built-in drum samples (w82, w84, w86 at f440) and an acid 303 stream bassline.",
    blocks: [
      CodeBlock(
        id: 0,
        name: "01: 4/4 Kick Drum (w82)",
        code: "# Setup: Voice 0, 808 Kick wave at f440, +3dB, one-shot
v0 w82 f440 a3 B0
---
# Pattern: Four-on-the-floor beat (loops every bar)
l1 ; +1.0 v0 l1 ; +2.0 v0 l1 ; +3.0 v0 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 1,
        name: "02: Offbeat Closed Hats (w84)",
        code: "# Setup: Voice 1, Closed Hat wave at f440, -3dB, one-shot
v1 w84 f440 a-3 B0
---
# Pattern: Offbeat 8th-note hats
+0.5 v1 l1 ; +1.5 v1 l1 ; +2.5 v1 l1 ; +3.5 v1 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 2,
        name: "03: Handclap Backbeat (w86)",
        code: "# Setup: Voice 2, Handclap wave at f440, -1dB, one-shot
v2 w86 f440 a-1 B0
---
# Pattern: Snappy backbeat on beats 2 & 4
+1.0 v2 l1 ; +3.0 v2 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 3,
        name: "04: Acid 303 Bassline Stream",
        code: "# Setup: 5-note pentatonic stream into slot 0, resonant DWGS saw on v3
( 36 39 43 46 48 ) /SS 0 ;
v3 w15 a-2 f800 q3.5 t0,0.22,0,0 B0
---
# Pattern: 16th-note stream stepping (rotates across bars!)
n&0 l1 ; +0.25 v3 n&0 l1 ; +0.5 v3 n&0 l1 ; +0.75 v3 n&0 l1",
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
    description: "Sub drone with 808 cowbell accents (w96) and plucked waveguide voices with deferred timing.",
    blocks: [
      CodeBlock(
        id: 0,
        name: "01: Deep Sub Drone",
        code: "# Continuous sub drone on DWGS wave 15\nv4 w15 p-0.5 a-4 n48 t0.5,1.5,0.4,1.0 B0 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 1,
        name: "02: Cowbell Accent Groove (w96)",
        code: "# 808 cowbell on beat accents using built-in wave 96 at f440\nv5 w96 f440 a-3 B0 ;\n+0.5 v5 l1 ; +1.0 v5 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 2,
        name: "03: Plucked Waveguide Arp",
        code: "# Physical plucks with variable delay in $0\n0.125 0 = ;\n( 60 62 65 67 72 74 ) /SS 2 ;\nv6 p-0.6 a-4 t0,0.3,0,0 B0 n&2 l1 ; +$0 v7 p0.6 a-4 t0,0.3,0,0 B0 n&2 l1",
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
