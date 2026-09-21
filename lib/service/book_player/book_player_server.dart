import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;

class Server {
  static final Server _singleton = Server._internal();

  factory Server() {
    return _singleton;
  }

  Server._internal();

  HttpServer? _server;
  final Random _random = Random.secure();
  final Map<String, String> _bookCapabilities = <String, String>{};

  Future<void> start() async {
    if (_server != null) {
      await stop();
    }

    final handler = const shelf.Pipeline().addHandler(_handleRequests);

    final int port = Prefs().lastServerPort;

    try {
      _server = await io.serve(handler, '127.0.0.1', port);
    } catch (e, s) {
      _server = await io.serve(handler, '127.0.0.1', 0);
      // Keep the fallback quiet about request data, while retaining the
      // original bind failure for diagnosing a stale saved port.
      stderr.writeln('Server: failed to bind saved port $port: $e\n$s');
    }

    Prefs().lastServerPort = _server!.port;
  }

  int get port {
    return _server!.port;
  }

  Future<void> stop() async {
    if (_server == null) {
      return;
    }
    await _server?.close(force: true);
    _server = null;
    // Keep capabilities across a restart. iOS may restart the listener while
    // an existing WebView still holds its book URL.
  }

  String registerBookPath(String filePath) {
    final canonicalPath = _resolveCanonicalFile(File(filePath));
    if (canonicalPath == null) {
      throw StateError('Book file is not available');
    }

    final suffix = _bookFileSuffix(canonicalPath);

    String capability;
    do {
      capability = '${_newCapability()}$suffix';
    } while (_bookCapabilities.containsKey(capability));
    _bookCapabilities[capability] = canonicalPath;
    return capability;
  }

  void unregisterBook(String capability) {
    _bookCapabilities.remove(capability);
  }

  String _newCapability() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _bookFileSuffix(String filePath) {
    final lowerPath = filePath.toLowerCase();
    for (final suffix in const [
      '.fb2.zip',
      '.epub',
      '.mobi',
      '.azw3',
      '.fb2',
      '.pdf',
      '.txt',
      '.cbz',
      '.fbz',
    ]) {
      if (lowerPath.endsWith(suffix)) {
        return suffix;
      }
    }
    final extension = path.extension(lowerPath);
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
  }

  Future<String> _loadAsset(String assetPath) async {
    return rootBundle.loadString(assetPath);
  }

  Future<shelf.Response> _handleRequests(shelf.Request request) async {
    final uriPath = request.requestedUri.path;

    if (uriPath.startsWith('/book/')) {
      return _handleBookRequest(request);
    } else if (uriPath.startsWith('/js/')) {
      final content = await _loadAsset('assets/js/${path.basename(uriPath)}');
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': 'application/javascript'},
      );
    } else if (uriPath.startsWith('/fonts/')) {
      return _handleFontRequest(uriPath);
    } else if (uriPath.startsWith('/foliate-js/')) {
      if (uriPath.endsWith('.epub')) {
        final file =
            await rootBundle.load('assets/foliate-js/${uriPath.substring(12)}');
        return shelf.Response.ok(
          file.buffer.asUint8List(),
          headers: {'Content-Type': 'application/epub+zip'},
        );
      }
      final content =
          await _loadAsset('assets/foliate-js/${uriPath.substring(12)}');

      final String contentType;
      if (uriPath.endsWith('.html')) {
        contentType = 'text/html';
      } else if (uriPath.endsWith('.css')) {
        contentType = 'text/css';
      } else if (uriPath.endsWith('.js')) {
        contentType = 'application/javascript';
      } else if (uriPath.endsWith('.json')) {
        contentType = 'application/json';
      } else {
        contentType = 'application/octet-stream';
      }

      return shelf.Response.ok(
        content,
        headers: {'Content-Type': contentType},
      );
    } else if (uriPath.startsWith('/bgimg/')) {
      return _handleBgimgRequest(request);
    }

