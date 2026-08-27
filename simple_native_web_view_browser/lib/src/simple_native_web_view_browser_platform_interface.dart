import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'simple_browser_cookie.dart';
import 'simple_browser_open_request.dart';
import 'simple_browser_reopen_policy.dart';

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
  Future<void> open(SimpleBrowserOpenRequest request) {
    throw UnimplementedError('open() has not been implemented.');
  }

  /// Закрывает браузер.
  Future<void> close() {
    throw UnimplementedError('close() has not been implemented.');
  }

  /// Устанавливает [cookies] и перезагружает текущую страницу.
  Future<void> reloadWithCookies(List<SimpleBrowserCookie> cookies) {
    throw UnimplementedError('reloadWithCookies() has not been implemented.');
  }
}

/// Реализация через MethodChannel (канал `simple_native_web_view_browser`).
///
/// События браузера (onLoadStop/onLoadError/onClosed) приходят по тому же
/// каналу с нативной стороны и маршрутизируются на колбэки активного
/// [SimpleBrowserOpenRequest].
class MethodChannelSimpleNativeWebViewBrowser
    extends SimpleNativeWebViewBrowserPlatform {
  static const _channel = MethodChannel('simple_native_web_view_browser');

  /// Таймаут ожидания нативного onClosed после close(): если событие
  /// потеряно (например, детач движка), сессия закрывается принудительно.
  final Duration closeFallbackTimeout;

  SimpleBrowserOpenRequest? _activeRequest;
  Timer? _closeFallbackTimer;

  MethodChannelSimpleNativeWebViewBrowser({
    this.closeFallbackTimeout = const Duration(seconds: 5),
  }) {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  @override
  Future<void> open(SimpleBrowserOpenRequest request) async {
    _closeFallbackTimer?.cancel();
    final previous = _activeRequest;
    if (previous != null) {
      final policy = request.reopenPolicy?.call(previous, request) ??
          SimpleBrowserReopenPolicy.replaceCallbacksAndSettingsAndReload;
      switch (policy) {
        case SimpleBrowserReopenPolicy.discard:
          // Сессия и её обработчики сохраняются, запрос отбрасывается.
          return;
        case SimpleBrowserReopenPolicy.replaceCallbacks:
          _activeRequest = request;
          return;
        case SimpleBrowserReopenPolicy.replaceCallbacksAndSettings:
          _activeRequest = request;
          await _invokeReopen('reopenSettings', request);
          return;
        case SimpleBrowserReopenPolicy.replaceCallbacksAndSettingsAndReload:
          _activeRequest = request;
          await _invokeReopen('open', request);
          return;
      }
    }

    _activeRequest = request;
    try {
      await _channel.invokeMethod<void>('open', _openArgs(request));
    } catch (_) {
      _activeRequest = null;
      rethrow;
    }
  }

  /// Вызывает нативный метод для замены сессии; при ошибке активный
  /// запрос сбрасывается (не восстанавливается) — ошибки принадлежат
  /// новой сессии.
  Future<void> _invokeReopen(
    String method,
    SimpleBrowserOpenRequest request,
  ) async {
    try {
      await _channel.invokeMethod<void>(method, _openArgs(request));
    } catch (_) {
      _activeRequest = null;
      rethrow;
    }
  }

  Map<String, Object?> _openArgs(SimpleBrowserOpenRequest request) {
    final enableDebugging = request.enableDebugging && !kReleaseMode;
    if (request.enableDebugging && kReleaseMode) {
      debugPrint('simple_native_web_view_browser: enableDebugging '
          'игнорируется в release-сборке');
    }
    return {
      'url': request.url.toString(),
      'userAgent': request.userAgent,
      'usePersistentCookieStore': request.usePersistentCookieStore,
      'initialCookies': [
        for (final cookie in request.initialCookies) _cookieToMap(cookie),
      ],
      'urlBarMode': request.urlBarMode.name,
      'enableDebugging': enableDebugging,
      'enableCookiesAndroid': request.enableCookiesAndroid,
      'allowFileAccess': request.allowFileAccess,
    };
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
    _scheduleCloseFallback();
  }

  /// Запускает таймер принудительного закрытия сессии на случай, если
  /// нативный onClosed не придёт (детaч движка, потеря события).
  void _scheduleCloseFallback() {
    if (_activeRequest == null) {
      return;
    }
    _closeFallbackTimer?.cancel();
    _closeFallbackTimer = Timer(closeFallbackTimeout, _forceCloseSession);
  }

  void _forceCloseSession() {
    final request = _activeRequest;
    if (request == null) {
      return;
    }
    _activeRequest = null;
    _callSafely(() => request.onClosed?.call());
  }

  @override
  Future<void> reloadWithCookies(List<SimpleBrowserCookie> cookies) async {
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
          _callSafely(() => request?.onLoadStop?.call(url));
        }
      case 'onLoadError':
        final url = Uri.tryParse(call.arguments as String? ?? '');
        if (url != null) {
          _callSafely(() => request?.onLoadError?.call(url));
        }
      case 'onSchemeRedirect':
        final url = Uri.tryParse(call.arguments as String? ?? '');
        if (url != null) {
          _callSafely(() => request?.onSchemeRedirect?.call(url));
        }
      case 'onClosed':
        _closeFallbackTimer?.cancel();
        _activeRequest = null;
        _callSafely(() => request?.onClosed?.call());
    }
  }

  /// Вызывает колбэк приложения, изолируя исключения пользовательского кода
  /// от маршрутизации событий канала.
  void _callSafely(VoidCallback callback) {
    try {
      callback();
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'simple_native_web_view_browser',
      ));
    }
  }

  Map<String, Object?> _cookieToMap(SimpleBrowserCookie cookie) {
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
  Future<void> open(SimpleBrowserOpenRequest request) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> reloadWithCookies(List<SimpleBrowserCookie> cookies) async {}
}
