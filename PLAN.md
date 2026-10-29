# Live-Skred: Live Coding & Reactive Audio Showcase with Lustre & Skred

A blueprint and architecture plan for **`live-skred`**, an interactive, browser-based live coding audio instrument built with **Gleam**, **Lustre**, and the **Skred 0.80.0** WebAssembly sound synthesis engine.

---

## 1. Vision & Philosophy

### 1.1 What is Live Coding in Music?
Live coding (often associated with the *Algorave* movement) treats code not as a static script compiled before execution, but as a live, expressive musical instrument. Performers write, modify, and evaluate code in real-time in front of an audience, projecting the code onto screens so listeners can see the music take form.

Two widely recognized pioneers in this field are:
* **TidalCycles** (Haskell) & **Strudel** (JavaScript/Web): They model music as infinite cyclical patterns using a concise "mini-notation" (e.g. `s("bd [sn:2 bd] ~ cp")`), mapping cycles into musical time.
* **Sonic Pi** (Ruby) & **SuperCollider** (SCLang): They model music as threads/routines and synth definitions with sleep/wait commands, allowing musicians to loop blocks of code and swap parameters live.

### 1.2 The Skred & Skode Difference
Skred brings something distinct and powerful to live coding:
1. **Concatenative / Stack / Sigil Architecture (Skode / ANDS)**:
   Instead of verbose syntax or nested function calls, Skode uses high-density atomic commands:
   * Direct voice manipulation: `v0 n60 l1` (Voice 0, MIDI note 60, gate open).
   * Time deferrals: `+0.25 v0 l0` (after 0.25 seconds, close gate) or `~1` (after 1 tempo tick).
   * Stream generators: `(60 63 67 70) /SS 0 ; (&0) vt` (populate stream `0` with a chord using `/SS 0` and step through it with `&0`).
   * Dynamic variables: `42 0 =` and `+$0 v0 l1` (schedule using variable `$0`).
   * Low-level physical synthesis: K-Synth waveguide algorithms, sample playback, stereo panning, ADSR envelopes, filters, and master effects.
2. **Bidirectional Control Plane**:
   Unlike one-way audio synthesis engines where the UI is blind to what the DSP engine is doing, Skred streams control plane events (`EVENT_GATE_ON`, `EVENT_GATE_OFF`, `EVENT_VOICE_ALLOC`, `EVENT_PEAK`) back to JavaScript/WASM at native frame rates.
3. **The Gleam & Lustre Advantage**:
   * **Typed AST & Real-Time Linting**: We have a full Skode parser and AST in Gleam. As the performer types, the AST is validated before touching the audio thread—eliminating runtime audio dropouts or engine panics.
   * **Pure Declarative UI (Lustre)**: Lustre's Model-View-Update (Elm architecture) provides deterministic, state-synchronized reactive visuals.
   * **Zero Heavy 3D Bloat**: Everything can be rendered crisply using hardware-accelerated SVG and CSS transforms directly driven by Lustre's virtual DOM.

---

## 2. The Performer's Experience (UX Design)

```
+---------------------------------------------------------------------------------------------------+
|  [live-skred]   BPM: [ 120 ]  QUANTUM: [ 1 Bar (4 Ticks) ]   CPU: [ OK ]    [ STOP / PANIC (Esc) ]  |
+----------------------------------------------------+----------------------------------------------+
|  CODE SPACE (Interactive Live Blocks & REPL)       |  VISUAL REACTOR (Lustre Reactive SVG)        |
|                                                    |                                              |
|  # [01: Kick & Snare]   [ ACTIVE / LOOPING ~4 ]    |       (15)  (0)   (1)                        |
|  v0 a0 B1 [waves/kick.wav] /w ;                    |    (14)             (2)   VOICE CONSTELLATION|
|  v1 a-3 B1 [waves/snare.wav] /w ;                  |  (13)     [ V0 ]      (3)  * Active nodes    |
|  v0 l1; +0.5 v1 l1; +0.5 v0 l1; +0.5 v1 l1         |  (12)    PULSING      (4)    glow & expand   |
|                                                    |    (11)             (5)    * Pitch = Radius  |
|  # [02: Acid Bassline]   [ ACTIVE / LOOPING ~1 ]   |       (10)  (7)   (6)      * Pan = Angle     |
|  ( 36 39 41 43 46 ) /SS 0 ;                        |                                              |
|  v2 n&0 l1 a-6 +0.25 l0                            |  STREAM & VARIABLE GAUGES                    |
|                                                    |  $0: [ 42.0 ]   &0: [ . * . . . ] (39)       |
|  # [03: Synth Arp]       [ MUTED ]                 |  $1: [  0.25]   &1: [ * . . . ]   (60)       |
|  v4 n60 l1; +0.125 n64; +0.125 n67; +0.125 n72     |                                              |
|                                                    |  TRIGGER SPECTRUM / PHASE TAPE               |
|  ------------------------------------------------  |  [||||||||||||||||||............] -6 dB Peak |
|  skred> v2 f800 q2                                 |  Log: Voice 0 Gate On, Voice 2 Gate On       |
+----------------------------------------------------+----------------------------------------------+
```

