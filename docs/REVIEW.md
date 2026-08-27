# REVIEW: анализ безопасности, флоу, качества кода и документации плагина simple_native_web_view_browser

> Полный технический аудит плагина `simple_native_web_view_browser` (v0.2.0).
> Дата: 2026-08-27. Язык: русский.

---

## 1. Методология и охват

### 1.1. Что проверялось

Проведён статический анализ всех исходников плагина, его тестов и документации,
а также кода потребителя в основном приложении (`lib/auth/...`).

| Компонент | Файлы |
|---|---|
| Dart API (публичный слой) | `simple_native_web_view_browser/lib/*.dart` (6 файлов) |
| Платформенный интерфейс | `lib/src/simple_native_web_view_browser_platform_interface.dart` |
| Android (Kotlin) | `BrowserActivity.kt`, `SimpleNativeWebViewBrowserPlugin.kt`, манифест, layout, styles, gradle |
| iOS (Swift) | `BrowserViewController.swift`, `SimpleNativeWebViewBrowserPlugin.swift`, podspec |
| Тесты | 2 unit-набора (23 теста), 2 integration-набора, тест демо-экрана |
| Документация | `README.md`, `docs/requirements.md`, `CHANGELOG.md` × 3, README платформенных пакетов |
| Потребитель | `/mypet-flutter/lib/auth/logic/utils/web_session/auth_embedded_browser.dart` |

### 1.2. Способы проверки

- Полное чтение исходников (Dart, Kotlin, Swift, XML, gradle, podspec).
- Проверка корректности запуска: `flutter analyze` в четырёх пакетах
  (ядро, android, ios, example) — **0 замечаний**;
  `flutter test` в `simple_native_web_view_browser` — **23/23 зелёных**.
- Сопоставление реализованного поведения с `docs/requirements.md` и `README.md`.
- Анализ атакующих поверхностей: MethodChannel, Intent-входы, WebView-настройки,
  cookie-манипуляции, обработка схем, жизненный цикл.

### 1.3. Шкалы оценок

**Severity** (степень риска):

- **Critical** — эксплуатация тривиальна, ущерб значителен (данные, сессии, репутация).
- **High** — существенный ущерб при конкретных условиях.
- **Medium** — заметный риск или нарушение обещаний API при ограниченных условиях.
- **Low** — незначительный риск при специфических условиях.
- **Info** — наблюдение / улучшение без прямого риска.

**Priority** (очередность исправления):

- **P0** — немедленно; **P1** — в ближайшем релизе; **P2** — планово; **P3** — по возможности.

---

## 2. Сводка

Плагин написан аккуратно и с явным вниманием к безопасности: валидация кук на
Dart-уровне, блокировка `file://` по умолчанию, гейт `enableDebugging` по
`kReleaseMode`, неэкспортируемая Activity, отсутствие JS-мостов, аккуратная
работа с жизненным циклом (защита от ложного `onClosed` при смене конфигурации,
гарантированный результат `open()` при неудачной презентации на iOS).
Покрытие тестами — сильное, особенно integration-уровня.

**Найденных проблем: 12, из них Medium — 3 (S1, S2, S7), Low — 6 (S3–S6, S8, S9),
Info — 3 (S10–S12).**
Критических и High-уязвимостей не обнаружено. Medium-находки: S1/S2 — cookie-
семантика Android (эксплуатация требует модифицированного процесса либо
специфических сценариев), S7 — риск краша при обращении к destroyed WebView
в узком окне «навигация в полёте + закрытие браузера».

| ID | Severity | Priority | Кратко |
|---|---|---|---|
| S1 | Medium | P1 | Нативная валидация кук отсутствует (защита только на Dart) |
| S2 | Medium | P1 | «Эфемерный» режим кук на Android не изолирует куки сеанса |
| S3 | Low | P2 | `enableDebugging` на Android не сбрасывается после закрытия |
| S4 | Low | P2 | Схемы `data:`/`about:`/`blob:` загружаются без ограничений (не документировано) |
| S5 | Low | P1 | iOS: ложные `onLoadError` при отмене навигации (`NSURLErrorCancelled`) |
| S6 | Low | P2 | Исключения пользовательских колбэков не защищены (Dart) |
| S7 | Medium | P1 | Android: риск обращения к destroyed WebView → потенциальный краш |
| S8 | Low | P2 | `getSerializable` deprecated; риск `TransactionTooLargeException` |
| S9 | Low | P2 | Гонка двойного `open()` → две `BrowserActivity` |
| S10 | Info | P2 | Параметры WebView не зафиксированы явно (mixed content и др.) |
| S11 | Info | P2 | User-Agent не санитизируется (CRLF) |
| S12 | Info | P3 | Потеря событий при детаче плагина с открытым браузером |

Общая оценка: **код готов к использованию**, но перед переносом в production
рекомендуется закрыть S1, S2, S5, S7 и обновить документацию (S2, S4).

---

## 3. Security Review

### 3.1. S1 — Отсутствие нативной валидации кук (защита только на Dart-уровне)

- **Severity:** Medium | **Priority:** P1
- **Локация:** `simple_browser_cookie.dart:27-65` (единственная валидация);
  `BrowserActivity.kt:430-451` (`setCookies` строит строку без проверок);
  `BrowserViewController.swift:632-646` (`makeCookie` полагается на `HTTPCookie`).
- **Описание.** Валидация символов `;`, `,` и управляющих символов выполняется
  только в конструкторе `SimpleBrowserCookie`. Нативные стороны **не** перепроверяют
  данные, пришедшие по MethodChannel: Kotlin собирает строку
  `"$name=$value; Path=$path; Domain=$domain"` как есть, Swift делегирует проверку
  `HTTPCookie(properties:)`.
