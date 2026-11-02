import '../domain/chat_models.dart';
import '../domain/unicode_emoji.dart';

enum ComposerAutocompleteTrigger { mention, channel, emoji }

enum ComposerAutocompleteKind { member, role, channel, emoji }

final class ComposerAutocompleteQuery {
  const ComposerAutocompleteQuery({
    required this.trigger,
    required this.text,
    required this.start,
    required this.end,
  });

  final ComposerAutocompleteTrigger trigger;
  final String text;
  final int start;
  final int end;

  static ComposerAutocompleteQuery? parse(String value, int cursor) {
    if (cursor < 0 || cursor > value.length) return null;
    final searchStart = (cursor - 80).clamp(0, cursor);
    for (var index = cursor - 1; index >= searchStart; index--) {
      final character = value[index];
      if (character == '\n' ||
          character == '\r' ||
          character == '<' ||
          character == '>') {
        return null;
      }
      final trigger = switch (character) {
        '@' => ComposerAutocompleteTrigger.mention,
        '#' => ComposerAutocompleteTrigger.channel,
        ':' => ComposerAutocompleteTrigger.emoji,
        _ => null,
      };
      if (trigger == null) continue;
      if (index > 0 && !_isBoundary(value[index - 1])) return null;
      final text = value.substring(index + 1, cursor);
      if (text.contains('@') || text.contains('#') || text.contains(':')) {
        return null;
      }
      return ComposerAutocompleteQuery(
        trigger: trigger,
        text: text.trim(),
        start: index,
        end: cursor,
      );
    }
    return null;
  }

  static bool _isBoundary(String character) =>
      RegExp(r'\s').hasMatch(character) || '([{,;:"\''.contains(character);
}

final class ComposerAutocompleteEdit {
  const ComposerAutocompleteEdit({required this.text, required this.cursor});

  final String text;
  final int cursor;
}

final class ComposerAutocompleteSuggestion {
  ComposerAutocompleteSuggestion({
    required this.id,
    required this.label,
    required this.description,
    required this.insertText,
    required this.kind,
    required List<String> searchTerms,
    this.initials,
    this.colorValue,
    this.avatarUrl,
    this.emojiUrl,
    this.unicodeGlyph,
  }) : _searchTerms = List.unmodifiable(searchTerms);

  final String id;
  final String label;
  final String description;
  final String insertText;
  final ComposerAutocompleteKind kind;
  final String? initials;
  final int? colorValue;
  final String? avatarUrl;

  /// The custom emoji's image, or null when this suggestion is not one.
  final String? emojiUrl;

  /// The unicode emoji's own character, or null when this suggestion is not
  /// one. The row draws it as the emoji rather than a stand-in shape.
  final String? unicodeGlyph;
  final List<String> _searchTerms;

  ComposerAutocompleteEdit apply(
    String value,
    ComposerAutocompleteQuery query,
  ) {
    final needsSpace =
        query.end >= value.length || !RegExp(r'\s').hasMatch(value[query.end]);
    final inserted = '$insertText${needsSpace ? ' ' : ''}';
    return ComposerAutocompleteEdit(
      text: value.replaceRange(query.start, query.end, inserted),
      cursor: query.start + inserted.length,
    );
  }
}

final class ComposerAutocompleteCatalog {
  const ComposerAutocompleteCatalog.empty() : _sources = null;

  /// Costs nothing to make, so the pane can make one on every build. Each list
  /// of suggestions is built when the first query needs it.
  ComposerAutocompleteCatalog.fromWorkspace(
    ChatWorkspace workspace,
    ConversationChannel activeChannel,
  ) : _sources = _CatalogSources(workspace, activeChannel);

  final _CatalogSources? _sources;

  /// Two catalogs are equal when they would offer the same suggestions. A new
  /// message, for one, leaves the catalog equal to the one before it.
  @override
  bool operator ==(Object other) =>
      other is ComposerAutocompleteCatalog && other._sources == _sources;

  @override
  int get hashCode => _sources.hashCode;

