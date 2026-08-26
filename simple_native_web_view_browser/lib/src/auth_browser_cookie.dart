/// Кука, устанавливаемая в браузере.
class AuthBrowserCookie {
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

  const AuthBrowserCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.isSecure = false,
    this.isHttpOnly = false,
  });
}
