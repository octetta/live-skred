# A Note to the Gleam & Lustre Community

> **Live Demo**: [https://octetta.github.io/live-skred/](https://octetta.github.io/live-skred/)  
> **Repository**: [https://github.com/octetta/live-skred](https://github.com/octetta/live-skred)

---

Hey everyone in the Gleam and BEAM worlds!

First and foremost: **thank you so much** to all the Gleam and BEAM folks who showed up to my Code BEAM workshop. Your warmth, curiosity, and energy meant the world to me and left a deep impression. That workshop was the spark that pushed me over the edge—I knew I had to roll up my sleeves and build something real with Gleam and Lustre.

This project, **`live-skred`**, is the result of that excitement.

---

### The Major Caveats (Read Before Judging!)

1. **Nearly 100% Vibe-Coded as an Excuse to Learn**:  
   I am not yet a seasoned Gleam programmer—I am, at best, deeply aspirational. This codebase was built rapidly as a hands-on vehicle to understand how Gleam's algebraic types, strict immutability, decoder pipelines, and Lustre’s Elm-style Model-View-Update (MVU) loop actually feel in practice. If you spot patterns that make you wince or places where an experienced Gleam coder would have done something far more idiomatic, please be gentle—and please teach me!

2. **The Goal: A Tool the Community Can Be Proud Of**:  
   I don't want this to just be a throwaway toy. My dream is to collaborate with this community to shape `live-skred` into a genuinely cool, rock-solid live-coding instrument that the BEAM/Gleam/Lustre ecosystem loves, uses for algoraves, and isn't embarrassed by.

3. **Harnessing Skred's Superpowers**:  
   Under the hood, this project is powered by **Skred 0.80.0** compiled to WebAssembly. Skred is a lightweight, sample-accurate C synthesizer engine with:
   * 256 simultaneous voices.
   * Single-cycle wavetables (classic waveforms plus vintage Korg DW-8000 DWGS waves).
   * 18 built-in 44.1 kHz one-shot drum models (`w82`–`w99`) synthesized from embedded physical K-synth scripts.
   * Array stream evaluation (`/SS`) and microsecond-level event deferrals (`+` and `~`).
   * A 60 Hz lock-free binary control plane event queue that pushes voice lifecycle telemetry across FFI directly into our Lustre SVG visualizer.

4. **The Strudel Gap (What Skred is Still Missing)**:  
   While Skred has immense raw synthesis power and low latency, I am very conscious that it is still missing some of the higher-level musical abstractions that make systems like **Strudel** and **TidalCycles** so fluid and intuitive. Strudel treats time as a continuous cyclic canvas ($0 \dots 1$), allowing effortless Euclidean polyrhythms, cycle subdivisions, and seamless hot-swapping. Skred, by contrast, is rooted in Forth-style imperative state mutation and relative event deferrals. Bridging that conceptual gap in a functional, type-safe frontend like Lustre is the big creative challenge ahead.

---

### What's Inside the Codebase

Even though I'm an aspirational beginner, we strove to make the Gleam and Lustre architecture clean, readable, and structured:

* **[src/live_skred/types.gleam](src/live_skred/types.gleam)**: Full domain models for code blocks, orbital voice nodes, quantized clocks, and typed control plane events.
* **[src/live_skred.gleam](src/live_skred.gleam)**: The central Lustre application controller (`init`, `update`, `view`), handling bar-quantized block launches, state management, and effect dispatching.
* **[src/live_skred/skode.gleam](src/live_skred/skode.gleam)**: A handwritten typed AST and recursive-descent parser for the Skode/ANDS live coding language, validating user input live with immediate UI error diagnostics.
* **[src/live_skred/views/editor.gleam](src/live_skred/views/editor.gleam)**: Interactive live code block cards with keyboard evaluation shortcuts (`Shift+Enter` for eval, `Ctrl+Enter` for quantized loop), a real-time 4-beat LED transport counter, and a bottom terminal console.
* **[src/live_skred/views/constellation.gleam](src/live_skred/views/constellation.gleam)**: A reactive 16-voice orbital SVG visualizer driven by Skred's WASM telemetry; clicking any voice circle inspects that voice's live synthesis parameters.
* **[src/live_skred/clock.gleam](src/live_skred/clock.gleam)**: Quantized tempo math and leak-free JavaScript timer subscriptions.
* **[src/skred_ffi.mjs](src/skred_ffi.mjs)**: The JS FFI bridge interfacing Lustre Effects with Emscripten WebAssembly and Web Audio.

---

### How to Run & Hack Locally

You can spin up the project with Mise and Make in seconds:

```bash
# 1. Clone the repository
git clone https://github.com/octetta/live-skred.git
cd live-skred

# 2. Install pinned toolchains (Gleam 1.19.2 + Node 26.12.0)
mise install

# 3. Start development server with hot reload
make dev
```
Open [http://localhost:3001](http://localhost:3001) in your browser.

Unit tests and type-checks:
```bash
make test     # Runs Gleam test suite
make check    # Verifies types and code formatting
make build    # Compiles production bundle to dist/
```

---

### How You Can Help / Where I'd Love Input

1. **Gleam & Lustre Code Review**: Where can our Lustre message handling and effect dispatching be cleaner or more idiomatic?
2. **Time & Cycle Abstractions**: How can we design a typed Gleam DSL on top of Skred that provides Strudel-like cyclic pattern manipulation while compiling down to Skred's sample-accurate defers?
3. **Sound & Feature Ideas**: What live-coding features would make you want to use this in a performance?

Feel free to open an issue, submit a PR, or ping me on the Gleam Discord. Thank you for welcoming an aspiring Gleam hacker into your wonderful community!

— **Joe Stewart**
