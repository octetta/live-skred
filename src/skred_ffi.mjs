// JavaScript FFI Bridge for live-skred
// Integrates Skred 0.80.0 WASM audio engine, control plane event pump, and Web Audio APIs

const win = typeof window !== "undefined" ? window : globalThis;

let moduleReady = false;
let engineStarted = false;
let commandQueue = [];
let audioContext = null;
let capturedStdout = [];

// Control Plane Event Subscriptions
let currentEventSubscription = null;
let eventPumpStarted = false;
let wasmEventsBuffer = null;
const EVENT_SIZE = 72; // sizeof(skred_control_event_t)
const MAX_EVENTS_BATCH = 64;

// ---------------------------------------------------------------------------
// 1. Skred WASM Engine Initialization & Stdout Hooking
// ---------------------------------------------------------------------------

function setupStdoutHook(M) {
  if (!M) return;
  const originalPrint = M.print || console.log;
  const originalPrintErr = M.printErr || console.error;

  M.print = function (...args) {
    const line = args.join(" ");
    capturedStdout.push(line);
    if (win.__skredStdout && !win.__skredStdout.includes(line)) {
      win.__skredStdout.push(line);
    }
    originalPrint.apply(console, args);
  };

  M.printErr = function (...args) {
    const line = args.join(" ");
    capturedStdout.push("[ERR] " + line);
    if (win.__skredStdout) {
      win.__skredStdout.push("[ERR] " + line);
    }
    originalPrintErr.apply(console, args);
  };
}

function getWasmModule() {
  if (win.Module && typeof win.Module.ccall === "function") {
    return win.Module;
  }
  return null;
}

export function initEngine(callback) {
  if (moduleReady && engineStarted) {
    if (callback) callback(true);
    return;
  }

  // Pre-configure Emscripten Module
  win.Module = win.Module || {};
  win.Module.locateFile = function (path) {
    if (typeof window !== "undefined") {
      return new URL("vendor/skred/" + path, window.location.href).href;
    }
    return "/vendor/skred/" + path;
  };

  // Setup stdout capture early
  setupStdoutHook(win.Module);

  const prevInit = win.Module.onRuntimeInitialized;
  win.Module.onRuntimeInitialized = function () {
    if (prevInit) prevInit();
    console.log("[live-skred] Skred WASM runtime initialized.");
    moduleReady = true;

    try {
      setupStdoutHook(win.Module);

      if (win.Module.FS) {
        try { win.Module.FS.mkdir("/waves"); } catch (e) {}
        try { win.Module.FS.mkdir("waves"); } catch (e) {}
      }

      // Enumerate playback devices and select default output (0); disable capture/input (-2)
      if (typeof win.Module._skred_enumerate_devices === "function") {
        win.Module._skred_enumerate_devices(0);
      }
      if (typeof win.Module._skred_audio_select === "function") {
        win.Module._skred_audio_select(0, 0);
        win.Module._skred_audio_select(1, -2);
      }

      // Start engine with 128 buffer size, 256 voices, default port (-1)
      if (typeof win.Module._skred_start === "function") {
        const res = win.Module._skred_start(128, 256, -1);
        console.log("[live-skred] _skred_start returned:", res);
        engineStarted = (res === 0);
      }

      // Enable logger for status command retrieval
      if (typeof win.Module._skred_logger === "function") {
        win.Module._skred_logger(1);
      }

      // 1. Clear/reset all voices using S-1
      executeSkredCommand("S-1");

      // 2. Set master volume: V0 (0 dB unity)
      executeSkredCommand("V0");

      // 3. Initialize voices 0..15 cleanly (no infinite wave loop B0, percussive decay envelope)
      // Voice 0 = Kick (w82), Voice 1 = Hat (w84), Voice 2 = Clap (w86)
      executeSkredCommand("v0 p-0.5 w82 f440 a3 B0");
      executeSkredCommand("v1 p0.5 w84 f440 a-3 B0");
      executeSkredCommand("v2 p0.0 w86 f440 a-1 B0");
      for (let i = 3; i < 16; i++) {
        const pan = (i % 2 === 0) ? -0.7 : 0.7;
        executeSkredCommand(`v${i} p${pan} n60 B0 t0,0.3,0,0 a-3`);
      }

      // Ensure all voices are silenced on startup
      executeSkredCommand("S-1");

      // 4. Enable voice lifecycle events on voices 0..15 (for real-time feedback)
      if (typeof win.Module._voice_control_events_set === "function") {
        for (let i = 0; i < 16; i++) {
          win.Module._voice_control_events_set(i, 1);
        }
      }
      for (let i = 0; i < 16; i++) {
        executeSkredCommand(`v${i} vc1`);
      }

      startWasmEventPump(win.Module);
      flushCommandQueue();

      if (callback) callback(engineStarted);
    } catch (err) {
      console.error("[live-skred] Failed to start Skred engine:", err);
      if (callback) callback(false);
    }
  };

  // If Module is already ready
  if (win.Module.calledRun || (win.Module.HEAPU32 && typeof win.Module.ccall === "function")) {
    win.Module.onRuntimeInitialized();
  }
}

