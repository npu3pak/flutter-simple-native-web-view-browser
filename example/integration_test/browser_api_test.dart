import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open → onLoadStop → close → onClosed', (tester) async {
    final browser = SimpleNativeBrowser();
    final loadStopped = Completer<Uri>();
    final closed = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
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
    final browser = SimpleNativeBrowser();
    final schemeUrl = Completer<Uri>();
    final closed = Completer<void>();
    var loadErrors = 0;

    final redirectUrl = 'demoapp://callback?code=test123';
    await browser.open(
      SimpleBrowserOpenRequest(
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
    final browser = SimpleNativeBrowser();
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
      SimpleBrowserOpenRequest(
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

  testWidgets('302-редирект на кастомную схему → onSchemeRedirect', (tester) async {
    final browser = SimpleNativeBrowser();
    final schemeUrls = <Uri>[];
    final closed = Completer<void>();

    // Локальный HTTP-сервер: 302-редирект на кастомную схему —
    // точный аналог серверного редиректа при завершении аутентификации.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path == '/start') {
        request.response
          ..statusCode = HttpStatus.movedTemporarily
          ..headers.set(HttpHeaders.locationHeader, 'demoapp://callback?code=server302')
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('http://127.0.0.1:${server.port}/start'),
        userAgent: 'integration-test-ua',
        onSchemeRedirect: schemeUrls.add,
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (schemeUrls.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(schemeUrls, isNotEmpty, reason: 'не пришёл onSchemeRedirect');
    expect(schemeUrls.single.toString(), startsWith('demoapp://'));
    expect(schemeUrls.single.toString(), contains('code=server302'));

    // Один и тот же редирект может прийти несколькими путями перехвата:
    // событие должно быть доставлено ровно один раз.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(schemeUrls, hasLength(1),
        reason: 'onSchemeRedirect пришёл более одного раза: $schemeUrls');

    await browser.close();
    await closed.future.timeout(const Duration(seconds: 20));
  });

  testWidgets('повторное закрытие и повторное открытие', (tester) async {
    final browser = SimpleNativeBrowser();
    var closedCount = 0;
    final firstClosed = Completer<void>();
    final secondClosed = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onClosed: () {
          closedCount++;
          if (!firstClosed.isCompleted) {
            firstClosed.complete();
          }
        },
      ),
    );

    // Двойное закрытие не должно падать и должно уведомлять один раз.
    await browser.close();
    await browser.close();
    await firstClosed.future.timeout(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(closedCount, 1, reason: 'onClosed должен прийти ровно один раз');

    // После закрытия браузер снова открывается и закрывается.
    final opened = Completer<void>();
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onLoadStop: (url) {
          if (!opened.isCompleted) {
            opened.complete();
          }
        },
        onClosed: () {
          closedCount++;
          if (!secondClosed.isCompleted) {
            secondClosed.complete();
          }
        },
      ),
    );
    await opened.future.timeout(const Duration(seconds: 30));

    await browser.close();
    await secondClosed.future.timeout(const Duration(seconds: 30));
    expect(closedCount, 2);
  });

  testWidgets('повторный open при активной сессии: discard', (tester) async {
    final browser = SimpleNativeBrowser();
    var firstStops = 0;
    var secondStops = 0;
    final firstOpened = Completer<void>();
    final closed = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onLoadStop: (url) {
          firstStops++;
          if (!firstOpened.isCompleted) {
            firstOpened.complete();
          }
        },
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );
    await firstOpened.future.timeout(const Duration(seconds: 30));

    // Повторный open отбрасывается: нового браузера нет, событий нет.
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        reopenPolicy: (_, _) => SimpleBrowserReopenPolicy.discard,
        onLoadStop: (_) => secondStops++,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(secondStops, 0, reason: 'событий у отброшенного запроса быть не должно');

    // Активная сессия (первый запрос) жива: закрывается корректно.
    await browser.close();
    await closed.future.timeout(const Duration(seconds: 15));
    expect(firstStops, greaterThanOrEqualTo(1));
  });

  testWidgets('повторный open: тот же URL → replaceCallbacks', (tester) async {
    final browser = SimpleNativeBrowser();
    var firstStops = 0;
    var secondStops = 0;
    final firstOpened = Completer<void>();
    final secondOpened = Completer<void>();
    final closed = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onLoadStop: (url) {
          firstStops++;
          if (!firstOpened.isCompleted) {
            firstOpened.complete();
          }
        },
      ),
    );
    await firstOpened.future.timeout(const Duration(seconds: 30));

    // Тот же URL: страница не перезагружается, привязываются коллбэки
    // нового запроса.
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        reopenPolicy: (oldRequest, newRequest) => oldRequest.url == newRequest.url
            ? SimpleBrowserReopenPolicy.replaceCallbacks
            : SimpleBrowserReopenPolicy.replaceCallbacksAndSettingsAndReload,
        onLoadStop: (url) {
          secondStops++;
          if (!secondOpened.isCompleted) {
            secondOpened.complete();
          }
        },
        // После перепривязки события идут в новый запрос.
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(secondStops, 0,
        reason: 'перезагрузки страницы быть не должно (URL не изменился)');

    // Ручная перезагрузка подтверждает перепривязку коллбэков.
    await browser.reloadWithCookies(const []);
    await secondOpened.future.timeout(const Duration(seconds: 30));
    expect(secondStops, greaterThanOrEqualTo(1));
    expect(firstStops, 1, reason: 'старые коллбэки отвязаны');

    await browser.close();
    await closed.future.timeout(const Duration(seconds: 15));
  });

  testWidgets('повторный open: другой URL → полная замена', (tester) async {
    final browser = SimpleNativeBrowser();
    var firstStops = 0;
    Uri? secondStopUrl;
    final firstOpened = Completer<void>();
    final secondOpened = Completer<void>();
    final closed = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        onLoadStop: (url) {
          firstStops++;
          if (!firstOpened.isCompleted) {
            firstOpened.complete();
          }
        },
      ),
    );
    await firstOpened.future.timeout(const Duration(seconds: 30));

    // Другой URL: вебвью навигируется на новый адрес.
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/?v=2'),
        userAgent: 'integration-test-ua',
        reopenPolicy: (oldRequest, newRequest) => oldRequest.url == newRequest.url
            ? SimpleBrowserReopenPolicy.replaceCallbacks
            : SimpleBrowserReopenPolicy.replaceCallbacksAndSettingsAndReload,
        onLoadStop: (url) {
          secondStopUrl = url;
          if (!secondOpened.isCompleted) {
            secondOpened.complete();
          }
        },
        // После замены сессии события идут в новый запрос.
        onClosed: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      ),
    );
    await secondOpened.future.timeout(const Duration(seconds: 30));
    expect(secondStopUrl.toString(), contains('?v=2'),
        reason: 'вебвью должно перейти на новый адрес');
    expect(firstStops, 1, reason: 'события перепривязаны к новому запросу');

    await browser.close();
    await closed.future.timeout(const Duration(seconds: 15));
  });

  testWidgets('initialCookies + reloadWithCookies → два onLoadStop', (tester) async {
    final browser = SimpleNativeBrowser();
    final stops = <Uri>[];
    final firstStop = Completer<void>();
    final secondStop = Completer<void>();

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'integration-test-ua',
        initialCookies: const [
          SimpleBrowserCookie(name: 'init_cookie', value: 'init_value', path: '/'),
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
      SimpleBrowserCookie(name: 'reload_cookie', value: 'reload_value', path: '/'),
    ]);

    await secondStop.future.timeout(const Duration(seconds: 30));
    expect(stops, hasLength(2));

    await browser.close();
  });
}
