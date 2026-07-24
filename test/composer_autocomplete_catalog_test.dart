import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/composer_autocomplete_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('parses and replaces the active mention token at the caret', () {
    final query = ComposerAutocompleteQuery.parse('Ship @mi today', 8)!;
    final suggestion = ComposerAutocompleteSuggestion(
      id: 'member-1',
      label: 'Mira',
      description: 'Member',
      insertText: '<@member-1>',
      kind: ComposerAutocompleteKind.member,
      searchTerms: const ['Mira'],
    );

    expect(query.trigger, ComposerAutocompleteTrigger.mention);
    expect(query.text, 'mi');
    expect(
      suggestion.apply('Ship @mi today', query).text,
      'Ship <@member-1> today',
    );
    expect(suggestion.apply('Ship @mi today', query).cursor, 16);
  });

  test(
    'rejects email, completed syntax, invalid selection, and distant triggers',
    () {
      expect(ComposerAutocompleteQuery.parse('mail a@b', 8), isNull);
      expect(ComposerAutocompleteQuery.parse('done <@123>', 11), isNull);
      expect(ComposerAutocompleteQuery.parse('@m', -1), isNull);
      expect(ComposerAutocompleteQuery.parse('@${'x' * 81}', 82), isNull);
    },
  );

  test('projects ranked guild members, roles, and channels', () {
    final catalog = ComposerAutocompleteCatalog.fromWorkspace(
      _workspace,
      _workspace.channelById('general'),
    );

    final memberQuery = ComposerAutocompleteQuery.parse('@mi', 3)!;
    final roleQuery = ComposerAutocompleteQuery.parse('@mod', 4)!;
    final channelQuery = ComposerAutocompleteQuery.parse('#voi', 4)!;

    expect(catalog.suggestionsFor(memberQuery).first.label, 'Mira Stone');
    expect(catalog.suggestionsFor(memberQuery).first.insertText, '<@member-1>');
    expect(
      catalog
          .suggestionsFor(roleQuery)
          .singleWhere((item) => item.kind == ComposerAutocompleteKind.role)
          .insertText,
      '<@&role-1>',
    );
    expect(catalog.suggestionsFor(channelQuery).first.insertText, '<#voice>');
  });

  test('direct conversations expose only their two members', () {
    final catalog = ComposerAutocompleteCatalog.fromWorkspace(
      _workspace,
      _workspace.channelById('dm-1'),
    );
    final mentions = catalog.suggestionsFor(
      ComposerAutocompleteQuery.parse('@', 1)!,
    );

    expect(mentions.map((item) => item.id), ['bot-1', 'member-1']);
    expect(
      catalog.suggestionsFor(ComposerAutocompleteQuery.parse('#', 1)!),
      isEmpty,
    );
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff5865f2,
    ),
    CommunitySpace.directMessages(),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: 'General work',
      kind: ChannelKind.text,
      position: 0,
    ),
    ConversationChannel(
      id: 'voice',
      spaceId: 'guild-1',
      name: 'voice-lab',
      topic: '',
      kind: ChannelKind.voice,
      position: 1,
    ),
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Mira Stone',
      topic: '',
      kind: ChannelKind.text,
      recipientId: 'member-1',
    ),
  ],
  members: const [
    Member(
      id: 'member-1',
      displayName: 'Mira Stone',
      initials: 'MS',
      role: 'Moderator',
      presence: Presence.online,
      colorValue: 0xff57f287,
      spaceIds: {'guild-1'},
      rolesBySpace: {'guild-1': 'Moderator'},
    ),
    Member(
      id: 'bot-1',
      displayName: 'Fly',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff5865f2,
      spaceIds: {'guild-1'},
    ),
    Member(
      id: 'outsider',
      displayName: 'Outside User',
      initials: 'OU',
      role: 'Guest',
      presence: Presence.offline,
      colorValue: 0xff808080,
      spaceIds: {'guild-2'},
    ),
  ],
  messages: const [],
  roles: const [
    CommunityRole(
      id: 'role-1',
      spaceId: 'guild-1',
      name: 'Moderator',
      position: 10,
      colorValue: 0xff57f287,
    ),
  ],
  currentMemberId: 'bot-1',
);