function ensureAudioContext() {
  const M = win.Module;
  if (M && M.audioContext && M.audioContext.state === "suspended") {
    M.audioContext.resume().catch(() => {});
  }
  if (win.miniaudio && Array.isArray(win.miniaudio.devices)) {
    for (const dev of win.miniaudio.devices) {
      if (dev && dev.webaudio && dev.webaudio.state === "suspended") {
        dev.webaudio.resume().catch(() => {});
      }
    }
  }
}

export function ensureEngineRunning() {
  const M = getWasmModule();
  if (!M) return false;
  ensureAudioContext();
  if (engineStarted) {
    return true;
  }
  if (typeof M._skred_audio_running === "function" && M._skred_audio_running()) {
    engineStarted = true;
    return true;
  }
  try {
    if (typeof M._skred_enumerate_devices === "function") {
      M._skred_enumerate_devices(0);
    }
    if (typeof M._skred_audio_select === "function") {
      M._skred_audio_select(0, 0);
      M._skred_audio_select(1, -2);
    }
    if (typeof M._skred_start === "function") {
      const res = M._skred_start(128, 256, -1);
      console.log("[live-skred] ensureEngineRunning _skred_start returned:", res);
      if (res === 0) {
        engineStarted = true;
        if (typeof M._skred_logger === "function") M._skred_logger(1);
        startWasmEventPump(M);
        return true;
      }
    }
  } catch (e) {
    console.warn("[live-skred] ensureEngineRunning warning:", e);
  }
  return false;
}

// Unlock audio on initial user interaction (resumes suspended AudioContext without re-initializing the engine)
if (typeof win.addEventListener === "function") {
  const unlock = () => {
    ensureAudioContext();
    win.removeEventListener("pointerdown", unlock);
    win.removeEventListener("touchstart", unlock);
    win.removeEventListener("keydown", unlock);
    win.removeEventListener("click", unlock);
  };
  win.addEventListener("pointerdown", unlock, { passive: true });
  win.addEventListener("touchstart", unlock, { passive: true });
  win.addEventListener("keydown", unlock, { passive: true });
  win.addEventListener("click", unlock, { passive: true });
}

// ---------------------------------------------------------------------------
// 2. Control Plane Event Pump (60Hz)
// ---------------------------------------------------------------------------

