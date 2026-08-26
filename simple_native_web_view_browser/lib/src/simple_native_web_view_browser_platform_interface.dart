import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'auth_browser_cookie.dart';
import 'auth_browser_open_request.dart';

/// Платформенный интерфейс simple_native_web_view_browser.
/// Реализации:
/// - simple_native_web_view_browser_android;
/// - simple_native_web_view_browser_ios.
abstract class SimpleNativeWebViewBrowserPlatform extends PlatformInterface {
  SimpleNativeWebViewBrowserPlatform() : super(token: _token);

  static final Object _token = Object();

  static SimpleNativeWebViewBrowserPlatform _instance =
      MethodChannelSimpleNativeWebViewBrowser();

  static SimpleNativeWebViewBrowserPlatform get instance => _instance;

  static set instance(SimpleNativeWebViewBrowserPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Открывает браузер с параметрами [request].
  Future<void> open(AuthBrowserOpenRequest request) {
    throw UnimplementedError('open() has not been implemented.');
  }

  /// Закрывает браузер.
  Future<void> close() {
    throw UnimplementedError('close() has not been implemented.');
  }

  /// Устанавливает [cookies] и перезагружает текущую страницу.
  Future<void> reloadWithCookies(List<AuthBrowserCookie> cookies) {
    throw UnimplementedError('reloadWithCookies() has not been implemented.');
  }
}

/// Реализация через MethodChannel (канал `simple_native_web_view_browser`).
///
/// События браузера (onLoadStop/onLoadError/onClosed) приходят по тому же
/// каналу с нативной стороны и маршрутизируются на колбэки активного
/// [AuthBrowserOpenRequest].
class MethodChannelSimpleNativeWebViewBrowser
    extends SimpleNativeWebViewBrowserPlatform {
  static const _channel = MethodChannel('simple_native_web_view_browser');

  AuthBrowserOpenRequest? _activeRequest;

  MethodChannelSimpleNativeWebViewBrowser() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  @override
  Future<void> open(AuthBrowserOpenRequest request) async {
    _activeRequest = request;
    try {
      await _channel.invokeMethod<void>('open', {
        'url': request.url.toString(),
        'userAgent': request.userAgent,
        'usePersistentCookieStore': request.usePersistentCookieStore,
        'initialCookies': [
          for (final cookie in request.initialCookies) _cookieToMap(cookie),
        ],
        'urlBarMode': request.urlBarMode.name,
      });
    } catch (_) {
      _activeRequest = null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
  }

  @override
  Future<void> reloadWithCookies(List<AuthBrowserCookie> cookies) async {
    await _channel.invokeMethod<void>('reloadWithCookies', {
      'cookies': [for (final cookie in cookies) _cookieToMap(cookie)],
    });
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    final request = _activeRequest;
    switch (call.method) {
      case 'onLoadStop':
        final url = Uri.tryParse(call.arguments as String? ?? '');
        if (url != null) {
          request?.onLoadStop?.call(url);
        }
      case 'onLoadError':
        final url = Uri.tryParse(call.arguments as String? ?? '');
        if (url != null) {
          request?.onLoadError?.call(url);
        }
      case 'onClosed':
        _activeRequest = null;
        request?.onClosed?.call();
    }
  }

  Map<String, Object?> _cookieToMap(AuthBrowserCookie cookie) {
    return {
      'name': cookie.name,
      'value': cookie.value,
      if (cookie.domain != null) 'domain': cookie.domain,
      if (cookie.path != null) 'path': cookie.path,
      'isSecure': cookie.isSecure,
      'isHttpOnly': cookie.isHttpOnly,
    };
  }
}

/// Мок для тестов.
class MockSimpleNativeWebViewBrowserPlatform
    extends SimpleNativeWebViewBrowserPlatform {
  @override
  Future<void> open(AuthBrowserOpenRequest request) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> reloadWithCookies(List<AuthBrowserCookie> cookies) async {}
}
