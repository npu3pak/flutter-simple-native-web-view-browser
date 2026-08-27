import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

import 'minimal_example_page.dart';

/// Пользовательский агент Chrome для Android.
const kChromeAndroidUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

/// Пользовательский агент Chrome для iOS (CriOS).
const kChromeIOSUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'CriOS/131.0.6778.134 Mobile/15E148 Safari/604.1';

/// Дефолтный пользовательский агент примера: Chrome той платформы,
/// на которой запущено приложение (несоответствие платформы в UA
/// заставляет сайты считать браузер устаревшим).
final String kDefaultUserAgent = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
    ? kChromeIOSUserAgent
    : kChromeAndroidUserAgent;

const kDefaultUrl = 'https://example.com';
const kDefaultRedirectPrefix = 'demoapp://';

class BrowserDemoScreen extends StatefulWidget {
  const BrowserDemoScreen({super.key});

  @override
  State<BrowserDemoScreen> createState() => _BrowserDemoScreenState();
}

class _BrowserDemoScreenState extends State<BrowserDemoScreen> {
  final _urlController = TextEditingController(text: kDefaultUrl);
  final _uaController = TextEditingController(text: kDefaultUserAgent);
  final _redirectPrefixController =
      TextEditingController(text: kDefaultRedirectPrefix);
  final _cookieNameController = TextEditingController(text: 'demo_cookie');
  final _cookieValueController = TextEditingController(text: 'demo_value');

  final _browser = SimpleNativeBrowser();
  final _log = <String>[];
  final _logScrollController = ScrollController();