### 2.1 The Code Space
* **Multi-Block Code Notebook**:
  * Code is organized into labeled blocks delimited by `# [name]` or blank lines.
  * Each block has its own execution and loop state (`Looping`, `One-Shot`, `Muted`, `Error`).
* **Evaluation Keybindings (Familiar to Live Coders)**:
  * `Ctrl+Enter` / `Cmd+Enter`: **Quantized Eval**. Evaluates the current block and aligns its loop to the next beat/bar (`~1` or `~4`).
  * `Shift+Enter`: **Immediate Eval**. Fires the current block immediately (great for drop-ins or rhythm breaks).
  * `Alt+Enter`: **One-Shot Trigger**. Runs the block once without scheduling a recurring loop.
  * `Ctrl+M`: **Mute/Unmute** current block.
  * `Esc` / `Ctrl+.`: **Global Panic**. Sends `S-1` (resets all voices immediately).
* **Inline AST Linter**:
  * As code is edited, the Gleam AST parser validates the syntax.
  * Valid tokens are color-coded (Atoms, Numbers, Deferrals, Streams, Arrays, Macros).
  * If an invalid character or unterminated array/bracket is typed, a small unobtrusive inline hint appears (`Line 2 Col 14: Expected number after '+'`) without halting audio playback.
* **Ad-hoc Scratch REPL**:
  * An always-accessible single-line input (`skred>`) at the bottom with command history (Up/Down arrow).
  * Ideal for rapid tweaks: changing a filter frequency (`v2 f1200`), checking status (`?v`), or bumping tempo.

### 2.2 The Visual Reactor (Realized with Lustre)
* **Orbital Voice Constellation (Lustre SVG)**:
  * 16 (or 32) voice nodes arranged in an orbital ring.
  * When a voice triggers (`EVENT_GATE_ON`), the node pulses in size, brightness, and ring radius.
  * Node color indicates voice type/register:
    * Bass/Kick (Voices 0–3): Warm Amber / Crimson (`#ff5722`)
    * Snare/Percussion (Voices 4–7): Neon Cyan (`#00e5ff`)
    * Leads/Synths (Voices 8–11): Electric Purple (`#d500f9`)
    * Poly/Aux (Voices 12–15): Emerald Green (`#00e676`)
  * Node position or trail modulates slightly based on pan and pitch.
* **Reactive Stream & Variable Gauges**:
  * Visual horizontal indicator showing the state of streams `&0..&7` and variables `$0..$9`.
  * When `(&0) vt` steps through an array, the active index in the array lights up in real-time.
* **Block Code Trigger Pulse**:
  * When Voice 2 fires from Block `# [02: Acid Bassline]`, the header and left border of that specific code block pulse with light, creating an immediate mental link between the code on screen and the sound in the room.
* **Master Telemetry HUD**:
  * Tempo indicator with a pulsing metronome orb.
  * Real-time master output dB meter.
  * Active voice counter (e.g. `4 / 16 active`).

---

## 3. Technical Architecture & Component Breakdown

```
+-----------------------------------------------------------------------------------------+
|                                    Browser Window                                       |
|                                                                                         |
|  +-----------------------------------------------------------------------------------+  |
|  |                            Lustre Web App (Gleam)                                 |  |
|  |                                                                                   |  |
|  |   [ Model ]                                                                       |  |
|  |   * blocks: Dict(Int, CodeBlock)       * control_plane: VoiceTelemetry            |  |
|  |   * repl: ReplState                    * clock: QuantizedClock                    |  |
|  |   * streams: Dict(Int, List(Float))    * presets: List(PerformancePreset)         |  |
|  |                                                                                   |  |
|  |   [ Update ]                                                                      |  |
|  |   * Msg: UserKeyCombo | CodeChanged | EvalBlock | ControlEventPoll | Tick           |  |
|  |                                                                                   |  |
|  |   [ View (Lustre Virtual DOM & SVG) ]                                             |  |
|  |   * Code Space: Block Editor, REPL buffer, AST error tooltips                     |  |
|  |   * Visual Reactor: SVG Voice Constellation, Stream Step Matrix, Output Meter     |  |
|  +-----------------------------------------+-----------------------------------------+  |
|                                            |                                            |
|                       Gleam AST Parser     | JS FFI & Event Pump                        |
|                                            v                                            |
|  +-----------------------------------------------------------------------------------+  |
|  |                     skred_ffi.mjs & Skred 0.80.0 WASM Binary                      |  |
|  |                                                                                   |  |
|  |   * skred_command()   <--- AST Serialized Strings / Raw Chunks                    |  |
|  |   * _skred_control_event_poll() ---> 72-byte structs polled at 60Hz              |  |
|  |   * SharedArrayBuffer / AudioWorklet DSP Core (Voices, K-Synth, Samples)          |  |
|  +-----------------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------------+
```

