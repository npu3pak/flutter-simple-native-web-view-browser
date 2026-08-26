import 'src/auth_browser_cookie.dart';
import 'src/auth_browser_open_request.dart';
import 'src/simple_native_web_view_browser_platform_interface.dart';

export 'src/auth_browser_cookie.dart';
export 'src/auth_browser_open_request.dart';
export 'src/auth_browser_url_bar_mode.dart';
export 'src/simple_native_web_view_browser_platform_interface.dart'
    show SimpleNativeWebViewBrowserPlatform, MethodChannelSimpleNativeWebViewBrowser;

/// Простой нативный браузер на основе WebView.
class AuthNativeBrowser {
  /// Открывает браузер с параметрами [request].
  Future<void> open(AuthBrowserOpenRequest request) {
    return SimpleNativeWebViewBrowserPlatform.instance.open(request);
  }

  /// Закрывает браузер.
  Future<void> close() {
    return SimpleNativeWebViewBrowserPlatform.instance.close();
  }

  /// Устанавливает [cookies] и перезагружает текущую страницу.
  Future<void> reloadWithCookies(List<AuthBrowserCookie> cookies) {
    return SimpleNativeWebViewBrowserPlatform.instance
        .reloadWithCookies(cookies);
  }
}
