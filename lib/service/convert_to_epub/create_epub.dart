import 'dart:io';

import 'package:anx_reader/service/convert_to_epub/generate_toc.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// 判断 [childPath] 是否严格位于 [parentPath] 之内（两者相等时返回 false）。
///
/// 用途：递归删除临时目录前做最后一道校验，确认删除目标确实在缓存目录内部。
/// 两侧路径先规范化（absolute + normalize）再比较，标题里带进来的 `..`
/// 等片段无法绕过判断。依赖 pubspec 中已声明的 `package:path`。
bool isPathStrictlyInside(String parentPath, String childPath) {
  final parent = p.normalize(p.absolute(parentPath));
  final child = p.normalize(p.absolute(childPath));
  return p.isWithin(parent, child);
}

/// 把书名等外部来源标题转换成可安全用作单个文件名（或目录名）段的字符串。
///
/// 用途：`createEpub` 用标题拼接缓存目录名与 epub 文件名。标题由 TXT 文件名
/// 推导而来（如 `..txt`、`《..》.txt`），可能含路径分隔符或 `..`，
/// 拼接出的路径会越出缓存目录，导致 `deleteSync(recursive: true)` 误删父目录。
///
/// 规则：截掉首尾空白；把路径分隔符与非法字符替换为 `_`；去掉首尾的空白与点；
/// 结果为空时回退为随机名。中文、`《》`、括号等正常字符原样保留。
String safeEpubFileName(String title) {
  var name = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  name = name.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  if (name.isEmpty) name = 'book_${const Uuid().v4()}';
  return name;
}

Future<File> createEpub(
  String titleString,
  String authorString,
  // List<String> chapters,
  List<Section> sections,
) async {
  // create epub
  final cacheDir = await getAnxTempDir();
  final safeTitle = safeEpubFileName(titleString);
  final epubDir = Directory('${cacheDir.path}/$safeTitle');
  // 仅当确认目录确实位于缓存目录内部时才递归删除，防止越界删除父目录。
  if (epubDir.existsSync() &&
      isPathStrictlyInside(cacheDir.path, epubDir.path)) {
    epubDir.deleteSync(recursive: true);
  }
  epubDir.createSync();

  // mimetype
  final mimetypeFile = File('${epubDir.path}/mimetype');
  mimetypeFile.createSync();
  mimetypeFile.writeAsStringSync('application/epub+zip');

  // META-INF/container.xml
  final metainfDir = Directory('${epubDir.path}/META-INF');
  metainfDir.createSync();
  final containerFile = File('${epubDir.path}/META-INF/container.xml');
  containerFile.createSync();
  containerFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  // OEBPS
  final oebpsDir = Directory('${epubDir.path}/OEBPS');
  oebpsDir.createSync();

  // content.opf
  final contentFile = File('${oebpsDir.path}/content.opf');
  contentFile.createSync();
  final manifestItems = List.generate(
          sections.length,
          (index) =>
              '    <item id="item$index" href="xhtml/$index.xhtml" media-type="application/xhtml+xml"/>')
      .join('\n');
  final spineItems = List.generate(
          sections.length, (index) => '    <itemref idref="item$index"/>')
      .join('\n');

  contentFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${_escapeXml(titleString)}</dc:title>
    <dc:creator>${_escapeXml(authorString)}</dc:creator>
    <dc:identifier id="pub-id">urn:uuid:${const Uuid().v4()}</dc:identifier>
  </metadata>

  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
    $manifestItems
  </manifest>

  <spine toc="ncx">
    $spineItems
  </spine>
</package>''');

  // toc.ncx
  final tocFile = File('${oebpsDir.path}/toc.ncx');
  tocFile.createSync();
  tocFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="zh-CN">
  <head>
    <meta name="dtb:uid" content="urn:uuid:${const Uuid().v4()}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="${sections.length}"/>
  </head>
  <docTitle>
    <text>${_escapeXml(titleString)}</text>
  </docTitle>
  <navMap>
    ${generateNestedToc(sections)}
  </navMap>
</ncx>''');

  // style.css
  final styleFile = File('${oebpsDir.path}/style.css');
  styleFile.createSync();
  styleFile.writeAsStringSync('''body {

}
''');
  // xhtml
  final xhtmlDir = Directory('${oebpsDir.path}/xhtml');
  xhtmlDir.createSync();
  for (var i = 0; i < sections.length; i++) {
    final xhtmlFile = File('${xhtmlDir.path}/$i.xhtml');
    xhtmlFile.createSync();

    final rawTitle = sections[i].title.trim();
    final level = sections[i].level.clamp(1, 6);
    final content = sections[i].content;

    final heading = rawTitle.isEmpty
        ? ''
        : '    <h$level>${_escapeXml(rawTitle)}</h$level>';

    final paragraphLines = content
        .split('\n')
        .map((e) => e.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => '    <p>${_escapeXml(line)}</p>')
        .toList();

    final bodyBuffer = StringBuffer();
    if (heading.isNotEmpty) {
      bodyBuffer.writeln(heading);
    }
    for (final line in paragraphLines) {
      bodyBuffer.writeln(line);
    }

    final bodyContent = bodyBuffer.toString().trimRight();

    xhtmlFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>${_escapeXml(rawTitle.isEmpty ? titleString : rawTitle)}</title>
  </head>
  <body>
${bodyContent.isEmpty ? '' : '$bodyContent\n'}
  </body>
</html>''');
  }

  // zip
  final zipFile = File('${cacheDir.path}/$safeTitle.epub');
  zipFile.createSync();

  try {
    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);
    await encoder.addFile(mimetypeFile);
    await encoder.addDirectory(metainfDir);
    await encoder.addDirectory(oebpsDir);
    await encoder.close();
  } catch (e) {
    AnxLog.severe('EPUB: ZIP compression failed: $e');
    rethrow;
  }

  // 同样只在缓存目录内部时才清理临时目录。
  if (isPathStrictlyInside(cacheDir.path, epubDir.path)) {
    epubDir.deleteSync(recursive: true);
  }
  return zipFile;
}
