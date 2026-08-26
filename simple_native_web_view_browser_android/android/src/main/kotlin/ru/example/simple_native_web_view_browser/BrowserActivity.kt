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
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.content.ContextCompat

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
    private val initialCookies = mutableListOf<Map<String, Any?>>()
    private var urlBarMode = "hidden"
    private var closedNotified = false

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
        @Suppress("UNCHECKED_CAST")
        initialCookies.addAll(
            (extras.getSerializable(EXTRA_INITIAL_COOKIES) as? List<Map<String, Any?>>).orEmpty(),
        )
        urlBarMode = extras.getString(EXTRA_URL_BAR_MODE) ?: "hidden"

        setContentView(R.layout.browser_activity)

        webView = findViewById(R.id.webView)
        webView.settings.userAgentString = extras.getString(EXTRA_USER_AGENT).orEmpty()
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.webViewClient = object : WebViewClient() {
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
                updateChromeState()
                // Кастомная схема (например, demoapp://...) не загружается:
                // ERR_UNKNOWN_URL_SCHEME приходит сюда с адресом редиректа.
                val failingUrl = request?.url?.toString() ?: url
                SimpleNativeWebViewBrowserPlugin.sendEvent("onLoadError", failingUrl)
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

        when (urlBarMode) {
            "hidden" -> {
                titleView?.visibility = View.VISIBLE
                titleView?.text = Uri.parse(url).host
            }
            else -> {
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
        webView.loadUrl(urlString)
    }

    private fun updateChromeState() {
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
        setCookies(initialCookies) {
            loadInitialPage()
        }
    }

    private fun loadInitialPage() {
        val scheme = Uri.parse(url).scheme?.lowercase()
        if (scheme !in listOf("http", "https", "data", "about", "file", "blob")) {
            SimpleNativeWebViewBrowserPlugin.sendEvent("onLoadError", url)
            return
        }
        webView.loadUrl(url)
    }

    /** Устанавливает куки и перезагружает текущую страницу. */
    fun reloadWithCookies(cookies: List<Map<String, Any?>>) {
        setCookies(cookies) {
            webView.reload()
        }
    }

    private fun setCookies(cookies: List<Map<String, Any?>>, completion: () -> Unit) {
        val cookieManager = CookieManager.getInstance()
        val host = Uri.parse(url).host.orEmpty()
        for (cookie in cookies) {
            val name = cookie["name"] as? String ?: continue
            val value = cookie["value"] as? String ?: continue
            val path = cookie["path"] as? String ?: "/"
            val domain = cookie["domain"] as? String ?: host
            val secure = cookie["isSecure"] as? Boolean == true
            val httpOnly = cookie["isHttpOnly"] as? Boolean == true
            var cookieString = "$name=$value; Path=$path; Domain=$domain"
            if (secure) {
                cookieString += "; Secure"
            }
            if (httpOnly) {
                cookieString += "; HttpOnly"
            }
            cookieManager.setCookie(url, cookieString)
        }
        cookieManager.flush()
        completion()
    }

    // MARK: - Жизненный цикл

    override fun onDestroy() {
        if (current === this) {
            current = null
            notifyClosed()
        }
        webView.settings.javaScriptEnabled = false
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