function startWasmEventPump(M) {
  if (!M || typeof M._skred_control_event_poll !== "function") return;
  if (!wasmEventsBuffer && typeof M._malloc === "function") {
    wasmEventsBuffer = M._malloc(MAX_EVENTS_BATCH * EVENT_SIZE);
  }
  if (eventPumpStarted) return;
  eventPumpStarted = true;

  function pump() {
    if (
      currentEventSubscription &&
      M &&
      typeof M._skred_control_event_poll === "function" &&
      wasmEventsBuffer &&
      M.HEAPU8
    ) {
      const count = M._skred_control_event_poll(wasmEventsBuffer, MAX_EVENTS_BATCH);
      if (count > 0) {
        const batch = [];
        const dv = new DataView(M.HEAPU8.buffer, wasmEventsBuffer, count * EVENT_SIZE);
        for (let i = 0; i < count; i++) {
          const off = i * EVENT_SIZE;
          const type = dv.getUint32(off, true);
          const seq = dv.getUint32(off + 16, true);
          const voice = dv.getInt32(off + 24, true);
          const pattern = dv.getInt32(off + 28, true);
          const step = dv.getInt32(off + 32, true);
          const id = dv.getInt32(off + 40, true);
          const val0 = dv.getFloat64(off + 48, true);
          const val1 = dv.getFloat64(off + 56, true);
          const val2 = dv.getFloat64(off + 64, true);
          batch.push({
            t: type,
            seq: seq,
            v: voice,
            p: pattern,
            s: step,
            id: id,
            vals: [val0, val1, val2],
          });
        }
        try {
          currentEventSubscription(batch);
        } catch (err) {
          console.error("[live-skred] Error dispatching event batch to Lustre:", err);
        }
      }
    }
    const schedule =
      typeof requestAnimationFrame !== "undefined"
        ? requestAnimationFrame
        : (cb) => setTimeout(cb, 16);
    schedule(pump);
  }

  const schedule =
    typeof requestAnimationFrame !== "undefined"
      ? requestAnimationFrame
      : (cb) => setTimeout(cb, 16);
  schedule(pump);
}

export function subscribeEvents(onBatch) {
  currentEventSubscription = onBatch;
  const M = getWasmModule();
  if (M) {
    startWasmEventPump(M);
  }
  return () => {
    currentEventSubscription = null;
  };
}

// ---------------------------------------------------------------------------
// 3. Command Execution & REPL Evaluation
// ---------------------------------------------------------------------------

const pendingContinuousCommands = new Map();
let continuousRafId = null;

const scheduleRaf =
  typeof requestAnimationFrame === "function"
    ? requestAnimationFrame
    : (fn) => setTimeout(fn, 16);
const cancelRaf =
  typeof cancelAnimationFrame === "function"
    ? cancelAnimationFrame
    : clearTimeout;

function getContinuousKey(cmd) {
  if (typeof cmd !== "string") return null;
  const trimmed = cmd.replace(/\s+/g, "");

  // Master volume parameter: ;V...; or V...
  if (/^;?V[-0-9.]+;?$/.test(trimmed)) {
    return "master_volume";
  }

  // Voice volume parameter: v0a...;v1a...
  const volMatch = /^v(\d+)a([-\d.]+);?$/.exec(trimmed);
  if (volMatch) {
    return `vol:${volMatch[1]}`;
  }

  return null;
}

export function flushContinuousCommands() {
  if (continuousRafId !== null) {
    cancelRaf(continuousRafId);
    continuousRafId = null;
  }
  if (pendingContinuousCommands.size === 0) return;
  for (const cmd of pendingContinuousCommands.values()) {
    executeSkredCommand(cmd);
  }
  pendingContinuousCommands.clear();
}

function flushCommandQueue() {
  const M = getWasmModule();
  if (!M) return;
  while (commandQueue.length > 0) {
    const cmd = commandQueue.shift();
    executeSkredCommand(cmd);
  }
}

function executeSkredCommand(cmd) {
  const M = getWasmModule();
  if (!M) return;
  try {
    ensureAudioContext();
    ensureEngineRunning();
    const ret = M.ccall("skred_command", "number", ["string"], [cmd]);
    if (M._skred_log) {
      const log = M.UTF8ToString(M._skred_log());
      if (log && log.trim()) {
        console.log(`[skred] ${cmd} (ret=${ret}):`, log);
      }
    }
  } catch (err) {
    console.error(`[skred] Command execution failed: ${cmd}`, err);
  }
}

