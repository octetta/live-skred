# The Acme / Oberon Live-Coding Workstation: A Manifesto & V2 Blueprint

> *"An operating system is a collection of things that don't fit into an editor."* — Rob Pike  
> *"Make it as simple as possible, but not simpler."* — Niklaus Wirth  

---

## 1. The Vision

The live coding world today is trapped between two flawed paradigms:
1. **The Bloated IDE / Canvas Hack**: Heavy Electron wrappers around VS Code or browser tabs with clumsy canvas animations pasted on top.
2. **The Widget-Heavy Web DAW**: A mess of sliders, cards, buttons, and form inputs that force performers to take their hands off the keyboard to tweak tiny UI knobs.

**Plan 9's Acme** and **Wirth's Oberon System** solved this thirty years ago with an insight that is even more radical today:

> **Text is not passive data to be edited. Text is the interface itself.**

In Acme and Oberon:
* There are no rigid button palettes or modal dialogs.
* Every window has an editable **Tag Bar** containing commands.
* **Any word on the screen can be executed.**
* Documents are organized in clean, non-overlapping **Tiling Columns** that maximize 100% of the display.

When you bring this philosophy to **Skred's C audio engine** using **Gleam and Lustre**, you don't just build another live-coding tool—you build a **distinctive, cult-favorite instrument** that challenges how humans interact with sound and code.

---

## 2. High-Density Screen Architecture (100% Viewport Utilization)

Instead of a scattered card grid, the workstation uses a clean, tiling columnar layout:

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ NewCol | Dump | Load | Tempo 120 | Quant 1bar | StopAll | Rec                                     LIVE │
├────────────────────────────────────────┬───────────────────────────────┬───────────────────────────────┤
│ [COLUMN 0: PATCHES & SYNTHESIS]        │ [COLUMN 1: THE LIVE SCORE]    │ [COLUMN 2: PLUMBER & MONITOR] │
│ /home/joe/set/synth.sk | Put | EvalAll │ /home/joe/set/score.sk | Put  │ Telemetry | Clear | Voices 6  │
├────────────────────────────────────────┼───────────────────────────────┼───────────────────────────────┤
│ ## 808 Kick Model (300ms)              │ ## Main Beat Sequence         │ [016.1] Hot-swapped :score.sk │
│ [                                      │ @track kick                   │ [016.1] Voice 0: Kick 808     │
│   N: 13230 T: !N                       │   808_bd a3.0                 │ [016.2] Voice 1: Hi-Hat 909   │
│   E: e(T*(0-6.9%N))                    │   ~16 1 T . . .  1 T . . .    │ [016.3] Voice 2: Hand Clap    │
│   W: w (E*S)+(Q*C*.1)                  │                               │                               │
│ ] k! k>d d>r /r 100                    │ @track bass                   │ MASTER STEREO VU              │
│                                        │   w20 a-2.0                   │ L: [■■■■■■■■■■■■□□□□] -3dB    │
│ ## Snare Synthesis                     │   ( 36 39 43 46 48 ) /SS 0    │ R: [■■■■■■■■■■■■□□□□] -3dB    │
│ [                                      │   ~16 1 ( $0 ? ) /S           │                               │
│   N: 12348 ...                         │                               │ ACTIVE VOICE POOL             │
│ ] k! k>d d>r /r 101                    │ @track hats                   │ v0: w100 808 Kick   -1dB █    │
│                                        │   w84 a-6.0                   │ v1: w84  909 Hat    -6dB ▄    │
│                                        │   ~16 . . 1 T .  . . 1 T .    │ v2: w86  Hand Clap  -4dB ▅    │
└────────────────────────────────────────┴───────────────────────────────┴───────────────────────────────┘
```

### The 4 Core Interaction Pillars:

1. **The Musical Tag Bar (Zero Modal Dialogs)**:
   Every window and column has an editable top text strip:
   ```text
   score.sk | Eval | Quant 1bar | Mute :hats | Solo :bass | Tempo 128 | Panic
   ```
   * You can click any command to run it.
   * You can type any command directly into the tag bar and execute it on the fly.
2. **Active Text ("The Whole Screen is an Instrument")**:
   In Oberon, any text formatted as a command can be executed.
   * If you see `w82` anywhere on your screen, **Alt+Click it** to audition that 808 kick immediately.
   * If you see `v0 \` or click a voice token, it opens the live inspector.
   * If you write `# Panic` or `# Mute`, clicking it executes the command.
