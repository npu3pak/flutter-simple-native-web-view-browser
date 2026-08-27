package ru.example.simple_native_web_view_browser

import android.annotation.SuppressLint
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.MotionEvent
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONException

/**
 * Нативный браузер «как в старых браузерах»: панели во всю ширину,
 * системные цвета темы (DayNight), веб-контент упирается в панели.
 *
 * Верхняя панель: крестик слева, заголовок/адресная строка по центру
 * экрана (плейсхолдер справа компенсирует отступ крестика).
 * Нижняя панель: назад/вперёд слева, обновить справа.
 */
class BrowserActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_USER_AGENT = "userAgent"
        const val EXTRA_USE_PERSISTENT_COOKIE_STORE = "usePersistentCookieStore"
        const val EXTRA_INITIAL_COOKIES = "initialCookies"
        const val EXTRA_URL_BAR_MODE = "urlBarMode"
        const val EXTRA_ENABLE_DEBUGGING = "enableDebugging"
        const val EXTRA_ENABLE_COOKIES = "enableCookiesAndroid"
        const val EXTRA_ALLOW_FILE_ACCESS = "allowFileAccess"

        /** Текущая открытая Activity (единственный экземпляр браузера). */
        var current: BrowserActivity? = null
    }

    private lateinit var webView: WebView
    private var addressField: EditText? = null
    private var titleView: TextView? = null
    private var backButton: ImageButton? = null
    private var forwardButton: ImageButton? = null

    private lateinit var url: String
    private var usePersistentCookieStore = true
    private var initialCookies = mutableListOf<Map<String, Any?>>()
    private var urlBarMode = "hidden"
    private var enableDebugging = false
    private var enableCookiesAndroid = true
    private var allowFileAccess = false
    private var closedNotified = false

    /** Предыдущее значение приёма кук процесса — восстанавливается в onDestroy. */
    private var previousAcceptCookie: Boolean? = null

    /** Guard единственной доставки onSchemeRedirect за сессию (аналог iOS). */
    private var schemeRedirectNotified = false

    /** WebView уничтожен: колбэки после destroy игнорируются. */
    private var webViewDestroyed = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this

        val extras = intent.extras ?: run {
            finish()
            return
        }
        url = extras.getString(EXTRA_URL) ?: ""
        usePersistentCookieStore = extras.getBoolean(EXTRA_USE_PERSISTENT_COOKIE_STORE, true)
        initialCookies.addAll(parseCookiesJson(extras.getString(EXTRA_INITIAL_COOKIES)))
        urlBarMode = extras.getString(EXTRA_URL_BAR_MODE) ?: "hidden"
        enableDebugging = extras.getBoolean(EXTRA_ENABLE_DEBUGGING, false)
        enableCookiesAndroid = extras.getBoolean(EXTRA_ENABLE_COOKIES, true)
        allowFileAccess = extras.getBoolean(EXTRA_ALLOW_FILE_ACCESS, false)

        setContentView(R.layout.browser_activity)

        // Веб-инспектор (Chrome DevTools) для всех WebView процесса:
        // применяем переданное значение в обе стороны.
        WebView.setWebContentsDebuggingEnabled(enableDebugging)

        webView = findViewById(R.id.webView)
        // UA задаётся только если передан: иначе используется стандартный
        // пользовательский агент WebView.
        extras.getString(EXTRA_USER_AGENT)
            ?.takeIf { it.isNotEmpty() }
            ?.let { webView.settings.userAgentString = it }
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        applyCookieAcceptance()
        applyFileAccessSettings()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val urlString = request?.url?.toString() ?: return false
                if (!isLoadableScheme(Uri.parse(urlString).scheme)) {
                    // Кастомная схема: отдаём приложению и не загружаем —
                    // иначе WebView покажет системный экран ошибки
                    // ERR_UNKNOWN_URL_SCHEME.
                    notifySchemeRedirect(urlString)
                    return true
                }
                return false
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                updateChromeState()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                updateChromeState()
                SimpleNativeWebViewBrowserPlugin.sendEvent("onLoadStop", url)
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                // Ошибки вторичных ресурсов (картинки, CSS, iframe)
                // приложению не сообщаются — только главный кадр.
                if (request?.isForMainFrame != true) {
                    return
                }
                updateChromeState()
                // Кастомная схема (например, demoapp://...) не загружается:
                // ERR_UNKNOWN_URL_SCHEME приходит сюда с адресом редиректа.
                val failingUrl = request?.url?.toString() ?: url
                if (isLoadableScheme(Uri.parse(failingUrl).scheme)) {
                    SimpleNativeWebViewBrowserPlugin.sendEvent("onLoadError", failingUrl)
                } else {
                    notifySchemeRedirect(failingUrl)
                }
            }
        }

        setupChrome()
        setupBackCallback()
        prepareCookiesAndLoad()
    }

    // MARK: - Хром

    private fun setupChrome() {
        findViewById<ImageButton>(R.id.closeButton).setOnClickListener {
            finish()
        }

        titleView = findViewById(R.id.titleView)
        addressField = findViewById(R.id.addressField)
        applyUrlBarMode()

        backButton = findViewById<ImageButton>(R.id.backButton).also {
            it.setOnClickListener {
                if (webView.canGoBack()) {
                    webView.goBack()
                }
            }
        }
        forwardButton = findViewById<ImageButton>(R.id.forwardButton).also {
            it.setOnClickListener {
                if (webView.canGoForward()) {
                    webView.goForward()
                }
            }
        }
        findViewById<ImageButton>(R.id.reloadButton).setOnClickListener {
            webView.reload()
        }
    }

    /// Применяет режим адресной строки (заголовок или адресное поле).
    /// Вызывается при создании и при замене сессии (replace).
    private fun applyUrlBarMode() {
        when (urlBarMode) {
            "hidden" -> {
                titleView?.visibility = View.VISIBLE
                titleView?.text = Uri.parse(url).host
                addressField?.visibility = View.GONE
            }
            else -> {
                titleView?.visibility = View.GONE
                addressField?.visibility = View.VISIBLE
                addressField?.isEnabled = (urlBarMode == "editable")
                addressField?.setText(url, TextView.BufferType.NORMAL)
                addressField?.setOnEditorActionListener { _, actionId, _ ->
                    if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_GO) {
                        submitAddress()
                        true
                    } else {
                        false
                    }
                }
                setupClearButton(addressField)
            }
        }
    }

    private fun setupClearButton(field: EditText?) {
        // Маленький кружок с крестиком (16dp) — явно мельче кнопок панели.
        val clearIcon = AppCompatResources.getDrawable(this, R.drawable.ic_clear)
        clearIcon?.setTint(ContextCompat.getColor(this, android.R.color.darker_gray))

        fun updateClearIcon() {
            if (field?.text?.isNotEmpty() == true) {
                field?.setCompoundDrawablesRelativeWithIntrinsicBounds(
                    null, null, clearIcon, null,
                )
            } else {
                field?.setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, null, null)
            }
        }

        field?.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) = updateClearIcon()
        })
        updateClearIcon()

        field?.setOnTouchListener { view, event ->
            val drawableEnd = (view as EditText).compoundDrawablesRelative[2]
            if (drawableEnd != null && event.action == MotionEvent.ACTION_UP) {
                val isInsideClear =
                    event.x >= view.width - view.totalPaddingEnd - drawableEnd.intrinsicWidth
                if (isInsideClear) {
                    view.setText("")
                    return@setOnTouchListener true
                }
            }
            false
        }
    }

    private fun submitAddress() {
        val text = addressField?.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) {
            return
        }
        var urlString = text
        if (!urlString.contains("://")) {
            urlString = "https://$urlString"
        }
        if (!isLoadableScheme(Uri.parse(urlString).scheme)) {
            notifySchemeRedirect(urlString)
            return
        }
        webView.loadUrl(urlString)
    }

    private fun updateChromeState() {
        if (webViewDestroyed) {
            return
        }
        setButtonEnabled(backButton, webView.canGoBack())
        setButtonEnabled(forwardButton, webView.canGoForward())
        val title = webView.title?.takeIf { it.isNotEmpty() } ?: Uri.parse(url).host
        titleView?.text = title
        addressField?.setText(webView.url ?: url, TextView.BufferType.NORMAL)
    }

    private fun setButtonEnabled(button: ImageButton?, enabled: Boolean) {
        button?.isEnabled = enabled
        button?.alpha = if (enabled) 1f else 0.38f
    }

    private fun setupBackCallback() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    finish()
                }
            }
        })
    }

    // MARK: - Куки

    private fun prepareCookiesAndLoad() {
        if (!usePersistentCookieStore) {
            // Эфемерный режим: чистим общие куки (хранилище WebView
            // глобально для процесса).
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        }
        setCookies(initialCookies, url) {
            loadInitialPage()
        }
    }

    private fun loadInitialPage() {
        val scheme = Uri.parse(url).scheme?.lowercase()
        if (!isLoadableScheme(scheme)) {
            notifySchemeRedirect(url)
            return
        }
        webView.loadUrl(url)
    }

    /** Применяет настройки нового запроса без загрузки страницы. */
    fun applyReopenSettings(
        url: String,
        userAgent: String?,
        initialCookies: List<Map<String, Any?>>,
        urlBarMode: String,
        enableDebugging: Boolean,
        enableCookiesAndroid: Boolean,
        allowFileAccess: Boolean,
    ) {
        this.url = url
        this.urlBarMode = urlBarMode
        this.enableDebugging = enableDebugging
        this.enableCookiesAndroid = enableCookiesAndroid
        this.allowFileAccess = allowFileAccess
        this.initialCookies.clear()
        this.initialCookies.addAll(initialCookies)
        schemeRedirectNotified = false

        // UA: переданный — применяем, пустой/отсутствует — системный дефолт.
        userAgent?.takeIf { it.isNotEmpty() }?.let {
            webView.settings.userAgentString = it
        } ?: run {
            webView.settings.userAgentString = null
        }
        // Инспектор глобальный для процесса: применяем переданное значение.
        WebView.setWebContentsDebuggingEnabled(enableDebugging)
        applyCookieAcceptance()
        applyFileAccessSettings()
        applyUrlBarMode()
    }

    /** Замена сессии при повторном открытии: вебвью переходит на новый адрес. */
    fun replace(
        url: String,
        userAgent: String?,
        initialCookies: List<Map<String, Any?>>,
        urlBarMode: String,
        enableDebugging: Boolean,
        enableCookiesAndroid: Boolean,
        allowFileAccess: Boolean,
    ) {
        applyReopenSettings(
            url, userAgent, initialCookies, urlBarMode, enableDebugging,
            enableCookiesAndroid, allowFileAccess,
        )

        val scheme = Uri.parse(url).scheme?.lowercase()
        if (!isLoadableScheme(scheme)) {
            notifySchemeRedirect(url)
            return
        }
        setCookies(this.initialCookies, url) {
            webView.loadUrl(url)
        }
    }

    /** Применение настроек нового запроса без перезагрузки страницы. */
    fun reopenSettings(
        url: String,
        userAgent: String?,
        initialCookies: List<Map<String, Any?>>,
        urlBarMode: String,
        enableDebugging: Boolean,
        enableCookiesAndroid: Boolean,
        allowFileAccess: Boolean,
    ) {
        applyReopenSettings(
            url, userAgent, initialCookies, urlBarMode, enableDebugging,
            enableCookiesAndroid, allowFileAccess,
        )
        // Куки применяются к хранилищу; вступят в силу при следующей загрузке.
        setCookies(this.initialCookies, url) { }
    }

    /** Можно ли загрузить адрес с указанной схемой в WebView. */
    private fun isLoadableScheme(scheme: String?): Boolean {
        val loadable = mutableListOf("http", "https", "data", "about", "blob")
        if (allowFileAccess) {
            loadable += "file"
        }
        return scheme in loadable
    }

    /** Единственная доставка onSchemeRedirect за сеанс браузера. */
    private fun notifySchemeRedirect(urlString: String) {
        if (schemeRedirectNotified) {
            return
        }
        schemeRedirectNotified = true
        SimpleNativeWebViewBrowserPlugin.sendEvent("onSchemeRedirect", urlString)
    }

    /** Применяет приём кук процесса; предыдущее значение восстанавливается
     *  в onDestroy (флаг глобальный для процесса). */
    private fun applyCookieAcceptance() {
        if (previousAcceptCookie == null) {
            previousAcceptCookie = CookieManager.getInstance().acceptCookie()
        }
        CookieManager.getInstance().setAcceptCookie(enableCookiesAndroid)
    }

    /** Жёсткие настройки доступа к файлам WebView. */
    private fun applyFileAccessSettings() {
        webView.settings.allowFileAccess = allowFileAccess
        webView.settings.allowFileAccessFromFileURLs = false
        webView.settings.allowUniversalAccessFromFileURLs = false
    }

    /** Устанавливает куки и перезагружает текущую страницу. */
    fun reloadWithCookies(cookies: List<Map<String, Any?>>) {
        val currentUrl = webView.url ?: url
        setCookies(cookies, currentUrl) {
            webView.reload()
        }
    }

    /** Устанавливает куки для [hostUrl]; невалидные значения пропускаются. */
    private fun setCookies(
        cookies: List<Map<String, Any?>>,
        hostUrl: String,
        completion: () -> Unit,
    ) {
        val cookieManager = CookieManager.getInstance()
        val host = Uri.parse(hostUrl).host.orEmpty()
        for (cookie in cookies) {
            val name = cookie["name"] as? String ?: continue
            val value = cookie["value"] as? String ?: continue
            val path = cookie["path"] as? String ?: "/"
            val domain = cookie["domain"] as? String ?: host
            if (!isValidCookieField(name, allowEmpty = false) ||
                !isValidCookieField(value, allowEmpty = true) ||
                !isValidCookieField(path, allowEmpty = true) ||
                !isValidCookieField(domain, allowEmpty = false)
            ) {
                continue
            }
            val secure = cookie["isSecure"] as? Boolean == true
            val httpOnly = cookie["isHttpOnly"] as? Boolean == true
            var cookieString = "$name=$value; Path=$path; Domain=$domain"
            if (secure) {
                cookieString += "; Secure"
            }
            if (httpOnly) {
                cookieString += "; HttpOnly"
            }
            cookieManager.setCookie(hostUrl, cookieString)
        }
        cookieManager.flush()
        completion()
    }

    /** Дополнительная защита от инъекции атрибутов кук на нативной стороне. */
    private fun isValidCookieField(value: String, allowEmpty: Boolean): Boolean {
        if (!allowEmpty && value.isEmpty()) {
            return false
        }
        for (char in value) {
            val code = char.code
            if (code < 0x20 || code == 0x7F || char == ';' || char == ',') {
                return false
            }
        }
        return true
    }

    /** Разбирает сериализованные куки (JSON-массив) из Intent. */
    private fun parseCookiesJson(json: String?): List<Map<String, Any?>> {
        if (json.isNullOrEmpty()) {
            return emptyList()
        }
        return try {
            val array = JSONArray(json)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val map = mutableMapOf<String, Any?>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        when (val value = obj.get(key)) {
                            is String, is Boolean -> map[key] = value
                            else -> map[key] = value?.toString()
                        }
                    }
                    add(map)
                }
            }
        } catch (_: JSONException) {
            emptyList()
        }
    }

    // MARK: - Жизненный цикл

    override fun onDestroy() {
        if (current === this) {
            current = null
            // При пересоздании (смена конфигурации) браузер не закрывался:
            // ложный onClosed не отправляем.
            if (!isChangingConfigurations) {
                notifyClosed()
            }
        }
        // Возвращаем приём кук процесса в исходное состояние.
        previousAcceptCookie?.let { CookieManager.getInstance().setAcceptCookie(it) }
        webView.settings.javaScriptEnabled = false
        webView.webViewClient = null
        webViewDestroyed = true
        webView.removeAllViews()
        webView.destroy()
        super.onDestroy()
    }

    private fun notifyClosed() {
        if (closedNotified) {
            return
        }
        closedNotified = true
        SimpleNativeWebViewBrowserPlugin.sendEvent("onClosed", null)
    }
}