export function sendCommand(cmd) {
  if (!cmd || !cmd.trim()) return;
  const M = getWasmModule();
  if (!M || !engineStarted) {
    commandQueue.push(cmd);
    return;
  }

  const key = getContinuousKey(cmd);
  if (key) {
    // Coalesce continuous slider updates to at most 1 per animation frame
    pendingContinuousCommands.set(key, cmd);
    if (continuousRafId === null) {
      continuousRafId = scheduleRaf(() => {
        continuousRafId = null;
        for (const c of pendingContinuousCommands.values()) {
          executeSkredCommand(c);
        }
        pendingContinuousCommands.clear();
      });
    }
  } else {
    flushContinuousCommands();
    executeSkredCommand(cmd);
  }
}

export function evalCommand(cmd, callback) {
  ensureAudioContext();
  ensureEngineRunning();
  flushContinuousCommands();
  const M = getWasmModule();
  if (!M) {
    if (callback) callback(cmd, -1, "Skred WASM engine is not yet initialized.");
    return;
  }
  try {
    capturedStdout = [];
    if (win.__skredStdout) win.__skredStdout.length = 0;

    const origLog = console.log;
    const origErr = console.error;
    const directConsoleOut = [];
    console.log = function (...args) {
      directConsoleOut.push(args.join(" "));
      origLog.apply(console, args);
    };
    console.error = function (...args) {
      directConsoleOut.push("[ERR] " + args.join(" "));
      origErr.apply(console, args);
    };

    if (typeof M._skred_logger === "function") M._skred_logger(1);
    const ret = M.ccall("skred_command", "number", ["string"], [cmd]);

    console.log = origLog;
    console.error = origErr;

    // Flush any unbuffered TTY output if Emscripten FS has pending bytes
    if (M.FS && M.FS.streams && M.FS.streams[1] && M.FS.streams[1].tty && M.FS.streams[1].tty.output && M.FS.streams[1].tty.output.length > 0) {
      const remainingBytes = M.FS.streams[1].tty.output;
      let flushText = "";
      if (typeof M.UTF8ArrayToString === "function") {
        flushText = M.UTF8ArrayToString(remainingBytes);
      } else {
        flushText = String.fromCharCode.apply(null, remainingBytes);
      }
      if (flushText) capturedStdout.push(flushText);
      M.FS.streams[1].tty.output = [];
    }

    let logResp = "";
    if (typeof M._skred_log === "function" && typeof M.UTF8ToString === "function") {
      const logPtr = M._skred_log();
      if (logPtr) logResp = M.UTF8ToString(logPtr);
    }

    const combined = [];
    if (win.__skredStdout && win.__skredStdout.length > 0) {
      combined.push(...win.__skredStdout);
    }
    for (const line of capturedStdout) {
      if (!combined.includes(line)) combined.push(line);
    }
    for (const line of directConsoleOut) {
      if (!line.includes("[live-skred]") && !line.includes("[SKRED OUT]") && !line.includes("[SKRED ERR]") && !combined.includes(line)) {
        combined.push(line);
      }
    }
    if (logResp && logResp.trim() && !combined.includes(logResp.trim())) {
      combined.push(logResp.trim());
    }

    const resultText = combined.join("\n").trim() || (ret === 0 ? "OK" : `Returned ${ret}`);
    if (callback) callback(cmd, ret, resultText);
  } catch (err) {
    console.error("[live-skred] evalCommand error:", err);
    if (callback) callback(cmd, -1, String(err.message || err));
  }
}

// ---------------------------------------------------------------------------
// 4. Quantized Musical Clock Timer
// ---------------------------------------------------------------------------

let activeClockTimer = null;

export function stopClock() {
  if (activeClockTimer !== null) {
    clearInterval(activeClockTimer);
    activeClockTimer = null;
  }
}

export function subscribeClock(intervalMs, onTick) {
  // Always clear any existing interval first to prevent duplicate rhythms
  stopClock();

  activeClockTimer = setInterval(() => {
    try {
      if (onTick) onTick();
    } catch (e) {
      console.error("[live-skred] Clock tick error:", e);
    }
  }, Math.max(10, intervalMs));

  return () => stopClock();
}