- **Воздействие.** Любой код в процессе приложения (собственный модуль, другой
  плагин, код, скомпрометированный через иной вектор) может вызвать канал
  `simple_native_web_view_browser` напрямую с произвольным map-аргументом и обойти
  Dart-валидацию. На Android это даёт **инъекцию атрибутов куки**
  (`; Domain=evil.com; Path=/; Expires=...`) в общее cookie-хранилище процесса —
  вплоть до записи кук на сторонние домены. На iOS `HTTPCookie(properties:)`
  валидирует значения по RFC и возвращает `nil` для недопустимых — платформа
  защищена встроенными средствами, но асимметрия сохраняется.
- **Рекомендация.** Перенести валидацию на нативные стороны (reject `;`, `,`,
  CR/LF и управляющих символов в `name`/`value`/`domain`/`path`, reject пустого
  `name`): в `BrowserActivity.setCookies` и в `BrowserViewController.makeCookie`
  перед построением строки/словаря. Плюс: отбрасывать куку с `Domain`, не
  совпадающим с хостом загрузки, если домен не задан явно.

### 3.2. S2 — «Эфемерный» режим кук на Android не изолирует куки сеанса

- **Severity:** Medium | **Priority:** P1
- **Локация:** `BrowserActivity.kt:293-303` (`prepareCookiesAndLoad`);
  `README.md:180-187`; `docs/requirements.md:66-70, 89`.
- **Описание.** При `usePersistentCookieStore=false` выполняется
  `CookieManager.removeAllCookies` + `flush` **на момент открытия**. Затем
  `initialCookies` и куки, выставленные сервером за время сеанса, пишутся в
  **общее** хранилище процесса и **остаются там после закрытия браузера**
  (очистка произойдёт только при следующем открытии в эфемерном режиме).
- **Воздействие.** Нарушение обещания API «куки не сохраняются после закрытия
  браузера»: на Android куки эфемерного сеанса переживают закрытие, доступны
  другим WebView процесса и «протекают» в следующий персистентный сеанс.
  На iOS `WKWebsiteDataStore.nonPersistent()` работает корректно — поведение
  платформ различается. Дополнительно `removeAllCookies` при открытии сносит
  сеансы **всех** WebView приложения (это ограничение документировано в
  requirements.md 6.1, но не в README).
- **Рекомендация.** Либо изменить документацию (README/requirements) с точным
  описанием семантики Android, либо изменить поведение: например, документировать
  эфемерный режим как «очистка общего хранилища при открытии» и рекомендовать
  для настоящей изоляции отдельный WebView-профиль. Также рассмотреть очистку
  только кук, установленных плагином (по имени/домену) в `onDestroy`.

### 3.3. S3 — `enableDebugging` на Android не сбрасывается после закрытия

- **Severity:** Low | **Priority:** P2
- **Локация:** `BrowserActivity.kt:90-93` (в `onCreate` вызов только в ветке
  `if (enableDebugging)`); `BrowserActivity.kt:340` (в `applyReopenSettings`
  значение применяется в обе стороны — корректно); `platform_interface.dart:108-112`
  (гейт `kReleaseMode` в Dart — корректно).
- **Описание.** `WebView.setWebContentsDebuggingEnabled(true)` — глобальный для
  процесса флаг. После сеанса с `enableDebugging=true` и закрытия браузера новый
  `open` с `enableDebugging=false` **не выключает** инспектор (в `onCreate`
  отсутствует ветка `else`), флаг остаётся активным до смерти процесса.
  В release-сборках Dart не передаст `true` (гейт `kReleaseMode`), поэтому риск
  ограничен debug-сборками, но поведение противоречит ожиданию «значение
  применяется ко всем WebView приложения» (README:262).
- **Рекомендация.** В `onCreate` всегда вызывать
  `WebView.setWebContentsDebuggingEnabled(enableDebugging)` (не только при `true`).
  В `onDestroy` можно возвращать `false` (с осторожностью — флаг общий для процесса).

### 3.4. S4 — Схемы `data:`/`about:`/`blob:` загружаются без ограничений

- **Severity:** Low | **Priority:** P2
- **Локация:** `BrowserActivity.kt:390-396`; `BrowserViewController.swift:246-252`;
  `BrowserActivity.kt:250-264` / `BrowserViewController.swift:439-451`
  (адресная строка принимает `data:` URL).
- **Описание.** Список загружаемых схем включает `data`, `about`, `blob` сверх
  `http(s)`. Страница может навигироваться на `data:text/html,...` без попадания
  в `onSchemeRedirect` (схема «загружаемая»), что открывает поверхность для
  фишинговых/спуфинговых страниц внутри «доверенного» браузера. `data:` URL можно
  ввести и в адресной строке. Отметка: использование `data:` намеренно —
  интеграционные тесты (JS-редирект) и демо (`_openRedirectDemo`) опираются на
  `Uri.dataFromString`.
- **Рекомендация.** Задокументировать это поведение как ограничение (раздел
  README/requirements); при необходимости вынести список схем в параметр запроса
  или ограничить `data:` только в debug.

### 3.5. S5 — iOS: ложные `onLoadError` при отмене навигации

- **Severity:** Low | **Priority:** P1
- **Локация:** `BrowserViewController.swift:544-579` (`handleNavigationError`
  не фильтрует `NSURLErrorCancelled`, код −999).
- **Описание.** Когда пользователь прерывает загрузку (нажал «Обновить»,
  перешёл по ссылке, закрыл браузер в момент навигации), WKWebView вызывает
  `didFail`/`didFailProvisionalNavigation` с `NSURLErrorCancelled`. Код отправляет
  `onLoadError` с адресом неудавшейся навигации, хотя ошибки не было.
- **Воздействие.** Приложение получает ложное событие ошибки. В потоке
  аутентификации (потребитель `auth_embedded_browser.dart:31-33` подписан на
  `onLoadError`) это может привести к неверному срабатыванию обработчика
  редиректа и закрытию браузера на совпадающем URL. На Android аналогичная
  проблема не воспроизводится (`onReceivedError` на отмену не приходит).
