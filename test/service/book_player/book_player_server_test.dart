import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final server = Server();
  final originalDocumentPath = documentPath;
  Directory? tempRoot;
  Directory? fontDirectory;
  Directory? bgimgDirectory;
  File? bookFile;
  File? fontFile;
  File? bgimgFile;
  File? outsideFile;

  Future<http.Response> get(String requestPath) async {
    final savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      return await http.get(
        Uri.parse('http://127.0.0.1:${server.port}$requestPath'),
      );
    } finally {
      HttpOverrides.global = savedOverrides;
    }
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'lastServerPort': 0});
    final prefs = Prefs();
    await prefs.initPrefs();

    tempRoot = Directory.systemTemp.createTempSync('anx-server-test-');
    documentPath = tempRoot!.path;
    fontDirectory = getFontDir()..createSync();
    bgimgDirectory = getBgimgDir()..createSync();

    bookFile = File(path.join(tempRoot!.path, 'sample.fb2.zip'))
      ..writeAsBytesSync(<int>[0x50, 0x4b, 0x03, 0x04]);
    fontFile = File(path.join(fontDirectory!.path, 'test-font.otf'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    bgimgFile = File(path.join(bgimgDirectory!.path, 'test-bg.png'))
      ..writeAsBytesSync(<int>[4, 5, 6]);
    outsideFile = File(path.join(tempRoot!.path, 'outside.bin'))
      ..writeAsBytesSync(<int>[7, 8, 9]);

    await server.start();
  });

  tearDownAll(() async {
    try {
      await server.stop();
    } finally {
      documentPath = originalDocumentPath;
      if (bookFile?.existsSync() ?? false) {
        bookFile!.deleteSync();
      }
      if (fontFile?.existsSync() ?? false) {
        fontFile!.deleteSync();
      }
      if (bgimgFile?.existsSync() ?? false) {
        bgimgFile!.deleteSync();
      }
      if (outsideFile?.existsSync() ?? false) {
        outsideFile!.deleteSync();
      }
      if (fontDirectory?.existsSync() ?? false) {
        fontDirectory!.deleteSync();
      }
      if (bgimgDirectory?.existsSync() ?? false) {
        bgimgDirectory!.deleteSync();
      }
      if (tempRoot?.existsSync() ?? false) {
        tempRoot!.deleteSync();
      }
    }
  });

  test('serves a registered book and keeps it valid across restart', () async {
    final capability = server.registerBookPath(bookFile!.path);
    expect(capability, matches(RegExp(r'^[A-Za-z0-9_-]+\.fb2\.zip$')));

    var response = await get('/book/$capability');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.bodyBytes, <int>[0x50, 0x4b, 0x03, 0x04]);

    final legacyPath = Uri.encodeComponent(bookFile!.path);
    response = await get('/book/$legacyPath');
    expect(response.statusCode, HttpStatus.notFound);
    expect((await get('/book/unknown-capability.epub')).statusCode,
        HttpStatus.notFound);

    await server.stop();
    await server.start();
    response = await get('/book/$capability');
    expect(response.statusCode, HttpStatus.ok);

    server.unregisterBook(capability);
    expect((await get('/book/$capability')).statusCode, HttpStatus.notFound);
  });

  test('keeps local resources contained and serves legal resources', () async {
    var response = await get('/fonts/test-font.otf');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.bodyBytes, <int>[1, 2, 3]);

    response = await get('/fonts/%2e%2e%2Foutside.bin');
    expect(response.statusCode, HttpStatus.notFound);

    response = await get('/bgimg/local/test-bg.png');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.bodyBytes, <int>[4, 5, 6]);

    response = await get('/bgimg/local/%2e%2e%2Foutside.bin');
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('serves the built-in background asset without broadening its path',
      () async {
    final asset = await rootBundle.load('assets/images/bgimg/bg1.jpg');
    final response = await get('/bgimg/assets/assets/images/bgimg/bg1.jpg');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.bodyBytes, asset.buffer.asUint8List());

    expect(
      (await get('/bgimg/assets/assets/images/bgimg/../pubspec.yaml'))
          .statusCode,
      HttpStatus.notFound,
    );
  });
}
