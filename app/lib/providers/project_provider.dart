import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/types.dart';
import '../models/project.dart';
import '../services/persistence_service.dart';

class ProjectNotifier extends AsyncNotifier<Project> {
  Timer? _saveTimer;

  @override
  Future<Project> build() async {
    // Load the most recently edited project, or create a new one
    final projects = await PersistenceService.instance.listAll();
    if (projects.isNotEmpty) return projects.first;
    final p = Project.create();
    await PersistenceService.instance.save(p);
    return p;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      state.whenData((p) => PersistenceService.instance.save(p));
    });
  }

  Future<void> _update(Project Function(Project) fn) async {
    state.whenData((p) {
      final next = fn(p).copyWith(updatedAt: DateTime.now());
      state = AsyncData(next);
      _scheduleSave();
    });
  }

  void updateBpm(double bpm)    => _update((p) => p.copyWith(bpm: bpm));
  void updateNumSteps(int n)    => _update((p) => p.copyWith(numSteps: n));
  void updateReverbRoom(double v) => _update((p) => p.copyWith(reverbRoom: v));
  void updateReverbDamp(double v) => _update((p) => p.copyWith(reverbDamp: v));

  void updateStep(int trackId, int stepIdx, StepData step) => _update((p) {
    final tracks = List<TrackConfig>.from(p.tracks);
    final steps  = List<StepData>.from(tracks[trackId].steps);
    steps[stepIdx] = step;
    tracks[trackId] = tracks[trackId].copyWith(steps: steps);
    return p.copyWith(tracks: tracks);
  });

  void updateVoiceParam(int trackId, VoiceParam param, double value) =>
      _update((p) {
    final tracks = List<TrackConfig>.from(p.tracks);
    final vp = tracks[trackId].voiceParams;
    tracks[trackId] = tracks[trackId].copyWith(
      voiceParams: switch (param) {
        VoiceParam.oscType  => vp.copyWith(oscType: OscType.values[value.round()]),
        VoiceParam.attack   => vp.copyWith(attack: value),
        VoiceParam.decay    => vp.copyWith(decay: value),
        VoiceParam.sustain  => vp.copyWith(sustain: value),
        VoiceParam.release  => vp.copyWith(release: value),
        VoiceParam.volume   => vp.copyWith(volume: value),
      },
    );
    return p.copyWith(tracks: tracks);
  });

  void updateEffect(int trackId, EffectParam param, double value) =>
      _update((p) {
    final tracks = List<TrackConfig>.from(p.tracks);
    final fx = tracks[trackId].effects;
    tracks[trackId] = tracks[trackId].copyWith(
      effects: switch (param) {
        EffectParam.reverbSend     => fx.copyWith(reverbSend: value),
        EffectParam.delaySend      => fx.copyWith(delaySend: value),
        EffectParam.delayTime      => fx.copyWith(delayTime: value),
        EffectParam.delayFeedback  => fx.copyWith(delayFeedback: value),
        EffectParam.distDrive      => fx.copyWith(distDrive: value),
        EffectParam.filterType     => fx.copyWith(filterMode: value.round()),
        EffectParam.filterCutoff   => fx.copyWith(filterCutoff: value),
        EffectParam.filterResonance => fx.copyWith(filterResonance: value),
        // Global params handled separately — don't update track effects
        EffectParam.reverbRoom || EffectParam.reverbDamp => fx,
      },
    );
    return p.copyWith(tracks: tracks);
  });

  void updateSamplePath(int trackId, String path) => _update((p) {
    final tracks = List<TrackConfig>.from(p.tracks);
    tracks[trackId] = tracks[trackId].copyWith(
      mode: TrackMode.sampler, samplePath: path);
    return p.copyWith(tracks: tracks);
  });

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final p = state.value;
    if (p != null) await PersistenceService.instance.save(p);
  }

  Future<void> loadProject(String id) async {
    final p = await PersistenceService.instance.load(id);
    if (p != null) state = AsyncData(p);
  }

  Future<void> newProject() async {
    await saveNow();
    final p = Project.create();
    await PersistenceService.instance.save(p);
    state = AsyncData(p);
  }
}

final projectProvider =
    AsyncNotifierProvider<ProjectNotifier, Project>(ProjectNotifier.new);
