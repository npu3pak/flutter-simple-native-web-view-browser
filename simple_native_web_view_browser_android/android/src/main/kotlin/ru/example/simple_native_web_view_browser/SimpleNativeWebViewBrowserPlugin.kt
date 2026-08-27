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
import org.json.JSONArray
import org.json.JSONObject

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
        // Детач движка с открытым браузером: завершаем Activity. onClosed
        // в этом сценарии может не дойти до Dart (канал уже обнулён) —
        // активную сессию принудительно закрывает fallback-таймер Dart.
        BrowserActivity.current?.finish()
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
            "reopenSettings" -> reopenSettings(call, result)
            else -> result.notImplemented()
        }
    }

    private fun reopenSettings(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        if (url == null) {
            result.error("invalid_arguments", "reopenSettings: некорректный url", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val initialCookies = (call.argument<List<Map<String, Any?>>>("initialCookies"))
            ?.toList() ?: emptyList()
        val current = BrowserActivity.current
        if (current == null) {
            result.error("browser_not_open", "Браузер не открыт", null)
            return
        }
        current.reopenSettings(
            url = url,
            userAgent = call.argument<String>("userAgent"),
            initialCookies = initialCookies,
            urlBarMode = call.argument<String>("urlBarMode") ?: "hidden",
            enableDebugging = call.argument<Boolean>("enableDebugging") ?: false,
            enableCookiesAndroid = call.argument<Boolean>("enableCookiesAndroid") ?: true,
            allowFileAccess = call.argument<Boolean>("allowFileAccess") ?: false,
        )
        result.success(null)
    }

    private fun open(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        if (url == null) {
            result.error("invalid_arguments", "open: некорректный url", null)
            return
        }
        val userAgent = call.argument<String>("userAgent")
        @Suppress("UNCHECKED_CAST")
        val initialCookies = (call.argument<List<Map<String, Any?>>>("initialCookies"))
            ?.toList() ?: emptyList()
        val urlBarMode = call.argument<String>("urlBarMode") ?: "hidden"
        val enableDebugging = call.argument<Boolean>("enableDebugging") ?: false
        val enableCookiesAndroid = call.argument<Boolean>("enableCookiesAndroid") ?: true
        val allowFileAccess = call.argument<Boolean>("allowFileAccess") ?: false

        // Повторное открытие: заменяем сессию в существующем браузере.
        BrowserActivity.current?.let { current ->
            current.replace(
                url = url,
                userAgent = userAgent,
                initialCookies = initialCookies,
                urlBarMode = urlBarMode,
                enableDebugging = enableDebugging,
                enableCookiesAndroid = enableCookiesAndroid,
                allowFileAccess = allowFileAccess,
            )
            result.success(null)
            return
        }

        val context = activity
        if (context == null) {
            result.error("no_activity", "Нет Activity для показа браузера", null)
            return
        }

        val intent = Intent(context, BrowserActivity::class.java).apply {
            putExtra(BrowserActivity.EXTRA_URL, url)
            userAgent?.let {
                putExtra(BrowserActivity.EXTRA_USER_AGENT, it)
            }
            putExtra(
                BrowserActivity.EXTRA_USE_PERSISTENT_COOKIE_STORE,
                call.argument<Boolean>("usePersistentCookieStore") ?: true,
            )
            putExtra(
                BrowserActivity.EXTRA_INITIAL_COOKIES,
                cookiesToJson(initialCookies),
            )
            putExtra(
                BrowserActivity.EXTRA_URL_BAR_MODE,
                urlBarMode,
            )
            putExtra(
                BrowserActivity.EXTRA_ENABLE_DEBUGGING,
                enableDebugging,
            )
            putExtra(
                BrowserActivity.EXTRA_ENABLE_COOKIES,
                enableCookiesAndroid,
            )
            putExtra(
                BrowserActivity.EXTRA_ALLOW_FILE_ACCESS,
                allowFileAccess,
            )
        }
        context.startActivity(intent)
        result.success(null)
    }

    private fun reloadWithCookies(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val cookies = call.argument<List<Map<String, Any?>>>("cookies")
        if (cookies == null) {
            result.error("invalid_arguments", "reloadWithCookies: аргументы не переданы", null)
            return
        }
        val current = BrowserActivity.current
        if (current == null) {
            result.error("browser_not_open", "Браузер не открыт", null)
        } else {
            current.reloadWithCookies(cookies)
            result.success(null)
        }
    }

    /** Сериализует куки в JSON-строку: компактнее и безопаснее по размеру Intent. */
    private fun cookiesToJson(cookies: List<Map<String, Any?>>): String {
        val array = JSONArray()
        for (cookie in cookies) {
            val obj = JSONObject()
            for ((key, value) in cookie) {
                if (value != null) {
                    obj.put(key, value)
                }
            }
            array.put(obj)
        }
        return array.toString()
    }
}
