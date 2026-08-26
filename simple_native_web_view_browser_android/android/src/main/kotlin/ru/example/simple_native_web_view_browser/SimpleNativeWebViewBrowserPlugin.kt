package ru.example.simple_native_web_view_browser

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android-реализация simple_native_web_view_browser.
 * Открывает отдельную Activity ([BrowserActivity]) с нативным браузером.
 * События (onLoadStop/onLoadError/onClosed) уходят в Dart по каналу
 * `simple_native_web_view_browser`.
 */
class SimpleNativeWebViewBrowserPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    companion object {
        private var channel: MethodChannel? = null
        private var activity: Activity? = null

        /** Отправка события нативного браузера в Dart. */
        fun sendEvent(method: String, arguments: Any?) {
            channel?.invokeMethod(method, arguments)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "simple_native_web_view_browser")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "open" -> open(call, result)
            "close" -> {
                BrowserActivity.current?.finish()
                result.success(null)
            }
            "reloadWithCookies" -> reloadWithCookies(call, result)
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        if (url == null) {
            result.error("invalid_arguments", "open: некорректный url", null)
            return
        }
        if (BrowserActivity.current != null) {
            result.error("browser_already_open", "Браузер уже открыт", null)
            return
        }
        val context = activity
        if (context == null) {
            result.error("no_activity", "Нет Activity для показа браузера", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val initialCookies = (call.argument<List<Map<String, Any?>>>("initialCookies"))
            ?.toList() ?: emptyList()

        val intent = Intent(context, BrowserActivity::class.java).apply {
            putExtra(BrowserActivity.EXTRA_URL, url)
            putExtra(
                BrowserActivity.EXTRA_USER_AGENT,
                call.argument<String>("userAgent").orEmpty(),
            )
            putExtra(
                BrowserActivity.EXTRA_USE_PERSISTENT_COOKIE_STORE,
                call.argument<Boolean>("usePersistentCookieStore") ?: true,
            )
            putExtra(
                BrowserActivity.EXTRA_INITIAL_COOKIES,
                ArrayList(initialCookies),
            )
            putExtra(
                BrowserActivity.EXTRA_URL_BAR_MODE,
                call.argument<String>("urlBarMode") ?: "hidden",
            )
        }
        context.startActivity(intent)
        result.success(null)
    }

    private fun reloadWithCookies(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val cookies = call.argument<List<Map<String, Any?>>>("cookies").orEmpty()
        val current = BrowserActivity.current
        if (current == null) {
            result.error("browser_not_open", "Браузер не открыт", null)
        } else {
            current.reloadWithCookies(cookies)
            result.success(null)
        }
    }
}
