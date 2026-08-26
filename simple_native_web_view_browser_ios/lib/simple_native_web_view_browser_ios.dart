import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

/// Реализация simple_native_web_view_browser для iOS.
class SimpleNativeWebViewBrowserIOS extends SimpleNativeWebViewBrowserPlatform {
  /// Вызывается DartPluginRegistrant при старте приложения.
  static void registerWith() {
    SimpleNativeWebViewBrowserPlatform.instance =
        MethodChannelSimpleNativeWebViewBrowser();
  }
}