- **Рекомендация.** В `handleNavigationError` игнорировать
  `error.code == NSURLErrorCancelled` (и, опционально, фильтровать `error` при
  активной новой навигации).

### 3.6. S6 — Исключения пользовательских колбэков не защищены

- **Severity:** Low | **Priority:** P2
- **Локация:** `platform_interface.dart:139-161` (`_handleNativeEvent`).
- **Описание.** Вызовы `request?.onLoadStop?.call(url)` и аналогичные выполняются
  без `try/catch`. Исключение в колбэке приложения уходит в текущую Zone как
  необработанная асинхронная ошибка: в debug — red screen/пауза в отладчике,
  в release — потеря события и разрыв обработки последующих сообщений канала.
- **Рекомендация.** Обернуть каждый вызов колбэка в `try/catch`
  (с `FlutterError.reportError`), чтобы ошибка пользовательского кода не рушила
  маршрутизацию событий.

### 3.7. S7 — Android: риск обращения к destroyed WebView → краш

- **Severity:** Medium | **Priority:** P1
- **Локация:** `BrowserActivity.kt:121-149` (колбэки `WebViewClient` вызывают
  `updateChromeState()` → `webView.canGoBack()`/`title`/`url`), `BrowserActivity.kt:266-272`,
  `onDestroy` `BrowserActivity.kt:455-470` (`webView.destroy()` без сброса
  `webViewClient`).
- **Описание.** Если навигация находится в полёте, когда активность завершается
  (крестик / «Назад» / `close()`), колбэки `WebViewClient` могут прийти **после**
  `destroy()`. `updateChromeState()` обращается к уничтоженному `WebView`
  (методы `canGoBack()`, `canGoForward()`, `getTitle()`, `getUrl()`), что
  выбрасывает `IllegalStateException: "WebView was destroyed"` на main-потоке.
- **Воздействие.** Некрасивое падение приложения в узком окне (загрузка ещё идёт,
  браузер закрыт). Вероятность невысока, но сценарий реальный (медленная сеть +
  быстрое закрытие).
- **Рекомендация.** Ввести флаг `destroyed` (выставляемый в `onDestroy` перед
  `destroy()`), проверять его в начале `updateChromeState()` и колбэков; перед
  `destroy()` сбрасывать `webView.webViewClient = null`.

### 3.8. S8 — `getSerializable` deprecated + риск `TransactionTooLargeException`

- **Severity:** Low | **Priority:** P2
- **Локация:** `BrowserActivity.kt:79-82`; `SimpleNativeWebViewBrowserPlugin.kt:140-147`.
- **Описание.** `Bundle.getSerializable` устарел с API 33. Куки передаются в
  `Intent` через `ArrayList` — при большом объёме (десятки КБ) возможен
  `TransactionTooLargeException` на `startActivity` (лимит транзакции Binder
  ~1 МБ на Intent).
- **Рекомендация.** Перейти на `BundleCompat.getSerializableExtra` / типизированный
  API; либо передавать куки сериализованной строкой (JSON) — компактнее и
  безопаснее по размеру; при необходимости — через статическое хранилище с
  генерацией одноразового ключа.

### 3.9. S9 — Гонка двойного `open()` → две `BrowserActivity`

- **Severity:** Low | **Priority:** P2
- **Локация:** `SimpleNativeWebViewBrowserPlugin.kt:114-127` (замена сессии только
  если `BrowserActivity.current != null`); `platform_interface.dart:60-90`.
- **Описание.** Два подряд вызова `open()` из Dart: первый ещё не создал
  Activity (создание асинхронно, `onCreate` не отработал), `current == null` —
  второй вызов выполняет `startActivity` повторно. Возникают две `BrowserActivity`:
  `current` перезаписывается последней созданной, первая остаётся в back stack,
  `onClosed` доставляется только от последней.
- **Воздействие.** Низкая вероятность (нужны два `open` в одном кванте времени),
  но последствия заметны: «лишняя» активность на экране и потеря события.
- **Рекомендация.** Задать `android:launchMode="singleInstance"` для
  `BrowserActivity` + флаг «создание в процессе» в плагине, либо на стороне Dart
  сериализовать вызовы `open` (очередь).

### 3.10. S10 — Параметры WebView не зафиксированы явно

- **Severity:** Info | **Priority:** P2
- **Локация:** `BrowserActivity.kt:101-104`; `BrowserViewController.swift:81-101`.
- **Описание.** Положительные моменты подтверждены: JS включён безусловно, но
  JS-мост (`addJavaScriptInterface`) **отсутствует**, никакой код на нативной
  стороне не инжектит JS из сети (`evaluateJavascript`/`runJavaScript` не
  используются). `allowFileAccessFromFileURLs` и `allowUniversalAccessFromFileURLs`
  принудительно `false` (`BrowserActivity.kt:417-421`) — отлично.
  При этом `mixedContentMode` не задан явно (дефолт `MIXED_CONTENT_NEVER_ALLOW`
  на targetSdk ≥ 21 — корректный, но не зафиксированный); `domStorageEnabled=true`
  оставляет localStorage доступным даже при `enableCookiesAndroid=false`.
- **Рекомендация.** Явно выставить `mixedContentMode = MIXED_CONTENT_NEVER_ALLOW`;
  задокументировать, что JS нельзя отключить и что localStorage не зависит от
  `enableCookiesAndroid`.

### 3.11. S11 — User-Agent без санитизации (CRLF)

- **Severity:** Info | **Priority:** P2
- **Локация:** `BrowserActivity.kt:98-100, 333-338`; `BrowserViewController.swift:89-91, 181-185`.
- **Описание.** `userAgent` — произвольная строка приложения. CR/LF в UA
  теоретически позволяют «дописать» заголовки запроса; риск самовведённый
  (приложение само передаёт UA), но санитизация тривиальна.
