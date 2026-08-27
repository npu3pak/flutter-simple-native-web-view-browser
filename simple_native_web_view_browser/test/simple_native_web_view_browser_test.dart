import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_native_web_view_browser/src/simple_native_web_view_browser_platform_interface.dart';

import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

const _channel = MethodChannel('simple_native_web_view_browser');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> outgoingCalls;

  setUp(() {
    outgoingCalls = [];
    // Свежий экземпляр реализации: активная сессия не должна
    // перетекать между тестами.
    SimpleNativeWebViewBrowserPlatform.instance =
        MethodChannelSimpleNativeWebViewBrowser();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      outgoingCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('open отправляет все параметры на нативную сторону', () async {
    final browser = SimpleNativeBrowser();
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/page'),
        userAgent: 'custom-ua',
        usePersistentCookieStore: false,
        enableDebugging: true,
        initialCookies: [
          SimpleBrowserCookie(
            name: 'a',
            value: 'b',
            domain: 'example.com',
            path: '/',
            isSecure: true,
            isHttpOnly: true,
          ),
        ],
        urlBarMode: SimpleBrowserUrlBarMode.readOnly,
      ),
    );

    expect(outgoingCalls, hasLength(1));
    final call = outgoingCalls.single;
    expect(call.method, 'open');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['url'], 'https://example.com/page');
    expect(args['userAgent'], 'custom-ua');
    expect(args['usePersistentCookieStore'], false);
    expect(args['enableDebugging'], true);
    expect(args['urlBarMode'], 'readOnly');
    expect(args['enableCookiesAndroid'], true);
    expect(args['allowFileAccess'], false);
    final cookies = args['initialCookies'] as List<Object?>;
    expect(cookies, hasLength(1));
    final cookie = cookies.single as Map<Object?, Object?>;
    expect(cookie['name'], 'a');
    expect(cookie['value'], 'b');
    expect(cookie['domain'], 'example.com');
    expect(cookie['path'], '/');
    expect(cookie['isSecure'], true);
    expect(cookie['isHttpOnly'], true);
  });

  test('userAgent можно не задавать', () async {
    final browser = SimpleNativeBrowser();
    await browser.open(
      SimpleBrowserOpenRequest(url: Uri.parse('https://example.com')),
    );

    expect(outgoingCalls, hasLength(1));
    final args = outgoingCalls.single.arguments as Map<Object?, Object?>;
    expect(args['userAgent'], isNull);
  });

  test('enableCookiesAndroid и allowFileAccess передаются на нативную сторону',
      () async {
    final browser = SimpleNativeBrowser();
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        enableCookiesAndroid: false,
        allowFileAccess: true,
      ),
    );

    expect(outgoingCalls, hasLength(1));
    final args = outgoingCalls.single.arguments as Map<Object?, Object?>;
    expect(args['enableCookiesAndroid'], false);
    expect(args['allowFileAccess'], true);
  });

  test('close и reloadWithCookies отправляют корректные вызовы', () async {
    final browser = SimpleNativeBrowser();
    await browser.close();
    await browser.reloadWithCookies([
      SimpleBrowserCookie(name: 'c', value: 'd', path: '/'),
    ]);

    expect(outgoingCalls.map((c) => c.method), ['close', 'reloadWithCookies']);
    final args = outgoingCalls.last.arguments as Map<Object?, Object?>;
    final cookies = args['cookies'] as List<Object?>;
    expect(cookies.single as Map<Object?, Object?>, containsPair('name', 'c'));
  });

  test('события onLoadStop/onLoadError маршрутизируются на колбэки', () async {
    final browser = SimpleNativeBrowser();
    final stopped = <Uri>[];
    final errors = <Uri>[];
    var closed = false;

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: stopped.add,
        onLoadError: errors.add,
        onClosed: () => closed = true,
      ),
    );

    await _sendNativeEvent('onLoadStop', 'https://example.com/stop');
    await _sendNativeEvent('onLoadError', 'demoapp://callback?code=1');

    expect(stopped, [Uri.parse('https://example.com/stop')]);
    expect(errors, [Uri.parse('demoapp://callback?code=1')]);
    expect(closed, isFalse);
  });

  test('onSchemeRedirect маршрутизируется на колбэк', () async {
    final browser = SimpleNativeBrowser();
    final schemes = <Uri>[];
    var loadErrors = 0;

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onSchemeRedirect: schemes.add,
        onLoadError: (_) => loadErrors++,
      ),
    );

    await _sendNativeEvent('onSchemeRedirect', 'myapp://login?code=1');
    await _sendNativeEvent('onLoadError', 'https://example.com/err');

    expect(schemes, [Uri.parse('myapp://login?code=1')]);
    expect(loadErrors, 1);
  });

  test('onClosed очищает активный запрос и вызывает колбэк', () async {
    final browser = SimpleNativeBrowser();
    var closed = false;

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: (_) {},
        onClosed: () => closed = true,
      ),
    );

    await _sendNativeEvent('onClosed', null);

    expect(closed, isTrue);
  });

  test('исключение в колбэке не рвёт маршрутизацию последующих событий',
      () async {
    final browser = SimpleNativeBrowser();
    final stopped = <Uri>[];

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadError: (_) => throw StateError('boom'),
        onLoadStop: stopped.add,
      ),
    );

    await _sendNativeEvent('onLoadError', 'https://example.com/err');
    await _sendNativeEvent('onLoadStop', 'https://example.com/stop');

    expect(stopped, [Uri.parse('https://example.com/stop')]);
  });

  test('reopenPolicy без резолвера: полная замена по умолчанию', () async {
    final browser = SimpleNativeBrowser();
    final firstStops = <Uri>[];
    final secondStops = <Uri>[];

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: firstStops.add,
      ),
    );
    expect(outgoingCalls, hasLength(1));

    // Второй open: резолвер не задан → полная замена, канал вызывается.
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/other'),
        userAgent: 'ua2',
        onLoadStop: secondStops.add,
      ),
    );
    expect(outgoingCalls, hasLength(2), reason: 'канал вызывается с новым запросом');
    final secondArgs = outgoingCalls.last.arguments as Map<Object?, Object?>;
    expect(secondArgs['url'], 'https://example.com/other');
    expect(secondArgs['userAgent'], 'ua2');

    await _sendNativeEvent('onLoadStop', 'https://example.com/other');
    expect(firstStops, isEmpty, reason: 'старые коллбэки отвязаны');
    expect(secondStops, [Uri.parse('https://example.com/other')]);
  });

  test('reopenPolicy: discard отбрасывает запрос и получает оба запроса', () async {
    final browser = SimpleNativeBrowser();
    final firstStops = <Uri>[];
    final secondStops = <Uri>[];
    Uri? resolverOld;
    Uri? resolverNew;

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: firstStops.add,
      ),
    );

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/discarded'),
        userAgent: 'ua',
        reopenPolicy: (oldRequest, newRequest) {
          resolverOld = oldRequest.url;
          resolverNew = newRequest.url;
          return SimpleBrowserReopenPolicy.discard;
        },
        onLoadStop: secondStops.add,
      ),
    );
    expect(resolverOld, Uri.parse('https://example.com'));
    expect(resolverNew, Uri.parse('https://example.com/discarded'));
    expect(outgoingCalls, hasLength(1), reason: 'канал не должен вызываться повторно');

    await _sendNativeEvent('onLoadStop', 'https://example.com/stop');
    expect(firstStops, [Uri.parse('https://example.com/stop')]);
    expect(secondStops, isEmpty, reason: 'отброшенный запрос событий не получает');
  });

  test('reopenPolicy: replaceCallbacks не трогает канал, события в новый запрос', () async {
    final browser = SimpleNativeBrowser();
    final firstStops = <Uri>[];
    final secondStops = <Uri>[];

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: firstStops.add,
      ),
    );

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        reopenPolicy: (_, _) => SimpleBrowserReopenPolicy.replaceCallbacks,
        onLoadStop: secondStops.add,
      ),
    );
    expect(outgoingCalls, hasLength(1), reason: 'канал не должен вызываться повторно');

    await _sendNativeEvent('onLoadStop', 'https://example.com/stop');
    expect(firstStops, isEmpty, reason: 'старые коллбэки отвязаны');
    expect(secondStops, [Uri.parse('https://example.com/stop')]);
  });

  test('reopenPolicy: replaceCallbacksAndSettings вызывает reopenSettings', () async {
    final browser = SimpleNativeBrowser();
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
      ),
    );

    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/settings'),
        userAgent: 'ua',
        reopenPolicy: (_, _) =>
            SimpleBrowserReopenPolicy.replaceCallbacksAndSettings,
      ),
    );
    expect(outgoingCalls, hasLength(2));
    expect(outgoingCalls.last.method, 'reopenSettings');
    final args = outgoingCalls.last.arguments as Map<Object?, Object?>;
    expect(args['url'], 'https://example.com/settings');
  });

  test('полная замена при ошибке канала не восстанавливает предыдущий запрос', () async {
    final browser = SimpleNativeBrowser();
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
      ),
    );

    // Второй вызов канала (первый после замены хендлера) бросает ошибку.
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      outgoingCalls.add(call);
      calls++;
      if (calls == 1) {
        throw PlatformException(code: 'boom');
      }
      return null;
    });

    await expectLater(
      browser.open(
        SimpleBrowserOpenRequest(
          url: Uri.parse('https://example.com/2'),
          userAgent: 'ua',
        ),
      ),
      throwsA(isA<PlatformException>()),
    );

    // Новый запрос снова открывается штатно: активная сессия сброшена.
    await browser.open(
      SimpleBrowserOpenRequest(
        url: Uri.parse('https://example.com/3'),
        userAgent: 'ua',
      ),
    );
    expect(outgoingCalls, hasLength(3));
  });

  test('по умолчанию установлена реализация через MethodChannel', () {
    expect(
      SimpleNativeWebViewBrowserPlatform.instance,
      isA<MethodChannelSimpleNativeWebViewBrowser>(),
    );
  });

  test('Mock-реализация регистрируется как instance', () {
    final mock = MockSimpleNativeWebViewBrowserPlatform();
    SimpleNativeWebViewBrowserPlatform.instance = mock;
    expect(SimpleNativeWebViewBrowserPlatform.instance, same(mock));
  });
}

Future<void> _sendNativeEvent(String method, Object? arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'simple_native_web_view_browser',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}
