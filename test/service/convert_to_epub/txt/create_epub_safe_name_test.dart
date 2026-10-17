import 'package:anx_reader/service/convert_to_epub/create_epub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 安全名必须能作为单个文件名段使用：
/// 非空、不含路径分隔符、不以点结尾、不是纯点串（否则会越出父目录）。
void expectSafeSegment(String name) {
  expect(name, isNotEmpty);
  expect(name.contains('/'), isFalse);
  expect(name.contains('\\'), isFalse);
  expect(name.endsWith('.'), isFalse);
  expect(RegExp(r'^\.+$').hasMatch(name), isFalse);
}

void main() {
  group('safeEpubFileName', () {
    // 标题来自被导入 TXT 文件名推导，可能包含路径片段。
    const dangerousTitles = <String>[
      '..',
      '...',
      '../x',
      'a/b',
      r'a\b',
      '',
      '   ',
    ];

    test('危险标题的产物都是合法文件名段', () {
      for (final title in dangerousTitles) {
        expectSafeSegment(safeEpubFileName(title));
      }
    });

    test('空标题与纯点串回退为随机名，且两次调用不同', () {
      for (final title in ['', '   ', '.', '..', '...', ' . . ']) {
        expect(safeEpubFileName(title), startsWith('book_'));
      }
      expect(safeEpubFileName('..'), isNot(safeEpubFileName('..')));
      expect(safeEpubFileName(''), isNot(safeEpubFileName('')));
    });

    test('正常标题保持不变', () {
      expect(safeEpubFileName('正常书名'), '正常书名');
      expect(safeEpubFileName('Book 1'), 'Book 1');
      expect(safeEpubFileName('ABC123'), 'ABC123');
      expect(safeEpubFileName('《..》'), '《..》');
      expect(safeEpubFileName('书名.'), '书名');
      expect(safeEpubFileName('  正常书名  '), '正常书名');
    });

    test('分隔符与非法字符被替换', () {
      expect(safeEpubFileName('a/b'), 'a_b');
      expect(safeEpubFileName(r'a\b'), 'a_b');
      expect(safeEpubFileName('../x'), '_x');
      expect(safeEpubFileName('书名:副题'), '书名_副题');
      expect(safeEpubFileName('a\nb'), 'a_b');
    });

    test('危险标题拼出的目录路径仍落在缓存目录内', () {
      const cacheDirPath = 'cache/anx_temp';
      for (final title in dangerousTitles) {
        final dirPath = p.join(cacheDirPath, safeEpubFileName(title));
        expect(isPathStrictlyInside(cacheDirPath, dirPath), isTrue);
      }
      // 修复前的行为：直接拼接标题会越出缓存目录。
      expect(isPathStrictlyInside(cacheDirPath, p.join(cacheDirPath, '..')),
          isFalse);
    });
  });

  group('isPathStrictlyInside', () {
    test('父目录内部返回 true', () {
      expect(isPathStrictlyInside('cache/anx', 'cache/anx/book'), isTrue);
      expect(
          isPathStrictlyInside('cache/anx', 'cache/anx/book/../book2'), isTrue);
    });

    test('父目录本身返回 false', () {
      expect(isPathStrictlyInside('cache/anx', 'cache/anx'), isFalse);
    });

    test('父目录之外返回 false', () {
      expect(isPathStrictlyInside('cache/anx', 'cache/other'), isFalse);
      expect(isPathStrictlyInside('cache/anx', 'cache/anx/..'), isFalse);
      expect(isPathStrictlyInside('cache/anx', 'cache/anx/../../other'),
          isFalse);
    });
  });
}
