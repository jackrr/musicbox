import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/types.dart';
import '../models/project.dart';
import 'engine_provider.dart';
import 'project_provider.dart';

// ---------------------------------------------------------------------------
// Playhead — polled from Rust at ~120 fps, deduplicated so rebuilds only
// happen when the step actually changes.
// ---------------------------------------------------------------------------

final playheadProvider = StreamProvider<int>((ref) {
  final engine = ref.watch(engineProvider);
  return Stream.periodic(const Duration(milliseconds: 8), (_) {
    return engine.getPlayhead();
  }).distinct();
});

// ---------------------------------------------------------------------------
// Sequencer state notifier
// ---------------------------------------------------------------------------

class SequencerState {
  final double bpm;
  final int numSteps;
  final bool playing;

  const SequencerState({
    this.bpm      = 120.0,
    this.numSteps = 16,
    this.playing  = false,
  });

  SequencerState copyWith({double? bpm, int? numSteps, bool? playing}) =>
      SequencerState(
        bpm:      bpm      ?? this.bpm,
        numSteps: numSteps ?? this.numSteps,
        playing:  playing  ?? this.playing,
      );
}

class SequencerNotifier extends StateNotifier<SequencerState> {
  final Ref _ref;

  SequencerNotifier(this._ref) : super(const SequencerState()) {
    // Sync initial project state into the engine on first load
    _ref.listen<AsyncValue<Project>>(projectProvider, (_, next) {
      next.whenData(_syncProject);
    }, fireImmediately: true);
  }

  void _syncProject(Project p) {
    final engine = _ref.read(engineProvider);
    engine.setBpm(p.bpm);
    engine.setNumSteps(p.numSteps);

    // Global reverb params
    engine.setEffect(0, EffectParam.reverbRoom, p.reverbRoom);
    engine.setEffect(0, EffectParam.reverbDamp, p.reverbDamp);

    for (var ti = 0; ti < kNumTracks; ti++) {
      final track = p.tracks[ti];
      for (var si = 0; si < kMaxSteps; si++) {
        final step = track.steps[si];
        engine.setStep(ti, si,
          active:   step.active,
          pitch:    step.pitch,
          velocity: step.velocity,
        );
      }
      // Voice params
      final vp = track.voiceParams;
      engine.setVoiceParam(ti, VoiceParam.oscType,  vp.oscType.index.toDouble());
      engine.setVoiceParam(ti, VoiceParam.attack,   vp.attack);
      engine.setVoiceParam(ti, VoiceParam.decay,    vp.decay);
      engine.setVoiceParam(ti, VoiceParam.sustain,  vp.sustain);
      engine.setVoiceParam(ti, VoiceParam.release,  vp.release);
      engine.setVoiceParam(ti, VoiceParam.volume,   vp.volume);
      // Effects
      final fx = track.effects;
      engine.setEffect(ti, EffectParam.reverbSend,     fx.reverbSend);
      engine.setEffect(ti, EffectParam.delaySend,      fx.delaySend);
      engine.setEffect(ti, EffectParam.delayTime,      fx.delayTime);
      engine.setEffect(ti, EffectParam.delayFeedback,  fx.delayFeedback);
      engine.setEffect(ti, EffectParam.distDrive,      fx.distDrive);
      engine.setEffect(ti, EffectParam.filterType,     fx.filterMode.toDouble());
      engine.setEffect(ti, EffectParam.filterCutoff,   fx.filterCutoff);
      engine.setEffect(ti, EffectParam.filterResonance, fx.filterResonance);
    }
    state = state.copyWith(bpm: p.bpm, numSteps: p.numSteps);
  }

  void play() {
    _ref.read(engineProvider).setTransport(TransportState.play);
    state = state.copyWith(playing: true);
  }

  void stop() {
    _ref.read(engineProvider).setTransport(TransportState.stop);
    state = state.copyWith(playing: false);
  }

  void setBpm(double bpm) {
    _ref.read(engineProvider).setBpm(bpm);
    state = state.copyWith(bpm: bpm);
    _ref.read(projectProvider.notifier).updateBpm(bpm);
  }

  void setNumSteps(int n) {
    _ref.read(engineProvider).setNumSteps(n);
    state = state.copyWith(numSteps: n);
    _ref.read(projectProvider.notifier).updateNumSteps(n);
  }

  void toggleStep(int trackId, int stepIdx, {int pitch = 60, double velocity = 0.8}) {
    final project = _ref.read(projectProvider).value;
    if (project == null) return;
    final current = project.tracks[trackId].steps[stepIdx];
    final newActive = !current.active;
    _ref.read(engineProvider).setStep(trackId, stepIdx,
      active: newActive, pitch: pitch, velocity: velocity);
    _ref.read(projectProvider.notifier).updateStep(
      trackId, stepIdx,
      current.copyWith(active: newActive, pitch: pitch, velocity: velocity),
    );
  }

  void setStep(int trackId, int stepIdx, StepData step) {
    _ref.read(engineProvider).setStep(trackId, stepIdx,
      active: step.active, pitch: step.pitch, velocity: step.velocity);
    _ref.read(projectProvider.notifier).updateStep(trackId, stepIdx, step);
  }
}

final sequencerProvider =
    StateNotifierProvider<SequencerNotifier, SequencerState>(
  (ref) => SequencerNotifier(ref),
);
