## 0.2.2

- При детаче движка с открытым браузером Activity завершается
  (onDetachedFromEngine); гарантия onClosed обеспечивается
  fallback-таймером на стороне Dart.

## 0.2.1

- Безопасность: нативная валидация кук (защита от инъекции атрибутов
  при прямом вызове канала), явный запрет mixed content.
- Исправления: `reloadWithCookies` применяет куки к текущему адресу
  страницы (а не к стартовому), защита от краша при обращении к
  уничтоженному WebView, сброс веб-инспектора при повторном открытии
  без отладки, унификация ошибки reloadWithCookies без аргументов.
- Передача initialCookies в Intent JSON-строкой (вместо устаревшего
  getSerializable), launchMode singleTask для BrowserActivity.

## 0.2.0

- Параметр `enableCookiesAndroid`: отключение приёма кук процесса
  (CookieManager.setAcceptCookie), восстановление при закрытии браузера.
- Параметр `allowFileAccess`: управление загрузкой `file://` и файловым
  доступом WebView; жёсткие настройки allowFileAccessFromFileURLs/
  allowUniversalAccessFromFileURLs.
- Безопасность: единственная доставка onSchemeRedirect за сеанс,
  onLoadError только для главного кадра, блокировка недопустимых схем
  в адресной строке.
- Исправление: ложный onClosed при смене темы (uiMode в configChanges),
  защита от пересоздания Activity.

## 0.1.0

- Android-реализация: BrowserActivity (панели инструментов, адресная
  строка, куки, события onLoadStop/onLoadError/onClosed), тема DayNight,
  системные цвета.