3. **Tiling Columns (Zero Window Overlap)**:
   * **Column 0**: Synthesis & Patches (`synth.sk` — physical K-synth models, wavetable loading).
   * **Column 1**: The Live Score (`score.sk` — active rhythms, basslines, melodic streams).
   * **Column 2**: Plumber & Telemetry (`monitor.sk` — live voice VU meters, diagnostic AST cards, compiler feedback).
4. **The Plumber (Telemetry as Text Streams)**:
   * Skred's 60 Hz binary telemetry ringbuffer flows into a live monitor column.
   * Voice lifecycle events and compiler errors are streamed as clean, clickable text.
   * Clicking an error line in the log immediately jumps the editor cursor to that exact line in the code column.

---

## 3. Keyboard-First Performance Controls

| Shortcut | Action | Behavior |
| :--- | :--- | :--- |
| **`Ctrl+Enter`** / **`Cmd+Enter`** | **Quantized Hot-Swap** | Arms the block under the cursor; swaps smoothly on the next bar downbeat. |
| **`Shift+Enter`** | **Instant Audition** | Immediately sends the current line or selection to Skred (ideal for adjusting synth timbre, filters, or testing a sample). |
| **`Ctrl+Alt+Enter`** | **Global Swap** | Evaluates the entire buffer and updates all tracks on the next downbeat. |
| **`Ctrl+.`** or **`Escape`** | **Panic** | Instantly stops all sound (`*l0`). |
| **`Ctrl+/`** | **Mute / Unmute** | Comments out the track pattern (`//`), cleanly resting that voice sequence without stopping other tracks. |
| **`Alt+Up` / `Alt+Down`** | **Jump Block** | Jumps cursor directly between `##` block headers. |
| **`F1`** | **Toggle Reference** | Expands or collapses the quick command / wavetable cheat sheet drawer. |

---

## 4. Why This Attracts Backers (Patreon / GitHub Sponsors / itch.io)

People do not sponsor generic web utilities. People sponsor **visionary tools that have a soul**, crafted by passionate creators who honor computing history while pushing creative tools forward.

### The Pitch to the World:
> *"What if Plan 9's Acme and Niklaus Wirth's Oberon were reborn in Gleam and WebAssembly to create the most responsive, tactile live-coding instrument on earth?"*

### Who Will Support This:
1. **The BEAM & Gleam Communities**:
   * Gleam is hungry for flagship, production-grade showcase apps that demonstrate the power of Lustre and Gleam's type system in high-performance domains like real-time audio.
2. **The Algorave & Live Coding Scene**:
   * Performers are always looking for tools that look stunning on stage projectors and allow blazing-fast, glitch-free improvisation without fiddling with mouse menus.
3. **The Systems & Retro-Computing Culture**:
   * Fans of Plan 9, Oberon, Forth, Smalltalk, and minimal computing love seeing these timeless ideas proven superior to modern bloated frameworks.

---

## 5. Architectural Alignment with Skred

Every piece of this vision maps directly to what Skred already does:

| Acme / Oberon Concept | Implementation in Gleam & Skred |
| :--- | :--- |
| **Contiguous Document** | Single `.sk` text buffer partitioned by `##` blocks. |
| **Tag Bar Commands** | Lustre header running Skred primitives (`M 120`, `x 0`, `*l0`). |
| **Active Text Audition** | Clickable tokens routed to Skred FFI (`skred_command("w82 a0 T")`). |
| **Plumber Telemetry** | 60 Hz lock-free ringbuffer decoded into typed Lustre events. |
| **Sample Accuracy** | Skred C engine handles micro-timing; Gleam coordinates the score. |

---

## 6. Implementation Roadmap (For When Tokens Reset)

- [ ] **Step 1**: Replace the multi-card grid with a unified document editor buffer supporting `##` block dividers.
- [ ] **Step 2**: Implement the Acme-style Tag Bar at the top of the editor with clickable/editable commands (`Eval`, `Tempo`, `StopAll`).
- [ ] **Step 3**: Route `Ctrl+Enter` to extract the active `##` block and dispatch it to Skred WASM on downbeat quantization.
- [ ] **Step 4**: Implement active text tokens (e.g. `Alt+Click` on `w82` auditions the drum).
- [ ] **Step 5**: Dock the Plumber / Monitor column on the right side for voice telemetry and responsive stereo VU meters.
