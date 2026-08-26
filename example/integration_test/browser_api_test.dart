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
    await closed.future.timeout(const Duration(seconds: 20));
  });

  testWidgets('кастомная схема → onSchemeRedirect → закрытие', (tester) async {
    final browser = AuthNativeBrowser();
    final schemeUrl = Completer<Uri>();
    final closed = Completer<void>();
    var loadErrors = 0;

    final redirectUrl = 'demoapp://callback?code=test123';
    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse(redirectUrl),
        userAgent: 'integration-test-ua',
        onSchemeRedirect: (url) {
          if (!schemeUrl.isCompleted) {
            schemeUrl.complete(url);
          }
        },
        onLoadError: (_) => loadErrors++,
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );

    final failedUrl = await schemeUrl.future.timeout(const Duration(seconds: 15));
    expect(failedUrl.toString(), startsWith('demoapp://'));
    expect(failedUrl.toString(), contains('code=test123'));
    // Кастомная схема не должна приходить как ошибка загрузки.
    expect(loadErrors, 0);

    // Редирект распознан приложением по префиксу — закрываем браузер.
    await browser.close();
    await closed.future.timeout(const Duration(seconds: 20));
  });

  testWidgets('JS-редирект на кастомную схему → onSchemeRedirect', (tester) async {
    final browser = AuthNativeBrowser();
    final schemeUrl = Completer<Uri>();
    final closed = Completer<void>();

    // Страница с inline-скриптом, который сразу переходит на кастомную
    // схему: навигация идёт через decidePolicyFor (iOS) и
    // shouldOverrideUrlLoading (Android) — как серверный редирект.
    final dataUrl = Uri.dataFromString(
      "<script>location.href='demoapp://callback?code=js1';</script>",
      mimeType: 'text/html',
    );

    await browser.open(
      AuthBrowserOpenRequest(
        url: dataUrl,
        userAgent: 'integration-test-ua',
        onSchemeRedirect: (url) {
          if (!schemeUrl.isCompleted) {
            schemeUrl.complete(url);
          }
        },
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );

    final redirected = await schemeUrl.future.timeout(const Duration(seconds: 15));
    expect(redirected.toString(), startsWith('demoapp://'));
    expect(redirected.toString(), contains('code=js1'));

    await browser.close();
    await closed.future.timeout(const Duration(seconds: 20));
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