  SimpleBrowserUrlBarMode _urlBarMode = SimpleBrowserUrlBarMode.hidden;
  var _usePersistentCookieStore = true;
  var _autoReloadWithCookies = false;
  var _browserOpen = false;
  Timer? _reloadTimer;

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _urlController.dispose();
    _uaController.dispose();
    _redirectPrefixController.dispose();
    _cookieNameController.dispose();
    _cookieValueController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    final time = TimeOfDay.now().format(context);
    setState(() => _log.add('[$time] $message'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _matchesRedirect(Uri url) {
    final prefix = _redirectPrefixController.text.trim();
    if (prefix.isEmpty) {
      return false;
    }
    return url.toString().toLowerCase().startsWith(prefix.toLowerCase());
  }

  void _handleUrl(Uri url, String tag) {
    _addLog('[$tag] $url');
    if (_matchesRedirect(url)) {
      _addLog('[redirect] распознан префикс, закрываю браузер');
      _browser.close();
    }
  }

  List<SimpleBrowserCookie> _cookiesFromForm() {
    final name = _cookieNameController.text.trim();
    final value = _cookieValueController.text.trim();
    if (name.isEmpty || value.isEmpty) {
      return const [];
    }
    return [
      SimpleBrowserCookie(name: name, value: value, path: '/'),
    ];
  }

  Future<void> _openBrowser({Uri? url}) async {
    if (_browserOpen) {
      _addLog('[error] браузер уже открыт');
      return;
    }
    _reloadTimer?.cancel();
    final cookies = _cookiesFromForm();
    try {
      await _browser.open(
        SimpleBrowserOpenRequest(
          url: url ?? Uri.parse(_urlController.text.trim()),
          userAgent: _uaController.text.trim(),
          usePersistentCookieStore: _usePersistentCookieStore,
          initialCookies: cookies,
          urlBarMode: _urlBarMode,
          enableDebugging: true,
          onLoadStop: (u) => _handleUrl(u, 'onLoadStop'),
          onLoadError: (u) => _handleUrl(u, 'onLoadError'),
          onSchemeRedirect: (u) => _handleUrl(u, 'onSchemeRedirect'),
          onClosed: () {
            _browserOpen = false;
            _addLog('[onClosed]');
          },
        ),
      );
      _browserOpen = true;
      _addLog('[open] браузер открыт: '
          '${_urlController.text.trim()} (mode=$_urlBarMode, '
          'persistent=$_usePersistentCookieStore, cookies=${cookies.length})');

      if (_autoReloadWithCookies && cookies.isNotEmpty) {
        _reloadTimer = Timer(const Duration(seconds: 5), () async {
          _addLog('[demo] reloadWithCookies: '
              '${cookies.map((c) => '${c.name}=${c.value}').join(', ')}');
          await _browser.reloadWithCookies(cookies);
        });
      }
    } catch (e) {
      _addLog('[error] не удалось открыть браузер: $e');
    }
  }

  Future<void> _openRedirectDemo() async {
    final redirectUrl = '${_redirectPrefixController.text.trim()}'
        'callback?code=demo123';
    final dataUrl = Uri.dataFromString(
      '<html><body style="font-family:sans-serif;text-align:center;'
      'padding-top:40vh"><a href="$redirectUrl">'
      'Перейти по кастомной схеме</a></body></html>',
      mimeType: 'text/html',
    );
    await _openBrowser(url: dataUrl);
  }

  Future<void> _closeBrowser() async {
    try {
      await _browser.close();
    } catch (e) {
      _addLog('[error] не удалось закрыть браузер: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Native WebView Browser'),
        actions: [
          TextButton(
            key: const ValueKey('minimalExampleButton'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MinimalExamplePage(),
                ),
              );
            },
            child: const Text('Минимальный пример'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('urlField'),
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Стартовый адрес',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('userAgentField'),
            controller: _uaController,
            decoration: const InputDecoration(
              labelText: 'User-Agent',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('redirectPrefixField'),
            controller: _redirectPrefixController,
            decoration: const InputDecoration(
              labelText: 'Префикс редиректа (onLoadError/onLoadStop)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('cookieNameField'),
                  controller: _cookieNameController,
                  decoration: const InputDecoration(
                    labelText: 'Кука: имя',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('cookieValueField'),
                  controller: _cookieValueController,
                  decoration: const InputDecoration(
                    labelText: 'Кука: значение',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Режим адресной строки', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<SimpleBrowserUrlBarMode>(
            groupValue: _urlBarMode,
            onChanged: (value) => setState(() => _urlBarMode = value!),
            child: Column(
              children: [
                for (final mode in SimpleBrowserUrlBarMode.values)
                  RadioListTile<SimpleBrowserUrlBarMode>(
                    key: ValueKey('urlBarMode_${mode.name}'),
                    dense: true,
                    title: Text(mode.name),
                    value: mode,
                  ),
              ],
            ),
          ),
          SwitchListTile(
            key: const ValueKey('persistentStoreSwitch'),
            dense: true,
            title: const Text('Постоянное хранилище кук'),
            value: _usePersistentCookieStore,
            onChanged: (value) => setState(() => _usePersistentCookieStore = value),
          ),
          SwitchListTile(
            key: const ValueKey('autoReloadSwitch'),
            dense: true,
            title: const Text('Авто reloadWithCookies через 5 секунд'),
            value: _autoReloadWithCookies,
            onChanged: (value) => setState(() => _autoReloadWithCookies = value),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('openButton'),
                onPressed: () => _openBrowser(),
                child: const Text('Открыть браузер'),
              ),
              OutlinedButton(
                key: const ValueKey('redirectDemoButton'),
                onPressed: _openRedirectDemo,
                child: const Text('Redirect-demo'),
              ),
              if (_browserOpen)
                OutlinedButton(
                  key: const ValueKey('closeButton'),
                  onPressed: _closeBrowser,
                  child: const Text('Закрыть'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Журнал событий', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              key: const ValueKey('eventLog'),
              controller: _logScrollController,
              padding: const EdgeInsets.all(8),
              children: [
                for (final entry in _log) Text(entry),
                if (_log.isEmpty) const Text('События пока не было'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