    return shelf.Response.notFound('Not found');
  }

  shelf.Response _handleBookRequest(shelf.Request request) {
    final capability = request.requestedUri.path.substring('/book/'.length);
    if (capability.isEmpty || capability.contains('/')) {
      return shelf.Response.notFound('Book not found');
    }

    final registeredPath = _bookCapabilities[capability];
    if (registeredPath == null) {
      return shelf.Response.notFound('Book not found');
    }

    final canonicalPath = _resolveCanonicalFile(File(registeredPath));
    if (canonicalPath == null || !_samePath(canonicalPath, registeredPath)) {
      return shelf.Response.notFound('Book not found');
    }

    final file = File(canonicalPath);
    return shelf.Response.ok(
      file.openRead(),
      headers: {'Content-Type': 'application/epub+zip'},
    );
  }

  shelf.Response _handleFontRequest(String uriPath) {
    final decodedName = _decodePath(uriPath.substring('/fonts/'.length));
    if (decodedName == null || !_isSimpleFileName(decodedName)) {
      return shelf.Response.notFound('Font not found');
    }

    final filePath = _resolveContainedFile(getFontDir(), decodedName);
    if (filePath == null) {
      return shelf.Response.notFound('Font not found');
    }

    return shelf.Response.ok(
      File(filePath).openRead(),
      headers: {
        'Content-Type': 'font/opentype',
        'cache-control': 'public, max-age=31536000',
      },
    );
  }

  Future<shelf.Response> _handleBgimgRequest(shelf.Request request) async {
    final bgimgPath =
        _decodePath(request.requestedUri.path.substring('/bgimg/'.length));
    if (bgimgPath == null) {
      return shelf.Response.notFound('Bgimg not found');
    }

    Uint8List bytes;
    if (bgimgPath.startsWith('assets/')) {
      final assetPath = bgimgPath.substring('assets/'.length);
      if (!assetPath.startsWith('assets/images/bgimg/') ||
          assetPath.contains('..') ||
          assetPath.contains('\\')) {
        return shelf.Response.notFound('Bgimg not found');
      }
      try {
        bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      } catch (_) {
        return shelf.Response.notFound('Bgimg not found');
      }
    } else if (bgimgPath.startsWith('local/')) {
      final localName = bgimgPath.substring('local/'.length);
      if (!_isSimpleFileName(localName)) {
        return shelf.Response.notFound('Bgimg not found');
      }
      final filePath = _resolveContainedFile(getBgimgDir(), localName);
      if (filePath == null) {
        return shelf.Response.notFound('Bgimg not found');
      }
      try {
        bytes = await File(filePath).readAsBytes();
      } catch (_) {
        return shelf.Response.notFound('Bgimg not found');
      }
    } else {
      return shelf.Response.notFound('Bgimg not found');
    }

    return shelf.Response.ok(
      bytes,
      headers: {'Content-Type': 'image/png'},
    );
  }

  String? _decodePath(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return null;
    }
  }

  bool _isSimpleFileName(String value) {
    return value.isNotEmpty &&
        value != '.' &&
        value != '..' &&
        !value.contains('/') &&
        !value.contains('\\');
  }

  String? _resolveContainedFile(Directory root, String fileName) {
    try {
      final rootPath = path.normalize(root.resolveSymbolicLinksSync());
      final candidate = File(path.join(rootPath, fileName));
      if (!candidate.existsSync()) {
        return null;
      }
      final candidatePath =
          path.normalize(candidate.resolveSymbolicLinksSync());
      if (!_isWithinDirectory(rootPath, candidatePath)) {
        return null;
      }
      return candidatePath;
    } catch (_) {
      return null;
    }
  }

  String? _resolveCanonicalFile(File file) {
    try {
      if (!file.existsSync()) {
        return null;
      }
      final canonicalPath = path.normalize(file.resolveSymbolicLinksSync());
      return File(canonicalPath).existsSync() ? canonicalPath : null;
    } catch (_) {
      return null;
    }
  }

  bool _isWithinDirectory(String rootPath, String candidatePath) {
    final relativePath = path.relative(candidatePath, from: rootPath);
    return relativePath != '.' &&
        relativePath != '..' &&
        !relativePath.startsWith('..${Platform.pathSeparator}') &&
        !path.isAbsolute(relativePath);
  }

  bool _samePath(String first, String second) {
    if (Platform.isWindows) {
      return path.normalize(first).toLowerCase() ==
          path.normalize(second).toLowerCase();
    }
    return path.normalize(first) == path.normalize(second);
  }
}
