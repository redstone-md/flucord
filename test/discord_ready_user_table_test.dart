import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_ready_user_table.dart';

void main() {
  test('indexes READY.users and resolves bare ids', () {
    final table = DiscordReadyUserTable()
      ..addAll(const [
        {'id': '123456789012345678', 'username': 'jack'},
        {'id': '234567890123456789', 'username': 'jill'},
        {'username': 'no id at all'},
        {'id': '', 'username': 'empty id'},
        'not an object',
      ]);

    expect(table.user('123456789012345678'), containsPair('username', 'jack'));
    expect(table.user('987654321098765432'), isNull);
    expect(
      table
          .expandUserIds(const ['234567890123456789', '123456789012345678'])
          .map((user) => user['username']),
      ['jill', 'jack'],
    );
    expect(table.unresolvedIds, isEmpty);
  });

  test('ignores a users section that is not a list', () {
    final table = DiscordReadyUserTable()..addAll('READY without users');

    expect(table.user('123456789012345678'), isNull);
    expect(table.expandUserIds('not a list'), isEmpty);
  });

  test(
    'expands recipient_ids into recipients and drops the compressed field',
    () {
      final table = DiscordReadyUserTable()
        ..addAll(const [
          {'id': '123456789012345678', 'username': 'jack'},
        ]);

      final expanded = table.expandRecipients(const {
        'id': '111111111111111111',
        'type': 1,
        'recipient_ids': ['123456789012345678'],
      });

      expect(expanded['recipient_ids'], isNull);
      expect((expanded['recipients']! as List).single, {
        'id': '123456789012345678',
        'username': 'jack',
      });
      expect(table.unresolvedIds, isEmpty);
    },
  );

  test('drops a recipient the user table never carried and reports it', () {
    final table = DiscordReadyUserTable()
      ..addAll(const [
        {'id': '123456789012345678', 'username': 'jack'},
      ]);

    final expanded = table.expandRecipients(const {
      'id': '111111111111111111',
      'recipient_ids': ['123456789012345678', '987654321098765432'],
    });

    expect((expanded['recipients']! as List).length, 1);
    expect(table.unresolvedIds, {'987654321098765432'});
    expect(
      () => table.unresolvedIds.add('222222222222222222'),
      throwsUnsupportedError,
    );
  });

  test('leaves an already uncompressed channel untouched', () {
    final table = DiscordReadyUserTable();
    const channel = {
      'id': '111111111111111111',
      'recipients': [
        {'id': '123456789012345678', 'username': 'jack'},
      ],
    };

    expect(identical(table.expandRecipients(channel), channel), isTrue);
  });

  test('clears the table once READY_SUPPLEMENTAL has been hydrated', () {
    final table = DiscordReadyUserTable()
      ..addAll(const [
        {'id': '123456789012345678', 'username': 'jack'},
      ])
      ..expandUserIds(const ['987654321098765432']);
    expect(table.unresolvedIds, isNotEmpty);

    table.clear();

    expect(table.user('123456789012345678'), isNull);
    expect(table.unresolvedIds, isEmpty);
  });
}
