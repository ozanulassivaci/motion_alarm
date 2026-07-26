import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import 'workout_session_local_store.dart';
import 'workout_session_state.dart';

const _tag = '[WorkoutSessionRepository]';

/// Persists in-progress workout state so it survives the process being
/// killed mid-exercise (per CLAUDE.md, nothing should silently lose
/// progress). A session belonging to a different alarm, or older than
/// [AppConfig.workoutSessionMaxAgeMinutes], is treated as stale and never
/// returned — a real morning workout finishes within minutes.
class WorkoutSessionRepository {
  WorkoutSessionRepository({WorkoutSessionLocalStore? store})
    : _store = store ?? WorkoutSessionLocalStore();

  final WorkoutSessionLocalStore _store;

  Future<WorkoutSessionState?> loadResumable(String alarmId) async {
    final saved = await _store.read();
    if (saved == null) return null;
    if (saved.alarmId != alarmId) {
      debugPrint(
        '$_tag loadResumable: saved session is for a different alarm '
        '(${saved.alarmId} != $alarmId); ignoring',
      );
      return null;
    }
    final ageMs = DateTime.now().millisecondsSinceEpoch - saved.savedAtEpochMs;
    final maxAgeMs = AppConfig.workoutSessionMaxAgeMinutes * 60 * 1000;
    if (ageMs > maxAgeMs) {
      debugPrint(
        '$_tag loadResumable: saved session is ${ageMs ~/ 60000}min old '
        '(max ${AppConfig.workoutSessionMaxAgeMinutes}min); discarding as stale',
      );
      await _store.clear();
      return null;
    }
    debugPrint(
      '$_tag loadResumable: resuming exercise '
      '${saved.currentExerciseIndex} at ${saved.repsCompletedForCurrentExercise} reps',
    );
    return saved;
  }

  Future<void> save(WorkoutSessionState session) => _store.write(session);

  Future<void> clear() => _store.clear();
}