  List<ComposerAutocompleteSuggestion> suggestionsFor(
    ComposerAutocompleteQuery query, {
    int limit = 8,
  }) {
    final sources = _sources;
    if (sources == null || limit <= 0) return const [];
    final source = switch (query.trigger) {
      ComposerAutocompleteTrigger.mention => sources.mentions,
      ComposerAutocompleteTrigger.channel => sources.channels,
      ComposerAutocompleteTrigger.emoji => sources.emojis,
    };
    final needle = query.text.toLowerCase();
    final matches =
        <({int index, int score, ComposerAutocompleteSuggestion value})>[];
    for (var index = 0; index < source.length; index++) {
      final suggestion = source[index];
      final score = _score(suggestion._searchTerms, needle);
      if (score != null) {
        matches.add((index: index, score: score, value: suggestion));
      }
    }
    matches.sort((left, right) {
      final score = left.score.compareTo(right.score);
      return score != 0 ? score : left.index.compareTo(right.index);
    });
    return List.unmodifiable(matches.take(limit).map((match) => match.value));
  }

  static int? _score(List<String> terms, String needle) {
    if (needle.isEmpty) return 0;
    int? best;
    for (final raw in terms) {
      final term = raw.toLowerCase();
      final score = term == needle
          ? 0
          : term.startsWith(needle)
          ? 1
          : term
                .split(RegExp(r'[\s_-]+'))
                .any((word) => word.startsWith(needle))
          ? 2
          : term.contains(needle)
          ? 3
          : null;
      if (score != null && (best == null || score < best)) best = score;
    }
    return best;
  }
}

/// What a catalog is built from. It holds the workspace's lists and not the
/// workspace, so a kept catalog does not keep old messages alive.
///
/// A workspace hands back the same list until that list changes, so comparing
/// the lists by identity tells whether the suggestions could differ.
final class _CatalogSources {
  _CatalogSources(ChatWorkspace workspace, this._activeChannel)
    : _members = workspace.members,
      _roles = workspace.roles,
      _spaceChannels = workspace.channelsFor(_activeChannel.spaceId),
      _emojis = workspace.emojis,
      _spaces = workspace.spaces,
      _currentMemberId = workspace.currentMemberId;

  final ConversationChannel _activeChannel;
  final List<Member> _members;
  final List<CommunityRole> _roles;
  final List<ConversationChannel> _spaceChannels;
  final List<GuildEmoji> _emojis;
  final List<CommunitySpace> _spaces;
  final String _currentMemberId;

  late final List<ComposerAutocompleteSuggestion> mentions = List.unmodifiable(
    _buildMentions(),
  );
  late final List<ComposerAutocompleteSuggestion> channels = List.unmodifiable(
    _buildChannels(),
  );
  late final List<ComposerAutocompleteSuggestion> emojis = List.unmodifiable(
    _buildEmojis(),
  );

  @override
  bool operator ==(Object other) =>
      other is _CatalogSources &&
      other._activeChannel.id == _activeChannel.id &&
      other._currentMemberId == _currentMemberId &&
      identical(other._members, _members) &&
      identical(other._roles, _roles) &&
      identical(other._spaceChannels, _spaceChannels) &&
      identical(other._emojis, _emojis) &&
      identical(other._spaces, _spaces);

  @override
  int get hashCode => _activeChannel.id.hashCode;

