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
