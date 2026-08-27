import 'package:flutter/material.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

/// Минимальный пример работы браузера: адрес, кнопки «Открыть»/«Закрыть»
/// и строка состояния с последним событием. Все параметры запроса —
/// значения по умолчанию, без отладочной обвязки.
class MinimalExamplePage extends StatefulWidget {
  const MinimalExamplePage({super.key});

  @override
  State<MinimalExamplePage> createState() => _MinimalExamplePageState();
}

class _MinimalExamplePageState extends State<MinimalExamplePage> {
  final _urlController = TextEditingController(text: 'https://example.com');
  final _browser = SimpleNativeBrowser();

  var _browserOpen = false;
  var _status = 'Браузер не открыт';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _setStatus(String message) {
    setState(() => _status = message);
  }

  Future<void> _openBrowser() async {
    if (_browserOpen) {
      _setStatus('Браузер уже открыт');
      return;
    }
    var urlString = _urlController.text.trim();
    if (urlString.isEmpty) {
      _setStatus('Введите адрес страницы');
      return;
    }
    if (!urlString.contains('://')) {
      urlString = 'https://$urlString';
    }
    try {
      await _browser.open(
        SimpleBrowserOpenRequest(
          url: Uri.parse(urlString),
          onLoadStop: (url) => _setStatus('Загружено: $url'),
          onLoadError: (url) => _setStatus('Ошибка загрузки: $url'),
          onSchemeRedirect: (url) => _setStatus('Кастомная схема: $url'),
          onDownloadStart: (url) => _setStatus('Скачивание файла: $url'),
          onClosed: () {
            _browserOpen = false;
            _setStatus('Браузер закрыт');
          },
        ),
      );
      _browserOpen = true;
      _setStatus('Браузер открыт');
    } catch (e) {
      _setStatus('Не удалось открыть браузер: $e');
    }
  }

  Future<void> _closeBrowser() async {
    try {
      await _browser.close();
      // Статус обновляем и здесь: нативный onClosed приходит отдельным
      // событием и повторит то же сообщение (идемпотентно).
      _browserOpen = false;
      _setStatus('Браузер закрыт');
    } catch (e) {
      _setStatus('Не удалось закрыть браузер: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Минимальный пример')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('minimalUrlField'),
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Адрес страницы',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                key: const ValueKey('minimalOpenButton'),
                onPressed: _openBrowser,
                child: const Text('Открыть'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('minimalCloseButton'),
                onPressed: _browserOpen ? _closeBrowser : null,
                child: const Text('Закрыть'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Статус', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _status,
              key: const ValueKey('minimalStatusText'),
            ),
          ),
        ],
      ),
    );
  }
}
