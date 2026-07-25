import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motion_alarm/app/app.dart';

void main() {
  testWidgets('shows the app name on the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MotionAlarmApp()),
    );

    expect(find.text('Motion Alarm'), findsOneWidget);
  });
}