- **Рекомендация.** Отбрасывать CR/LF в `userAgent` при передаче в WebView либо
  валидировать в `SimpleBrowserOpenRequest`.

### 3.12. S12 — Потеря событий при детаче плагина с открытым браузером

- **Severity:** Info | **Priority:** P3
- **Локация:** `SimpleNativeWebViewBrowserPlugin.kt:39-42` (`onDetachedFromEngine`
  обнуляет канал, но не завершает `BrowserActivity`); `sendEvent` (тихий no-op);
  Dart `_activeRequest` (`platform_interface.dart:53`).
- **Описание.** При детаче Flutter-движка (пересоздание Activity, фоновое
  уничтожение) события браузера молча теряются, а `_activeRequest` остаётся
  «висеть» до следующего `open` (который корректно пересоздаст сессию).
- **Рекомендация.** В `onDetachedFromEngine` вызывать
  `BrowserActivity.current?.finish()`. В Dart — дополнительно сбрасывать
  `_activeRequest` в `close()`.

### 3.13. Подтверждённые сильные практики

- `BrowserActivity` — `android:exported="false"`, без intent-filter
  (`AndroidManifest.xml:4-10`); вход только через собственный плагин.
- `file://` заблокирован по умолчанию на обеих платформах; файловые флаги
  `allowFileAccessFromFileURLs`/`allowUniversalAccessFromFileURLs` принудительно
  выключены даже при `allowFileAccess=true`.
- `enableDebugging` не попадает в release-сборки (`kReleaseMode`-гейт в Dart).
- Плагин не добавляет `usesCleartextTraffic`, ATS-исключений и не ослабляет
  сетевые политики приложения (README:359-366 — корректная документация).
- Валидация кук на Dart + развёрнутые юнит-тесты (защита от инъекции атрибутов).
- iOS: `HTTPCookie(properties:)` сам отклоняет недопустимые куки.
- `onLoadError` на Android — только для главного кадра (`BrowserActivity.kt:137-139`).
- Единственная доставка `onSchemeRedirect` за сеанс на обеих платформах
  (защита от дублирования событий при множественных путях перехвата).
- `allowFileAccess` гейтится в `isLoadableScheme` — при `false` схема `file`
  не загружается и уходит в `onSchemeRedirect`.
- Нет логирования секретов: по каналу передаются только URL и куки, запрошенные
  приложением; плагин ничего не пишет в логи (кроме debug-предупреждения
  `platform_interface.dart:110-112`).

---

## 4. Flow Analysis (анализ флоу)

### 4.1. Флоу «Открытие браузера» (первый `open`)

```
Dart: SimpleNativeBrowser.open(request)
  └─ Platform.instance.open(request)  [MethodChannelSimpleNativeWebViewBrowser]
       ├─ _activeRequest == null? НЕТ → см. 4.2 (reopen)
       │  _activeRequest = request
       │  channel.invokeMethod('open', args)          // url, userAgent, cookies, ...
       │       │ успех → future resolved
       │       └ ошибка → _activeRequest = null; rethrow
       ▼
Native Android: onMethodCall('open')
  ├─ BrowserActivity.current != null → current.replace(...)   // 4.2 (нативный дубль)
  ├─ activity == null → error 'no_activity'
  └─ startActivity(BrowserActivity, extras)
       ▼
BrowserActivity.onCreate
  ├─ current = this
  ├─ чтение extras (url, UA, cookies, urlBarMode, enableDebugging, ...)
  ├─ setWebContentsDebuggingEnabled(enableDebugging)          // только если true [S3]
  ├─ webView.settings: JS=on, DOM storage=on, UA (если задан)
  ├─ applyCookieAcceptance()   // enableCookiesAndroid → setAcceptCookie [S1/S2]
  ├─ applyFileAccessSettings() // file-флаги
  ├─ WebViewClient (перехват схем, onPageStarted/Finished/onReceivedError)
  ├─ setupChrome(), setupBackCallback()
  └─ prepareCookiesAndLoad()
       ├─ !usePersistentCookieStore → CookieManager.removeAllCookies+flush [S2]
       └─ setCookies(initialCookies) → loadInitialPage()
             ├─ схема загружаемая → webView.loadUrl(url)
             └─ кастомная схема → notifySchemeRedirect(url)   // без загрузки

Native iOS: handle('open')
  ├─ browserViewController != nil → replace(...)              // 4.2
  ├─ topViewController не найден/занят → error 'no_view_controller'
  └─ present(BrowserViewController, fullScreen)
       ▼
BrowserViewController.viewDidLoad
  ├─ websiteDataStore: default() | nonPersistent()            // true эфемерность
  ├─ customUserAgent (если задан), isInspectable (iOS 16.4+)
  ├─ WKNavigationDelegate + WKUIDelegate
  └─ setCookies(initialCookies) → loadInitialPage()
        ├─ схема загружаемая → webView.load(URLRequest)
        └─ кастомная схема → notifySchemeRedirect             // без загрузки
```

Замечания по флоу:

- **Порядок «куки → загрузка» гарантирован на обеих платформах** (загрузка
  страницы начинается только после завершения установки кук) — соответствует
  требованиям 4.7.1.
- На iOS `setCookies` использует `DispatchGroup`; при невызове completion
  (маловероятно) загрузка зависла бы — на практике completion вызывается всегда.
- На Android флаг «создание Activity в процессе» отсутствует → гонка S9.

### 4.2. Флоу «Повторное открытие» (reopen-политики)

Повторный `open` при активной сессии в Dart:

```
open(request):
  previous = _activeRequest
  policy = request.reopenPolicy?.(previous, request)
           ?? replaceCallbacksAndSettingsAndReload
  switch (policy):
    discard                     → return                    // ничего не меняется
    replaceCallbacks            → _activeRequest = request  // только колбэки
    replaceCallbacksAndSettings → _activeRequest = request
                                 channel('reopenSettings')  // настройки без reload
    ...AndReload                → _activeRequest = request
                                 channel('open')            // нативный replace
  при ошибке канала → _activeRequest = null, rethrow         // сессия «ничья»
```

