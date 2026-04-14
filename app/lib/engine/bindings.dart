import 'dart:ffi';
import 'dart:io';

// --- Native type aliases -------------------------------------------------------

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart   = Pointer<Void> Function();

typedef _VoidPtrNative = Void Function(Pointer<Void>);
typedef _VoidPtrDart   = void Function(Pointer<Void>);

typedef _SendCmdNative = Bool Function(
    Pointer<Void>, Uint8, Uint8, Uint8, Uint8, Float);
typedef _SendCmdDart = bool Function(
    Pointer<Void>, int, int, int, int, double);

typedef _GetPlayheadNative = Int32 Function(Pointer<Void>);
typedef _GetPlayheadDart   = int Function(Pointer<Void>);

typedef _LoadSampleNative = Bool Function(
    Pointer<Void>, Uint8, Pointer<Uint8>, Size);
typedef _LoadSampleDart = bool Function(
    Pointer<Void>, int, Pointer<Uint8>, int);

typedef _ExportWavNative = Bool Function(
    Pointer<Void>, Pointer<Uint8>, Size, Uint32);
typedef _ExportWavDart = bool Function(
    Pointer<Void>, Pointer<Uint8>, int, int);

typedef _ExportProgressNative = Uint32 Function(Pointer<Void>);
typedef _ExportProgressDart   = int Function(Pointer<Void>);

typedef _StartRecordingNative = Bool Function(Pointer<Void>);
typedef _StartRecordingDart   = bool Function(Pointer<Void>);

typedef _StopRecordingNative = Bool Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _StopRecordingDart   = bool Function(Pointer<Void>, Pointer<Uint8>, int);

// --- EngineBindings ------------------------------------------------------------

/// Raw FFI bindings to the Rust engine shared library.
///
/// Low-level. Use [AudioEngine] for all application code.
class EngineBindings {
  final DynamicLibrary _lib;

  late final Pointer<Void> Function() create;
  late final void Function(Pointer<Void>) destroy;
  late final void Function(Pointer<Void>) start;
  late final void Function(Pointer<Void>) stop;
  late final bool Function(Pointer<Void>, int, int, int, int, double) sendCommand;
  late final int  Function(Pointer<Void>) getPlayhead;
  late final bool Function(Pointer<Void>, int, Pointer<Uint8>, int) loadSample;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int, int) exportWav;
  late final int  Function(Pointer<Void>) exportProgress;
  late final bool Function(Pointer<Void>) startRecording;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int) stopRecording;

  EngineBindings() : _lib = _openLibrary() {
    create = _lib.lookupFunction<_CreateNative, _CreateDart>(
        'musicbox_engine_create');
    destroy = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
        'musicbox_engine_destroy');
    start = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
        'musicbox_engine_start');
    stop = _lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
        'musicbox_engine_stop');
    sendCommand = _lib.lookupFunction<_SendCmdNative, _SendCmdDart>(
        'musicbox_engine_send_command');
    getPlayhead = _lib.lookupFunction<_GetPlayheadNative, _GetPlayheadDart>(
        'musicbox_engine_get_playhead');
    loadSample = _lib.lookupFunction<_LoadSampleNative, _LoadSampleDart>(
        'musicbox_engine_load_sample');
    exportWav = _lib.lookupFunction<_ExportWavNative, _ExportWavDart>(
        'musicbox_engine_export_wav');
    exportProgress = _lib.lookupFunction<_ExportProgressNative, _ExportProgressDart>(
        'musicbox_engine_export_progress');
    startRecording = _lib.lookupFunction<_StartRecordingNative, _StartRecordingDart>(
        'musicbox_engine_start_recording');
    stopRecording = _lib.lookupFunction<_StopRecordingNative, _StopRecordingDart>(
        'musicbox_engine_stop_recording');
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libmusicbox_engine.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
        'musicbox engine: unsupported platform "${Platform.operatingSystem}"');
  }
}
