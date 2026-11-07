import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/file_navigation_memory_repository.dart';
import 'package:flucord/src/domain/navigation_memory.dart';

void main() {
  late Directory directory;
  late FileNavigationMemoryRepository repository;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('flucord-navigation-');
    addTearDown(() => directory.deleteSync(recursive: true));
    repository = FileNavigationMemoryRepository(
      directory: () async => directory,
    );
    file = File('${directory.path}/${FileNavigationMemoryRepository.fileName}');
  });

  test('a saved memory reads back whole', () async {
    await repository.save(
      const NavigationMemory(
        accountId: '100000000000000001',
        lastSpaceId: '200000000000000001',
        lastChannels: {'200000000000000001': '300000000000000002'},
        collapsedCategoryIds: {'300000000000000009'},
        openFolderIds: {7},
        positions: {
          '300000000000000002': ReadingPosition(
            messageId: '900000000000000001',
            fromTop: 12.5,
          ),
        },
      ),
    );

    final read = await repository.load();

    expect(read?.accountId, '100000000000000001');
    expect(read?.lastSpaceId, '200000000000000001');
    expect(read?.lastChannels, {'200000000000000001': '300000000000000002'});
    expect(read?.collapsedCategoryIds, {'300000000000000009'});
    expect(read?.openFolderIds, {7});
    final position = read?.positions['300000000000000002'];
    expect(position?.messageId, '900000000000000001');
    expect(position?.fromTop, 12.5);
  });

  test('a file that will not parse reads as no memory', () async {
    file.writeAsStringSync('{broken');

    expect(await repository.load(), isNull);
  });

  test('a file of the wrong shape reads as no memory', () async {
    file.writeAsStringSync('{"lastSpace": 7}');

    expect(await repository.load(), isNull);
  });

  test('a part of the wrong shape is left out', () async {
    file.writeAsStringSync(
      '{"account": "1", "lastSpace": 7, "lastChannels": [],'
      ' "collapsedCategories": ["2", 3], "openFolders": [6, "7"],'
      ' "positions": {"4": {"message": 5}}}',
    );

    final read = await repository.load();

    expect(read?.accountId, '1');
    expect(read?.lastSpaceId, isNull);
    expect(read?.lastChannels, isEmpty);
    expect(read?.collapsedCategoryIds, {'2'});
    expect(read?.openFolderIds, {6});
    expect(read?.positions, isEmpty);
  });

  test('a cleared memory leaves nothing to read', () async {
    await repository.save(const NavigationMemory(accountId: '1'));

    await repository.clear();

    expect(await repository.load(), isNull);
    expect(file.readAsStringSync(), isNot(contains('"account"')));
  });
}
