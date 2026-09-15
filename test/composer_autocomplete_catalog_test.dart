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

  test('a colon matches custom emoji by name across servers, and unicode', () {
    final catalog = ComposerAutocompleteCatalog.fromWorkspace(
      _workspace,
      _workspace.channelById('general'),
    );

    final forgeQuery = ComposerAutocompleteQuery.parse('a :forge_s', 10)!;
    expect(forgeQuery.trigger, ComposerAutocompleteTrigger.emoji);
    final forgeMatches = catalog.suggestionsFor(forgeQuery);
    expect(forgeMatches.first.kind, ComposerAutocompleteKind.emoji);
    expect(forgeMatches.first.id, 'forge-spark');
    expect(forgeMatches.first.label, 'forge_spark');
    // The other server names the emoji it owns.
    expect(forgeMatches.first.description, 'Forge');
    expect(forgeMatches.first.insertText, '<:forge_spark:forge-spark>');

    final relayQuery = ComposerAutocompleteQuery.parse(':relay', 6)!;
    final relayMatches = catalog.suggestionsFor(relayQuery);
    // Only the available one; the unavailable `relay_gone` is withheld.
    expect(
      relayMatches
          .where((item) => !item.id.startsWith('unicode-'))
          .map((item) => item.id),
      ['relay-horn'],
    );
    expect(relayMatches.first.description, 'Night Shift');
    expect(relayMatches.first.insertText, '<:relay_horn:relay-horn>');
  });

  test('a colon matches the unicode catalogue and inserts the glyph', () {
    final catalog = ComposerAutocompleteCatalog.fromWorkspace(
      _workspace,
      _workspace.channelById('general'),
    );

    final rocketQuery = ComposerAutocompleteQuery.parse('Ship it :rocket', 15)!;
    final matches = catalog.suggestionsFor(rocketQuery);
    expect(matches.first.id, 'unicode-rocket');
    expect(matches.first.label, 'rocket');
    expect(matches.first.insertText, '🚀');
    // What lands in the composer replaces the whole `:rock` token.
    final edit = matches.first.apply('Ship it :rocket today', rocketQuery);
    expect(edit.text, 'Ship it 🚀 today');

    // A keyword also finds it: `launch` is one of the rocket's words.
    final launchQuery = ComposerAutocompleteQuery.parse('Ship it :launch', 15)!;
    expect(
      catalog
          .suggestionsFor(launchQuery)
          .any((item) => item.id == 'unicode-rocket'),
      isTrue,
    );
  });

  test('a colon inside a mention is not an emoji trigger', () {
    // The `:` inside a `<:name:id>` is already spoken for.
    expect(ComposerAutocompleteQuery.parse('a <:forge:', 10), isNull);
    // A bare colon at a word boundary opens the emoji trigger, with an empty
    // name, exactly the way Discord's own client opens it.
    final bare = ComposerAutocompleteQuery.parse('hi :', 4)!;
    expect(bare.trigger, ComposerAutocompleteTrigger.emoji);
    expect(bare.text, '');
    expect(bare.start, 3);
    expect(bare.end, 4);
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
    CommunitySpace(
      id: 'guild-2',
      name: 'Night Shift',
      monogram: 'NS',
      colorValue: 0xff765341,
    ),
    CommunitySpace.directMessages(),
  ],
  emojis: const [
    GuildEmoji(id: 'forge-spark', spaceId: 'guild-1', name: 'forge_spark'),
    GuildEmoji(id: 'relay-horn', spaceId: 'guild-2', name: 'relay_horn'),
    // Another server's emoji that is unavailable right now: Discord withholds
    // it from autocomplete, and so does the catalog.
    GuildEmoji(
      id: 'gone',
      spaceId: 'guild-2',
      name: 'relay_gone',
      available: false,
    ),
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
