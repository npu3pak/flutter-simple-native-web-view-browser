import Flutter
import UIKit
import WebKit

/// Режим отображения адресной строки.
enum BrowserUrlBarMode: String {
  case hidden
  case editable
  case readOnly
}

/// Контроллер нативного браузера: WKWebView + собственные верхняя
/// (плоский крестик, заголовок/адресная строка) и нижняя
/// (назад/вперёд/обновить) панели «как в старых браузерах».
///
/// Панели — обычные UIView во всю ширину до краёв экрана с системным
/// фоном: корректно выглядят в светлой и тёмной теме на любой iOS 15+,
/// без чёрных полос. Кнопки — плоские UIButton без фона и тени;
/// disabled-вид обеспечивает UIKit (снижение непрозрачности).
final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
  private var url: URL
  private var userAgent: String
  private let usePersistentCookieStore: Bool
  private var initialCookies: [[String: Any]]
  private var urlBarMode: BrowserUrlBarMode
  private var enableDebugging: Bool
  private var allowFileAccess: Bool
  private weak var channel: FlutterMethodChannel?

  private var webView: WKWebView!
  private var topBar: UIView!
  private var topStack: UIStackView!
  private var bottomBar: UIView!
  private var bottomBarHeightConstraint: NSLayoutConstraint!
  private var topTitleLabel: UILabel?
  private var addressField: UITextField?
  private var backButton: UIButton!
  private var forwardButton: UIButton!
  private var reloadButton: UIButton!

  /// Вызывается один раз после фактического закрытия браузера.
  var onClosed: (() -> Void)?
  private var closedNotified = false

  init(
    url: URL,
    userAgent: String,
    usePersistentCookieStore: Bool,
    initialCookies: [[String: Any]],
    urlBarMode: BrowserUrlBarMode,
    enableDebugging: Bool,
    allowFileAccess: Bool,
    channel: FlutterMethodChannel?
  ) {
    self.url = url
    self.userAgent = userAgent
    self.usePersistentCookieStore = usePersistentCookieStore
    self.initialCookies = initialCookies
    self.urlBarMode = urlBarMode
    self.enableDebugging = enableDebugging
    self.allowFileAccess = allowFileAccess
    self.channel = channel
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    webView?.navigationDelegate = nil
    webView?.uiDelegate = nil
    webView?.stopLoading()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    edgesForExtendedLayout = []

    let configuration = WKWebViewConfiguration()
    if usePersistentCookieStore {
      configuration.websiteDataStore = .default()
    } else {
      configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    }

    webView = WKWebView(frame: .zero, configuration: configuration)
    if !userAgent.isEmpty {
      webView.customUserAgent = userAgent
    }
    if enableDebugging {
      // Веб-инспектор (Safari Web Inspector) доступен с iOS 16.4.
      if #available(iOS 16.4, *) {
        webView.isInspectable = true
      }
    }
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)

    setupTopBar()
    setupBottomBar()

    // Единый блок констрейнтов: каждое отношение задано ровно один раз.
    NSLayoutConstraint.activate([
      // Верхняя панель: от верхнего края экрана до 44pt ниже статус-бара.
      topBar.topAnchor.constraint(equalTo: view.topAnchor),
      topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topBar.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 44),

      // WebView: контент упирается в верхнюю и нижнюю панели.
      webView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

      // Нижняя панель: от webView до нижнего края экрана.
      bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bottomBarHeightConstraint,
    ])

    setCookies(initialCookies, hostUrl: url) { [weak self] in
      guard let self = self else { return }
      self.loadInitialPage()
    }
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    // Пересчитываем высоту панели при смене safe area (поворот,
    // ландшафт и т.п.).
    bottomBarHeightConstraint.constant = 44 + view.safeAreaInsets.bottom
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Закрепляем клавиатурный first responder за WebView: hardware-
    // клавиши (например, Enter) уходят в веб-контент, а не во Flutter,
    // иначе сфокусированные элементы Flutter могут сработать повторно.
    webView.becomeFirstResponder()
  }

  /// Схемы, которые WebView может загрузить. Кастомные схемы (например,
  /// demoapp://...) загрузить нельзя: при попытке загрузки WKWebView может
  /// вообще не начать навигацию, поэтому такое событие отдаём приложению
  /// напрямую как перенаправление на кастомную схему.
  private func loadInitialPage() {
    guard let scheme = url.scheme?.lowercased(),
          isLoadableScheme(scheme) else {
      notifySchemeRedirect(url.absoluteString)
      return
    }
    webView.load(URLRequest(url: url))
  }

  /// Применяет настройки нового запроса без загрузки страницы.
  /// Используется при замене сессии (reopenSettings и replace).
  func applyReopenSettings(
    url: URL,
    userAgent: String,
    initialCookies: [[String: Any]],
    urlBarMode: BrowserUrlBarMode,
    enableDebugging: Bool,
    allowFileAccess: Bool
  ) {
    self.url = url
    self.userAgent = userAgent
    self.initialCookies = initialCookies
    self.urlBarMode = urlBarMode
    self.enableDebugging = enableDebugging
    self.allowFileAccess = allowFileAccess
    schemeRedirectNotified = false

    if userAgent.isEmpty {
      webView.customUserAgent = nil
    } else {
      webView.customUserAgent = userAgent
    }
    // Инспектор переключаем в обе стороны: повторное открытие
    // с enableDebugging=false должно отключать его.
    if #available(iOS 16.4, *) {
      webView.isInspectable = enableDebugging
    }
    applyUrlBarMode()
  }

  /// Замена сессии при повторном открытии (reopenPolicy == replace):
  /// текущее вебвью переходит на новый адрес, все настройки нового
  /// запроса применяются полностью.
  func replace(
    url: URL,
    userAgent: String,
    initialCookies: [[String: Any]],
    urlBarMode: BrowserUrlBarMode,
    enableDebugging: Bool,
    allowFileAccess: Bool,
    result: @escaping FlutterResult
  ) {
    applyReopenSettings(
      url: url,
      userAgent: userAgent,
      initialCookies: initialCookies,
      urlBarMode: urlBarMode,
      enableDebugging: enableDebugging,
      allowFileAccess: allowFileAccess)

    setCookies(initialCookies, hostUrl: url) { [weak self] in
      guard let self = self else { return }
      self.loadInitialPage()
      result(nil)
    }
  }

  /// Применение настроек нового запроса без перезагрузки страницы
  /// (reopenPolicy == replaceCallbacksAndSettings).
  func reopenSettings(
    url: URL,
    userAgent: String,
    initialCookies: [[String: Any]],
    urlBarMode: BrowserUrlBarMode,
    enableDebugging: Bool,
    allowFileAccess: Bool,
    result: @escaping FlutterResult
  ) {
    applyReopenSettings(
      url: url,
      userAgent: userAgent,
      initialCookies: initialCookies,
      urlBarMode: urlBarMode,
      enableDebugging: enableDebugging,
      allowFileAccess: allowFileAccess)
    // Куки применяются к хранилищу; вступят в силу при следующей загрузке.
    setCookies(initialCookies, hostUrl: url) {
      result(nil)
    }
  }

  /// Можно ли загрузить адрес с указанной схемой в WebView.
  private func isLoadableScheme(_ scheme: String) -> Bool {
    var loadable = ["http", "https", "data", "about", "blob"]
    if allowFileAccess {
      loadable.append("file")
    }
    return loadable.contains(scheme)
  }

  /// Единственная доставка перенаправления на кастомную схему за сеанс
  /// браузера: один и тот же редирект может прийти через несколько
  /// путей перехвата (decidePolicyFor, серверный редирект, ошибка).
  private var schemeRedirectNotified = false

  private func notifySchemeRedirect(_ urlString: String?) {
    guard let urlString = urlString, !schemeRedirectNotified else { return }
    schemeRedirectNotified = true
    channel?.invokeMethod("onSchemeRedirect", arguments: urlString)
  }

  // MARK: - Хром

  /// Верхняя панель: плоский крестик слева, заголовок или адресная строка.
  private func setupTopBar() {
    topBar = UIView()
    topBar.translatesAutoresizingMaskIntoConstraints = false
    topBar.backgroundColor = .systemBackground
    view.addSubview(topBar)

    let closeButton = makeBarButton(
      "xmark",
      action: #selector(closeTapped),
      width: 32,
      pointSize: 20)

    // Пустой плейсхолдер справа, равный по ширине крестику: заголовок
    // и адресная строка центрируются относительно всего экрана.
    let placeholder = UIView()
    placeholder.translatesAutoresizingMaskIntoConstraints = false

    topStack = UIStackView(arrangedSubviews: [closeButton, placeholder])
    topStack.translatesAutoresizingMaskIntoConstraints = false
    topStack.axis = .horizontal
    topStack.spacing = 8
    topStack.alignment = .center
    topBar.addSubview(topStack)
    applyUrlBarMode()

    NSLayoutConstraint.activate([
      topStack.topAnchor.constraint(equalTo: topBar.safeAreaLayoutGuide.topAnchor),
      topStack.leadingAnchor.constraint(
        equalTo: topBar.safeAreaLayoutGuide.leadingAnchor,
        constant: 16),
      topStack.trailingAnchor.constraint(
        equalTo: topBar.safeAreaLayoutGuide.trailingAnchor,
        constant: -16),
      topStack.heightAnchor.constraint(equalToConstant: 44),
      placeholder.widthAnchor.constraint(equalTo: closeButton.widthAnchor),
    ])
  }

  /// Создаёт и подставляет центральный элемент верхней панели
  /// (заголовок или адресную строку) в соответствии с urlBarMode.
  /// Вызывается при создании и при замене сессии (replace).
  private func applyUrlBarMode() {
    guard let topStack = topStack else { return }

    // Удаляем прежний центральный элемент.
    if let centerView = topStack.arrangedSubviews.first(where: {
      $0 !== topStack.arrangedSubviews.first && $0 !== topStack.arrangedSubviews.last
    }) {
      topStack.removeArrangedSubview(centerView)
      centerView.removeFromSuperview()
    }
    topTitleLabel = nil
    addressField = nil

    let centerView: UIView
    switch urlBarMode {
    case .hidden:
      let label = UILabel()
      label.text = url.host
      label.lineBreakMode = .byTruncatingTail
      label.textAlignment = .center
      label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
      topTitleLabel = label
      centerView = label
    case .editable, .readOnly:
      let field = UITextField()
      field.borderStyle = .none
      field.placeholder = url.host
      field.text = url.absoluteString
      field.autocapitalizationType = .none
      field.autocorrectionType = .no
      field.keyboardType = .URL
      field.returnKeyType = .go
      field.isEnabled = (urlBarMode == .editable)
      // Крестик очистки значения — только в редактируемом режиме.
      field.clearButtonMode = (urlBarMode == .editable) ? .whileEditing : .never
      field.addTarget(self, action: #selector(addressBarSubmitted), for: .editingDidEndOnExit)
      field.textAlignment = .center
      field.font = UIFont.systemFont(ofSize: 17)
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      addressField = field
      centerView = field
    }
    topStack.insertArrangedSubview(centerView, at: 1)
  }

  /// Нижняя панель «как в старых браузерах»: во всю ширину до нижнего
  /// края экрана, safe-area полоса закрашена фоном панели.
  /// Назад/вперёд — слева, обновить — справа.
  private func setupBottomBar() {
    bottomBar = UIView()
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.backgroundColor = .systemBackground
    view.addSubview(bottomBar)

    // Явная высота панели: 44pt + нижняя safe-area полоса. Без неё
    // высоты webView и панели неоднозначны, и AutoLayout может
    // схлопнуть webView до нуля.
    bottomBarHeightConstraint = bottomBar.heightAnchor.constraint(
      equalToConstant: 44 + view.safeAreaInsets.bottom)

    backButton = makeBarButton("chevron.backward", action: #selector(goBack))
    forwardButton = makeBarButton("chevron.forward", action: #selector(goForward))
    reloadButton = makeBarButton("arrow.clockwise", action: #selector(reloadTapped))

    // Распорка раздвигает кластер (слева) и кнопку обновления (справа).
    let flexible = UIView()
    flexible.translatesAutoresizingMaskIntoConstraints = false
    flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let stack = UIStackView(arrangedSubviews: [
      backButton, forwardButton, flexible, reloadButton,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.spacing = 18
    stack.alignment = .center
    bottomBar.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: bottomBar.topAnchor),
      stack.leadingAnchor.constraint(
        equalTo: bottomBar.safeAreaLayoutGuide.leadingAnchor,
        constant: 16),
      stack.trailingAnchor.constraint(
        equalTo: bottomBar.safeAreaLayoutGuide.trailingAnchor,
        constant: -16),
      stack.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  /// Плоская кнопка: без фона и тени, системное изменение цвета
  /// при нажатии, disabled-вид обеспечивает UIKit.
  private func makeBarButton(
    _ systemName: String,
    action: Selector,
    width: CGFloat = 44,
    pointSize: CGFloat = 22
  ) -> UIButton {
    let button = UIButton(type: .system)
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    button.setImage(
      UIImage(systemName: systemName, withConfiguration: configuration),
      for: .normal)
    button.tintColor = .label
    button.addTarget(self, action: action, for: .touchUpInside)
    button.widthAnchor.constraint(equalToConstant: width).isActive = true
    return button
  }

  @objc private func closeTapped() {
    closeFromDart()
  }

  @objc private func goBack() {
    if webView.canGoBack {
      webView.goBack()
    }
  }

  @objc private func goForward() {
    if webView.canGoForward {
      webView.goForward()
    }
  }

  @objc private func reloadTapped() {
    webView.reload()
  }

  @objc private func addressBarSubmitted() {
    guard let text = addressField?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else {
      return
    }
    var urlString = text
    if !urlString.contains("://") {
      urlString = "https://" + urlString
    }
    if let url = URL(string: urlString) {
      webView.load(URLRequest(url: url))
    }
  }

  // MARK: - Закрытие

  private var isClosing = false

  /// Закрытие из кода (метод close()) или кнопкой «крестик».
  /// Повторный вызов во время закрытия игнорируется; если контроллер
  /// уже не представлен — закрытие уведомляется сразу.
  func closeFromDart() {
    guard !isClosing else { return }
    isClosing = true
    if presentingViewController != nil {
      dismiss(animated: true) { [weak self] in
        self?.notifyClosed()
      }
    } else {
      notifyClosed()
    }
  }

  private func notifyClosed() {
    guard !closedNotified else { return }
    closedNotified = true
    channel?.invokeMethod("onClosed", arguments: nil)
    onClosed?()
  }

  // MARK: - Состояние навигации

  private func updateChromeState() {
    backButton.isEnabled = webView.canGoBack
    forwardButton.isEnabled = webView.canGoForward
    let title = webView.title?.isEmpty == false ? webView.title : url.host
    if let topTitleLabel = topTitleLabel {
      topTitleLabel.text = title
    }
    if let addressField = addressField {
      addressField.text = webView.url?.absoluteString ?? url.absoluteString
    }
  }

  // MARK: - WKNavigationDelegate

  /// Серверный редирект (302) на кастомную схему может не проходить
  /// через decidePolicyFor: перехватываем здесь, отдаём адрес приложению
  /// и останавливаем навигацию, чтобы редирект не ушёл в систему.
  func webView(
    _ webView: WKWebView,
    didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
  ) {
    guard let url = webView.url,
          let scheme = url.scheme?.lowercased(),
          !isLoadableScheme(scheme) else {
      return
    }
    notifySchemeRedirect(url.absoluteString)
    webView.stopLoading()
  }

  /// Перехватывает навигацию на кастомную схему на любом шаге навигации
  /// (серверные редиректы, клики по ссылкам, JS-переходы): отдаёт адрес
  /// приложению и отменяет навигацию. Без перехвата WKWebView может
  /// молча оборвать такую навигацию без вызова didFailProvisionalNavigation.
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if let scheme = navigationAction.request.url?.scheme?.lowercased(),
       !isLoadableScheme(scheme) {
      notifySchemeRedirect(navigationAction.request.url?.absoluteString)
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  /// Состояние кнопок и адресной строки обновляем сразу после начала
  /// навигации: история уже содержит новую запись, «Назад»/«Вперёд»
  /// должны стать доступными до завершения загрузки.
  func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    updateChromeState()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    updateChromeState()
    channel?.invokeMethod("onLoadStop", arguments: webView.url?.absoluteString)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    handleNavigationError(error, webView: webView)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    handleNavigationError(error, webView: webView)
  }

  private func handleNavigationError(_ error: Error, webView: WKWebView) {
    updateChromeState()
    // Отмена навигации пользователем или новой навигацией — не ошибка загрузки.
    if (error as NSError).code == NSURLErrorCancelled {
      return
    }
    // Адрес ошибки берём из userInfo: при попытке открыть кастомную схему
    // (например, demoapp://...) навигация падает, а failing URL — это
    // адрес редиректа, который ожидает приложение. В зависимости от типа
    // ошибки URL лежит в одном из ключей userInfo.
    let nsError = error as NSError
    let failingUrl =
      nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
      ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
        .flatMap(URL.init(string:))
      ?? webView.url

    // Кастомная схема (не загружаемая WebView) — это перенаправление
    // в приложение, а не ошибка загрузки.
    if let scheme = failingUrl?.scheme?.lowercased(),
       !isLoadableScheme(scheme) {
      notifySchemeRedirect(failingUrl?.absoluteString)
      return
    }
    channel?.invokeMethod(
      "onLoadError",
      arguments: failingUrl?.absoluteString)
  }

  // MARK: - WKUIDelegate

  /// Ссылки с target=_blank открываем в том же WebView.
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil {
      webView.load(navigationAction.request)
    }
    return nil
  }

  // MARK: - Куки

  /// Устанавливает [cookies] и перезагружает текущую страницу.
  func reloadWithCookies(_ cookies: [[String: Any]], result: @escaping FlutterResult) {
    let currentUrl = webView.url ?? url
    setCookies(cookies, hostUrl: currentUrl) { [weak self] in
      self?.webView.reload()
      result(nil)
    }
  }

  private func setCookies(
    _ cookies: [[String: Any]],
    hostUrl: URL,
    completion: @escaping () -> Void
  ) {
    let dataStore = webView.configuration.websiteDataStore
    let group = DispatchGroup()
    for cookieDict in cookies {
      group.enter()
      setCookie(cookieDict, dataStore: dataStore, hostUrl: hostUrl) { _ in
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }

  private func setCookie(
    _ dict: [String: Any],
    dataStore: WKWebsiteDataStore,
    hostUrl: URL,
    completion: @escaping (Bool) -> Void
  ) {
    guard let cookie = makeCookie(from: dict, hostUrl: hostUrl) else {
      completion(false)
      return
    }
    dataStore.httpCookieStore.setCookie(cookie) {
      completion(true)
    }
  }

  private func makeCookie(from dict: [String: Any], hostUrl: URL) -> HTTPCookie? {
    let name = dict["name"] as? String ?? ""
    let value = dict["value"] as? String ?? ""
    let path = dict["path"] as? String ?? "/"
    let domain = dict["domain"] as? String ?? hostUrl.host ?? ""
    // Дополнительная защита от инъекции атрибутов кук на нативной стороне.
    guard isCookieFieldValid(name, allowEmpty: false),
          isCookieFieldValid(value, allowEmpty: true),
          isCookieFieldValid(path, allowEmpty: true),
          isCookieFieldValid(domain, allowEmpty: false) else {
      return nil
    }
    var properties: [HTTPCookiePropertyKey: Any] = [:]
    properties[.name] = name
    properties[.value] = value
    properties[.path] = path
    properties[.domain] = domain
    if dict["isSecure"] as? Bool == true {
      properties[.secure] = "TRUE"
    }
    if dict["isHttpOnly"] as? Bool == true {
      properties[HTTPCookiePropertyKey("HttpOnly")] = "YES"
    }
    return HTTPCookie(properties: properties)
  }

  private func isCookieFieldValid(_ value: String, allowEmpty: Bool) -> Bool {
    if !allowEmpty && value.isEmpty {
      return false
    }
    return !value.unicodeScalars.contains { scalar in
      let code = scalar.value
      return code < 0x20 || code == 0x7F || scalar == ";" || scalar == ","
    }
  }
}
