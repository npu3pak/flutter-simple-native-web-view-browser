import 'auth_browser_cookie.dart';
import 'auth_browser_url_bar_mode.dart';

/// Обработчик ошибки загрузки страницы.
typedef AuthBrowserOnLoadError = void Function(Uri url);

/// Обработчик успешного завершения загрузки страницы.
typedef AuthBrowserOnLoadStop = void Function(Uri url);

/// Обработчик закрытия браузера.
typedef AuthBrowserOnClosed = void Function();

/// Параметры открытия браузера.
class AuthBrowserOpenRequest {
  /// Стартовый адрес.
  final Uri url;

  /// Пользовательский агент (User-Agent) WebView.
  final String userAgent;

  /// Использовать постоянное хранилище кук.
  final bool usePersistentCookieStore;

  /// Начальные куки, устанавливаемые до загрузки страницы.
  final List<AuthBrowserCookie> initialCookies;

  /// Режим отображения адресной строки.
  final AuthBrowserUrlBarMode urlBarMode;

  /// Обработчик ошибки загрузки страницы.
  final AuthBrowserOnLoadError? onLoadError;

  /// Обработчик успешного завершения загрузки страницы.
  final AuthBrowserOnLoadStop? onLoadStop;

  /// Обработчик закрытия браузера.
  final AuthBrowserOnClosed? onClosed;

  const AuthBrowserOpenRequest({
    required this.url,
    required this.userAgent,
    this.usePersistentCookieStore = true,
    this.initialCookies = const [],
    this.urlBarMode = AuthBrowserUrlBarMode.hidden,
    this.onLoadError,
    this.onLoadStop,
    this.onClosed,
  });
}
