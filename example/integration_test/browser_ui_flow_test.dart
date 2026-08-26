import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:simple_native_web_view_browser_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI-флоу: открытие по кастомной схеме → редирект → закрытие',
      (tester) async {
    // Высокий вьюпорт, чтобы все элементы формы и журнал были построены
    // без прокрутки: пока открыт нативный браузер, жесты перехватываются
    // им, и прокрутка Flutter-списка невозможна.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BrowserDemoApp());
    await tester.pumpAndSettle();

    // Стартовый адрес с кастомной схемой: загрузка невозможна,
    // onLoadError → префикс распознан → браузер закрывается сам.
    await tester.enterText(
      find.byKey(const ValueKey('urlField')),
      'demoapp://callback?code=ui123',
    );
    await tester.tap(find.byKey(const ValueKey('openButton')));
    await tester.pump();

    // Ждём появления в журнале событий onClosed.
    final logVisible = find.byKey(const ValueKey('eventLog'));
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (_logTexts(tester, logVisible).any((t) => t.contains('[onClosed]'))) {
        break;
      }
    }

    final finalTexts = _logTexts(tester, logVisible);
    expect(finalTexts.any((t) => t.contains('[onSchemeRedirect]')), isTrue,
        reason: 'ожидался onSchemeRedirect в журнале: $finalTexts');
    expect(finalTexts.any((t) => t.contains('[redirect]')), isTrue,
        reason: 'ожидалось распознавание редиректа: $finalTexts');
    expect(finalTexts.any((t) => t.contains('[onClosed]')), isTrue,
        reason: 'ожидался onClosed в журнале: $finalTexts');
  });
}

List<String> _logTexts(WidgetTester tester, Finder logFinder) {
  return tester
      .widgetList<Text>(find.descendant(of: logFinder, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
}
