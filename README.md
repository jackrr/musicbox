# musicbox

Offline-first mobile music-making app for Android and iOS.

**Stack:** Flutter (UI, Riverpod state) + Rust audio engine (dart:ffi)

---

## Architecture

```
musicbox/
├── app/              # Flutter application
│   └── lib/
│       ├── engine/   # dart:ffi bridge (bindings, typed wrapper, types)
│       ├── models/   # Plain Dart data models (Project, TrackConfig, …)
│       ├── providers/ # Riverpod state (project, sequencer, AI)
│       ├── services/ # Persistence, AI (Claude API), export
│       └── ui/       # Pages: sequencer, synth, sampler, effects, AI, settings
└── engine/           # Rust crate → cdylib (.so) on Android, staticlib (.a) on iOS
    └── src/
        ├── audio.rs      # cpal stream + real-time audio callback
        ├── sequencer.rs  # Sample-accurate 8-track × 64-step clock
        ├── synth/        # 16-voice pool, oscillators, ADSR, biquad filter
        ├── sampler.rs    # WAV playback with pitch-ratio interpolation
        ├── effects.rs    # Freeverb reverb, tempo-synced delay, soft-clip
        ├── export.rs     # Offline WAV render (hound)
        └── commands.rs   # C-ABI command protocol (rtrb ring buffer)
```

The Rust engine exposes a flat C ABI (`musicbox_engine_*`). Dart loads it via `DynamicLibrary` and communicates through a lock-free SPSC ring buffer (rtrb) for audio commands and atomics for read-only state (playhead position, export progress).

---

## First-time setup

### Prerequisites

| Tool | Install |
|------|---------|
| Flutter SDK | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Rust toolchain | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Android NDK + cargo-ndk | `cargo install cargo-ndk` then install NDK via Android Studio SDK Manager |
| iOS: cargo-lipo + Xcode | `cargo install cargo-lipo` (Mac only) |

### 1. Clone and fetch Flutter packages

```sh
git clone git@github.com:jackrr/musicbox.git
cd musicbox/app
flutter pub get
```

### 2. Build the Rust engine

**Android:**
```sh
./scripts/build_android.sh
# Outputs libmusicbox_engine.so to app/android/app/src/main/jniLibs/
```

**iOS (Mac only):**
```sh
./scripts/build_ios.sh
# Outputs libmusicbox_engine.a to app/ios/
# Link it in Xcode: Build Phases → Link Binary With Libraries
```

---

## Development workflow

### Rust engine

```sh
cd engine

# Type-check (fast)
cargo check

# Run unit tests
cargo test

# Build release (then re-run the platform script above)
cargo build --release
```

After changing Rust code, re-run the appropriate build script before launching the Flutter app.

### Flutter app

```sh
cd app

# Run on a connected device / emulator
flutter run

# Analyze without running
flutter analyze

# Run Flutter unit tests
flutter test
```

### Iterating quickly

For UI-only changes that don't touch the engine, `flutter run` hot-reload (`r`) works normally. For any Rust change:

1. `cargo check` in `engine/` to catch errors fast
2. `./scripts/build_android.sh --dev` (or `--dev` on iOS) for a debug build
3. `flutter run` (full restart required after a native lib change — hot-reload won't pick it up)

---

## AI Assist

The app calls the Claude API directly from the device — no backend required. To use AI features:

1. Get an Anthropic API key from [console.anthropic.com](https://console.anthropic.com)
2. Open the app → **Settings** → paste your key
3. The key is stored in the device keychain (iOS Keychain / Android Keystore) and never written to disk in plaintext

---

## License

MIT — see [LICENSE](LICENSE)
