/// Кука, устанавливаемая в браузере.
class SimpleBrowserCookie {
  /// Имя куки.
  final String name;

  /// Значение куки.
  final String value;

  /// Домен, для которого действует кука.
  final String? domain;

  /// Путь, для которого действует кука.
  final String? path;

  /// Передавать куку только по защищённому соединению.
  final bool isSecure;

  /// Кука недоступна скриптам на странице.
  final bool isHttpOnly;

  /// Создаёт куку с проверкой допустимости значений.
  ///
  /// В [name], [value], [domain] и [path] запрещены символы `;` и `,`,
  /// а также управляющие символы (CR/LF и прочие из диапазона 0x00–0x1F,
  /// 0x7F) — они позволяют внедрить дополнительные атрибуты в строку
  /// Set-Cookie на нативной стороне. [name] не может быть пустым.
  SimpleBrowserCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.isSecure = false,
    this.isHttpOnly = false,
  }) {
    _validate('name', name, allowEmpty: false);
    _validate('value', value);
    if (domain != null) {
      _validate('domain', domain!, allowEmpty: false);
    }
    if (path != null) {
      _validate('path', path!);
    }
  }

  static void _validate(String field, String value, {bool allowEmpty = true}) {
    if (!allowEmpty && value.isEmpty) {
      throw ArgumentError.value(value, field, 'не может быть пустым');
    }
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7F) {
        throw ArgumentError.value(
          value,
          field,
          'содержит недопустимые управляющие символы',
        );
      }
    }
    if (value.contains(';') || value.contains(',')) {
      throw ArgumentError.value(
        value,
        field,
        'содержит недопустимые символы ";", ","',
      );
    }
  }
}
