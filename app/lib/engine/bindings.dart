import 'dart:ffi';
import 'dart:io';

// --- Native type aliases -------------------------------------------------------

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();

typedef _VoidPtrNative = Void Function(Pointer<Void>);
typedef _VoidPtrDart = void Function(Pointer<Void>);

// --- EngineBindings ------------------------------------------------------------

/// Raw FFI bindings to the Rust engine shared library.
///
/// This class is intentionally low-level. Use [AudioEngine] for all
/// application code.
class EngineBindings {
  final DynamicLibrary _lib;

  late final Pointer<Void> Function() create;
  late final void Function(Pointer<Void>) destroy;
  late final void Function(Pointer<Void>) start;
  late final void Function(Pointer<Void>) stop;

  EngineBindings() : _lib = _openLibrary() {
    create = _lib.lookupFunction<_CreateNative, _CreateDart>(
      'musicbox_engine_create',
    );
    destroy = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
      'musicbox_engine_destroy',
    );
    start = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
      'musicbox_engine_start',
    );
    stop = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
      'musicbox_engine_stop',
    );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libmusicbox_engine.so');
    }
    if (Platform.isIOS) {
      // Static lib is linked directly into the process on iOS.
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
      'musicbox engine: unsupported platform "${Platform.operatingSystem}"',
    );
  }
}
