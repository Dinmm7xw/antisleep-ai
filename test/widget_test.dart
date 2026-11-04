import 'package:antisleep_ai/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AntiSleep AI renders HomeScreen and switches language',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AntiSleepAIApp());

    // Verify default KK start trip button is visible
    expect(find.text('САПАРДЫ БАСТАУ'), findsOneWidget);

    // Switch language to RU
    await tester.tap(find.text('RU'));
    await tester.pumpAndSettle();
    expect(find.text('НАЧАТЬ ПОЕЗДКУ'), findsOneWidget);

    // Switch language to EN
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('START TRIP'), findsOneWidget);
  });
}
