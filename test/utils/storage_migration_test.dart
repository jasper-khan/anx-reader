import 'dart:io';

import 'package:anx_reader/utils/get_path/storage_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the source data after a successful migration', () async {
    final root = await Directory.systemTemp.createTemp(
      'anx_reader_storage_migration_test_',
    );
    final sourcePath = '${root.path}${Platform.pathSeparator}source';
    final destinationPath = '${root.path}${Platform.pathSeparator}destination';
    final sourceFilePath =
        '$sourcePath${Platform.pathSeparator}file${Platform.pathSeparator}book.epub';
    final sourceDatabasePath =
        '$sourcePath${Platform.pathSeparator}databases${Platform.pathSeparator}app_database.db';
    final destinationFilePath =
        '$destinationPath${Platform.pathSeparator}file${Platform.pathSeparator}book.epub';
    final destinationDatabasePath =
        '$destinationPath${Platform.pathSeparator}databases${Platform.pathSeparator}app_database.db';

    try {
      await Directory(File(sourceFilePath).parent.path).create(recursive: true);
      await Directory(File(sourceDatabasePath).parent.path)
          .create(recursive: true);
      await File(sourceFilePath).writeAsString('book');
      await File(sourceDatabasePath).writeAsString('database');

      final result = await performStorageMigration(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
      );

      expect(result, isTrue);
      expect(await File(sourceFilePath).exists(), isTrue);
      expect(await File(sourceDatabasePath).exists(), isTrue);
      expect(await File(destinationFilePath).readAsString(), 'book');
      expect(await File(destinationDatabasePath).readAsString(), 'database');
    } finally {
      if (await File(sourceFilePath).exists()) {
        await File(sourceFilePath).delete();
      }
      if (await File(sourceDatabasePath).exists()) {
        await File(sourceDatabasePath).delete();
      }
      if (await File(destinationFilePath).exists()) {
        await File(destinationFilePath).delete();
      }
      if (await File(destinationDatabasePath).exists()) {
        await File(destinationDatabasePath).delete();
      }
      if (await Directory('$sourcePath${Platform.pathSeparator}file')
          .exists()) {
        await Directory('$sourcePath${Platform.pathSeparator}file').delete();
      }
      if (await Directory('$sourcePath${Platform.pathSeparator}databases')
          .exists()) {
        await Directory(
          '$sourcePath${Platform.pathSeparator}databases',
        ).delete();
      }
      if (await Directory('$destinationPath${Platform.pathSeparator}file')
          .exists()) {
        await Directory(
          '$destinationPath${Platform.pathSeparator}file',
        ).delete();
      }
      if (await Directory('$destinationPath${Platform.pathSeparator}databases')
          .exists()) {
        await Directory(
          '$destinationPath${Platform.pathSeparator}databases',
        ).delete();
      }
      if (await Directory(sourcePath).exists()) {
        await Directory(sourcePath).delete();
      }
      if (await Directory(destinationPath).exists()) {
        await Directory(destinationPath).delete();
      }
      if (await Directory(root.path).exists()) {
        await Directory(root.path).delete();
      }
    }
  });

  test('keeps the source data when migration copying fails', () async {
    final root = await Directory.systemTemp.createTemp(
      'anx_reader_storage_migration_test_',
    );
    final sourcePath = '${root.path}${Platform.pathSeparator}source';
    final sourceFilePath =
        '$sourcePath${Platform.pathSeparator}file${Platform.pathSeparator}book.epub';
    final destinationPath =
        '${root.path}${Platform.pathSeparator}destination_file';

    try {
      await Directory(File(sourceFilePath).parent.path).create(recursive: true);
      await File(sourceFilePath).writeAsString('book');
      await File(destinationPath).writeAsString('not a directory');

      final result = await performStorageMigration(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
      );

      expect(result, isFalse);
      expect(await File(sourceFilePath).readAsString(), 'book');
    } finally {
      if (await File(sourceFilePath).exists()) {
        await File(sourceFilePath).delete();
      }
      if (await File(destinationPath).exists()) {
        await File(destinationPath).delete();
      }
      if (await Directory('$sourcePath${Platform.pathSeparator}file')
          .exists()) {
        await Directory('$sourcePath${Platform.pathSeparator}file').delete();
      }
      if (await Directory(sourcePath).exists()) {
        await Directory(sourcePath).delete();
      }
      if (await Directory(root.path).exists()) {
        await Directory(root.path).delete();
      }
    }
  });
}
