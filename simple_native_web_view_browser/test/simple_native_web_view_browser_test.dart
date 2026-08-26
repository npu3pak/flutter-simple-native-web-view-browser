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
    final browser = AuthNativeBrowser();
    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse('https://example.com/page'),
        userAgent: 'custom-ua',
        usePersistentCookieStore: false,
        initialCookies: const [
          AuthBrowserCookie(
            name: 'a',
            value: 'b',
            domain: 'example.com',
            path: '/',
            isSecure: true,
            isHttpOnly: true,
          ),
        ],
        urlBarMode: AuthBrowserUrlBarMode.readOnly,
      ),
    );

    expect(outgoingCalls, hasLength(1));
    final call = outgoingCalls.single;
    expect(call.method, 'open');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['url'], 'https://example.com/page');
    expect(args['userAgent'], 'custom-ua');
    expect(args['usePersistentCookieStore'], false);
    expect(args['urlBarMode'], 'readOnly');
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

  test('close и reloadWithCookies отправляют корректные вызовы', () async {
    final browser = AuthNativeBrowser();
    await browser.close();
    await browser.reloadWithCookies(const [
      AuthBrowserCookie(name: 'c', value: 'd', path: '/'),
    ]);

    expect(outgoingCalls.map((c) => c.method), ['close', 'reloadWithCookies']);
    final args = outgoingCalls.last.arguments as Map<Object?, Object?>;
    final cookies = args['cookies'] as List<Object?>;
    expect(cookies.single as Map<Object?, Object?>, containsPair('name', 'c'));
  });

  test('события onLoadStop/onLoadError маршрутизируются на колбэки', () async {
    final browser = AuthNativeBrowser();
    final stopped = <Uri>[];
    final errors = <Uri>[];
    var closed = false;

    await browser.open(
      AuthBrowserOpenRequest(
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

  test('onClosed очищает активный запрос и вызывает колбэк', () async {
    final browser = AuthNativeBrowser();
    var closed = false;

    await browser.open(
      AuthBrowserOpenRequest(
        url: Uri.parse('https://example.com'),
        userAgent: 'ua',
        onLoadStop: (_) {},
        onClosed: () => closed = true,
      ),
    );

    await _sendNativeEvent('onClosed', null);

    expect(closed, isTrue);
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
