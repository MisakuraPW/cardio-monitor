import 'package:flutter_test/flutter_test.dart';

import 'package:cardio_upper_computer/app.dart';

void main() {
  testWidgets('App shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CardioMonitorApp());
    expect(find.text('多源心肺功能监测上位机'), findsOneWidget);
  });
}