Нативно:

- Android: `open` при `BrowserActivity.current != null` → `current.replace(...)`
  (применяет настройки, `setCookies(initialCookies)`, `loadUrl(newUrl)`);
  `reopenSettings` — только настройки + `setCookies`, без навигации.
- iOS: `open` при `browserViewController != nil` → `replace(...)`; аналогично
  `reopenSettings`. Обе ветки возвращают результат через `result` только после
  завершения установки кук.

Замечания:

- **Колбэки старой сессии отвязываются** сразу в Dart (`_activeRequest` заменён) —
  события приходят только новому запросу. Это осознанный дизайн, покрытый
  юнит-тестами (`reopenPolicy: replaceCallbacks...`).
- **«Stale» события**: нативные события, сгенерированные до замены (например,
  `onPageFinished` старой страницы), после замены маршрутизируются **новому**
  запросу. Приложение должно быть готово к `onLoadStop` со старым URL.
- При `discard` канал не вызывается; отброшенный запрос никогда не получает
  событий (покрыто тестом).
- При ошибке канала во время reopen `_activeRequest` сбрасывается — старое
  «нативное» окно остаётся, но колбэки отвязаны; следующий `open` создаст
  сессию заново (на Android — replace, на iOS — replace). Поведение покрыто
  тестом `полная замена при ошибке канала...`.

### 4.3. Флоу «События и маршрутизация»

```
Native → channel.invokeMethod('onLoadStop'|'onLoadError'|'onSchemeRedirect'|'onClosed')
Dart: _handleNativeEvent(call)
  ├─ onLoadStop     → Uri.tryParse(args) → request?.onLoadStop?(url)
  ├─ onLoadError    → Uri.tryParse(args) → request?.onLoadError?(url)
  ├─ onSchemeRedirect → Uri.tryParse(args) → request?.onSchemeRedirect?(url)
  └─ onClosed       → _activeRequest = null; request?.onClosed?()
```

Источники событий:

| Событие | Android | iOS |
|---|---|---|
| `onLoadStop` | `onPageFinished` (main frame) | `didFinish` |
| `onLoadError` | `onReceivedError` (только main frame); кастомная схема → `onSchemeRedirect` | `didFail` / `didFailProvisionalNavigation`; кастомная схема → `onSchemeRedirect`; **не фильтруется `NSURLErrorCancelled` [S5]** |
| `onSchemeRedirect` | `shouldOverrideUrlLoading` (только top-level), `onReceivedError` с кастомной схемой, стартовый URL, `submitAddress` | `decidePolicyFor` (все фреймы), `didReceiveServerRedirectForProvisionalNavigation`, ошибка с кастомной схемой, стартовый URL |
| `onClosed` | `onDestroy` при `!isChangingConfigurations` (один раз) | `dismiss` completion / `closeFromDart` (один раз) |

Замечания:

- **Одноразовая доставка `onSchemeRedirect`** за сеанс (флаг
  `schemeRedirectNotified`, сбрасывается при reopen). Защищает от дублей одного
  редиректа (покрыто integration-тестом «302-редирект»), но **молча отбрасывает
  второй редирект** в рамках того же сеанса — приложение, не закрывшее браузер
  после первого редиректа, не получит второго. Требует документации (см. 6).
- **Асимметрия subframe**: iOS перехватывает навигации с кастомной схемой во
  всех фреймах (`decidePolicyFor` без проверки `targetFrame`), Android — только
  в главном. На Android попытка iframe уйти на `demoapp://...` тихо блокируется
  WebView без события приложению.
- **`onClosed` на Android** — только при настоящем закрытии: при пересоздании
  Activity (config change) событие не отправляется (`isChangingConfigurations`).
  Перечень `configChanges` в манифесте покрывает основные повороты/темы.
- Потребитель (`auth_embedded_browser.dart:39-49`) подписан на все три
  навигационных события с защитой `_isRedirectHandled` — корректная схема,
  но не защищает от ложного `onLoadError` [S5].

### 4.4. Флоу «Закрытие браузера»

```
Способы закрытия:
  1. Крестик (iOS closeButton / Android closeButton) → finish()/closeFromDart()
  2. Метод close() из Dart → channel('close')
  3. Системная кнопка «Назад» (Android onBackPressed → finish при !canGoBack)
  4. (iOS) dismiss не доступен — fullScreen без свайпа

Android: finish() → onDestroy
  ├─ current === this → current = null
  ├─ !isChangingConfigurations → notifyClosed() → channel('onClosed')
  ├─ восстановление CookieManager.setAcceptCookie(previousAcceptCookie) [S1]
  ├─ javaScriptEnabled=false; removeAllViews; destroy()
  └─ риск: колбэки WebViewClient после destroy → [S7]

iOS: closeFromDart()
  ├─ guard !isClosing
  ├─ presentingViewController != nil → dismiss { notifyClosed() }
  └─ else → notifyClosed() сразу
       notifyClosed(): guard !closedNotified → channel('onClosed'); onClosed?()
  └─ onClosed → plugin: browserViewController = nil  (освобождение)
```

Замечания:

- Двойное закрытие безопасно: `isClosing`/`closedNotified` (iOS),
  `closedNotified` (Android); покрыто тестом «повторное закрытие и повторное
  открытие».
- Dart `close()` не сбрасывает `_activeRequest` самостоятельно — полагается на
  `onClosed` (см. S12). Если `onClosed` по какой-то причине не придёт,
  `_activeRequest` останется; следующий `open` корректно пересоздаст сессию.
