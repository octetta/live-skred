# live-skred

[![Deploy to GitHub Pages](https://github.com/octetta/live-skred/actions/workflows/deploy.yml/badge.svg)](https://github.com/octetta/live-skred/actions/workflows/deploy.yml)
[![Live Demo](https://img.shields.io/badge/demo-octetta.github.io%2Flive--skred-blue)](https://octetta.github.io/live-skred/)
[![Gleam](https://img.shields.io/badge/gleam-1.19.2-ffaff3)](https://gleam.run)
[![Lustre](https://img.shields.io/badge/lustre-vdom-purple)](https://github.com/lustre-labs/lustre)
[![Skred](https://img.shields.io/badge/audio%20engine-skred%200.80.0%20WASM-orange)](https://github.com/octetta/pulp)

**live-skred** is a browser-based algorave live coding instrument combining **Skred 0.80.0** (a 256-voice sample-accurate C synthesis engine in WebAssembly), a typed **Skode AST & Parser**, and a reactive **Gleam + Lustre** web interface featuring an interactive SVG voice constellation and quantized tempo transport.

> 🌐 **Try it live in your browser**: [https://octetta.github.io/live-skred/](https://octetta.github.io/live-skred/)  
> 💌 **Read the Community Note**: [COMMUNITY_NOTE.md](COMMUNITY_NOTE.md)  
> 📖 **Field Guide & Mental Model**: [HELP_JOE_UNDERSTAND.md](HELP_JOE_UNDERSTAND.md)

---

## Features

* **Real-time Algorave Blocks**: Live code blocks with syntax checking, one-shot evaluation (`Shift+Enter`), and bar-quantized loop scheduling (`Ctrl+Enter` / `Loop ~16`).
* **Quantized Musical Clock**: Bar and beat LED transport counter locking rhythm tracks to musical downbeats without drift.
* **Built-in Physical Drum Models**: 18 one-shot drum wavetables (slots `w82`–`w99` at `f440`/`n69`) synthesized via K-synth scripts (Kick, Snare, Closed/Open Hats, Clap, Rimshot, Toms, Cymbals, Cowbell).
* **Array Streams & Deferrals**: Array streams (`/SS`) for generative arpeggios, plus sample-accurate beat-relative defers (`+0.25`, `+0.5`, `+1.0`).
* **Interactive Orbital Voice Constellation**: Real-time SVG orbital ring showing voice activity (0..15); click any voice circle to inspect its live parameters in the terminal.
* **Terminal REPL Console & Quick Diagnostics**: Built-in inspection toolbar (`??` Voices, `\` Details, `/s 2` Audio Driver, `?ws` Wavetables, `?S` Streams, `GS` Status, `S-1` Panic).
* **Pure Gleam & Lustre Architecture**: Clean Model-View-Update (MVU) state management with full type safety and zero client-side crashes.

---

## Quick Start

### Prerequisites
* [Mise](https://mise.jdx.dev/) (recommended) or Gleam 1.19.2+ & Node.js 22+.
* Modern web browser with WebAudio support.

### Local Development

```bash
# 1. Clone the repo
git clone https://github.com/octetta/live-skred.git
cd live-skred

# 2. Install pinned toolchains via Mise
mise install

# 3. Start local development server with hot reload
make dev
```
Open [http://localhost:3001](http://localhost:3001) in your browser.

### Building & Testing

```bash
make test     # Run Gleam unit tests (AST, clocks, presets)
make check    # Verify Gleam types and formatting
make format   # Auto-format Gleam codebase
make build    # Build production bundle to dist/
```

---

## Live Coding Quick Cheatsheet

```skode
# Four-on-the-floor electro kick using built-in wave 82
v0 w82 f440 a3 B0 l1 ; +1.0 v0 l1 ; +2.0 v0 l1 ; +3.0 v0 l1

# Offbeat closed hat using wave 84
v1 w84 f440 a-3 B0 ; +0.5 v1 l1 ; +1.5 v1 l1 ; +2.5 v1 l1 ; +3.5 v1 l1

# Snappy backbeat handclap using wave 86
v2 w86 f440 a-1 B0 ; +1.0 v2 l1 ; +3.0 v2 l1

# 303 acid bassline stepping through an array stream
( 36 39 43 46 48 ) /SS 0 ;
v3 w15 a-2 f800 q3.5 t0,0.22,0,0 B0 n&0 l1 ; +0.25 v3 n&0 l1 ; +0.5 v3 n&0 l1 ; +0.75 v3 n&0 l1
```

* **Shift+Enter**: Evaluate block once immediately.
* **Ctrl+Enter / Cmd+Enter**: Arm block for quantized 1-bar looping (`~16`).
* **Click Orbit Node**: Print voice parameters to terminal (`v<id> \`).

---

## License

MIT © Joe Stewart & Contributors. Built with Gleam, Lustre, and Skred.
