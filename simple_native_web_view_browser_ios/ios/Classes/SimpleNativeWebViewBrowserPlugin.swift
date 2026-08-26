import Flutter
import UIKit

/// iOS-реализация simple_native_web_view_browser.
///
/// Открывает полноэкранный нативный браузер (WKWebView) с собственными
/// панелями инструментов (обычные UIView с системными цветами): корректно
/// отображаются в светлой и тёмной теме, без чёрных полос.
public class SimpleNativeWebViewBrowserPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var browserViewController: BrowserViewController?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "simple_native_web_view_browser",
      binaryMessenger: registrar.messenger())
    let instance = SimpleNativeWebViewBrowserPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "open: аргументы не переданы",
          details: nil))
        return
      }
      openBrowser(args: args, result: result)

    case "close":
      if let browserViewController = browserViewController {
        browserViewController.closeFromDart()
      }
      result(nil)

    case "reloadWithCookies":
      guard let args = call.arguments as? [String: Any],
            let cookies = args["cookies"] as? [[String: Any]] else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "reloadWithCookies: аргументы не переданы",
          details: nil))
        return
      }
      guard let browserViewController = browserViewController else {
        result(FlutterError(
          code: "browser_not_open",
          message: "Браузер не открыт",
          details: nil))
        return
      }
      browserViewController.reloadWithCookies(cookies, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openBrowser(args: [String: Any], result: @escaping FlutterResult) {
    guard let urlString = args["url"] as? String,
          let url = URL(string: urlString) else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "open: некорректный url",
        details: nil))
      return
    }

    guard browserViewController == nil else {
      result(FlutterError(
        code: "browser_already_open",
        message: "Браузер уже открыт",
        details: nil))
      return
    }

    let userAgent = args["userAgent"] as? String ?? ""
    let usePersistentCookieStore = args["usePersistentCookieStore"] as? Bool ?? true
    let initialCookies = args["initialCookies"] as? [[String: Any]] ?? []
    let urlBarMode = BrowserUrlBarMode(
      rawValue: args["urlBarMode"] as? String ?? "hidden") ?? .hidden

    guard let topViewController = UIApplication.shared.topViewController() else {
      result(FlutterError(
        code: "no_view_controller",
        message: "Не найден контроллер для показа браузера",
        details: nil))
      return
    }

    let controller = BrowserViewController(
      url: url,
      userAgent: userAgent,
      usePersistentCookieStore: usePersistentCookieStore,
      initialCookies: initialCookies,
      urlBarMode: urlBarMode,
      channel: channel)
    controller.onClosed = { [weak self] in
      self?.browserViewController = nil
    }
    controller.modalPresentationStyle = .fullScreen
    controller.modalTransitionStyle = .coverVertical

    browserViewController = controller
    topViewController.present(controller, animated: true) {
      result(nil)
    }
  }
}

extension UIApplication {
  /// Текущее активное окно (scene-aware).
  var currentKeyWindow: UIWindow? {
    connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  /// Верхний контроллер цепочки presented/navigation/tab.
  func topViewController(base: UIViewController? = nil) -> UIViewController? {
    var top = base ?? currentKeyWindow?.rootViewController
    while true {
      if let presented = top?.presentedViewController {
        top = presented
      } else if let navigationController = top as? UINavigationController {
        top = navigationController.visibleViewController
      } else if let tabBarController = top as? UITabBarController {
        top = tabBarController.selectedViewController
      } else {
        return top
      }
    }
  }
}
