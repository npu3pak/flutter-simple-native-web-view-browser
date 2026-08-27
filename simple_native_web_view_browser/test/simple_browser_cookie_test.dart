import 'package:flutter_test/flutter_test.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

void main() {
  group('SimpleBrowserCookie: валидация значений', () {
    test('валидные куки создаются', () {
      expect(
        () => SimpleBrowserCookie(name: 'session', value: 'abc123'),
        returnsNormally,
      );
      expect(
        () => SimpleBrowserCookie(
          name: 'a',
          value: 'b',
          domain: 'example.com',
          path: '/path',
        ),
        returnsNormally,
      );
    });

    test('имя не может быть пустым', () {
      expect(
        () => SimpleBrowserCookie(name: '', value: 'v'),
        throwsArgumentError,
      );
    });

    test('символ ";" в name запрещён', () {
      expect(
        () => SimpleBrowserCookie(name: 'a;b', value: 'v'),
        throwsArgumentError,
      );
    });

    test('символ ";" в value запрещён', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v; Domain=evil.com'),
        throwsArgumentError,
      );
    });

    test('символ "," в value запрещён', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v,next'),
        throwsArgumentError,
      );
    });

    test('CRLF-инъекция в value запрещена', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v\r\nSet-Cookie: x=y'),
        throwsArgumentError,
      );
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v\nSet-Cookie: x=y'),
        throwsArgumentError,
      );
    });

    test('управляющие символы запрещены', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v\x07'),
        throwsArgumentError,
      );
    });

    test('недопустимый domain отклоняется', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v', domain: 'x;y'),
        throwsArgumentError,
      );
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v', domain: ''),
        throwsArgumentError,
      );
    });

    test('недопустимый path отклоняется', () {
      expect(
        () => SimpleBrowserCookie(name: 'a', value: 'v', path: '/p,q'),
        throwsArgumentError,
      );
    });
  });
}
