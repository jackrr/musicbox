# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Commands

### Rust engine (`engine/`)
```sh
cargo check          # fast type-check
cargo test           # unit tests
cargo build --release
```
After any Rust change, rebuild for the target platform before running the Flutter app:
```sh
./scripts/build_android.sh       # debug build: add --dev
./scripts/build_ios.sh           # Mac only
```

### Flutter app (`app/`)
```sh
flutter pub get
flutter run          # requires a connected device/emulator
flutter analyze
flutter test
flutter test test/foo_test.dart  # single test file
```

Hot-reload (`r`) works for UI-only changes. Any Rust change requires a full restart after the native lib is rebuilt — hot-reload will not pick it up.

---

## Architecture

```
musicbox/
├── app/    # Flutter (UI + Riverpod state + dart:ffi bridge)
└── engine/ # Rust cdylib (Android .so) / staticlib (iOS .a)
```

### Rust → Dart boundary

The engine exposes a flat C ABI (`musicbox_engine_*`). All runtime communication goes through a **lock-free SPSC ring buffer (rtrb)**:

```
Dart  →  musicbox_engine_send_command(ptr, kind, track_id, param_a, param_b, value: f32)
```

The command protocol (from `engine/src/commands.rs`):

| kind | command | track_id | param_a | param_b | value |
|------|---------|----------|---------|---------|-------|
| 0 | NoteOn | track | pitch | velocity (0–127) | — |
| 1 | NoteOff | track | pitch | — | — |
| 2 | SetVoiceParam | track | VoiceParam index | — | f32 |
| 3 | SetBPM | — | — | — | bpm |
| 4 | SetTransport | — | 0=stop 1=play 2=reset | — | — |
| 5 | SetStep | track | step_idx | pitch | velocity (0=clear) |
| 6 | SetEffect | track | EffectParam index | — | f32 |
| 7 | SetNumSteps | — | n | — | — |
| 8 | SetSampleParam | track | SampleParam index | — | f32 |

Read-only state crosses the boundary via atomics: `musicbox_engine_get_playhead` (returns current step or -1).

**Critical:** The enum indices in `app/lib/engine/types.dart` (`VoiceParam`, `EffectParam`, `SampleParam`) must match the `#[repr(u8)]` Rust enums in `engine/src/commands.rs` exactly.

### Flutter state layers

| Provider | Type | Role |
|----------|------|------|
| `engineProvider` | `Provider<AudioEngine>` | Singleton FFI wrapper, lives for app lifetime |
| `projectProvider` | `AsyncNotifierProvider<ProjectNotifier, Project>` | Source of truth for all project data; debounced auto-save (2 s) |
| `sequencerProvider` | `StateNotifierProvider<SequencerNotifier, SequencerState>` | Transport controls (play/stop/BPM/numSteps); listens to `projectProvider` and syncs all track data to the engine on every change |
| `playheadProvider` | `StreamProvider<int>` | Polls `engine.getPlayhead()` at ~120 fps; `.distinct()` so rebuilds only happen on step change |

`SequencerNotifier._syncProject` is the single place that pushes a full project snapshot into the engine (voice params, effects, sample params, steps, sample file paths). It fires immediately on first load and on every `projectProvider` change.

### Sample loading timing constraint

WAV decoding inside `_syncProject` **must** be deferred with `Future.microtask()`. Calling blocking FFI synchronously inside Riverpod's state-propagation chain triggers a SIGTRAP on Flutter's native side. The `_loadedSamplePaths` list prevents duplicate loads across sync cycles.

### Input handling pattern

Sampler pads and play-mode pads use `Listener` (not `GestureDetector`) for `noteOn` so the event fires immediately on pointer-down without going through the gesture arena. `GestureDetector` wraps `Listener` only for secondary gestures (long-press to open editor, drag-to-reorder in edit mode).

### Android build requirements

Three things are required for the Rust cdylib to work on Android (see `engine/build.rs` and `scripts/build_android.sh`):
1. `JNI_OnLoad` symbol must be exported (cpal requirement)
2. `ndk-context` must be initialized before cpal opens the audio stream
3. `libc++_shared.so` must be copied into `jniLibs/` alongside `libmusicbox_engine.so`

### Navigation

Six bottom-nav tabs defined in `app/lib/main.dart`: SEQ → SYNTH → SAMPLER → FX → PADS → AI. Pages are kept alive in an `IndexedStack`.

### AI feature

The AI page calls the Claude API directly from the device. API key is stored in the device keychain (iOS Keychain / Android Keystore) and configured via Settings.
