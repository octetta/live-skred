# Help Joe Understand: The Live-Skred Mental Model & Hacker's Guide

> **A field guide to `live-skred` for Joe Stewart.**  
> Written to connect what Strudel does to what Skred does, demystify the timing & synchronization math, explain the Gleam/Lustre codebase architecture, and give you concrete recipes to hack on while your weekly token quota resets.

---

## Table of Contents
1. [The Big Picture: What is Live-Skred?](#1-the-big-picture-what-is-live-skred)
2. [The Strudel Connection: Cycles vs. Defers](#2-the-strudel-connection-cycles-vs-defers)
3. [The Sync Mystery Solved: Why Things Felt Out of Whack](#3-the-sync-mystery-solved-why-things-felt-out-of-whack)
4. [Where Command Output Lives & How to Inspect Voices](#4-where-command-output-lives--how-to-inspect-voices)
5. [Skode Language & Built-in Drums Reference](#5-skode-language--built-in-drums-reference)
6. [Tour of the Gleam & Lustre Codebase](#6-tour-of-the-gleam--lustre-codebase)
7. [Hacker Recipes: What You Can Build During the Token Reset](#7-hacker-recipes-what-you-can-build-during-the-token-reset)

---

## 1. The Big Picture: What is Live-Skred?

**Live-skred** is an experimental live-coding musical instrument running entirely in the browser. It combines three key layers:
1. **The Audio Engine (`Skred 0.80.0` in WebAssembly)**: A high-performance, sample-accurate C synthesis engine featuring 256 voices, single-cycle wavetables (classic + DWGS), 44.1 kHz one-shot drum models (waves 82–99), physical modeling synthesis, stereo delay buses, and an event queue.
2. **The Live Language (`Skode` / `ANDS`)**: A typed, concise Forth-inspired notation for sound design, stream sequencing, and timed event deferrals.
3. **The UI & Control Plane (`Gleam + Lustre`)**: A functional reactive web frontend using the Elm-style Model-View-Update (MVU) pattern, driving an interactive code editor, a live REPL terminal, a quantized musical clock, and an SVG orbital voice constellation.

---

## 2. The Strudel Connection: Cycles vs. Defers

If you've heard about or seen **Strudel** (or **TidalCycles**), you might wonder: *How does what we built in Live-Skred compare to Strudel?*

### The Strudel / TidalCycles Mental Model: "Cycles & Slices"
* In Strudel, **time is continuous and cyclic**. Everything is measured against a global **Cycle** (typically 1 musical measure/bar).
* A pattern is a pure mathematical function of time: `TimeSpan -> [Events]`.
* When you write:
  ```javascript
  s("bd hh sd hh")
  ```
  Strudel automatically divides the 1-cycle bar into 4 equal slices:
  * Slice 0.00..0.25: `bd` (bass drum)
  * Slice 0.25..0.50: `hh` (hi-hat)
  * Slice 0.50..0.75: `sd` (snare drum)
  * Slice 0.75..1.00: `hh` (hi-hat)
* When you press **Ctrl+Enter** in Strudel to edit code while music is playing:
  **It never interrupts the middle of a bar.** The engine waits for the next cycle downbeat ($t = 0.0$) and cleanly hot-swaps the new pattern in phase.

### The Skred Mental Model: "State Machine & Event Queue"
* Skred comes from the Forth / modular synth tradition.
* It is a **stateful C machine**: voice `v0` remembers its current wave (`w82`), its pitch (`f440` or `n69`), its amplitude (`a0`), its envelope (`t0,0.2,0,0`), and whether it loops (`B0` or `B1`).
* Skred executes commands **imperatively**:
  * `v0 l1` triggers voice 0 right now.
  * `+0.5 v0 l1` pushes an event into Skred's internal sample-accurate queue to execute 0.5 beats in the future.
  * `( 60 63 67 ) /SS 0` stores an array of MIDI notes into Stream slot 0, and `n&0` pops the next note each time it evaluates.

### How Live-Skred Bridges the Two Worlds
In `live-skred`, each **Live Code Block** represents a musical pattern track:
* **Block 0 (Kick)** loops every 16 ticks (1 bar = 4 beats in 4/4 time).
* **Block 1 (Hats)** loops every 16 ticks, with offbeat defers (`+0.5`, `+1.5`, `+2.5`, `+3.5`).
* **Block 2 (Clap)** loops every 16 ticks, on backbeats (`+1.0`, `+3.0`).
* **Block 3 (Acid Bass)** loops every 4 ticks (1 beat), popping notes from an array stream (`n&0`).

---

## 3. The Sync Mystery Solved: Why Things Felt Out of Whack

When you first started playing with blocks, you noticed: *"when i do start things they don't seem to have any rhyme or reason on how they're synced."*

### Why that happened
1. **Immediate Execution on Mouse Click**:
   Previously, clicking the `🔁 Loop` button evaluated the block's code **immediately on your mouse click** (e.g. at beat 2.37) and *then* scheduled repeats on the clock.
   If you clicked Kick at beat 1.1 and clicked Hat 2 seconds later at beat 3.4, their internal `+` defers were firing completely out of phase with each other!
2. **Paused Clock**:
   If the master clock was paused, clicking "Loop" only triggered the block once because the clock wasn't advancing ticks.
3. **Missing Visual Anchor**:
   There was no visual indicator showing where the downbeat was, making it impossible to see the rhythm grid.

### How it is fixed now (Quantized Launch)
1. **Quantized Launching**:
   When you click `🔁 Loop ~16` (or press **Ctrl+Enter**), the block is **armed**. It does **not** fire immediately out of phase. Instead, it waits for the next bar downbeat (`tick % 16 == 0`), ensuring Kick, Hats, Clap, and Bass all launch on the exact same zero-crossing!
   *(If the clock was paused, clicking Loop automatically starts it at tick 0).*
2. **Visual Bar & Beat Counter**:
   The top transport bar now features an LED beat display:
   ```
   BAR 1 : BEAT 2   [1] [●] [3] [4]
   ```
   You can watch the 4 beats sweep across the bar in real time at your chosen BPM.

### The Math of Defers (`+` vs `~`) & Semicolons (`;`)
In Skred's C engine (`skode.c` line 2110):
```c
if (mode == '+') delay *= (tempo_time_per_step * 4.0f);
```
* **`+delay` is Tempo-Relative**:
  `delay` is multiplied by 1 beat (quarter note).
  * `+1.0` = exactly **1 beat** (quarter note).
  * `+0.5` = **half a beat** (8th note).
  * `+0.25` = **quarter of a beat** (16th note).
  * `+4.0` = **4 beats** (1 full 4/4 bar).
* **`~delay` is Raw Seconds**:
  `~0.25` waits 250 milliseconds regardless of tempo.
* **The Semicolon (`;`) Chunk Reset**:
  Each chunk ending with `;` resets Skred's defer accumulator `ctx->defer_last = 0`.
  Therefore, this pattern:
  ```
  v0 w82 f440 a3 B0 l1 ;
  +1.0 v0 l1 ;
  +2.0 v0 l1 ;
  +3.0 v0 l1
  ```
  schedules 4 kicks at exact bar positions: **0.0 beats**, **1.0 beats**, **2.0 beats**, and **3.0 beats**!

---

## 4. Where Command Output Lives & How to Inspect Voices

### The Console Output Pane
All command evaluations, voice status queries, and error messages appear in the **Terminal Console Pane** located directly below the diagnostic toolbar and above the text input:

```
┌────────────────────────────────────────────────────────────────────────┐
│ DIAGNOSTICS: [?? Voices] [/s 2 Audio] [\ Details] [?ws Waves] [?S] ... │
├────────────────────────────────────────────────────────────────────────┤
│ ⚡ CONSOLE OUTPUT & DIAGNOSTIC LOGS                                     │
├────────────────────────────────────────────────────────────────────────┤
│ > ??                                                                   │
│ V  0  n69  f440.00  a 3.0  w82  t0.00 0.22 0.00 0.00  B0  [ACTIVE]     │
│ V  1  n69  f440.00  a-3.0  w84  t0.00 0.06 0.00 0.00  B0  [IDLE]       │
├────────────────────────────────────────────────────────────────────────┤
│ skred> [ Type command here and press Enter...                        ] │
└────────────────────────────────────────────────────────────────────────┘
```

### Inspecting Voices Manually
You have four easy ways to check voices:
1. **Click Any Voice in the Orbital Constellation**:
   Clicking circle `v0`, `v1`, etc. in the SVG orbit automatically dispatches `v<id> \`, which prints that voice's complete parameter sheet (wavetable, pitch, filter, ADSR, pan) into the console.
2. **Click `[?? Voices]`**:
   Prints a compact list of all currently active voices and their frequencies.
3. **Click `[/s 2 Audio]`**:
   Prints the audio engine driver, samplerate, buffer size, and voice pool allocations.
4. **Type into the REPL Input and press Enter**:
   * `??` : Show active voices.
   * `\` : Show selected voice details.
   * `v3 \` : Select voice 3 and show its details.
   * `?ws` : Show loaded wavetables.
   * `?S` : Show active array stream contents.
   * `S-1` : Emergency panic button (stops all 256 voices).

---

## 5. Skode Language & Built-in Drums Reference

### Built-in One-Shot Drum Samples (Slots 82–99)
Skred contains high-fidelity 44.1 kHz one-shot drum models generated at startup from embedded K-synth scripts. **They are designed to play at standard pitch `f440` (or `n69`) with loop disabled (`B0`):**

| Slot | Instrument | Typical Usage & Tuning |
|---|---|---|
| **`w82`** | Kick | Solid 300 ms electro kick. `v0 w82 f440 a3 B0 l1` |
| **`w83`** | Snare | Crisp 280 ms backbeat snare. `v1 w83 f440 a0 B0 l1` |
| **`w84`** | Closed Hat (CHH) | Tight 200 ms metallic tick. `v1 w84 f440 a-3 B0 l1` |
| **`w85`** | Open Hat (OHH) | 750 ms sizzling open hat. `v1 w85 f440 a-3 B0 l1` |
| **`w86`** | Hand Clap | Multi-clap burst with room tail. `v2 w86 f440 a-1 B0 l1` |
| **`w87`** | Rimshot | 60 ms high-tension rim click. `v2 w87 f440 a0 B0 l1` |
| **`w88`–`w90`** | Toms | Low (`w88`), Mid (`w89`), and High (`w90`) tuned toms. |
| **`w94`** | Crash Cymbal | 1500 ms wide stereo splash crash. |
| **`w95`** | Ride Cymbal | 1200 ms metallic ping with long decay. |
| **`w96`** | 808 Cowbell | Iconic dual-tone cowbell (900 ms). `v5 w96 f440 a-2 B0 l1` |
| **`w97`** | Clave | High-pitched wooden clave block (100 ms). |
| **`w98`** | Maracas | Short high-frequency shaker stroke (80 ms). |

### Core Skode Syntax Atoms
* `v<0..15>` : Select active voice.
* `w<id>` : Select wavetable (`0`=sine, `1`=saw, `15`=DWGS synth, `82..99`=drums).
* `f<hz>` : Set frequency in Hertz (e.g. `f440`, `f65`).
* `n<midi>` : Set pitch by MIDI note number (e.g. `n60`=C4, `n69`=A4).
* `a<db>` : Set amplitude in decibels (e.g. `a0`=0 dB unity, `a-6`=-6 dB, `a3`=+3 dB).
* `p<pan>` : Set stereo pan from `-1.0` (hard left) to `+1.0` (hard right).
* `t<a,d,s,r>` : Configure ADSR envelope (e.g. `t0,0.22,0,0` for a short percussive decay).
* `B0` / `B1` : Disable / enable wavetable looping. *(Keep `B0` for one-shot drums!).*
* `l1` / `l0` : Gate voice ON (velocity 1.0) / Gate voice OFF.
* `( 60 63 67 ) /SS 0` : Create an array stream in slot 0.
* `n&0` : Pop the next MIDI note from stream 0 and assign it to pitch.
* `+<beats>` : Tempo-relative deferral.
* `;` : Chunk separator (resets defer accumulator).

---

## 6. Tour of the Gleam & Lustre Codebase

The project follows the standard **Lustre MVU (Model-View-Update)** architecture:

```
                    ┌─────────────────────────┐
                    │       Skred WASM        │
                    │   (Audio Thread + C)    │
                    └───────────▲─────────────┘
                                │ FFI (Effects & Polling)
                    ┌───────────▼─────────────┐
                    │      skred_ffi.mjs      │
                    │ (JS Web Audio + Events) │
                    └───────────▲─────────────┘
                                │ Effect(Msg)
  ┌─────────────────────────────┼─────────────────────────────┐
  │ Lustre Application Loop     │                             │
  │                             ▼                             │
  │                     ┌───────────────┐                     │
  │         ┌──────────►│  live_skred   │◄──────────┐         │
  │         │           │   (Update)    │           │         │
  │         │           └───────┬───────┘           │         │
  │   User Interactions         │ State (Model)   Effects     │
  │   (Clicks, Typing)          ▼                 (Ticks,     │
  │         │           ┌───────────────┐         Audio Init) │
  │         └───────────┤  views/editor │           │         │
  │                     │ views/constell│───────────┘         │
  │                     └───────────────┘                     │
  └───────────────────────────────────────────────────────────┘
```

### Module Guide
* [src/live_skred/types.gleam](file:///home/stewartj/book/live-skred/src/live_skred/types.gleam):
  Contains all types: `Model`, `Msg`, `CodeBlock`, `VoiceNode`, `QuantizedClock`, `ReplState`, and `SkredEvent`. Whenever you want to add a new user action or piece of state, start here!
* [src/live_skred.gleam](file:///home/stewartj/book/live-skred/src/live_skred.gleam):
  The top-level program.
  * `init()`: Sets up the initial model (paused clock, starter preset, silence).
  * `update()`: Handles all incoming messages (`ClockTick`, `EvalBlockImmediate`, `EvalBlockQuantized`, `SubmitReplCommand`, etc.).
  * `view()`: Arranges the layout into transport bar, code blocks, orbital constellation, and REPL bar.
* [src/live_skred/clock.gleam](file:///home/stewartj/book/live-skred/src/live_skred/clock.gleam):
  Pure mathematical helpers converting BPM to tick intervals in milliseconds (`tick_interval_ms`).
* [src/live_skred/skode.gleam](file:///home/stewartj/book/live-skred/src/live_skred/skode.gleam):
  The typed ANDS / Skode AST and recursive-descent parser. Handles array streams (`/SS`), deferrals (`+` and `~`), and validates your code as you type with instant visual error reporting.
* [src/live_skred/presets.gleam](file:///home/stewartj/book/live-skred/src/live_skred/presets.gleam):
  The curated bank of starter blocks (Minimal Techno Groove, Ambient Clouds).
* [src/live_skred/views/editor.gleam](file:///home/stewartj/book/live-skred/src/live_skred/views/editor.gleam):
  Renders the transport bar with beat LEDs, the code block cards with AST indicators, the REPL console, and the new **Skode Syntax & Help Modal**.
* [src/live_skred/views/constellation.gleam](file:///home/stewartj/book/live-skred/src/live_skred/views/constellation.gleam):
  Renders the 16 orbital voice nodes as clickable SVG circles, animated in real time by 60 Hz control plane events.
* [src/skred_ffi.mjs](file:///home/stewartj/book/live-skred/src/skred_ffi.mjs):
  The bridge between Lustre and Emscripten WebAssembly. Starts the audio context on user interaction, polls the control plane event queue, flushes stdout/TTY, and executes commands.

---

## 7. Hacker Recipes: What You Can Build During the Token Reset

Here are 4 concrete, rewarding experiments you can try out on your own while waiting for your token reset:

### Recipe 1: Add a New Drum Pattern Preset
Open [src/live_skred/presets.gleam](file:///home/stewartj/book/live-skred/src/live_skred/presets.gleam) and add an 80s Electro-Funk groove using cowbell (`w96`) and handclap (`w86`):
```gleam
pub fn electro_funk_set() -> PresetSet {
  PresetSet(
    name: "80s Electro Funk",
    description: "Syncopated beat with 808 cowbells and snappy claps",
    blocks: [
      CodeBlock(
        id: 0,
        name: "01: Syncopated Kick (w82)",
        code: "v0 w82 f440 a3 B0 l1 ; +0.75 v0 l1 ; +1.5 v0 l1 ; +2.5 v0 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 1,
        name: "02: Snare & Clap Layer (w83 + w86)",
        code: "v1 w83 f440 a0 B0 ; v2 w86 f440 a-1 B0 ;\n+1.0 v1 l1 v2 l1 ; +3.0 v1 l1 v2 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
      CodeBlock(
        id: 2,
        name: "03: Cowbell Melody (w96)",
        code: "v5 w96 B0 a-2 f440 l1 ; +0.5 v5 f520 l1 ; +1.25 v5 f440 l1 ; +2.0 v5 f660 l1",
        status: Ready,
        active_pulse: False,
        last_error: None,
      ),
    ],
  )
}
```
Add `electro_funk_set()` to `all_presets()` at line 125, run `make check`, and it will immediately show up in the top preset dropdown!

### Recipe 2: Experiment with Generative Streams
In any block, load a pentatonic scale into Stream 0 and random delay times into variable `$0`:
```
( 48 51 53 55 58 60 63 65 ) /SS 0 ;
0.25 0 = ;
v3 w15 a-2 f1200 q2.5 t0,0.18,0,0 B0 n&0 l1 ;
+$0 v3 n&0 l1 ;
+$0 v3 n&0 l1 ;
+$0 v3 n&0 l1
```
Hit **Shift+Enter** to hear it, or **🔁 Loop ~16** to let it cycle infinitely.

### Recipe 3: Add a Custom Sound Design Macro
Open the REPL input at the bottom and define a custom macro called `acid` that configures a screaming 303 voice:
```
[acid] : v3 w15 a-2 f1400 q4.0 t0,0.20,0,0 B0 ;
```
Now in any code block, you can just call `acid n48 l1 ; +0.5 acid n51 l1`!

### Recipe 4: Build & Test Workflow
Remember that your classic Makefile has everything you need:
* `make dev`: Starts Vite dev server with hot reload on port 3001.
* `make test`: Runs all Gleam unit tests.
* `make format`: Auto-formats all Gleam code cleanly.
* `make check`: Verifies types and formatting.
* `make build`: Produces the production bundle.

Have fun hacking on Live-Skred! You have a rock-solid foundation, sample-accurate audio, and full type safety.
