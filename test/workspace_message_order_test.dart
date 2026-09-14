import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ChatWorkspace.upsertMessage] places a message in its channel's timeline
/// without re-sorting every message the client has cached. These pin the
/// ordering that used to come from that sort.
void main() {
  test('a channel lookup answers with the same list every time', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
    ]);

    final first = workspace.messagesFor('alpha');
    final second = workspace.messagesFor('alpha');

    expect(identical(first, second), isTrue);
    expect(
      () => first.add(_message('a-3', 'alpha', 5)),
      throwsUnsupportedError,
    );
  });

  test('places an arriving message after the ones its channel already had', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
    ]);

    final next = workspace.upsertMessage(_message('a-3', 'alpha', 5));

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-2', 'a-3']);
  });

  test('slots a late arrival into place rather than appending it', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 5),
    ]);

    final next = workspace.upsertMessage(_message('a-3', 'alpha', 3));

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-3', 'a-2']);
  });

  test('replaces an edited message in place', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
      _message('a-3', 'alpha', 5),
    ]);

    final next = workspace.upsertMessage(
      _message('a-2', 'alpha', 3, body: 'edited'),
    );

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-2', 'a-3']);
    expect(next.messagesFor('alpha')[1].body, 'edited');
  });

  test('leaves another channel untouched', () {
    final workspace = _workspaceWith([
      _message('b-1', 'beta', 2),
      _message('a-1', 'alpha', 4),
      _message('b-2', 'beta', 6),
    ]);

    final next = workspace.upsertMessage(_message('a-2', 'alpha', 1));

    expect(_idsIn(next, 'beta'), ['b-1', 'b-2']);
    expect(_idsIn(next, 'alpha'), ['a-2', 'a-1']);
  });
}

List<String> _idsIn(ChatWorkspace workspace, String channelId) => [
  for (final message in workspace.messagesFor(channelId)) message.id,
];

ChatMessage _message(
  String id,
  String channelId,
  int minute, {
  String body = 'hello',
}) => ChatMessage(
  id: id,
  channelId: channelId,
  authorId: 'lena',
  body: body,
  sentAt: DateTime.utc(2026, 1, 1, 0, minute),
);

ChatWorkspace _workspaceWith(List<ChatMessage> messages) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'F',
      colorValue: 0xFF5865F2,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'alpha',
      spaceId: 'guild-1',
      name: 'alpha',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'beta',
      spaceId: 'guild-1',
      name: 'beta',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [],
  messages: messages,
  currentMemberId: 'lena',
);
