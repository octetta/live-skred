# Vile + Skred Live-Coding Integration

> **The Hacker's Tiling Workstation**: Live-code against a headless Skred audio daemon via UDP using the classic `vile` (VI Like Emacs) text editor.

---

## 1. Architectural Overview

```
 ┌───────────────────────────────────────────────────────────────┐
 │                   VILE TEXT EDITOR                            │
 │  ┌─────────────────────────────────────────────────────────┐  │
 │  │ Window 1: synth.sk (Physical K-synth drum models)       │  │
 │  ├─────────────────────────────────────────────────────────┤  │
 │  │ Window 2: score.sk (Live sequences, streams, tempo)     │  │
 │  └─────────────────────────────────────────────────────────┘  │
 │          │                                                    │
 │          ▼ (.,.w !skred-send OR VileSkred.pm)                 │
 └──────────┼────────────────────────────────────────────────────┘
            │
            │ UDP Datagrams (localhost:60440)
            ▼
 ┌───────────────────────────────────────────────────────────────┐
 │                   MINI-SKRED DAEMON                           │
 │  • Headless C synthesizer running sample-accurate audio thread│
 │  • 256 physical voices, wavetables, array streams             │
 │  • Evaluates ANDS / Skode commands atomically with zero jitter│
 └───────────────────────────────────────────────────────────────┘
```

This integration brings the **Acme / Oberon philosophy** directly to terminal hackers:
1. **Zero UI Bloat**: No electron, no web browser, no canvas slowdowns.
2. **Multi-Window Tiling**: Use vile's built-in window splitting (`^T`) to view synthesis patches and performance sequences side-by-side in the same terminal.
3. **Sample-Accurate Execution**: All audio computation happens inside Skred's native C audio loop. Your editor simply fires lightweight UDP datagrams to update state on the fly.

---

## 2. Directory Contents

* **`skred-send`**: Standalone Perl CLI script that reads Skode code from STDIN or arguments and pushes a UDP datagram to Skred (`localhost:60440`).
* **`skred-daemon`**: Bash launcher that starts `mini-skred` in headless daemon mode (`-n -p60440 -v32`).
* **`skred.rc`**: Vile macro and configuration file defining stored procedures and keybindings.
* **`VileSkred.pm`**: Native Perl module for `vile` builds compiled with embedded Perl (`--with-perl`).

---

## 3. Installation & Setup

### 1. Install the scripts to your PATH
```bash
cp skred-send skred-daemon ~/bin/
chmod +x ~/bin/skred-send ~/bin/skred-daemon
```

### 2. Configure Vile
Copy `skred.rc` and `VileSkred.pm` to your `~/.vile` folder:
```bash
mkdir -p ~/.vile
cp skred.rc VileSkred.pm ~/.vile/
```

Add this line to your `~/.vilerc`:
```vile
source ~/.vile/skred.rc
```

---

## 4. Usage

### 1. Start the Skred Daemon
In any terminal or tmux pane:
```bash
skred-daemon &
```

### 2. Open your performance score in Vile
```bash
vile demo.sk
```

### 3. Performance Shortcuts in Vile

| Keystroke | Mode | Action |
| :--- | :--- | :--- |
| **`\e`** or **`^X-e`** | Normal | **Eval Line**: Sends the current line to Skred via UDP. |
| **`\s`** or **`^X-a`** | Normal | **Eval File**: Sends the entire buffer to Skred. |
| **`\p`** or **`^X-p`** | Normal | **Panic**: Immediately stops all audio voices (`*l0`). |
| **`:'<,'>w !skred-send`** | Visual | **Eval Selection**: Evaluates highlighted block of code. |

---

## 5. Multi-Window Live Jamming (Acme Style)

Vile allows multiple viewports into the same or different files:
* **`^T`** : Split window horizontally (`split-current-window`).
* **`^N`** : Jump to next window (`next-window`).
* **`^P`** : Jump to previous window (`previous-window`).

Keep your drum sound design at the top of your screen and your live acid pattern at the bottom. Tweak partials and decay in the top view, jump down, and trigger new note streams—all from pure muscle memory in Vile.
