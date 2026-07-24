import '../domain/chat_models.dart';

enum ComposerAutocompleteTrigger { mention, channel }

enum ComposerAutocompleteKind { member, role, channel }

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
        _ => null,
      };
      if (trigger == null) continue;
      if (index > 0 && !_isBoundary(value[index - 1])) return null;
      final text = value.substring(index + 1, cursor);
      if (text.contains('@') || text.contains('#')) return null;
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
  }) : _searchTerms = List.unmodifiable(searchTerms);

  final String id;
  final String label;
  final String description;
  final String insertText;
  final ComposerAutocompleteKind kind;
  final String? initials;
  final int? colorValue;
  final String? avatarUrl;
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
  const ComposerAutocompleteCatalog.empty()
    : _mentionSuggestions = const [],
      _channelSuggestions = const [];

  ComposerAutocompleteCatalog._({
    required List<ComposerAutocompleteSuggestion> mentionSuggestions,
    required List<ComposerAutocompleteSuggestion> channelSuggestions,
  }) : _mentionSuggestions = List.unmodifiable(mentionSuggestions),
       _channelSuggestions = List.unmodifiable(channelSuggestions);

  final List<ComposerAutocompleteSuggestion> _mentionSuggestions;
  final List<ComposerAutocompleteSuggestion> _channelSuggestions;

  factory ComposerAutocompleteCatalog.fromWorkspace(
    ChatWorkspace workspace,
    ConversationChannel activeChannel,
  ) {
    final members =
        workspace.members
            .where((member) {
              if (activeChannel.isDirectMessage) {
                return member.id == workspace.currentMemberId ||
                    member.id == activeChannel.recipientId;
              }
              return member.spaceIds.isEmpty ||
                  member.spaceIds.contains(activeChannel.spaceId);
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
    final mentionSuggestions = members
        .map(
          (member) => ComposerAutocompleteSuggestion(
            id: member.id,
            label: member.displayName,
            description: activeChannel.isDirectMessage
                ? 'Member'
                : '${member.roleFor(activeChannel.spaceId)} · Member',
            insertText: '<@${member.id}>',
            kind: ComposerAutocompleteKind.member,
            searchTerms: [
              member.displayName,
              member.roleFor(activeChannel.spaceId),
              member.id,
            ],
            initials: member.initials,
            colorValue: member.colorValue,
            avatarUrl: member.avatarUrlFor(
              activeChannel.isDirectMessage ? null : activeChannel.spaceId,
            ),
          ),
        )
        .toList(growable: true);

    if (!activeChannel.isDirectMessage) {
      final roles =
          workspace.roles
              .where((role) => role.spaceId == activeChannel.spaceId)
              .toList(growable: false)
            ..sort((left, right) {
              final position = right.position.compareTo(left.position);
              return position != 0
                  ? position
                  : left.name.toLowerCase().compareTo(right.name.toLowerCase());
            });
      mentionSuggestions.addAll(
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

    final channelSuggestions = activeChannel.isDirectMessage
        ? const <ComposerAutocompleteSuggestion>[]
        : (workspace.channelsFor(activeChannel.spaceId)..sort((left, right) {
                final position = left.position.compareTo(right.position);
                return position != 0
                    ? position
                    : left.name.toLowerCase().compareTo(
                        right.name.toLowerCase(),
                      );
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
    return ComposerAutocompleteCatalog._(
      mentionSuggestions: mentionSuggestions,
      channelSuggestions: channelSuggestions,
    );
  }

  List<ComposerAutocompleteSuggestion> suggestionsFor(
    ComposerAutocompleteQuery query, {
    int limit = 8,
  }) {
    if (limit <= 0) return const [];
    final source = switch (query.trigger) {
      ComposerAutocompleteTrigger.mention => _mentionSuggestions,
      ComposerAutocompleteTrigger.channel => _channelSuggestions,
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

  static String _channelDescription(ConversationChannel channel) =>
      switch (channel.kind) {
        ChannelKind.text when channel.isThread => 'Thread',
        ChannelKind.text => 'Text Channel',
        ChannelKind.voice => 'Voice Channel',
        ChannelKind.forum => 'Forum Channel',
        ChannelKind.media => 'Media Channel',
      };
}