- **Восстановление приёма кук** (`enableCookiesAndroid`): предыдущее значение
  сохраняется в `previousAcceptCookie` при первом применении и восстанавливается
  в `onDestroy`. Edge-случай: если между двумя сеансами значение процесса менял
  другой код, восстановление вернёт сохранённое (старое) значение.

### 4.5. Флоу «Куки»

```
initialCookies: Dart (валидация) → канал → native:
  Android: setCookies(): для каждой куки
    cookieString = "name=value; Path=path; Domain=host|domain[; Secure][; HttpOnly]"
    CookieManager.setCookie(url, cookieString) + flush
  iOS: setCookies(): DispatchGroup → httpCookieStore.setCookie(HTTPCookie)
       (HTTPCookie валидирует; недопустимая кука тихо пропускается)

reloadWithCookies: тот же механизм, затем webView.reload()

usePersistentCookieStore=false:
  Android: removeAllCookies + flush при открытии; куки сеанса остаются в общем
           хранилище после закрытия [S2]
  iOS:     WKWebsiteDataStore.nonPersistent() — истинная эфемерность

enableCookiesAndroid=false (Android):
  setAcceptCookie(false) для процесса; восстановление в onDestroy
```

Замечания:

- **`reloadWithCookies` таргетит хост изначального URL** (`this.url`), а не
  текущего: после навигации/редиректа на другой домен куки установятся для
  исходного хоста и не применятся к открытой странице. Одинаковое поведение
  на обеих платформах — но это функциональный пробел (см. 5.1).
- **`isSecure` + http**: Secure-кука для http-URL молча отбрасывается платформой
  (ожидаемо, но не документировано).
- При `enableCookiesAndroid=false` localStorage всё равно работает (S10) —
  «отключение кук» не означает полной изоляции хранилища.

### 4.6. Флоу «Кастомные схемы» (все точки перехвата)

```
Попытка открыть myapp://... (клик, JS, 302, стартовый URL, адресная строка)

Android:
  1. shouldOverrideUrlLoading (top-level) → notifySchemeRedirect + true (блок)
  2. onReceivedError с ERR_UNKNOWN_URL_SCHEME и кастомной схемой → notifySchemeRedirect
  3. loadInitialPage(): схема не загружаемая → notifySchemeRedirect (без loadUrl)
  4. submitAddress(): схема не загружаемая → notifySchemeRedirect
  5. iframe-навигация на кастомную схему — не перехватывается (асимметрия, 4.3)

iOS:
  1. decidePolicyFor (все фреймы) → notifySchemeRedirect + .cancel
  2. didReceiveServerRedirectForProvisionalNavigation → notifySchemeRedirect + stopLoading
  3. handleNavigationError с кастомной схемой failingUrl → notifySchemeRedirect
  4. loadInitialPage(): → notifySchemeRedirect (без load)
  5. addressBarSubmitted: URL без валидации схемы, но блокируется decidePolicyFor

Все пути сходятся в notifySchemeRedirect с флагом однократности.
```

Замечания:

- Многоточечность перехвата оправдана: разные сценарии (302-редирект, JS,
  отказ навигации) приходят разными путями; флаг однократности убирает дубли
  (покрыто integration-тестами).
- Событие `onSchemeRedirect` НЕ доставляется, если предыдущее уже было
  обработано в текущем сеансе — для потоков с несколькими редиректами
  требуется закрытие/переоткрытие браузера (см. 4.3).

---

## 5. Качество кода (Code Quality)

### 5.1. Функциональные пробелы и асимметрия платформ

1. **`reloadWithCookies` использует хост изначального, а не текущего URL**
   (`BrowserActivity.kt:432`, `BrowserViewController.swift:637`). После перехода
   страницы на другой домен куки «не догоняют» текущий хост. Рекомендация:
   использовать `webView.url` (текущий) с фолбэком на изначальный.
2. **Разная обработка ошибок аргументов**: Android `reloadWithCookies` при
   отсутствии `cookies` молча перезагружает страницу без кук
   (`SimpleNativeWebViewBrowserPlugin.kt:171`), iOS возвращает
   `invalid_arguments`. Асимметрия API — стоит унифицировать.
3. **iOS не фильтрует `NSURLErrorCancelled`** (S5) — расхождение с Android по
   качеству событий.
4. **Односторонний сброс `enableDebugging` на Android** (S3) — расхождение
   с iOS, где `isInspectable` применяется в обе стороны при reopen.
5. **Subframe-навигации на кастомные схемы**: iOS сообщает приложению, Android —
   нет (см. 4.3).

### 5.2. Dart

- Структура пакета корректна: публичный API + `src/`, экспорт только нужных
  сущностей, `plugin_platform_interface` с токеном и `Mock`-реализацией для тестов.
- Полиморфная схема reopen-политик через enum + резолвер — чисто и покрыто
  тестами.
- `_cookieToMap`/`_openArgs` собирают аргументы идемпотентно; `enableDebugging`
  гейтится `kReleaseMode` — хорошо.
- Недочёты:
  - `_handleNativeEvent` без защиты исключений колбэков (S6).
  - `_activeRequest` — единственная глобальная точка состояния: не сбрасывается
    в `close()` (S12), возможна гонка при последовательных `open` (S9).
  - Русскоязычные док-комментарии — консистентно, но нестандартно для
    публикуемых пакетов (актуально только если пакет станет публичным).
  - Отсутствуют `toString`/`==` у `SimpleBrowserOpenRequest`/`SimpleBrowserCookie`
    (не требуется, но удобно для отладки).

### 5.3. Android (Kotlin)

- Хорошая организация: `BrowserActivity` самодостаточна, плагин — тонкая
  обвязка канала. Жизненный цикл продуман: `current`-static чистится в
  `onDestroy`, `notifyClosed` одноразовый, защита от config-change.
- `configChanges` в манифесте покрывает поворот/темы — браузер не пересоздаётся
  на лету (сознательное решение, задокументировано в CHANGELOG).
