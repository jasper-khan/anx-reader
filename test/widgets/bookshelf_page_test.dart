import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/page/home_page/bookshelf_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBookList extends BookList {
  _FakeBookList(this.books);

  final List<List<Book>> books;

  @override
  Future<List<List<Book>>> build() async => books;
}

class _FakeTagList extends TagList {
  @override
  Future<List<Tag>> build() async => <Tag>[];
}

class _FakeGroupDao extends GroupDao {
  @override
  Future<List<TbGroup>> build() async => <TbGroup>[];
}

class _FakeSyncStatus extends SyncStatus {
  _FakeSyncStatus(this.value);

  final SyncStatusModel value;

  @override
  Future<SyncStatusModel> build() async => value;
}

Book _book(int index) {
  final now = DateTime(2026, 1, 1);
  return Book(
    id: index + 1,
    title: 'Book $index',
    coverPath: '',
    filePath: '',
    lastReadPosition: '',
    readingPercentage: 0,
    author: 'Author $index',
    isDeleted: false,
    rating: 0,
    createTime: now,
    updateTime: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bookshelf lazily builds books and scrolls to later items',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = Prefs();
    await prefs.initPrefs();

    const totalBooks = 300;
    final books = List<List<Book>>.generate(
      totalBooks,
      (index) => <Book>[_book(index)],
    );
    const syncStatus = SyncStatusModel(
      localOnly: <int>[],
      remoteOnly: <int>[],
      both: <int>[],
      nonExistent: <int>[],
      downloading: <int>[],
      uploading: <int>[],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookListProvider.overrideWith(() => _FakeBookList(books)),
          tagListProvider.overrideWith(_FakeTagList.new),
          groupDaoProvider.overrideWith(_FakeGroupDao.new),
          syncStatusProvider.overrideWith(
              () => _FakeSyncStatus(syncStatus)),
        ],
        child: provider.ChangeNotifierProvider<Prefs>.value(
          value: prefs,
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const BookshelfPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialFolders = tester.widgetList(find.byType(BookFolder)).length;
    expect(initialFolders, greaterThan(0));
    expect(initialFolders, lessThan(totalBooks));
    expect(find.text('Book ${totalBooks - 1}'), findsNothing);

    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);
    final grid = tester.widget<GridView>(gridFinder);
    expect(grid.childrenDelegate, isA<SliverChildBuilderDelegate>());

    await tester.drag(gridFinder, const Offset(0, -100000));
    await tester.pumpAndSettle();

    expect(find.text('Book ${totalBooks - 1}'), findsWidgets);
  });
}
