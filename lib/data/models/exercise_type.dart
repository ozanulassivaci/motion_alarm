enum ExerciseType { squat, jumpingJack, highKnees, overheadReach }

extension ExerciseTypeLabel on ExerciseType {
  String get label => switch (this) {
    ExerciseType.squat => 'Squat',
    ExerciseType.jumpingJack => 'Jumping Jack',
    ExerciseType.highKnees => 'Yüksek Diz (High Knees)',
    ExerciseType.overheadReach => 'Yukarı Uzanma (Overhead Reach)',
  };
}