- Недочёты:
  - Placeholder-идентификаторы: `namespace = ru.example...`, gradle
    `version = 1.0-SNAPSHOT` (`build.gradle.kts:1-2,30`), классы в пакете
    `ru.example` — для внутреннего использования допустимо, но стоит привести
    в порядок перед публикацией.
  - `getSerializable` deprecated (S8).
  - `updateChromeState()` обращается к WebView без guard (S7).
  - `applyReopenSettings` смешивает UI-обновления и настройки WebView — читается
    нормально, но объём метода растёт.
  - Строковые литералы `"hidden"`/`"editable"` для `urlBarMode` на канале —
    дублируют enum Dart; при переименовании enum-значений контракт сломается
    незаметно (стоит констант/комментария).

### 5.4. iOS (Swift)

- Аккуратная работа с памятью: `weak self` во всех замыканиях, `deinit`
  снимает делегатов и останавливает загрузку, `browserViewController` nil-ится
  через `onClosed`.
- Презентация защищена от «зависшего» `open()`: проверки `isBeingPresented`/
  `isBeingDismissed`/`viewIfLoaded?.window`, fallback-ошибка при неудачной
  презентации (покрыто CHANGELOG).
- `topViewController` scene-aware — корректно для iOS 13+.
- Недочёты:
  - Нет `accessibilityLabel` у кнопок панели (SF Symbols дают VoiceOver только
    дефолтное описание).
  - `makeBarButton` — длинные строки параметров без форматирования (стиль).
  - `userAgent`/`initialCookies` дублируют контракт из Dart (тот же риск, что
    на Android).
  - `setCookies` с `DispatchGroup` — корректно, но без таймаута; теоретически
    возможна «зависшая» загрузка (см. 4.1).

### 5.5. Инфраструктура

- **Плюсы:** `.gitignore` покрывает `build/`, `.dart_tool/`, `.idea/`, `Pods/`;
  зависимости — только `appcompat` (Android) и `Flutter`/`WebKit` (iOS);
  `publish_to: none` — пакет внутренний.
- **Минусы:** отсутствует CI (анализ, юнит-тесты, интеграционные прогоны);
  нет линтера для Kotlin/Swift; podspec `homepage = https://example.com` —
  placeholder; версии трёх пакетов синхронизированы (0.2.0) — хорошо.
- **Пример:** демо-экран содержит `enableDebugging: true` (корректно для demo;
  в release Dart-гейт не пропустит).

---

## 6. Анализ документации (Documentation Review)

### 6.1. README.md

**Сильные стороны:**

- Чёткая структура с оглавлением, инструкция по подключению, описание всех
  параметров с примерами.
- **Безопасностные предупреждения на высоком уровне:** «WebView для OAuth
  категорически не рекомендуется» с рекомендациями `ASWebAuthenticationSession`
  и Custom Tabs + AppAuth (README:310-317); описание HTTP/cleartext/ATS политик
  (README:359-366); предупреждение о разделяемом cookie-хранилище Android
  (README:187); глобальность флага отладки на Android (README:262).
- Точная документация reopen-политик и ограничения «один браузер».

**Пробелы:**

1. Не описана **одноразовая доставка `onSchemeRedirect`** за сеанс — второй
   редирект молча отбрасывается (важно для auth-флоу).
2. «Эфемерный» режим описан как «куки не сохраняются после закрытия браузера»
   — на Android это неверно (S2).
3. Не описано, что `reloadWithCookies` устанавливает куки для **изначального**
   хоста, а не текущего.
4. Не описан факт, что `enableDebugging` на Android остаётся активным для
   процесса после закрытия браузера (S3).
5. Нет раздела архитектуры/устройства плагина (каналы, события, жизненный цикл).
6. Нет раздела «Как запускать тесты» (unit + integration).
7. Не описано разрешение схем `data:`/`about:`/`blob:` (S4).
8. Раздел «Известные проблемы» — только одна проблема (клавиатура iOS);
   найденные ограничения (subframe-схемы, гонка двойного open, ложный
   onLoadError) не упомянуты.

### 6.2. docs/requirements.md

**Сильные стороны:** полная спецификация поведения, термины, критерии приёмки,
явное ограничение 6.1 (общее хранилище кук Android).

**Несоответствия и пробелы:**

| Требование | Статус |
|---|---|
| 4.7.3 «куки не сохраняются после закрытия браузера» (эфемерный режим) | На Android не выполняется (S2) — частично признано в 6.1 |
| 4.3.3 «адреса с кастомной схемой не передаются как ошибка загрузки» | Выполнено (кроме iOS `NSURLErrorCancelled`-ложных ошибок, S5) |
| 4.7.2 `reloadWithCookies` | Выполнено, но таргетинг хоста не оговорён |
| 3.5 «плагин не должен препятствовать механизмам доверия сертификатам» | Выполнено (нативные политики не трогаются) |

Отсутствуют требования: однократность `onSchemeRedirect` (поведение есть —
спеки нет), native-валидация кук, поведение `enableDebugging` после закрытия,
список разрешённых схем.

### 6.3. CHANGELOG (три пакета)

- Описания корректны и совпадают с реализацией; версии синхронизированы (0.2.0).
- Отметка о том, что `SimpleBrowserCookie` перестал быть const и валидирует
  значения — хорошая практика обратной совместимости.

---

## 7. Анализ тестов (Test Analysis)

### 7.1. Покрытие

| Уровень | Покрытие | Оценка |
|---|---|---|
| Unit (Dart) | Валидация кук (9 тестов, 12 expect-проверок), платформенный интерфейс (open-аргументы, события, все 4 reopen-политики, сброс при ошибке канала) | Отлично |
| Integration (Android/iOS) | open→onLoadStop→close→onClosed; кастомная схема (стартовая/JS/302); однократность onSchemeRedirect; двойное закрытие; discard; replaceCallbacks; полная замена; initialCookies+reloadWithCookies; блок file://; enableCookiesAndroid=false (с локальным HTTP-сервером) | Отлично |
| UI-flow | Открытие по кастомной схеме → журнал событий → закрытие | Средне (1 сценарий) |
| Native unit (Kotlin/Swift) | — | Отсутствует |

