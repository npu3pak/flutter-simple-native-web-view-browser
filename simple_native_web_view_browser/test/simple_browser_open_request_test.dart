import 'package:flutter_test/flutter_test.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

void main() {
  group('SimpleBrowserOpenRequest: валидация userAgent', () {
    test('валидный userAgent принимается', () {
      expect(
        () => SimpleBrowserOpenRequest(
          url: Uri.parse('https://example.com'),
          userAgent: 'Mozilla/5.0 (Linux; Android 14) Chrome/131.0',
        ),
        returnsNormally,
      );
    });

    test('userAgent можно не задавать', () {
      expect(
        () => SimpleBrowserOpenRequest(url: Uri.parse('https://example.com')),
        returnsNormally,
      );
    });

    test('CR в userAgent запрещён', () {
      expect(
        () => SimpleBrowserOpenRequest(
          url: Uri.parse('https://example.com'),
          userAgent: 'UA\r\nX-Evil: 1',
        ),
        throwsArgumentError,
      );
    });

    test('LF в userAgent запрещён', () {
      expect(
        () => SimpleBrowserOpenRequest(
          url: Uri.parse('https://example.com'),
          userAgent: 'UA\nX-Evil: 1',
        ),
        throwsArgumentError,
      );
    });
  });
}
