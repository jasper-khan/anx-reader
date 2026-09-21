import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    tempRoot = await Directory.systemTemp.createTemp('anx_style_widget_test_');
    await Directory(
      '${tempRoot.path}${Platform.pathSeparator}font',
    ).create(recursive: true);
    documentPath = tempRoot.path;
    await Prefs().saveLocaleToPrefs('en');
    Prefs().showActionLabels = false;
    await Server().start();
  });

  tearDown(() async {
    await Server().stop();
    documentPath = previousDocumentPath;
    final fontFile = File(
      '${tempRoot.path}${Platform.pathSeparator}font${Platform.pathSeparator}custom.ttf',
    );
    if (await fontFile.exists()) {
      await fontFile.delete();
    }
    final fontDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}font',
    );
    if (await fontDir.exists()) {
      await fontDir.delete();
    }
    if (await tempRoot.exists()) {
      await tempRoot.delete();
    }
  });

  testWidgets('caches fonts across rebuilds and refreshes on locale change',
      (tester) async {
    final fontFile = File(
      '${tempRoot.path}${Platform.pathSeparator}font${Platform.pathSeparator}custom.ttf',
    );
    // Six zero bytes are enough for getFontNameFromFile to return its invalid
    // font fallback without depending on a real font asset.
    fontFile.writeAsBytesSync(List<int>.filled(6, 0));

    await _pumpLocalized(tester, const Locale('en'));

    final state = tester.state<StyleWidgetState>(find.byType(StyleWidget));
    final englishFonts = state.fonts();
    final englishDownload = englishFonts.firstWhere(
      (font) => font.name == 'download',
    );
    expect(
      englishFonts.any((font) => font.name == 'customFont0'),
      isTrue,
    );

    fontFile.deleteSync();
    await _pumpLocalized(tester, const Locale('en'));

    final rebuiltState =
        tester.state<StyleWidgetState>(find.byType(StyleWidget));
    final cachedFonts = rebuiltState.fonts();
    expect(identical(cachedFonts, englishFonts), isTrue);
    expect(cachedFonts.any((font) => font.name == 'customFont0'), isTrue);

    await Prefs().saveLocaleToPrefs('zh-CN');
    await _pumpLocalized(tester, const Locale('zh', 'CN'));

    final chineseFonts = rebuiltState.fonts();
    final chineseDownload = chineseFonts.firstWhere(
      (font) => font.name == 'download',
    );
    expect(identical(chineseFonts, englishFonts), isFalse);
    expect(chineseFonts.any((font) => font.name == 'customFont0'), isFalse);
    expect(chineseDownload.label, isNot(englishDownload.label));
  });
}

Future<void> _pumpLocalized(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(_host(locale));
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(StyleWidget).evaluate().isNotEmpty) {
      return;
    }
  }
  expect(find.byType(StyleWidget), findsOneWidget);
}

Widget _host(Locale locale) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: StyleWidget(
          themes: const <ReadTheme>[],
          epubPlayerKey: GlobalKey<EpubPlayerState>(),
          setCurrentPage: (_) {},
          hideAppBarAndBottomBar: (_) {},
        ),
      ),
    ),
  );
}