### 3.1 Gleam Modules & Sharing
We can reuse and expand the battle-tested modules from `rototem-web`:
1. **`skode.gleam`** (AST & Parser):
   * Parsing Skode tokens, atoms, multi-args, parenthesized arrays, and deferrals (`+$0`, `~&1`).
   * AST transformations, note-to-frequency conversions (`n>f`), and syntax validation.
2. **`skred.gleam`** (Engine Commands & Events):
   * Voice formatting, master controls, device selection, event type decoders.
3. **`clock.gleam`** (New - Quantized Timing Engine):
   * Handles musical tempo, bar/beat quantizing, and looping evaluation ticks.
4. **`views/constellation.gleam`** (New - Lustre Reactive SVG):
   * Pure Lustre SVG components rendering orbital nodes, trigger rings, and stream vectors.
5. **`views/editor.gleam`** (New - Block Code Editor):
   * Block-based textareas with line numbers, AST status indicators, and keyboard handlers.
6. **`presets.gleam`** (New - Curated Algorave Starters):
   * Ready-to-jam sets of blocks demonstrating techno, ambient, acid, and generative physical modeling.

---

## 4. Curated Jam Starters (Onboarding for Newcomers)

To make `live-skred` immediately playable without needing prior experience in TidalCycles or Strudel, the app will include built-in one-click live sets:

### Set 1: "The 4/4 Minimal Techno Groove"
```skode
# [01: Kick & Sub]
v0 a0 [waves/kick.wav] /w ;
v0 l1 ; +0.5 v0 l1 ; +0.5 v0 l1 ; +0.5 v0 l1

# [02: Offbeat Open Hat]
v1 a-4 [waves/hat.wav] /w ;
+0.25 v1 l1 ; +0.5 v1 l1 ; +0.5 v1 l1 ; +0.5 v1 l1

# [03: Acid 303 Lead]
( 36 39 43 46 48 ) /SS 0 ;
v2 f700 q3.5 B1 ;
v2 n&0 l1 a-3 +0.25 l0
```

### Set 2: "Generative K-Synth Ambient Clouds"
```skode
# [01: Drone Root]
v4 p-0.5 a-6 n48 t1 2 2 4 l1

# [02: Physical Plucks with Variable Deferral]
0.125 0 = ; # $0 = 1/8 note delay
( 60 62 65 67 72 74 ) /SS 1 ;
v5 p0.5 a-4 n&1 l1 ; +$0 v6 n&1 l1 ; +$0 v7 n&1 l1
```

---

## 5. Implementation Roadmap

### Phase 1: Workspace Scaffolding & WASM Engine Setup
* [ ] Initialize project `~/book/live-skred` with `gleam.toml`, `package.json`, and Vite setup.
* [ ] Vendor `skred_api.js` and `skred_api.wasm` (0.80.0) from Pulp release.
* [ ] Import/integrate `skode.gleam` (AST & parser) and `skred.gleam` (FFI bridge).
* [ ] Implement basic HTML shell with COOP/COEP headers for AudioWorklet and SharedArrayBuffer.

### Phase 2: The Core Live Block Editor & Quantized Looper
* [ ] Build block editor model in Lustre (parsing text blocks by `# [name]` comments).
* [ ] Implement keybindings (`Ctrl+Enter` to eval/loop block, `Shift+Enter` for immediate eval).
* [ ] Connect AST parser to provide live syntax validation and error badges per block.
* [ ] Implement the `clock.gleam` quantized scheduler (ticks/bars for synchronized block re-evaluation).

### Phase 3: Lustre Reactive SVG Visuals (The Reactor)
* [ ] Build the 16-voice Orbital Constellation in SVG (`views/constellation.gleam`).
* [ ] Connect the control plane event pump (`_skred_control_event_poll`) to Lustre messages.
* [ ] Animate node scaling, color transitions, and decay on `EVENT_GATE_ON`/`EVENT_GATE_OFF`.
* [ ] Implement active stream step matrix (`&0..&7`) and variable table HUD (`$0..$9`).
* [ ] Add block pulse highlight when corresponding voices fire.

### Phase 4: Scratch REPL, Telemetry, & Preset Library
* [ ] Add the single-line REPL bar with command history and Skred query output (`?v`, `?a`).
* [ ] Build master volume meter and BPM control slider with tap-tempo.
* [ ] Add preset loader with curated Algorave jams (Techno, Ambient, Acid, Physical Modeling).
* [ ] Add global Panic button (`Esc` / `S-1`).

### Phase 5: Polish & Documentation
* [ ] Verify audio stability across loop changes and rapid typing.
* [ ] Create user guide / cheat sheet explaining Skode live coding idioms.
* [ ] Write automated Gleam tests for clock and block parsing.

---

## 6. Next Steps & Execution

Would you like to proceed with **Phase 1** (scaffolding `~/book/live-skred`, setting up Gleam + Lustre + Vite, vendoring the 0.80.0 WASM engine, and porting the AST/FFI modules)? We can inspect each milestone step-by-step.