  List<ComposerAutocompleteSuggestion> _buildMentions() {
    final members =
        _members
            .where((member) {
              if (_activeChannel.isDirectMessage) {
                return member.id == _currentMemberId ||
                    member.id == _activeChannel.recipientId;
              }
              return member.spaceIds.isEmpty ||
                  member.spaceIds.contains(_activeChannel.spaceId);
            })
            .toList(growable: false)
          ..sort((left, right) {
            final presence = left.presence.index.compareTo(
              right.presence.index,
            );
            return presence != 0
                ? presence
                : left.displayName.toLowerCase().compareTo(
                    right.displayName.toLowerCase(),
                  );
          });
    final suggestions = members
        .map(
          (member) => ComposerAutocompleteSuggestion(
            id: member.id,
            label: member.displayName,
            description: _activeChannel.isDirectMessage
                ? 'Member'
                : '${member.roleFor(_activeChannel.spaceId)} · Member',
            insertText: '<@${member.id}>',
            kind: ComposerAutocompleteKind.member,
            searchTerms: [
              member.displayName,
              member.roleFor(_activeChannel.spaceId),
              member.id,
            ],
            initials: member.initials,
            colorValue: member.colorValue,
            avatarUrl: member.avatarUrlFor(
              _activeChannel.isDirectMessage ? null : _activeChannel.spaceId,
            ),
          ),
        )
        .toList(growable: true);

    if (!_activeChannel.isDirectMessage) {
      final roles =
          _roles
              .where((role) => role.spaceId == _activeChannel.spaceId)
              .toList(growable: false)
            ..sort((left, right) {
              final position = right.position.compareTo(left.position);
              return position != 0
                  ? position
                  : left.name.toLowerCase().compareTo(right.name.toLowerCase());
            });
      suggestions.addAll(
        roles.map(
          (role) => ComposerAutocompleteSuggestion(
            id: role.id,
            label: role.name,
            description: 'Role',
            insertText: '<@&${role.id}>',
            kind: ComposerAutocompleteKind.role,
            searchTerms: [role.name, role.id],
            colorValue: role.colorValue,
          ),
        ),
      );
    }
    return suggestions;
  }

  List<ComposerAutocompleteSuggestion> _buildChannels() {
    if (_activeChannel.isDirectMessage) return const [];
    return ([..._spaceChannels]..sort((left, right) {
          final position = left.position.compareTo(right.position);
          return position != 0
              ? position
              : left.name.toLowerCase().compareTo(right.name.toLowerCase());
        }))
        .map(
          (channel) => ComposerAutocompleteSuggestion(
            id: channel.id,
            label: channel.name,
            description: _channelDescription(channel),
            insertText: '<#${channel.id}>',
            kind: ComposerAutocompleteKind.channel,
            searchTerms: [channel.name, channel.topic, channel.id],
          ),
        )
        .toList(growable: false);
  }

  /// Custom emoji from every server the account is in, each naming its
  /// server, followed by the whole unicode set.
  ///
  /// The custom ones lead because a name typed after a colon is most often a
  /// server's own; the unicode ones follow, ranked the way the catalogue
  /// ranks them. Availability is what Discord enforces, not the client: an
  /// unavailable emoji is left out here rather than sent and refused.
  List<ComposerAutocompleteSuggestion> _buildEmojis() {
    final spaceNames = {for (final space in _spaces) space.id: space.name};
    return [
      for (final emoji in _emojis.where((emoji) => emoji.available))
        ComposerAutocompleteSuggestion(
          id: emoji.id,
          label: emoji.name,
          description: spaceNames[emoji.spaceId] ?? emoji.spaceId,
          insertText: emoji.messageSyntax,
          kind: ComposerAutocompleteKind.emoji,
          searchTerms: [emoji.name, spaceNames[emoji.spaceId] ?? ''],
          emojiUrl: emoji.imageUrl,
        ),
      ..._unicodeSuggestions,
    ];
  }

  /// The unicode half, built once: it holds no workspace state.
  static final List<ComposerAutocompleteSuggestion> _unicodeSuggestions = [
    for (final emoji in UnicodeEmojiCatalog.all)
      ComposerAutocompleteSuggestion(
        id: 'unicode-${emoji.name}',
        label: emoji.name,
        description: 'Unicode',
        insertText: emoji.glyph,
        kind: ComposerAutocompleteKind.emoji,
        searchTerms: [emoji.name, emoji.searchTerms],
        unicodeGlyph: emoji.glyph,
      ),
  ];

  static String _channelDescription(ConversationChannel channel) =>
      switch (channel.kind) {
        ChannelKind.text when channel.isThread => 'Thread',
        ChannelKind.text => 'Text Channel',
        ChannelKind.voice => 'Voice Channel',
        ChannelKind.forum => 'Forum Channel',
        ChannelKind.media => 'Media Channel',
      };
}
