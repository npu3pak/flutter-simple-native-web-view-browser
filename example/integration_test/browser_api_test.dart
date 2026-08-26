import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open → onLoadStop → close → onClosed', (tester) async {
    final browser = AuthNativeBrowser();
    final loadStopped = Completer<Uri>();
    final closed = Completer<void>();

    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onLoadStop: (url) {
          if (!loadStopped.isCompleted) {
            loadStopped.complete(url);
          }
        },
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );

    final loadedUrl = await loadStopped.future.timeout(const Duration(seconds: 30));
    expect(loadedUrl.host, 'example.com');

    await browser.close();
    await closed.future.timeout(const Duration(seconds: 10));
  });

  testWidgets('кастомная схема → onLoadError → закрытие', (tester) async {
    final browser = AuthNativeBrowser();
    final errorUrl = Completer<Uri>();
    final closed = Completer<void>();

    final redirectUrl = 'demoapp://callback?code=test123';
    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse(redirectUrl),
        userAgent: 'integration-test-ua',
        onLoadError: (url) {
          if (!errorUrl.isCompleted) {
            errorUrl.complete(url);
          }
        },
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );

    final failedUrl = await errorUrl.future.timeout(const Duration(seconds: 15));
    expect(failedUrl.toString(), startsWith('demoapp://'));
    expect(failedUrl.toString(), contains('code=test123'));

    // Редирект распознан приложением по префиксу — закрываем браузер.
    await browser.close();
    await closed.future.timeout(const Duration(seconds: 10));
  });

  testWidgets('initialCookies + reloadWithCookies → два onLoadStop', (tester) async {
    final browser = AuthNativeBrowser();
    final stops = <Uri>[];
    final firstStop = Completer<void>();
    final secondStop = Completer<void>();

    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        initialCookies: const [
          AuthBrowserCookie(name: 'init_cookie', value: 'init_value', path: '/'),
        ],
        onLoadStop: (url) {
          stops.add(url);
          if (stops.length == 1 && !firstStop.isCompleted) {
            firstStop.complete();
          }
          if (stops.length == 2 && !secondStop.isCompleted) {
            secondStop.complete();
          }
        },
      ),
    );

    await firstStop.future.timeout(const Duration(seconds: 30));

    await browser.reloadWithCookies(const [
      AuthBrowserCookie(name: 'reload_cookie', value: 'reload_value', path: '/'),
    ]);

    await secondStop.future.timeout(const Duration(seconds: 30));
    expect(stops, hasLength(2));

    await browser.close();
  });
}