### 7.2. Пробелы

1. Нет юнит-тестов нативной логики: восстановление `acceptCookie`, однократность
   `notifySchemeRedirect` на Android, `isInspectable`-сброс.
2. Нет теста ложного `onLoadError` при отмене навигации (S5).
3. Нет теста гонки двойного `open` (S9).
4. Нет теста `reloadWithCookies` после перехода на другой домен (5.1).
5. Нет теста эфемерного режима Android: персистентность кук после закрытия (S2).
6. Нет теста исключений из пользовательских колбэков (S6).
7. UI-flow покрыт одним сценарием; нет проверки панелей, кнопок назад/вперёд,
   трёх режимов адресной строки в integration.

### 7.3. Состояние

- `flutter analyze`: 0 замечаний во всех четырёх пакетах (ядро, android, ios, example).
- `flutter test`: 23/23 зелёных.

---

## 8. Приоритизированный план исправлений

### P1 — ближайший релиз

| № | Действие | Связано |
|---|---|---|
| 1 | Нативная валидация кук на Android и iOS (reject `;`, `,`, control, пустого name) | S1 |
| 2 | iOS: игнорировать `NSURLErrorCancelled` в `handleNavigationError` | S5 |
| 3 | Android: guard `destroyed` в `updateChromeState` и колбэках WebViewClient; сброс `webViewClient` перед `destroy()` | S7 |
| 4 | Уточнить документацию эфемерного режима кук на Android (или изменить поведение) | S2 |

### P2 — планово

| № | Действие | Связано |
|---|---|---|
| 5 | `onCreate`: всегда вызывать `setWebContentsDebuggingEnabled(enableDebugging)` | S3 |
| 6 | `try/catch` вокруг колбэков в `_handleNativeEvent` | S6 |
| 7 | `BundleCompat.getSerializableExtra` + компактная сериализация кук | S8 |
| 8 | `launchMode="singleInstance"` для `BrowserActivity` | S9 |
| 9 | Явно выставить `mixedContentMode = NEVER_ALLOW`; документировать JS/localStorage | S10 |
| 10 | Санитизация CR/LF в `userAgent` | S11 |
| 11 | Документация: одноразовый `onSchemeRedirect`, схемы `data:`/`about:`/`blob:`, `reloadWithCookies` и хост, архитектура, команды тестов | S2/S4/§6 |

### P3 — по возможности

| № | Действие | Связано |
|---|---|---|
| 12 | `onDetachedFromEngine` → `BrowserActivity.current?.finish()`; сброс `_activeRequest` в `close()` | S12 |
| 13 | Замена placeholder-ов (`ru.example`, gradle version, podspec homepage) | §5.3 |
| 14 | CI: analyze + unit + integration; линтеры Kotlin/Swift | §5.5 |
| 15 | `accessibilityLabel` для iOS-кнопок; унификация обработки ошибок `reloadWithCookies` | §5.1/5.4 |
| 16 | Тесты: native unit, S5/S9/S2/S6-сценарии, UI-flow панелей и адресной строки | §7 |

---

## 9. Приложение: проверенные файлы

```
docs/requirements.md
README.md
simple_native_web_view_browser/
  CHANGELOG.md, pubspec.yaml, analysis_options.yaml
  lib/simple_native_web_view_browser.dart
  lib/src/simple_browser_cookie.dart
  lib/src/simple_browser_open_request.dart
  lib/src/simple_browser_reopen_policy.dart
  lib/src/simple_browser_url_bar_mode.dart
  lib/src/simple_native_web_view_browser_platform_interface.dart
  test/simple_browser_cookie_test.dart
  test/simple_native_web_view_browser_test.dart
simple_native_web_view_browser_android/
  CHANGELOG.md, pubspec.yaml, README.md, analysis_options.yaml
  android/build.gradle.kts, settings.gradle.kts
  android/src/main/AndroidManifest.xml
  android/src/main/kotlin/ru/example/simple_native_web_view_browser/
    BrowserActivity.kt, SimpleNativeWebViewBrowserPlugin.kt
  android/src/main/res/layout/browser_activity.xml
  android/src/main/res/values/{styles,strings}.xml
  android/src/main/res/drawable/ic_*.xml (5)
  lib/simple_native_web_view_browser_android.dart
simple_native_web_view_browser_ios/
  CHANGELOG.md, pubspec.yaml, README.md, analysis_options.yaml
  ios/simple_native_web_view_browser_ios.podspec
  ios/Classes/BrowserViewController.swift
  ios/Classes/SimpleNativeWebViewBrowserPlugin.swift
  lib/simple_native_web_view_browser_ios.dart
example/
  lib/main.dart, lib/browser_demo_screen.dart
  test/browser_demo_screen_test.dart
  integration_test/browser_api_test.dart
  integration_test/browser_ui_flow_test.dart
  android/app/src/main/AndroidManifest.xml
  ios/Runner/Info.plist
Потребитель: /mypet-flutter/lib/auth/logic/utils/web_session/auth_embedded_browser.dart
```

---

## 10. Заключение

Плагин соответствует заявленным требованиям и написан с хорошей инженерной
дисциплиной: продуманный жизненный цикл, осознанные компромиссы безопасности,
сильное тестовое покрытие, качественная пользовательская документация.
Найденные проблемы носят преимущественно характер «глубины обороны» и точности
поведения. Перед производственным использованием рекомендуется закрыть пункты
P1 (нативная валидация кук, фильтр отмены навигации iOS, guard destroyed-WebView,
корректировка документации эфемерного режима Android).
