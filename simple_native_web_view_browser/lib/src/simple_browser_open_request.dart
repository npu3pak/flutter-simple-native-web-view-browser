import 'simple_browser_cookie.dart';
import 'simple_browser_reopen_policy.dart';
import 'simple_browser_url_bar_mode.dart';

/// Обработчик ошибки загрузки страницы.
typedef SimpleBrowserOnLoadError = void Function(Uri url);

/// Обработчик попытки открыть адрес с кастомной схемой
/// (например, myapp://...). Такие адреса не загружаются в браузере.
typedef SimpleBrowserOnSchemeRedirect = void Function(Uri url);

/// Обработчик успешного завершения загрузки страницы.
typedef SimpleBrowserOnLoadStop = void Function(Uri url);

/// Обработчик закрытия браузера.
typedef SimpleBrowserOnClosed = void Function();

/// Решает, что делать при повторном открытии, когда сессия уже активна.
/// Принимает активный (старый) и новый запросы, возвращает действие.
typedef SimpleBrowserReopenPolicyResolver = SimpleBrowserReopenPolicy Function(
    SimpleBrowserOpenRequest oldRequest, SimpleBrowserOpenRequest newRequest);

/// Параметры открытия браузера.
class SimpleBrowserOpenRequest {
  /// Стартовый адрес.
  final Uri url;

  /// Пользовательский агент (User-Agent) WebView.
  /// Если не задан — используется стандартный пользовательский агент
  /// платформы.
  final String? userAgent;

  /// Использовать постоянное хранилище кук.
  final bool usePersistentCookieStore;

  /// Начальные куки, устанавливаемые до загрузки страницы.
  final List<SimpleBrowserCookie> initialCookies;

  /// Режим отображения адресной строки.
  final SimpleBrowserUrlBarMode urlBarMode;

  /// Включает режим отладки WebView: веб-инспектор
  /// (Safari Web Inspector / Chrome DevTools).
  final bool enableDebugging;

  /// Поведение при повторном открытии, когда браузер уже открыт.
  /// Если не задан — применяется полная замена сессии
  /// (SimpleBrowserReopenPolicy.replaceCallbacksAndSettingsAndReload).
  final SimpleBrowserReopenPolicyResolver? reopenPolicy;

  /// Обработчик ошибки загрузки страницы.
  final SimpleBrowserOnLoadError? onLoadError;

  /// Обработчик попытки открыть адрес с кастомной схемой.
  final SimpleBrowserOnSchemeRedirect? onSchemeRedirect;

  /// Обработчик успешного завершения загрузки страницы.
  final SimpleBrowserOnLoadStop? onLoadStop;

  /// Обработчик закрытия браузера.
  final SimpleBrowserOnClosed? onClosed;

  const SimpleBrowserOpenRequest({
    required this.url,
    this.userAgent,
    this.usePersistentCookieStore = true,
    this.initialCookies = const [],
    this.urlBarMode = SimpleBrowserUrlBarMode.hidden,
    this.enableDebugging = false,
    this.reopenPolicy,
    this.onLoadError,
    this.onSchemeRedirect,
    this.onLoadStop,
    this.onClosed,
  });
}
